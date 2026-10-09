if Code.ensure_loaded?(ExRatatui.App) do
  defmodule Ascii.ExRatatui.Viewer do
    @moduledoc """
    A terminal app that plays pieces full screen: space pauses, ← and →
    step through the pieces, q quits.

        Ascii.ExRatatui.Viewer.run(piece: "donut")

    It is an `ExRatatui.App`, so it runs under a supervisor too, and over
    ExRatatui's other transports. Served over SSH, each client gets a viewer
    of its own:

        children = [
          {Ascii.ExRatatui.Viewer,
           transport: :ssh, port: 2222, auto_host_key: true, app_opts: [piece: "matrix-rain"]}
        ]

    then `ssh -p 2222 localhost`. Each viewer plays its piece with an
    `Ascii.Player`, so keys still work while a scene sets up, and a piece
    that closes a loop is drawn once a cycle.

    ## Options

      * `:piece` - the piece to play first: a slug or a module. Defaults to
        the first of `:pieces`.
      * `:pieces` - the pieces ← and → step through, in order. Defaults to
        every piece. A `:piece` not among them comes first.
      * `:options` - options for `:piece`, whenever it plays; the others
        play with their own.
      * `:fps`, `:paper`, `:color`, `:ink`, `:gradient` - as for
        `Ascii.new/2`, for every piece: `ink: "#7fdbca"` draws each piece
        in one ink in that colour.
      * `:parts` - colours for parts (see `Ascii.Parts`): `true` for
        those each piece suggests, or a map for `:piece`'s, whenever it
        plays.
      * `:mode`, `:ground` - how colour is drawn, as for `Ascii.ExRatatui`:
        `mode: :ansi256` for terminals without 24-bit colour.
      * `:interactive` - keys go to a piece that can be used first (see
        `Ascii.handle_event/2`): a file tree's arrows, a form's typing.
        Those it has no use for are the viewer's, so q still quits unless
        the piece takes it; Ctrl-C always does.

            Ascii.ExRatatui.Viewer.run(piece: "file-tree", options: %{walk: false}, interactive: true)

    and `ExRatatui.App`'s own, such as `:transport`, `:name` and
    `:test_mode`.

    Only available when `ex_ratatui` is a dependency.
    """
    use ExRatatui.App

    alias Ascii.{Frame, Player}
    alias ExRatatui.Event.Key
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Style
    alias ExRatatui.Widgets.Paragraph

    @play [:fps, :paper, :color, :ink, :gradient]

    @doc """
    Plays in this terminal until it is quit, for a script or `mix run`:

        mix run -e 'Ascii.ExRatatui.Viewer.run(piece: "donut")'

    Takes the options above.
    """
    @spec run(opts :: keyword()) :: :ok | {:error, term()}
    def run(opts \\ []) do
      # Checked first: a viewer that fails to start takes its caller with it.
      with {:ok, pieces, index} <- lineup(opts),
           piece = Enum.at(pieces, index),
           {:ok, _anim} <-
             Ascii.prepare(piece, Keyword.take(opts, @play ++ [:options, :parts])),
           {:ok, pid} <- start_link(Keyword.put_new(opts, :name, nil)) do
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end
      end
    end

    @impl true
    def mount(opts) do
      with {:ok, pieces, index} <- lineup(opts) do
        play(%{
          pieces: pieces,
          index: index,
          given: {Enum.at(pieces, index), Keyword.get(opts, :options, %{})},
          play: Keyword.take(opts, @play),
          parts: Keyword.get(opts, :parts),
          draw: Keyword.take(opts, [:mode, :ground]),
          interactive: Keyword.get(opts, :interactive, false),
          paused: false,
          player: nil,
          ref: nil,
          meta: nil,
          frame: nil,
          shown: false
        })
      end
    end

    # The pieces to step through, and where the first is among them.
    defp lineup(opts) do
      pieces = Keyword.get(opts, :pieces, Ascii.pieces())
      piece = Keyword.get(opts, :piece, List.first(pieces))

      {pieces, index} =
        case Enum.find_index(pieces, &(&1 == piece)) do
          nil -> {[piece | pieces], 0}
          index -> {pieces, index}
        end

      if Enum.all?(pieces, &match?({:ok, _}, Ascii.resolve(&1))),
        do: {:ok, pieces, index},
        else: {:error, :unknown_piece}
    end

    # Starts the piece at `index`, and stops the one before. Until its first
    # frame comes, an empty one of its size stands in for it.
    defp play(state) do
      piece = Enum.at(state.pieces, state.index)

      # Its own options and parts if it is the piece given them; parts: true
      # is for every piece.
      {options, parts} =
        case state.given do
          {^piece, options} -> {options, state.parts}
          _other -> {%{}, if(state.parts == true, do: true)}
        end

      ref = make_ref()

      with {:ok, player} <-
             Player.start_link(
               [piece: piece, options: options, parts: parts, ref: ref] ++ state.play
             ) do
        drop(state.player)
        meta = Ascii.meta!(piece)
        {:ok, %{state | player: player, ref: ref, meta: meta, frame: blank(meta), shown: false}}
      end
    end

    # Without waiting for it: a player still setting up a scene would hold
    # up the keys until it was done. Its last frames are passed over by
    # their ref.
    defp drop(nil), do: :ok

    defp drop(player) do
      Process.unlink(player)
      Process.exit(player, :shutdown)
    end

    defp blank(meta) do
      lines = List.duplicate(String.duplicate(" ", meta.cols), meta.rows)
      %Frame{text: Enum.join(lines, "\n"), lines: lines, cols: meta.cols, rows: meta.rows, t: 0.0}
    end

    @impl true
    def render(state, %ExRatatui.Frame{width: width, height: height}) do
      area = %Rect{x: 0, y: 0, width: width, height: max(height - 1, 0)}
      art = Ascii.ExRatatui.place(state.frame, area, [title: state.meta.name] ++ state.draw)

      if height > 0,
        do: [art, {status(state), %Rect{x: 0, y: height - 1, width: width, height: 1}}],
        else: [art]
    end

    defp status(state) do
      keys = if match?([_], state.pieces), do: [], else: ["←/→ piece"]
      keys = if state.interactive, do: ["keys to the piece first" | keys], else: keys
      paused = if state.paused, do: ["paused"], else: []
      text = Enum.join(paused ++ ["space pause" | keys] ++ ["q quit"], " · ")
      %Paragraph{text: " " <> text, style: %Style{modifiers: [:dim]}}
    end

    @impl true
    def handle_event(%Key{code: "c", modifiers: ["ctrl"]}, state), do: {:stop, state}

    def handle_event(%Key{kind: kind} = key, %{interactive: true, shown: true} = state)
        when kind in ["press", "repeat"] do
      with {:key, _} = event <- Ascii.ExRatatui.event(key, %Rect{}),
           {:ok, _options} <- Player.handle_event(state.player, event) do
        {:noreply, state}
      else
        _ -> if kind == "press", do: key(key, state), else: {:noreply, state}
      end
    end

    def handle_event(%Key{kind: "press"} = key, state), do: key(key, state)
    def handle_event(_event, state), do: {:noreply, state}

    defp key(%Key{code: code}, state) when code in ["q", "esc"], do: {:stop, state}
    defp key(%Key{code: "c", modifiers: ["ctrl"]}, state), do: {:stop, state}
    defp key(%Key{code: " "}, state), do: {:noreply, pause(state)}
    defp key(%Key{code: "right"}, state), do: step(state, 1)
    defp key(%Key{code: "left"}, state), do: step(state, -1)
    defp key(_key, state), do: {:noreply, state}

    # The player is paused once it has drawn its first frame: until then it
    # may be setting up, and would hold up the call.
    defp pause(%{shown: false} = state), do: %{state | paused: not state.paused}

    defp pause(%{paused: true} = state) do
      :ok = Player.resume(state.player)
      %{state | paused: false}
    end

    defp pause(state) do
      :ok = Player.pause(state.player)
      %{state | paused: true}
    end

    defp step(%{pieces: [_]} = state, _by), do: {:noreply, state}

    defp step(state, by) do
      {:ok, state} = play(%{state | index: Integer.mod(state.index + by, length(state.pieces))})
      {:noreply, state}
    end

    @impl true
    def handle_info({:ascii_frame, ref, frame}, %{ref: ref} = state) do
      if state.paused and not state.shown, do: :ok = Player.pause(state.player)
      {:noreply, %{state | frame: frame, shown: true}}
    end

    # This process traps exits, so its player's crash comes as a message.
    def handle_info({:EXIT, player, reason}, %{player: player}), do: exit(reason)
    def handle_info(_message, state), do: {:noreply, state, render?: false}
  end
end
