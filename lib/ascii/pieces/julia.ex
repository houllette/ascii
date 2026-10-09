defmodule Ascii.Pieces.Julia do
  @moduledoc """
  Three dots, green, red and purple, glinting now and then.

  The Julia logo, three dots, green, red and purple, with a glint crossing it
  every few seconds.

  Drawn from devicon's julia-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from julia-plain.svg. The
  logo is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 60 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "julia: three dots, green,
  red and purple, glinting now and then". A player's or a component's `label`
  gives words of your own, as "the Julia logo".

  ## Example

  ```elixir
  still = Ascii.new!("julia", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("julia", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {60, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="julia" label="the Julia logo" />
  <Ascii.Phoenix.player socket={@socket} id="julia" piece="julia" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/julia.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "julia",
    category: :logos,
    note: "three dots, green, red and purple, glinting now and then",
    cols: 60,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#eeeeee",
      "#cb3c33",
      "#389826",
      "#9558b2",
      "#f4f4f4",
      "#dd807a",
      "#7ebc72",
      "#ba92cd",
      "#fafafa",
      "#efc5c2",
      "#c3e0be",
      "#dfcde8",
      "#eeeeee",
      "#cb3c33",
      "#389826",
      "#9558b2",
      "#f4f4f4",
      "#dd807a",
      "#7ebc72",
      "#ba92cd",
      "#fafafa",
      "#efc5c2",
      "#c3e0be",
      "#dfcde8"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

                         __pp888888qq_,
                       _p88888888888888q_
                     _p888888888888888888q,
                    )8888888888888888888888(
                   .888888888888888888888888,
                   q888888888888888888888888p
                   d888888888888888888888888b
                   d888888888888888888888888P
                   '888888888888888888888888'
                    "8888888888888888888888"
                     'Y888888888888888888P'
                       'Y88888888888888P'
                          '"YP8888PP"'
           __pppqqqqq_,                  __ppppqqqq__
        _p8888888888888q_,            ._p8888888888888q_
      _p888888888888888888p          q888888888888888888q,
     q888888888888888888888q,      .p888888888888888888888p
    \88888888888888888888888p      q88888888888888888888888,
    d888888888888888888888888,    |888888888888888888888888b
    8888888888888888888888888P    |8888888888888888888888888
    8888888888888888888888888|    |8888888888888888888888888
    )888888888888888888888888      888888888888888888888888(
     Y8888888888888888888888"      "8888888888888888888888P
      "8888888888888888888P'        '88888888888888888888"
        "888888888888888P"            "8888888888888888"
          '"Y8888888PP"                  "Y88888888P"'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                         __pp888888qq__
                      .pp88888888888888q_,
                     _88888888888888888888_
                    q8888888888888888888888p
                   q888888888888888888888888p
                   88888888888888888888888888
                  :88888888888888888888888888.
                   88888888888888888888888888
                   d888888888888888888888888P
                    88888888888888888888888P
                     Y88888888888888888888P
                      'Y8888888888888888P'
               ____      "Y888888888PP"      ___,
          _pp88888888qq_,     ''''     ._pp88888888qq_
       _p8888888888888888q,          _p8888888888888888q,
      q88888888888888888888q,      .p88888888888888888888_
     q8888888888888888888888q,    .p8888888888888888888888p
    q888888888888888888888888p    q888888888888888888888888p
    88888888888888888888888888,  .88888888888888888888888888
    88888888888888888888888888|  |88888888888888888888888888
    88888888888888888888888888'  '88888888888888888888888888
    "888888888888888888888888P    O888888888888888888888888"
     )8888888888888888888888P      88888888888888888888888P
      "88888888888888888888"        "88888888888888888888"
        "8888888888888888"'          '"8888888888888888"
          '"Y88888888P"'                '"Y88888888P"'

  """

  @ink ~S"""

                         00000000000000
                      00002222222222220000
                     0002222222222222222000
                    002222222222222222222200
                   00222222222222222222222200
                   00222222222222222222222200
                  0022222222222222222222222200
                   02222222222222222222222200
                   00222222222222222222222200
                    002222222222222222222200
                     0022222222222222222200
                      00002222222222220000
               0000      00000000000000      0000
          000000000000000     0000     000000000000000
       00001111111111110000          00003333333333330000
      00011111111111111111000      00033333333333333333000
     0011111111111111111111000    0003333333333333333333300
    00111111111111111111111100    00333333333333333333333300
    001111111111111111111111100  003333333333333333333333300
    011111111111111111111111100  003333333333333333333333300
    001111111111111111111111100  003333333333333333333333300
    00111111111111111111111100    00333333333333333333333300
     001111111111111111111100      003333333333333333333300
      0001111111111111111100        0033333333333333333000
        0001111111111110000          0000333333333333000
          00000000000000                00000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
