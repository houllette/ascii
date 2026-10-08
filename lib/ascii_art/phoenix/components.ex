if Code.ensure_loaded?(Phoenix.Component) do
  defmodule AsciiArt.Phoenix.Components do
    @moduledoc """
    Function components for drawing pieces in Phoenix, without JavaScript.

    `ascii/1` draws one frame, frame 0 by default: upstream's own rule is
    that frame 0 is a good still, and it is all a reader who prefers reduced
    motion sees, and what a dead view or an email gets. To play a piece, see
    `AsciiArt.Phoenix.player/1`.

        <AsciiArt.Phoenix.Components.ascii piece="donut" />
        <AsciiArt.Phoenix.Components.ascii piece="night-coast" label="a lighthouse at night" />
        <AsciiArt.Phoenix.Components.ascii piece="elixir" mono class="logo" />

    `frame/1` draws a frame you already have, from an `AsciiArt.Player` your
    LiveView subscribes to, say.

    Only available when `phoenix_live_view` is a dependency.
    """
    use Phoenix.Component

    alias AsciiArt.Render.HTML

    @pre_style "margin:0;line-height:1.2;letter-spacing:0;white-space:pre;font-variant-ligatures:none"

    @doc """
    One frame of a piece as a `<pre>`.

    A text piece is its text, in the page's own colour. A coloured piece is
    its text in spans of its palette, over its `ground`; `mono` draws it in
    one ink instead. The `<pre>` is `role="img"`, labelled with `label` or the
    piece's name.
    """
    attr(:piece, :any, required: true, doc: "a slug or a module")
    attr(:t, :float, default: 0.0, doc: "the time to draw, in seconds")
    attr(:options, :map, default: %{}, doc: "the piece's options, checked against its defaults")
    attr(:mono, :boolean, default: false, doc: "draw a coloured piece in one ink")
    attr(:paper, :boolean, default: false, doc: "dark ink on a light page")
    attr(:now, :any, default: nil, doc: "a DateTime for pieces that read the clock")

    attr(:label, :string,
      default: nil,
      doc: "what the picture shows; the piece's name by default"
    )

    attr(:rest, :global)

    def ascii(assigns) do
      opts = [options: assigns.options, paper: assigns.paper, color: not assigns.mono]

      # Frame 0 is kept after the first time (see AsciiArt.still/2): a
      # scene's set-up is paid once, not on every render.
      frame =
        if assigns.t == 0 and assigns.now == nil do
          {:ok, frame} = AsciiArt.still(assigns.piece, opts) |> raise_on_error()
          frame
        else
          anim = AsciiArt.new!(assigns.piece, opts)
          {frame, _anim} = AsciiArt.frame(anim, assigns.t, now: assigns.now)
          frame
        end

      assigns =
        assign(assigns,
          label: assigns.label || AsciiArt.meta!(assigns.piece).name,
          style: style(frame),
          content: {:safe, HTML.render(frame)}
        )

      ~H"""
      <pre role="img" aria-label={@label} style={@style} {@rest}>{@content}</pre>
      """
    end

    @doc """
    A frame you already have as a `<pre>`, drawn as `ascii/1` draws one: for
    frames from an `AsciiArt.Player` your LiveView subscribes to, or from
    `AsciiArt.frame/3`. Each row is an element of its own, so as the frame
    changes LiveView sends only the rows that did.

        <AsciiArt.Phoenix.Components.frame frame={@frame} label="the Elixir logo" />
    """
    attr(:frame, AsciiArt.Frame, required: true)
    attr(:label, :string, default: "ascii art", doc: "what the picture shows")
    attr(:rest, :global)

    def frame(assigns) do
      %AsciiArt.Frame{} = frame = assigns.frame
      last = frame.rows - 1

      rows =
        for {html, y} <- Enum.with_index(HTML.rows(frame)),
            do: {:safe, if(y < last, do: [html, ?\n], else: html)}

      assigns = assign(assigns, style: style(frame), rows: rows)

      ~H"""
      <pre role="img" aria-label={@label} style={@style} {@rest}><span :for={{row, y} <- Enum.with_index(@rows)} :key={y}>{row}</span></pre>
      """
    end

    defp raise_on_error({:ok, _} = ok), do: ok

    defp raise_on_error({:error, reason}),
      do: raise(ArgumentError, "ascii_art: #{inspect(reason)}")

    @doc false
    def style(frame) do
      case HTML.style(frame) do
        nil -> @pre_style
        ground -> @pre_style <> ";" <> ground
      end
    end
  end
end
