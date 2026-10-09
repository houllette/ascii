if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Ascii.Phoenix do
    @moduledoc """
    Pieces in Phoenix: `player/1` plays one in a page, through its own
    LiveView (`Ascii.Phoenix.PlayerLive`); `live_player/1` plays one
    inside yours (`Ascii.Phoenix.PlayerComponent`), taking new options as
    your assigns change, for live data. For a still, use
    `Ascii.Phoenix.Components.ascii/1`.

        <Ascii.Phoenix.player socket={@socket} id="donut" piece="donut" />
        <Ascii.Phoenix.player socket={@socket} id="coast" piece="night-coast" render={:server} />
        <Ascii.Phoenix.player socket={@socket} id="hello" piece="big-text" ink="#ff5f6d,#ffc371" />
        <Ascii.Phoenix.player socket={@socket} id="boot" piece="boot-log" parts />
        <Ascii.Phoenix.live_player id="files" piece="file-tree" options={%{walk: false, paths: @paths}} interactive notify />

    Only available when `phoenix_live_view` is a dependency.
    """
    use Phoenix.Component

    @doc """
    Plays a piece inside your LiveView, taking new options each time it is
    rendered with them: for live data (see `Ascii.Phoenix.PlayerComponent`).

        <Ascii.Phoenix.live_player id="load" piece="gauge" options={%{label: "load", value: @load}} />
    """
    attr(:id, :string, required: true, doc: "unique on the page")
    attr(:piece, :any, required: true, doc: "a slug, or a module implementing `Ascii.Piece`")

    attr(:options, :map,
      default: %{},
      doc: "the piece's options; new ones are taken up as it plays"
    )

    attr(:fps, :integer, default: nil, doc: "frames a second; the piece's own by default")
    attr(:mono, :boolean, default: false, doc: "draw a coloured piece in one ink")
    attr(:ink, :any, default: nil, doc: "as for `player/1`")
    attr(:gradient, :atom, default: nil, doc: "as for `player/1`")
    attr(:parts, :any, default: nil, doc: "as for `player/1`")
    attr(:paper, :boolean, default: false, doc: "dark ink on a light page")
    attr(:render, :atom, values: [:client, :server], default: :client, doc: "as for `player/1`")
    attr(:label, :string, default: nil, doc: "as for `player/1`")
    attr(:interactive, :boolean, default: false, doc: "as for `player/1`")

    attr(:notify, :boolean,
      default: false,
      doc: "send your LiveView each key and click (see `Ascii.Phoenix.PlayerComponent`)"
    )

    def live_player(assigns) do
      ~H"""
      <.live_component
        module={Ascii.Phoenix.PlayerComponent}
        id={@id}
        piece={@piece}
        options={@options}
        fps={@fps}
        mono={@mono}
        ink={@ink}
        gradient={@gradient}
        parts={@parts}
        paper={@paper}
        render={@render}
        label={@label}
        interactive={@interactive}
        notify={@notify}
      />
      """
    end

    @doc """
    Plays a piece, embedding `Ascii.Phoenix.PlayerLive` with `live_render/3`.
    """
    attr(:socket, :any,
      required: true,
      doc: "the parent LiveView's socket (or the conn in a dead view)"
    )

    attr(:id, :string, required: true, doc: "a DOM id, unique on the page")
    attr(:piece, :any, required: true, doc: "a slug, or a module implementing `Ascii.Piece`")
    attr(:options, :map, default: %{}, doc: "the piece's options")
    attr(:fps, :integer, default: nil, doc: "frames a second; the piece's own by default")
    attr(:mono, :boolean, default: false, doc: "draw a coloured piece in one ink")

    attr(:ink, :any,
      default: nil,
      doc:
        "the colour of a piece in one ink: `\"#rrggbb\"`, or a list (or comma-separated) " <>
          "for a gradient; see `Ascii.Ink`"
    )

    attr(:gradient, :atom,
      values: [nil, :horizontal, :vertical, :diagonal],
      default: nil,
      doc: "which way several inks run; `:horizontal` by default"
    )

    attr(:parts, :any,
      default: nil,
      doc:
        "colours for the piece's parts: a map of part names to colours, or `true` for " <>
          "the ones it suggests; see `Ascii.Parts`"
    )

    attr(:paper, :boolean, default: false, doc: "dark ink on a light page")

    attr(:render, :atom,
      values: [:client, :server],
      default: :client,
      doc:
        "`:client` draws in the browser with the hook (loops sent once, then only changes); " <>
          "`:server` patches HTML from the server, with no hook"
    )

    attr(:label, :string,
      default: nil,
      doc:
        "what the picture shows, for screen readers; by default the piece tells it from " <>
          "its options (`Ascii.describe/1`)"
    )

    attr(:interactive, :boolean,
      default: false,
      doc:
        "keys and clicks go to the piece (`Ascii.handle_event/2`): its element takes " <>
          "focus, and arrows, space, enter and typing reach it (clicks need the hook)"
    )

    attr(:notify, :boolean,
      default: false,
      doc:
        "send the LiveView that embeds the player `{:ascii, id, info}` for each key " <>
          "and click (see `Ascii.Phoenix.PlayerComponent`)"
    )

    def player(assigns) do
      session =
        %{
          "piece" => assigns.piece,
          "options" => assigns.options,
          "mono" => assigns.mono,
          "ink" => assigns.ink,
          "gradient" => assigns.gradient && Atom.to_string(assigns.gradient),
          "parts" => assigns.parts,
          "paper" => assigns.paper,
          "render" => Atom.to_string(assigns.render),
          "label" => assigns.label,
          "fps" => assigns.fps,
          "interactive" => assigns.interactive,
          "notify" => assigns.notify
        }
        |> Map.reject(fn {_k, v} -> v == nil end)

      assigns = assign(assigns, session: session)

      ~H"""
      {live_render(@socket, Ascii.Phoenix.PlayerLive, id: @id, session: @session)}
      """
    end
  end
end
