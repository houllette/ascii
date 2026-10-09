defmodule AsciiArt.Pieces.Scala do
  @moduledoc """
  The red spiral stair, glinting now and then.

  The Scala logo, a red spiral stair, with a glint crossing it every few
  seconds.

  Drawn from devicon's scala-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from scala-plain.svg. The
  logo is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `AsciiArt.loop/1`).

  The picture is always 37 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "scala: the red spiral stair,
  glinting now and then". A player's or a component's `label` gives words of
  your own, as "the Scala logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("scala", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("scala", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {37, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="scala" label="the Scala logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="scala" piece="scala" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/scala.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "scala",
    category: :logos,
    note: "the red spiral stair, glinting now and then",
    cols: 37,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#3a0d09",
      "#e33524",
      "#7f625f",
      "#ed7c71",
      "#c4b6b5",
      "#f7c2bd",
      "#b6291c",
      "#e33524",
      "#d0746b",
      "#ed7c71",
      "#e9bfbb",
      "#f7c2bd"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                                 __pp
                          ___ppp88888
            ______ppppp88888888888888
    q88888888888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    88888888888888888888888888888888P
    888888888888888888888888888P""'
    88888888888888888PP""""'      ._p
    YYY^""""""''            ___pp8888
                ._____pppq88888888888
    qqqqqqq88888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    88888888888888888888888888888888P
    8888888888888888888888888888P""'
    8888888888888888888PP"""'      __
    888PPPP"""""''           ___pp888
                   _____pppq888888888
    qqqqpppppqq8888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    88888888888888888888888888888PY"
    8888888888888888888888PY""'
    88888888PPP"""""'

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                                 __pp
                          ___ppp88888
            ______ppppp88888888888888
    q88888888888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    88888888888888888888888888888888P
    88888888888888888888888888888888q
    888888888888888888888888888888888
    888888888888888888888888888888888
      '""Y888888888888888888888888888
    qqqqqqq88888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    88888888888888888888888888888888q
    888888888888888888888888888888888
    888888888888888888888888888888888
     '""Y8888888888888888888888888888
    qqqqpppp8888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    888888888888888888888888888888888
    88888888888888888888888888888PY"
    8888888888888888888888PY""'
    88888888PPP"""""'

  '''

  @ink ~S"""

                                 1111
                          11111111111
            1111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111100000
    111111111111111111100000000000000
    111100000000000000000000000111111
      0000000000000000111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111110000
    111111111111111111111000000000000
    111111100000000000000000000011111
     00000000000000000001111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    111111111111111111111111111111111
    11111111111111111111111111111111
    111111111111111111111111111
    11111111111111111

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
