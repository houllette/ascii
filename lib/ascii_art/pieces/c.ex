defmodule AsciiArt.Pieces.C do
  @moduledoc """
  A c on a blue hexagon, glinting now and then.

  The C logo, a C on a hexagon, with a glint crossing it every few seconds.

  Drawn from devicon's c-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from c-plain.svg. The logo
  is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `AsciiArt.loop/1`).

  The picture is always 49 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "c: a c on a blue hexagon,
  glinting now and then". A player's or a component's `label` gives words of
  your own, as "the C logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("c", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("c", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {49, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="c" label="the C logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="c" piece="c" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/c.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "c",
    category: :logos,
    note: "a c on a blue hexagon, glinting now and then",
    cols: 49,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#659ad3",
      "#ffffff",
      "#03599c",
      "#9bbde2",
      "#ffffff",
      "#5b93bf",
      "#d1e1f2",
      "#ffffff",
      "#b3cde1",
      "#659ad3",
      "#ffffff",
      "#0362ab",
      "#9bbde2",
      "#ffffff",
      "#5b99c8",
      "#d1e1f2",
      "#ffffff",
      "#b3d0e6"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

                       _pp8qq_
                   __p888888888q_,
                _pp888888888888888qq_
            ._p88888888888888888888888q_,
         _pp88888888888888888888888888888qq_
     ._p88888888888P"'         '"Y88888888888q_,
    q88888888888"'                 '"88888888888p
    8888888888"          ___          "8888888888
    88888888P       _pp8888888qq_       888888888
    8888888P      _p8888888888888q,  __p888888888
    8888888      q88888888888888888q8888888888888
    888888|     \88888888888888888888888888888888
    888888'     d88888888888888888888888888888888
    888888,     d88888888888888888888888888888888
    888888|     "88888888888888888888888888888888
    888888b      "88888888888888888P8888888888888
    8888888p      '88888888888888P"  '"8888888888
    88888888q,      '"88888888P"'      .p88888888
    8888888888_           '           _8888888888
    O88888888888q_                 _p88888888888P
      "Y88888888888q__,        __pp8888888888P"
         ""88888888888888qqq8888888888888P"'
            '"888888888888888888888888P"
                "Y88888888888888888""
                   '"8888888888P"'
                       "Y888P"

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                       _pp8qq_
                   __p888888888q_,
                _pp888888888888888qq_
            ._p88888888888888888888888q_,
         _pp88888888888888888888888888888qq_
      _p8888888888888888888888888888888888888q_,
    q8888888888888888888888888888888888888888888p
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888
    Y8888888888888888888888888888888888888888888P
      "Y8888888888888888888888888888888888888P"
         '"888888888888888888888888888888P"'
             "Y88888888888888888888888P"
                ""88888888888888888""
                   '"8888888888P"'
                       "Y888P"

  """

  @ink ~S"""

                       0000000
                   000000000000000
                000000000000000000000
            00000000000000000000000000000
         00000000000000000000000000000000000
      000000000000001111111111111000000000000000
    000000000000111111111111111111111000000000000
    000000000011111111111111111111111110000000222
    000000000111111111000000000111111111002222222
    000000001111111000000000000000111112222222222
    000000011111110000000000000000022222222222222
    000000111111100000000000000022222222222222222
    000000111111000000000000222222222222222222222
    000000111111000000000222222222222222222222222
    000000111111100000222222222222222222222222222
    000000011111112222222222222222222222222222222
    000000001111111222222222222222111112222222222
    000000022111111111222222222111111111222222222
    000022222211111111111111111111111112222222222
    022222222222111111111111111111111222222222222
      22222222222222111111111111122222222222222
         22222222222222222222222222222222222
             222222222222222222222222222
                222222222222222222222
                   222222222222222
                       2222222

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
