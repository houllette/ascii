defmodule Ascii.Pieces.Haskell do
  @moduledoc """
  An angle, a lambda and an equals sign, glinting now and then.

  The Haskell logo, an angle, a lambda and an equals sign, with a glint
  crossing it every few seconds.

  Drawn from devicon's haskell-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from
  haskell-plain.svg. The logo is a trademark of its owner, shown here to name
  the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 69 by 25.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "haskell: an angle, a lambda
  and an equals sign, glinting now and then". A player's or a component's
  `label` gives words of your own, as "the Haskell logo".

  ## Example

  ```elixir
  still = Ascii.new!("haskell", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("haskell", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {69, 25, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="haskell" label="the Haskell logo" />
  <Ascii.Phoenix.player socket={@socket} id="haskell" piece="haskell" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/haskell.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "haskell",
    category: :logos,
    note: "an angle, a lambda and an equals sign, glinting now and then",
    cols: 69,
    rows: 25,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#463b63",
      "#5e5187",
      "#904f8c",
      "#87809a",
      "#968eb1",
      "#b78db4",
      "#c8c4d0",
      "#cfcbdb",
      "#decadd",
      "#665690",
      "#655791",
      "#904f8c",
      "#9c91b7",
      "#9b92b8",
      "#b78db4",
      "#d1ccde",
      "#d1cdde",
      "#decadd"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

    "88888888888,  "88888888888p
     "88888888888p  '88888888888q,
       O8888888888q,  "88888888888,
        "88888888888,  "88888888888p
         "88888888888p   88888888888q,
           O8888888888q,  "88888888888,
            "88888888888,  "88888888888p   ._________________________
             "88888888888p   88888888888q,  "888888888888888888888888
               O8888888888q,  "88888888888,  "88888888888888888888888
                "88888888888,  "88888888888p  '8888888888888888888888
                 "88888888888p   88888888888q,  "YYYYYYYYYYYYYYYYYYYY
                  .88888888888P   q88888888888,
                 _88888888888"  .p8888888888888p   ~qqqqqqqqqqqqqqqqq
                q88888888888"  _8888888888888888q,  "8888888888888888
              .p8888888888P   q8888888888888888888,  "888888888888888
             _88888888888"  .p888888888888888888888p   88888888888888
            q88888888888"  _88888888888" O8888888888q,  """""""""""""
          .p8888888888P   q88888888888"   "88888888888,
         _88888888888"  .p8888888888P      "88888888888p
        q88888888888"  _88888888888"         O8888888888q,
      .p8888888888P   q88888888888"           "88888888888,
     _88888888888"  .p8888888888P              "88888888888p
    )88888888888"  _88888888888"                 O8888888888q,

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

    "88888888888,  "88888888888p
     "88888888888p  '88888888888q,
       O8888888888q,  "88888888888,
        "88888888888,  "88888888888p
         "88888888888p   88888888888q,
           O8888888888q,  "88888888888,
            "88888888888,  "88888888888p   ._________________________
             "88888888888p   88888888888q,  "888888888888888888888888
               O8888888888q,  "88888888888,  "88888888888888888888888
                "88888888888,  "88888888888p  '8888888888888888888888
                 "88888888888p   88888888888q,  "YYYYYYYYYYYYYYYYYYYY
                  .88888888888P   q88888888888,
                 _88888888888"  .p8888888888888p   ~qqqqqqqqqqqqqqqqq
                q88888888888"  _8888888888888888q,  "8888888888888888
              .p8888888888P   q8888888888888888888,  "888888888888888
             _88888888888"  .p888888888888888888888p   88888888888888
            q88888888888"  _88888888888" O8888888888q,  """""""""""""
          .p8888888888P   q88888888888"   "88888888888,
         _88888888888"  .p8888888888P      "88888888888p
        q88888888888"  _88888888888"         O8888888888q,
      .p8888888888P   q88888888888"           "88888888888,
     _88888888888"  .p8888888888P              "88888888888p
    )88888888888"  _88888888888"                 O8888888888q,

  '''

  @ink ~S"""

    0000000000000  1111111111111
     0000000000000  11111111111111
       0000000000000  1111111111111
        0000000000000  1111111111111
         0000000000000   1111111111111
           0000000000000  1111111111111
            0000000000000  1111111111111   22222222222222222222222222
             0000000000000   1111111111111  2222222222222222222222222
               0000000000000  1111111111111  222222222222222222222222
                0000000000000  1111111111111  22222222222222222222222
                 0000000000000   1111111111111  222222222222222222222
                  0000000000000   1111111111111
                 0000000000000  1111111111111111   222222222222222222
                0000000000000  1111111111111111111  22222222222222222
              0000000000000   111111111111111111111  2222222222222222
             0000000000000  111111111111111111111111   22222222222222
            0000000000000  1111111111111 1111111111111  2222222222222
          0000000000000   1111111111111   1111111111111
         0000000000000  1111111111111      1111111111111
        0000000000000  1111111111111         1111111111111
      0000000000000   1111111111111           1111111111111
     0000000000000  1111111111111              1111111111111
    0000000000000  1111111111111                 1111111111111

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
