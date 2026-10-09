defmodule AsciiArt.Pieces.Css do
  @moduledoc """
  The blue shield with a 3, glinting now and then.

  The CSS logo, a blue shield with a 3, with a glint crossing it every few
  seconds.

  Drawn from devicon's css3-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from css3-plain.svg. The
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

  The picture is always 50 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "css: the blue shield with a
  3, glinting now and then". A player's or a component's `label` gives words
  of your own, as "the CSS logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("css", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("css", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {50, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="css" label="the CSS logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="css" piece="css" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/css.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "css",
    category: :logos,
    note: "the blue shield with a 3, glinting now and then",
    cols: 50,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#1572b6",
      "#f6f7f7",
      "#33a9dc",
      "#67a3d0",
      "#f9fafa",
      "#7ac7e8",
      "#b9d5e9",
      "#fcfdfd",
      "#c2e5f5",
      "#1572b6",
      "#f6f7f7",
      "#33a9dc",
      "#67a3d0",
      "#f9fafa",
      "#7ac7e8",
      "#b9d5e9",
      "#fcfdfd",
      "#c2e5f5"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

    8888888888888888888888888888888888888888888888
    d88888888888888888888888888888888888888888888P
    |88888888888888888888888888888888888888888888|
    |88888888888888888888888888888888888888888888|
    '88888888PPPPPPPPPPPPPPPPPPPPPPPPPPPP88888888'
     88888888                            88888888
     88888888                            88888888
     d8888888qqqqqqqqqqqqqqqqqqqqqp     :8888888P
     |88888888888888888888888888888     |8888888|
     |88888888888888888888888888888     q8888888|
      88888888888888"""""""""""""""     d8888888
      88888888888888|                   88888888
      d8888888888888b                  .8888888P
      d88888888888888qqqqqqqqqqqqp     |8888888P
      |888888888888888888888888888     |8888888|
      '8888888b     d888888888888P     d8888888'
       88888888     d888888888888P     d8888888
       88888888      '""Y888PP""'      88888888
       d8888888,                      .8888888P
       |8888888qqq__,            .__ppp8888888|
       |88888888888888qqq____ppp88888888888888|
       '88888888888888888888888888888888888888
        88888888888888888888888888888888888888
        "Y888888888888888888888888888888888PP"
             '""Y8888888888888888888PP""'
                    '""Y88888P^""'

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

    8888888888888888888888888888888888888888888888
    d88888888888888888888888888888888888888888888P
    d88888888888888888888888888888888888888888888P
    |88888888888888888888888888888888888888888888|
    '88888888888888888888888888888888888888888888'
     88888888888888888888888888888888888888888888
     88888888888888888888888888888888888888888888
     d888888888888888888888888888888888888888888P
     |888888888888888888888888888888888888888888|
     |888888888888888888888888888888888888888888|
      888888888888888888888888888888888888888888
      888888888888888888888888888888888888888888
      d8888888888888888888888888888888888888888P
      d8888888888888888888888888888888888888888P
      |8888888888888888888888888888888888888888|
      '8888888888888888888888888888888888888888'
       8888888888888888888888888888888888888888
       8888888888888888888888888888888888888888
       d88888888888888888888888888888888888888P
       |88888888888888888888888888888888888888|
       |88888888888888888888888888888888888888|
       '88888888888888888888888888888888888888'
        88888888888888888888888888888888888888
        "Y888888888888888888888888888888888PP"
             '""Y8888888888888888888PP""'
                    '""Y88888PY""'

  """

  @ink ~S"""

    0000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000
    0000000000000000000000022222222222222222220000
    0000000000000000000000022222222222222222200000
    0000000000000000000000022222222222222222200000
     00000000111111111111111111111111111122220000
     00000000111111111111111111111111111122220000
     00000000000000000000002222222211111122220000
     00000000000000000000002222222211111122220000
     00000000000000000000002222222211111122200000
      000000000000000111111111111111111122220000
      000000000000001111111111111111111122220000
      000000000000000111111111111111111122220000
      000000000000000000000222222211111122220000
      000000000000000000000222222211111122200000
      000000000111110000000222222211111222200000
       0000000011111100000022222211111122220000
       0000000011111111100022211111111122220000
       0000000011111111111111111111111122220000
       0000000000111111111111111111112222220000
       0000000000000000001111222222222222200000
       0000000000000000000022222222222222200000
        00000000000000000002222222222200000000
        00000000000000000002222000000000000000
             0000000000000000000000000000
                    00000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
