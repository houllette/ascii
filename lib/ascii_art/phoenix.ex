if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AsciiArt.Phoenix do
    @moduledoc """
    Pieces in Phoenix: `player/1` plays one in a page, through its own
    LiveView (`AsciiArt.Phoenix.PlayerLive`); `live_player/1` plays one
    inside yours (`AsciiArt.Phoenix.PlayerComponent`), taking new options as
    your assigns change, for live data. For a still, use
    `AsciiArt.Phoenix.Components.ascii/1`.

        <AsciiArt.Phoenix.player socket={@socket} id="donut" piece="donut" />
        <AsciiArt.Phoenix.player socket={@socket} id="coast" piece="night-coast" render={:server} />

    Only available when `phoenix_live_view` is a dependency.
    """
    use Phoenix.Component

    @doc """
    Plays a piece inside your LiveView, taking new options each time it is
    rendered with them: for live data (see `AsciiArt.Phoenix.PlayerComponent`).

        <AsciiArt.Phoenix.live_player id="load" piece="gauge" options={%{label: "load", value: @load}} />
    """
    attr(:id, :string, required: true, doc: "unique on the page")
    attr(:piece, :any, required: true, doc: "a slug, or a module implementing `AsciiArt.Piece`")

    attr(:options, :map,
      default: %{},
      doc: "the piece's options; new ones are taken up as it plays"
    )

    attr(:fps, :integer, default: nil, doc: "frames a second; the piece's own by default")
    attr(:mono, :boolean, default: false, doc: "draw a coloured piece in one ink")
    attr(:paper, :boolean, default: false, doc: "dark ink on a light page")
    attr(:render, :atom, values: [:client, :server], default: :client, doc: "as for `player/1`")
    attr(:label, :string, default: nil, doc: "what the picture shows")

    def live_player(assigns) do
      ~H"""
      <.live_component
        module={AsciiArt.Phoenix.PlayerComponent}
        id={@id}
        piece={@piece}
        options={@options}
        fps={@fps}
        mono={@mono}
        paper={@paper}
        render={@render}
        label={@label}
      />
      """
    end

    @doc """
    Plays a piece, embedding `AsciiArt.Phoenix.PlayerLive` with `live_render/3`.
    """
    attr(:socket, :any,
      required: true,
      doc: "the parent LiveView's socket (or the conn in a dead view)"
    )

    attr(:id, :string, required: true, doc: "a DOM id, unique on the page")
    attr(:piece, :any, required: true, doc: "a slug, or a module implementing `AsciiArt.Piece`")
    attr(:options, :map, default: %{}, doc: "the piece's options")
    attr(:fps, :integer, default: nil, doc: "frames a second; the piece's own by default")
    attr(:mono, :boolean, default: false, doc: "draw a coloured piece in one ink")
    attr(:paper, :boolean, default: false, doc: "dark ink on a light page")

    attr(:render, :atom,
      values: [:client, :server],
      default: :client,
      doc:
        "`:client` draws in the browser with the hook (loops sent once, then only changes); " <>
          "`:server` patches HTML from the server, with no hook"
    )

    attr(:label, :string, default: nil, doc: "what the picture shows")

    def player(assigns) do
      session =
        %{
          "piece" => assigns.piece,
          "options" => assigns.options,
          "mono" => assigns.mono,
          "paper" => assigns.paper,
          "render" => Atom.to_string(assigns.render),
          "label" => assigns.label,
          "fps" => assigns.fps
        }
        |> Map.reject(fn {_k, v} -> v == nil end)

      assigns = assign(assigns, session: session)

      ~H"""
      {live_render(@socket, AsciiArt.Phoenix.PlayerLive, id: @id, session: @session)}
      """
    end
  end
end
