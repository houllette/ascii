defmodule Ascii.Pieces.Rust do
  @moduledoc """
  The r in its cog, in ferris orange, glinting now and then.

  The Rust logo, an R in a cog, in Ferris orange, with a glint crossing it
  every few seconds.

  Drawn from devicon's rust-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is the same drawing. The logo is a
  trademark of its owner, shown here to name the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 64 by 32.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "rust: the r in its cog, in
  ferris orange, glinting now and then". A player's or a component's `label`
  gives words of your own, as "the Rust logo".

  ## Example

  ```elixir
  still = Ascii.new!("rust", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("rust", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {64, 32, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="rust" label="the Rust logo" />
  <Ascii.Phoenix.player socket={@socket} id="rust" piece="rust" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/rust.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "rust",
    category: :logos,
    note: "the r in its cog, in ferris orange, glinting now and then",
    cols: 64,
    rows: 32,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#f74c00",
      "#fa8b59",
      "#fdc9b3",
      "#f74c00",
      "#fa8b59",
      "#fdc9b3"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                           qq_  _8q,  _p,
                     .pq_,_888qp8888qp888,__pq
                 p__ q88888888888P888888888888, _pq
                '888888888888888,  )888888888888888
            \qqqp888888888P""'"88qp88"'""Y888888888qppq,
            "888888888P"        "8P"        "Y888888888'
         pqqp888888P"                          "8888888qqqp
         888888888qq________________________     "88888888P
       .__88888888888888888888888888888888888q_    "888888__
      d8888888888888888888888888888888888888888q,   |88888888P
       Y8888888888888888888888888888888888888888b  .88888888"
    ._pp888   88p  8888888888        '"8888888888  p8|  |888qq_
    "888888qqp88P  8888888888        __888888888" '888qpp88888P'
      "88888P"'    888888888888888888888888888P'    '"Y888888"
    _p888888       88888888888888888888888888_         '888888q_
    "8888888       888888888888888888888888888q,     ___888888P"
      _88888,      8888888888      '"8888888888p     88888888_
    \p888888p......8888888888        '8888888888__._p888888888q,
     "Y888888888888888888888888888p   )888888888888888888888PY"
       q88888888888888888888888888b   '888888888888888888888p
      d888888888888888888888888888P    "888888888888888888888b
        '"888888P""""""""""""""""""      """"""""""8888888"'
         q8888888qpppqqp                    pqqqqp88888888p
         "^^Y888888P""88,                  q88""8888888Y^^"
            |888888_ _d8p                  88(  _888888,
            /8P^"888888888qqq__________ppq888888888"YP8"
                .8888888888888888888888888888888888
                 ""' )888888888888888888888888| """
                     '8P"'"888PY8888P8888"'"88
                           "P"  "88"  "8"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                           qq_  _8q,  _p,
                     .pq_,_888qp8888qp888,__pq
                 p__ q88888888888P888888888888, _pq
                '888888888888888,  )888888888888888
            \qqqp888888888P""'"88qp88"'""Y888888888qppq,
            "888888888P"        "8P"        "Y888888888'
         pqqp888888P"                          "8888888qqqp
         888888888qq________________________     "88888888P
       .__88888888888888888888888888888888888q_    "888888__
      d8888888888888888888888888888888888888888q,   |88888888P
       Y8888888888888888888888888888888888888888b  .88888888"
    ._pp888   88p  8888888888        '"8888888888  p8|  |888qq_
    "888888qqp88P  8888888888        __888888888" '888qpp88888P'
      "88888P"'    888888888888888888888888888P'    '"Y888888"
    _p888888       88888888888888888888888888_         '888888q_
    "8888888       888888888888888888888888888q,     ___888888P"
      _88888,      8888888888      '"8888888888p     88888888_
    \p888888p......8888888888        '8888888888__._p888888888q,
     "Y888888888888888888888888888p   )888888888888888888888PY"
       q88888888888888888888888888b   '888888888888888888888p
      d888888888888888888888888888P    "888888888888888888888b
        '"888888P""""""""""""""""""      """"""""""8888888"'
         q8888888qpppqqp                    pqqqqp88888888p
         "^^Y888888P""88,                  q88""8888888Y^^"
            |888888_ _d8p                  88(  _888888,
            /8P^"888888888qqq__________ppq888888888"YP8"
                .8888888888888888888888888888888888
                 ""' )888888888888888888888888| """
                     '8P"'"888PY8888P8888"'"88
                           "P"  "88"  "8"

  '''

  @ink ~S"""

                           000  0000  000
                     0000000000000000000000000
                 000 00000000000000000000000000 000
                00000000000000000  0000000000000000
            00000000000000000000000000000000000000000000
            000000000000        0000        000000000000
         000000000000                          000000000000
         00000000000000000000000000000000000     0000000000
       0000000000000000000000000000000000000000    000000000
      0000000000000000000000000000000000000000000   0000000000
       000000000000000000000000000000000000000000  0000000000
    0000000   000  0000000000        000000000000  000  0000000
    0000000000000  0000000000        000000000000 00000000000000
      000000000    00000000000000000000000000000    0000000000
    00000000       000000000000000000000000000         000000000
    00000000       00000000000000000000000000000     00000000000
      0000000      0000000000      0000000000000     000000000
    0000000000000000000000000        000000000000000000000000000
     000000000000000000000000000000   0000000000000000000000000
       0000000000000000000000000000   00000000000000000000000
      00000000000000000000000000000    00000000000000000000000
        000000000000000000000000000      0000000000000000000
         000000000000000                    000000000000000
         0000000000000000                  0000000000000000
            00000000 0000                  000  00000000
            00000000000000000000000000000000000000000000
                00000000000000000000000000000000000
                 000 00000000000000000000000000 000
                     0000000000000000000000000
                           000  0000  000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
