if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AsciiArt.Phoenix.PlayerLive do
    @moduledoc """
    A LiveView that plays one piece, to embed with `live_render/3` (or
    `AsciiArt.Phoenix.player/1`). It owns its process and its timer, so the
    page that embeds it needs no `handle_info` of its own.

    The dead render is frame 0, whole, as HTML, so a page that never connects
    still shows the picture. Once connected the piece plays one of two ways.

    ## In the browser (`"render" => "client"`, the default)

    With the hook in `priv/static/ascii_art_hook.js` registered, the browser
    draws: a text piece in its `<pre>`, a coloured one on a `<canvas>`. What
    the server sends depends on the piece:

      * A piece that closes a loop (see `AsciiArt.loop/1`) is drawn for one
        cycle, in a task, and the cycle is sent once: each frame as the rows
        cells that changed from the one before, compressed when the browser can
        inflate it. From then on the browser repeats it and the server does
        nothing. A cycle over 512 KB as sent is played like any other piece.
      * Any other piece is drawn on the server at its frame rate, and each
        frame sends the runs of cells that changed, or nothing when none
        did: a scene, which changes a few cells in a hundred, sends a few
        kilobytes a frame rather than forty. Play
        stops while the picture is off screen or its tab hidden.

    Readers who prefer reduced motion keep frame 0. Register the hook in
    your `app.js`:

        import {AsciiArt} from "../../deps/ascii_art/priv/static/ascii_art_hook.js"
        let liveSocket = new LiveSocket("/live", Socket, {hooks: {AsciiArt}, ...})

    If no hook answers within two seconds of connecting, the player draws on
    the server instead.

    ## On the server (`"render" => "server"`)

    No JavaScript but LiveView's: the server draws each frame and LiveView
    patches the `<pre>` a row at a time, so only the rows that changed are
    sent, and nothing for a frame that did not change. A loop is drawn once
    and replayed. The server cannot tell when the picture is out of sight, so
    it plays on.

    ## Session

    Only these keys are read; values may be strings, as from params:

      * `"piece"` - a slug, or a module implementing `AsciiArt.Piece`. A
        string is always a slug, never read as a module name.
      * `"options"` - the piece's options, checked against its defaults.
      * `"fps"` - frames a second, 0 to 60.
      * `"mono"`, `"paper"` - as for `AsciiArt.new/2`.
      * `"render"` - `"client"` (default) or `"server"`.
      * `"label"` - what the picture shows, for screen readers.

    Only available when `phoenix_live_view` is a dependency.
    """
    use Phoenix.LiveView

    alias AsciiArt.Phoenix.Playback

    @impl true
    def mount(_params, session, socket) do
      session = if is_map(session), do: session, else: %{}

      how = %{render: session["render"], label: label(session), id: socket.id, owner: :live}
      {:ok, Playback.init(socket, piece(session), opts(session), how)}
    end

    defp piece(%{"piece" => piece}) when is_binary(piece) or is_atom(piece), do: piece
    defp piece(_session), do: nil

    defp opts(session) do
      [
        options: options(session["options"]),
        paper: truthy?(session["paper"]),
        color: not truthy?(session["mono"])
      ] ++ if(session["fps"] != nil, do: [fps: session["fps"]], else: [])
    end

    defp options(options) when is_map(options) or is_list(options), do: options
    defp options(_options), do: %{}

    defp truthy?(value), do: value in [true, "true"]

    defp label(%{"label" => label}) when is_binary(label), do: String.slice(label, 0, 200)
    defp label(_session), do: nil

    @impl true
    def handle_async(:loop, result, socket), do: {:noreply, Playback.looped(socket, result)}

    @impl true
    def handle_info({:tick, timer}, socket), do: {:noreply, Playback.tick(socket, timer)}

    # A tick from outside (a test, a parent) draws a frame without changing the pace.
    def handle_info(:tick, socket), do: {:noreply, Playback.tick(socket, nil)}
    def handle_info(:no_hook, socket), do: {:noreply, Playback.no_hook(socket)}

    @impl true
    def handle_event("ascii_art:ready", params, socket),
      do: {:noreply, Playback.ready(socket, params)}

    def handle_event("ascii_art:visible", %{"visible" => visible}, socket),
      do: {:noreply, Playback.visible(socket, visible)}

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    @impl true
    def render(assigns), do: Playback.render(assigns)
  end
end
