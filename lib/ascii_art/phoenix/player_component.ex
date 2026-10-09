if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AsciiArt.Phoenix.PlayerComponent do
    @moduledoc """
    A LiveComponent that plays a piece inside your LiveView and takes new
    options as they change: for live data, a reading for a gauge, the latest
    samples for a sparkline.

        <AsciiArt.Phoenix.live_player id="load" piece="gauge" options={%{label: "load", value: @load}} />

    or, the same, `<.live_component module={AsciiArt.Phoenix.PlayerComponent}
    id="load" ... />`. Each time your LiveView renders it with other
    `options`, the piece takes them up while it plays
    (`AsciiArt.put_options/2`): the gauge's needle swings from the last
    reading to the new one, bars ease to new values, a sparkline scrolls on.
    Another `piece`, `fps`, `paper`, `mono`, `ink`, `gradient`, `parts` or
    `render` starts it afresh.

    It plays as `AsciiArt.Phoenix.PlayerLive` does, with the same hook and
    the same economy: a loop is sent to the browser once, anything else as
    the cells that change, nothing while out of sight (see that module). The
    difference is where it runs: in your LiveView's process, whose state the
    options come from, rather than in a LiveView of its own. That suits
    widgets, which draw in well under a millisecond; a 200×100 scene costs
    milliseconds a frame, and is better in `AsciiArt.Phoenix.player/1`.

    ## Attributes

    `id` (required, unique on the page), `piece` (a slug or a module),
    `options`, `fps`, `paper`, `mono`, `ink`, `gradient`, `parts`, `render`
    (`:client`, the default, or `:server`), `label`, `interactive` and
    `notify`, as for `AsciiArt.Phoenix.player/1`.

    ## Keys and clicks

    With `interactive`, the piece takes keys and clicks
    (`AsciiArt.handle_event/2`): a file tree's cursor moves, a form's box
    ticks. With `notify`, your LiveView is sent each of them as well, as
    `{:ascii_art, id, %{event: event, part: part, text: text, options:
    options}}`: the event, the part clicked and its text (see
    `AsciiArt.part_at/4`), and the options the piece now has, from which to
    read what was chosen.

        def handle_info({:ascii_art, "files", %{event: {:key, "enter"}, options: options}}, socket),
          do: {:noreply, open_file(socket, options.cursor)}

    The options you give are merged over what the piece's events have
    changed, so leave out those it keeps (a tree's `cursor` and `open`, a
    form's `fields`) unless you mean to set them, and never give back what
    it told you: it has that already, and keys typed in the meantime would
    be undone.

    Only available when `phoenix_live_view` is a dependency.
    """
    use Phoenix.LiveComponent

    alias AsciiArt.Phoenix.Playback

    # A timer or a fallback from the player: delivered by
    # send_update_after/4, ignored if it was set before the piece last started
    # afresh.
    @impl true
    def update(%{ascii_art: message, gen: gen}, %{assigns: %{gen: gen}} = socket),
      do: {:ok, deliver(socket, message)}

    def update(%{ascii_art: _message}, socket), do: {:ok, socket}

    def update(assigns, socket) do
      config =
        Map.take(assigns, [
          :piece,
          :fps,
          :paper,
          :mono,
          :ink,
          :gradient,
          :parts,
          :render,
          :interactive,
          :notify
        ])

      options = Map.get(assigns, :options) || %{}

      socket =
        cond do
          socket.assigns[:config] != config -> fresh(socket, assigns, config, options)
          socket.assigns[:given] == options -> socket
          true -> socket |> assign(given: options) |> Playback.put_options(options)
        end

      {:ok, socket}
    end

    # A new piece, or the same drawn otherwise: set up anew, under a new DOM
    # id, so the browser starts its hook afresh too.
    defp fresh(socket, assigns, config, options) do
      gen = (socket.assigns[:gen] || 0) + 1
      id = "ascii-art-#{assigns.id}-#{gen}"

      opts =
        [
          options: options,
          paper: assigns[:paper] == true,
          color: assigns[:mono] != true,
          ink: assigns[:ink],
          gradient: assigns[:gradient],
          parts: assigns[:parts]
        ] ++ if(assigns[:fps] != nil, do: [fps: assigns[:fps]], else: [])

      how = %{
        render: Map.get(assigns, :render) || :client,
        label: assigns[:label],
        id: id,
        owner: {__MODULE__, assigns.id, gen},
        target: socket.assigns.myself,
        interactive: assigns[:interactive] == true,
        notify: assigns[:notify] == true,
        name: assigns.id
      }

      socket
      |> Phoenix.LiveView.cancel_async(:loop)
      |> assign(config: config, given: options, gen: gen)
      |> Playback.init(Map.get(assigns, :piece), opts, how)
    end

    defp deliver(socket, {:tick, timer}), do: Playback.tick(socket, timer)
    defp deliver(socket, :no_hook), do: Playback.no_hook(socket)

    @impl true
    def handle_async(:loop, result, socket), do: {:noreply, Playback.looped(socket, result)}

    @impl true
    def handle_event("ascii_art:ready", params, socket),
      do: {:noreply, Playback.ready(socket, params)}

    def handle_event("ascii_art:visible", %{"visible" => visible}, socket),
      do: {:noreply, Playback.visible(socket, visible)}

    def handle_event("ascii_art:key", params, socket),
      do: {:noreply, Playback.key(socket, params)}

    def handle_event("ascii_art:click", params, socket),
      do: {:noreply, Playback.click(socket, params)}

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    @impl true
    def render(assigns), do: Playback.render(assigns)
  end
end
