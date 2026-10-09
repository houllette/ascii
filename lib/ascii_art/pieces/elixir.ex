defmodule AsciiArt.Pieces.Elixir do
  @moduledoc """
  The purple drop, glinting now and then.

  The Elixir logo, a purple drop, with a glint crossing it every few seconds.

  Drawn from devicon's elixir-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is the same drawing. The
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

  The picture is always 38 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "elixir: the purple drop,
  glinting now and then". A player's or a component's `label` gives words of
  your own, as "the Elixir logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("elixir", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("elixir", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {38, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="elixir" label="the Elixir logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="elixir" piece="elixir" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/elixir.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "elixir",
    category: :logos,
    note: "the purple drop, glinting now and then",
    cols: 38,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#9c88ad",
      "#f4f3f4",
      "#664a78",
      "#cec5d7",
      "#816a92",
      "#46265c",
      "#afa2b9",
      "#bfb2ca",
      "#f8f7f8",
      "#9c89a7",
      "#dfd9e5",
      "#ad9eb8",
      "#877295",
      "#cbc3d2",
      "#e1dbe6",
      "#fcfbfc",
      "#d1c9d7",
      "#f0eef3",
      "#d9d2de",
      "#c8bece",
      "#e7e3ea",
      "#9c88ad",
      "#f4f3f4",
      "#715285",
      "#cec5d7",
      "#816a92",
      "#7d44a4",
      "#afa2b9",
      "#bfb2ca",
      "#f8f7f8",
      "#a38fb0",
      "#dfd9e5",
      "#ad9eb8",
      "#ab85c4",
      "#cbc3d2",
      "#e1dbe6",
      "#fcfbfc",
      "#d4cbda",
      "#f0eef3",
      "#d9d2de",
      "#d8c7e4",
      "#e7e3ea"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

                   __p|
                 _p888p
               _p888888
              q88888888,
            _q888888888p
           _888888888888,
          q88888888888888,
         q8888888888888888_
        q888888888888888888q,
       q888888888888888888888_
      \88888888888888888888888p,
      8888888888888888888888888p,
     q888888888888888888888888888p
    .88888888888888888888888888888q,
    |8888888888888888888888888888888,
    q88888888888888888888888888888888,
    888888888888888888888888888888888p
    d888888888888888888888888888888888
    |88888888888888888888888888888888O
    '88888888888888888888888888888888|
     )888888888888888888888888888888O
      Y8888888888888888888888888888O'
       "88888888888888888888888888P
         "8888888888888888888888P'
           "88888888888888OOOY"
              ""Y88888OYY""'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                   __p|
                 _p888p
               _p888888
              q88888888,
            _q888888888p
           _888888888888,
          q88888888888888,
         q8888888888888888_
        q888888888888888888q,
       q888888888888888888888_
      \88888888888888888888888p,
      8888888888888888888888888p,
     q888888888888888888888888888p
    .88888888888888888888888888888q,
    |8888888888888888888888888888888,
    q88888888888888888888888888888888,
    888888888888888888888888888888888p
    d888888888888888888888888888888888
    |88888888888888888888888888888888O
    '88888888888888888888888888888888|
     )888888888888888888888888888888O
      Y8888888888888888888888888888O'
       "88888888888888888888888888P
         "8888888888888888888888P'
           "88888888888888OOOY"
              ""Y88888OYY""'

  """

  @ink ~S"""

                   0000
                 550000
               55550004
              3555554444
            335555554444
           33555555554400
          0355555555554000
         035555555555225000
        033555555555525550000
       00355555555552555555011
      00035555555552222222222111
      444355522555522222222222211
     44445555525552222222222244222
    44444555555555222244442224442222
    444442555555554444444444444422222
    4444422555555544444444444000222222
    4444422225555524444444444222222222
    4444422222555522200222222222222222
    0422222222255222222222222222222226
    0002222222224222222222222222222666
     00000002224442222222222226666666
      0000000066666644444444443333333
       0000000666666664440440000000
         0000066666666666040000000
           00006166666600333333
              00001106333333

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
