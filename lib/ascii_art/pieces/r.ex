defmodule AsciiArt.Pieces.R do
  @moduledoc """
  A blue r over a grey ring, glinting now and then.

  The R logo, a blue R over a grey ring, with a glint crossing it every few
  seconds.

  Drawn from devicon's r-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from r-plain.svg. The logo
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

  The picture is always 69 by 27.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "r: a blue r over a grey
  ring, glinting now and then". A player's or a component's `label` gives
  words of your own, as "the R logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("r", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("r", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {69, 27, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="r" label="the R logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="r" piece="r" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/r.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "r",
    category: :logos,
    note: "a blue r over a grey ring, glinting now and then",
    cols: 69,
    rows: 27,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#b0b2b6",
      "#2066b9",
      "#97989e",
      "#cccdd0",
      "#6e9cd2",
      "#bbbcc0",
      "#e7e8e9",
      "#bcd1ea",
      "#e0e0e2",
      "#b0b2b6",
      "#2066b9",
      "#97989e",
      "#cccdd0",
      "#6e9cd2",
      "#bbbcc0",
      "#e7e8e9",
      "#bcd1ea",
      "#e0e0e2"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                       ___ppppq88888888888qqqqq__,
                  __pp88888888888888888888888888888qq__
              __p888888888888888888888888888888888888888q_,
           _pp888888888888888888888888888888888888888888888qq,
         _p8888888888888888888888PP""""""""""""""YP88888888888q,
       _p888888888888888888P"'                        '"Y8888888q,
      _8888888888888888P"     .________________________,  '"888888,
     )88888888888888P"        |88888888888888888888888888qq_ "88888(
    _88888888888888"          |88888888888888888888888888888q, )8888,
    d8888888888888'           |8888888888888888888888888888888, O888b
    8888888888888'            |88888888888888888888888888888888 '8888
    8888888888888             |88888888888         Y88888888888. 8888
    d888888888888,            |88888888888         |88888888888  888P
    '888888888888p            |88888888888________p88888888888P )888'
     '888888888888q,          |888888888888888888888888888888P _888'
      '8888888888888p,        |8888888888888888888888888888P" _88P'
        "8888888888888q_      |888888888888888888888888P"" ._888"
          "88888888888888qq_, |888888888888888888888888qq_Y888"
            'Y8888888888888888|88888888888    "88888888888q/'
               '"8888888888888|88888888888|8888(888888888888,
                   '""88888888|88888888888|88888p888888888888_
                         ''"""|88888888888""""''  O88888888888p
                              |88888888888         Y88888888888p
                              |88888888888          )88888888888q,
                              |88888888888           )888888888888,

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                       ___ppppq88888888888qqqqq__,
                  __pp88888888888888888888888888888qq__
              __p888888888888888888888888888888888888888q_,
           _pp888888888888888888888888888888888888888888888qq,
         _p8888888888888888888888PP""""""""""""""YP88888888888q,
       _p888888888888888888P"'                        '"Y8888888q,
      _8888888888888888P"     .________________________,  '"888888,
     )88888888888888P"        |88888888888888888888888888qq_ "88888(
    _88888888888888"          |88888888888888888888888888888q, )8888,
    d8888888888888'           |8888888888888888888888888888888, O888b
    8888888888888'            |88888888888888888888888888888888 '8888
    8888888888888             |88888888888         Y88888888888. 8888
    d888888888888,            |88888888888         |88888888888  888P
    '888888888888p            |88888888888________p88888888888P )888'
     '888888888888q,          |888888888888888888888888888888P _888'
      '8888888888888_,        |8888888888888888888888888888P" _88P'
        "8888888888888q_      |888888888888888888888888P"" ._888"
          "88888888888888qq_  |8888888888888888888888888qpp888"
            'Y8888888888888888q88888888888    "888888888888P'
               '"8888888888888888888888888888888888888888888,
                   '""888888888888888888888888888888888888888_
                         ''"""Y88888888888P"""''  O88888888888p
                              |88888888888         Y88888888888p
                              |88888888888          )88888888888q,
                              |88888888888           )888888888888,

  '''

  @ink ~S"""

                       000000000000000000000000000
                  0000000000000000000000000000000000000
              000000000000000000000000000000000000000000000
           000000000000000000000000000000000000000000000000000
         0000000000000000000000000000000000000000000000000000022
       00000000000000000000000                        000002222222
      0000000000000000000     11111111111111111111111111  222222222
     00000000000000000        111111111111111111111111111111 2222222
    0000000000000000          11111111111111111111111111111111 222222
    000000000000000           111111111111111111111111111111111 22222
    00000000000000            111111111111111111111111111111111 22222
    0000000000000             111111111111         1111111111111 2222
    00000000000000            111111111111         111111111111  2222
    00000000000000            111111111111111111111111111111111 22222
     000000000000000          11111111111111111111111111111111 22222
      0000000000000000        1111111111111111111111111111111 22222
        0000000000000000      1111111111111111111111111111 222222
          000000000000002222  111111111111111111111111111122222
            000000000222222222211111111111    111111111111122
               0002222222222222111111111112222221111111111111
                   2222222222221111111111122222221111111111111
                         22222211111111111222222  1111111111111
                              111111111111         1111111111111
                              111111111111          11111111111111
                              111111111111           11111111111111

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
