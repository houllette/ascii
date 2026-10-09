if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Ascii.Phoenix.Playback do
    @moduledoc false
    # A piece played in a socket's assigns: what Ascii.Phoenix.PlayerLive
    # (a LiveView of its own) and Ascii.Phoenix.PlayerComponent (a
    # component in yours) share. Each owner hands the socket in and takes it
    # back; they differ only in how a message comes back to them later
    # (`later/3`), and in where the hook's events go (`target`).
    #
    # With the hook (`mode: :client`) the browser draws: a looping piece is
    # sent once, as one cycle; any other is sent a frame at a time, as the
    # runs of cells that changed. Without (`mode: :server`) LiveView patches
    # the HTML a row at a time. Stages: :waiting for the hook, :stream while
    # the server draws, :loop once the browser plays a cycle.

    use Phoenix.Component

    import Phoenix.LiveView, only: [push_event: 3, start_async: 3, cancel_async: 2, connected?: 1]

    alias Ascii.{Animation, Frame}
    alias Ascii.Phoenix.Components
    alias Ascii.Render.HTML

    @max_step 100
    @renders %{"client" => :client, "server" => :server, client: :client, server: :server}
    # How long a hook has to answer before the server draws instead, in ms.
    @wait 2000
    # The most a loop may take to send (compressed, if it is) or to keep.
    @budget 512 * 1024

    @doc false
    # The piece set up in the assigns, and started if connected. `owner` is
    # :live, or {component_module, component_id, generation}; `id` names the
    # DOM element and the player's events.
    def init(socket, piece, opts, %{render: render, label: label, id: id, owner: owner} = how) do
      case first(socket, piece, opts) do
        {:ok, anim, frame, told} ->
          mode = Map.get(@renders, render, :client)
          meta = Ascii.meta!(piece)

          socket
          |> assign(
            anim: anim,
            # Frame 0, which the template draws; and the latest frame, which
            # it does not, so a new one sends nothing by itself.
            still: frame,
            frame: frame,
            drawn: drawn(frame, meta),
            mode: mode,
            stage: :waiting,
            # Given, or told from the options, and told again as they change.
            label: label || told,
            given_label: label,
            interactive: Map.get(how, :interactive) == true,
            notify: Map.get(how, :notify) == true,
            name: Map.get(how, :name, id),
            dom_id: id <> "-art",
            event: "ascii:" <> id,
            target: Map.get(how, :target),
            owner: owner,
            error: nil,
            loop: nil,
            rows: if(mode == :server, do: rows(frame), else: []),
            t: 0.0,
            visible: false,
            timer: nil,
            deflate?: false,
            last: now(),
            next_at: now()
          )
          |> start()

        {:error, reason} ->
          assign(socket, error: describe(reason), mode: nil, target: Map.get(how, :target))
      end
    end

    # The animation and frame 0. Before the page connects only frame 0 is
    # drawn, and that is kept (Ascii.still/2): the piece is set up for the
    # page that plays it, not for the HTML first sent.
    defp first(socket, piece, opts) do
      if connected?(socket) do
        with {:ok, anim} <- Ascii.new(piece, opts) do
          {frame, anim} = Ascii.frame(anim, 0.0)
          {:ok, anim, frame, Ascii.describe(anim)}
        end
      else
        with {:ok, frame} <- Ascii.still(piece, opts),
             {:ok, anim} <- Ascii.prepare(piece, opts),
             do: {:ok, nil, frame, Ascii.describe(anim)}
      end
    end

    defp describe(:unknown_piece), do: "unknown piece"
    defp describe({:invalid_option, key}), do: "invalid option #{inspect(key)}"

    # What the template shows of frame 0, worked out once: in render/1 it
    # would count as changed on every tick, and be sent again.
    defp drawn(%Frame{} = still, meta) do
      %{
        # Colours of an ink rather than the piece's own palette: the hook
        # draws them as text, in spans, the size of the piece in one ink.
        spans: still.colors != nil and still.palette != meta.palette,
        style: Components.style(still),
        html: {:safe, HTML.render(still)},
        palette: still.colors && JSON.encode!(still.palette),
        colors: still.colors && Base.encode64(still.colors),
        text: still.text
      }
    end

    # The browser draws: wait for the hook. The server draws: start now.
    defp start(socket) do
      cond do
        not connected?(socket) ->
          socket

        socket.assigns.mode == :client ->
          later(socket, :no_hook, @wait)
          socket

        true ->
          socket |> assign(visible: true, stage: :stream) |> play(false)
      end
    end

    # A message back to the owner in `ms`.
    defp later(%{assigns: %{owner: :live}}, message, ms),
      do: Process.send_after(self(), message, ms)

    defp later(%{assigns: %{owner: {module, id, gen}}}, message, ms),
      do:
        Phoenix.LiveView.send_update_after(
          self(),
          module,
          %{id: id, ascii: message, gen: gen},
          ms
        )

    # Plays frame by frame, and if the piece loops, draws one cycle in a task
    # to send (or keep) when it is done.
    defp play(%{assigns: %{anim: anim, mode: mode}} = socket, deflate?) do
      socket = socket |> assign(last: now(), next_at: now(), deflate?: deflate?) |> schedule()

      if anim.meta.loop,
        do: start_async(socket, :loop, fn -> cycle(anim, mode, deflate?) end),
        else: socket
    end

    defp cycle(anim, mode, deflate?) do
      with {:ok, frames, fps} <- Ascii.loop(anim), do: pack(mode, frames, fps, deflate?)
    end

    # For the browser: each frame what changed from the one before (see
    # changes/2), or the index of an earlier frame it repeats; as JSON,
    # deflated, if the browser can inflate it.
    defp pack(:client, frames, fps, deflate?) do
      loop = %{fps: fps, frames: deltas(frames)}
      json = JSON.encode!(loop)

      {payload, size} =
        if deflate? do
          packed = Base.encode64(:zlib.compress(json))
          {%{deflate: packed}, byte_size(packed)}
        else
          {loop, byte_size(json)}
        end

      if size <= @budget, do: {:ok, payload}, else: :error
    end

    # For the server: the frames themselves, each picture kept once.
    defp pack(:server, frames, fps, _deflate?) do
      {kept, seen} =
        Enum.map_reduce(frames, %{}, fn frame, seen ->
          case Map.fetch(seen, picture(frame)) do
            {:ok, same} -> {same, seen}
            :error -> {frame, Map.put(seen, picture(frame), frame)}
          end
        end)

      size =
        seen
        |> Map.keys()
        |> Enum.map(fn {text, colors} -> byte_size(text) + byte_size(colors || "") end)
        |> Enum.sum()

      if size <= @budget, do: {:ok, {List.to_tuple(kept), fps}}, else: :error
    end

    defp deltas([first | rest]) do
      start = {[changes(nil, first)], first, %{picture(first) => 0}}

      {list, _prev, _seen} =
        rest
        |> Enum.with_index(1)
        |> Enum.reduce(start, fn {frame, i}, {list, prev, seen} ->
          case Map.fetch(seen, picture(frame)) do
            {:ok, j} when j != i - 1 -> {[j | list], frame, seen}
            _ -> {[changes(prev, frame) | list], frame, Map.put_new(seen, picture(frame), i)}
          end
        end)

      Enum.reverse(list)
    end

    defp picture(%Frame{text: text, colors: colors}), do: {text, colors}

    # What of `frame` differs from `prev` (see `Ascii.Frame.changes/3`), for
    # the wire: [y, x, text, colours as base64]. Frame 0 is every row whole.
    defp changes(prev, %Frame{} = frame) do
      for {y, x, text, colors} <- Frame.changes(prev, frame),
          do: [y, x, text, colors && Base.encode64(colors)]
    end

    defp row_colors(%Frame{colors: nil}, _y), do: nil

    defp row_colors(%Frame{colors: colors, cols: cols}, y),
      do: binary_part(colors, y * cols, cols)

    @doc false
    # The cycle drawn in the task: the browser takes it up at the play time
    # reached, so it runs on from the picture it shows, and the server's part
    # is over; or the server keeps it, to replay.
    def looped(%{assigns: %{mode: :client, stage: :stream}} = socket, {:ok, {:ok, loop}}) do
      event = %{loop: Map.put(loop, :t, socket.assigns.t)}
      socket |> push_event(socket.assigns.event, event) |> assign(stage: :loop, timer: nil)
    end

    def looped(%{assigns: %{mode: :server}} = socket, {:ok, {:ok, loop}}),
      do: assign(socket, loop: loop)

    def looped(socket, _no_loop), do: socket

    @doc false
    # A tick: the one scheduled, or (`nil`) one from outside, a test or a
    # parent, which draws a frame without changing the pace.
    def tick(%{assigns: %{timer: timer}} = socket, timer) when timer != nil,
      do: socket |> assign(timer: nil) |> step() |> schedule()

    def tick(socket, nil), do: step(socket)
    def tick(socket, _stale), do: socket

    @doc false
    # No hook answered: the server draws.
    def no_hook(%{assigns: %{mode: :client, stage: :waiting}} = socket),
      do: socket |> assign(mode: :server, rows: rows(socket.assigns.frame)) |> start()

    def no_hook(socket), do: socket

    @doc false
    # The hook is there. If the picture is no longer the one it was given
    # (new options came first), it gets the picture as it is.
    def ready(%{assigns: %{mode: :client, stage: :waiting}} = socket, params) do
      socket = assign(socket, visible: params["visible"] == true, stage: :stream)
      %{frame: frame, still: still} = socket.assigns
      socket = if picture(frame) == picture(still), do: socket, else: whole(socket, frame)
      play(socket, params["deflate"] == true)
    end

    def ready(socket, _params), do: socket

    @doc false
    # The hook says whether the picture can be seen: the server ticks only then.
    def visible(%{assigns: %{stage: :stream}} = socket, visible) when is_boolean(visible) do
      socket = assign(socket, visible: visible)

      if visible,
        do: socket |> assign(last: now(), next_at: now()) |> schedule(),
        else: assign(socket, timer: nil)
    end

    def visible(socket, _visible), do: socket

    @doc false
    # New options while playing (`Ascii.put_options/2`): the piece carries
    # on with them, drawn at once, a cycle it was playing dropped and sought
    # anew.
    def put_options(%{assigns: %{error: nil, anim: anim}} = socket, options) do
      case Ascii.put_options(anim, options) do
        {:ok, ^anim} -> socket
        {:ok, anim} -> retake(assign(socket, anim: anim))
        {:error, reason} -> assign(socket, error: describe(reason))
      end
    end

    def put_options(socket, _options), do: socket

    defp retake(%{assigns: %{stage: stage, mode: mode, anim: anim, t: t}} = socket) do
      socket = if stage == :waiting, do: socket, else: cancel_async(socket, :loop)
      {frame, anim} = Ascii.frame(anim, t)
      socket = socket |> assign(anim: anim, loop: nil) |> retell()

      cond do
        stage == :waiting ->
          assign(socket, frame: frame, rows: if(mode == :server, do: rows(frame), else: []))

        mode == :server ->
          socket |> assign(frame: frame, rows: rows(frame)) |> seek(socket.assigns.deflate?)

        # Playing frame by frame at the same size: what changed goes now, so
        # a key shows at once, and a still, which never ticks, shows at all.
        stage == :stream and
            {frame.cols, frame.rows} == {socket.assigns.frame.cols, socket.assigns.frame.rows} ->
          socket |> show(frame) |> seek(socket.assigns.deflate?)

        true ->
          socket |> assign(stage: :stream) |> whole(frame) |> seek(socket.assigns.deflate?)
      end
    end

    # New words for the picture from its new options, unless it was given
    # some: the hook keeps its element's attributes, so it is told them.
    defp retell(%{assigns: %{given_label: nil, anim: anim, label: label}} = socket) do
      case Ascii.describe(anim) do
        ^label -> socket
        told -> socket |> tell(told) |> assign(label: told)
      end
    end

    defp retell(socket), do: socket

    defp tell(%{assigns: %{mode: :client, stage: stage, event: event}} = socket, told)
         when stage != :waiting,
         do: push_event(socket, event, %{label: told})

    defp tell(socket, _told), do: socket

    @keys %{
      "ArrowUp" => "up",
      "ArrowDown" => "down",
      "ArrowLeft" => "left",
      "ArrowRight" => "right",
      "Enter" => "enter",
      "Escape" => "esc",
      "Tab" => "tab",
      "Backspace" => "backspace",
      "Delete" => "delete",
      "Home" => "home",
      "End" => "end",
      "PageUp" => "page_up",
      "PageDown" => "page_down"
    }

    @doc false
    # A key from the browser, by its DOM name (`KeyboardEvent.key`), for an
    # interactive player: given to the piece by ExRatatui's name for it
    # (`t:Ascii.event/0`), a character as itself. Keys held with ctrl,
    # alt or meta are the browser's.
    def key(%{assigns: %{interactive: true}} = socket, %{"key" => key} = params)
        when is_binary(key) do
      if params["ctrlKey"] == true or params["altKey"] == true or params["metaKey"] == true do
        socket
      else
        case key_name(key, params["shiftKey"] == true) do
          nil -> socket
          name -> event(socket, {:key, name}, nil)
        end
      end
    end

    def key(socket, _params), do: socket

    defp key_name("Tab", true), do: "back_tab"
    defp key_name(key, _shift?) when is_map_key(@keys, key), do: Map.fetch!(@keys, key)

    defp key_name(key, _shift?) do
      case String.to_charlist(key) do
        [c] when c >= 0x20 and c != 0x7F -> key
        _ -> nil
      end
    end

    @doc false
    # A click on a cell, from the hook: column and row, and the play time of
    # the frame the browser showed if it plays a loop.
    def click(%{assigns: %{interactive: true}} = socket, %{"x" => x, "y" => y} = params)
        when is_integer(x) and is_integer(y),
        do: event(socket, {:click, x, y}, params["t"])

    def click(socket, _params), do: socket

    # The piece takes the event if it can, carrying on from the options it
    # gives; and the app, if it asked, is told what happened and where.
    defp event(%{assigns: %{error: nil, anim: %Animation{} = anim}} = socket, event, t) do
      shown = shown(socket, t)

      socket =
        case Ascii.handle_event(anim, event) do
          {:ok, ^anim} -> socket
          {:ok, anim} -> retake(assign(socket, anim: anim))
          :ignore -> socket
        end

      notify(socket, event, shown)
    end

    defp event(socket, _event, _t), do: socket

    # The frame the reader saw: the latest sent, or a loop's at its time.
    defp shown(%{assigns: %{stage: :loop, anim: anim}}, t) when is_number(t),
      do: anim |> Ascii.frame(t) |> elem(0)

    defp shown(%{assigns: %{frame: frame}}, _t), do: frame

    defp notify(%{assigns: %{notify: false}} = socket, _event, _shown), do: socket

    defp notify(%{assigns: %{anim: anim, name: name, owner: owner}} = socket, event, shown) do
      {part, text} =
        case event do
          {:click, x, y} -> Ascii.part_at(anim, shown, x, y) || {nil, nil}
          _key -> {nil, nil}
        end

      info = %{event: event, part: part, text: text, options: socket.assigns.anim.options}
      to = if owner == :live, do: socket.parent_pid, else: self()
      if to, do: send(to, {:ascii, name, info})
      socket
    end

    # Looks for a cycle again, keeping the pace if playing.
    defp seek(%{assigns: %{anim: anim, mode: mode}} = socket, deflate?) do
      socket = if socket.assigns.timer, do: socket, else: schedule(socket)

      if anim.meta.loop,
        do: start_async(socket, :loop, fn -> cycle(anim, mode, deflate?) end),
        else: socket
    end

    # The whole picture for the browser, its size with it: what it shows
    # from now on, a cycle it was playing stopped.
    defp whole(socket, %Frame{} = frame) do
      event = %{frame: %{cols: frame.cols, rows: frame.rows, runs: changes(nil, frame)}}
      socket |> push_event(socket.assigns.event, event) |> assign(frame: frame)
    end

    defp step(%{assigns: %{error: nil, stage: :stream, visible: true}} = socket) do
      now = now()
      t = socket.assigns.t + min(now - socket.assigns.last, @max_step) / 1000
      {frame, socket} = next(assign(socket, t: t, last: now))
      show(socket, frame)
    end

    defp step(socket), do: socket

    # The loop's frame at the play time, or a new one.
    defp next(%{assigns: %{loop: {frames, fps}, t: t}} = socket),
      do: {elem(frames, rem(trunc(t * fps), tuple_size(frames))), socket}

    defp next(%{assigns: %{anim: anim, t: t}} = socket) do
      {frame, anim} = Ascii.frame(anim, t)
      {frame, assign(socket, anim: anim)}
    end

    # Nothing goes out for a picture that has not changed.
    defp show(%{assigns: %{frame: shown}} = socket, frame) do
      if picture(frame) == picture(shown), do: socket, else: send_frame(socket, frame)
    end

    defp send_frame(%{assigns: %{mode: :client, frame: shown, event: event}} = socket, frame),
      do: socket |> push_event(event, %{runs: changes(shown, frame)}) |> assign(frame: frame)

    defp send_frame(%{assigns: %{frame: shown, rows: rows}} = socket, frame),
      do: assign(socket, frame: frame, rows: rows(frame, shown, rows))

    # Each row's HTML, ending in a newline but the last. In a keyed
    # comprehension, LiveView sends only the rows that change.
    defp rows(%Frame{} = frame) do
      last = frame.rows - 1
      for {html, y} <- Enum.with_index(HTML.rows(frame)), do: row(html, y, last)
    end

    defp rows(%Frame{rows: n} = frame, %Frame{rows: n} = prev, prev_rows) do
      last = n - 1

      for {{old, {line, before}}, y} <-
            Enum.with_index(Enum.zip(prev_rows, Enum.zip(frame.lines, prev.lines))) do
        if line == before and row_colors(frame, y) == row_colors(prev, y),
          do: old,
          else: row(HTML.row(frame, y), y, last)
      end
    end

    defp rows(frame, _prev, _prev_rows), do: rows(frame)

    defp row(html, y, last) when y < last, do: {:safe, [html, ?\n]}
    defp row(html, _y, _last), do: {:safe, html}

    defp schedule(
           %{assigns: %{stage: :stream, visible: true, anim: %Animation{fps: fps}}} = socket
         )
         when fps > 0 do
      now = now()
      due = max(socket.assigns.next_at + 1000 / fps, now)
      timer = make_ref()
      later(socket, {:tick, timer}, round(due - now))
      assign(socket, timer: timer, next_at: due)
    end

    defp schedule(socket), do: socket

    defp now, do: System.monotonic_time(:microsecond) / 1000

    @doc false
    def render(%{error: error} = assigns) when error != nil do
      ~H"""
      <div role="alert">ascii: {@error}</div>
      """
    end

    def render(%{mode: :client} = assigns) do
      ~H"""
      <div
        id={@dom_id}
        phx-hook="Ascii"
        phx-update="ignore"
        phx-target={@target}
        role={if @interactive, do: "application", else: "img"}
        aria-label={@label}
        tabindex={@interactive && "0"}
        data-interactive={@interactive && "true"}
        data-event={@event}
        data-cols={@still.cols}
        data-rows={@still.rows}
        data-cell={@still.cell}
        data-palette={@drawn.palette}
        data-spans={@drawn.spans && "true"}
        data-ground={@still.ground}
        data-text={@drawn.text}
        data-colors={@drawn.colors}
      ><pre aria-hidden="true" style={@drawn.style}>{@drawn.html}</pre></div>
      """
    end

    def render(%{interactive: true} = assigns) do
      ~H"""
      <pre
        id={@dom_id <> "-pre"}
        role="application"
        aria-label={@label}
        tabindex="0"
        phx-keydown="ascii:key"
        phx-target={@target}
        style={@drawn.style}
      ><span :for={{row, y} <- Enum.with_index(@rows)} :key={y}>{row}</span></pre>
      """
    end

    def render(assigns) do
      ~H"""
      <pre id={@dom_id <> "-pre"} role="img" aria-label={@label} style={@drawn.style}><span :for={{row, y} <- Enum.with_index(@rows)} :key={y}>{row}</span></pre>
      """
    end
  end
end
