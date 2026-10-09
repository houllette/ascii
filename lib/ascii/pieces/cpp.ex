defmodule Ascii.Pieces.Cpp do
  @moduledoc """
  C++ on a blue hexagon, glinting now and then.

  C++: the C++ logo, a C and two plus signs on a hexagon, with a glint
  crossing it every few seconds.

  Drawn from devicon's cplusplus-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from
  cplusplus-plain.svg. The logo is a trademark of its owner, shown here to
  name the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 50 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "c++: c++ on a blue hexagon,
  glinting now and then". A player's or a component's `label` gives words of
  your own, as "the C++ logo".

  ## Example

  ```elixir
  still = Ascii.new!("cpp", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("cpp", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {50, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="cpp" label="the C++ logo" />
  <Ascii.Phoenix.player socket={@socket} id="cpp" piece="cpp" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/cpp.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "c++",
    category: :logos,
    note: "c++ on a blue hexagon, glinting now and then",
    cols: 50,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#659ad2",
      "#ffffff",
      "#004482",
      "#00599c",
      "#9bbde2",
      "#ffffff",
      "#5985ae",
      "#5993bf",
      "#d1e1f2",
      "#ffffff",
      "#b3c7da",
      "#b3cde1",
      "#659ad2",
      "#ffffff",
      "#005fb5",
      "#0062ab",
      "#9bbde2",
      "#ffffff",
      "#5997cf",
      "#5999c8",
      "#d1e1f2",
      "#ffffff",
      "#b3cfe9",
      "#b3d0e6"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                       _pp88qq_
                   __p8888888888q_,
                _pp8888888888888888qq_
            __p888888888888888888888888q_,
         _pp888888888888888888888888888888qq_
     ._p88888888888888PP""""""Y888888888888888q_,
    )8888888888888P"'            '"Y8888888888888(
    888888888888"                    "888888888888
    8888888888P                        Y8888888888
    888888888"        __ppqqqq_,     ._p8888888888
    88888888P       _p8888888888q,_pp8888888888888
    88888888       .888888888888888888888888888888
    8888888b       q88888888888888888PY "P8PP" P88
    8888888b       d88888888888888888qp \q8bq, qp8
    88888888,      '8888888888888888888qp8888qq888
    88888888p       '88888888888P''"88888888888888
    888888888(        '"Y8888P"'      "Y8888888888
    8888888888q,                      .p8888888888
    888888888888_,                  ._888888888888
    "8888888888888q_,            __p8888888888888"
      "888888888888888qqq____ppp88888888888888P"
         "Y88888888888888888888888888888888P"
            '"8888888888888888888888888P"'
                "Y888888888888888888P"
                   '"88888888888P"'
                       "Y8888P"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                       _pp88qq_
                   __p8888888888q_,
                _pp8888888888888888qq_
            __p888888888888888888888888q_,
         _pp888888888888888888888888888888qq_
     ._p88888888888888888888888888888888888888q_,
    )88888888888888888888888888888888888888888888(
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888
    "88888888888888888888888888888888888888888888"
      "888888888888888888888888888888888888888P"
         "Y88888888888888888888888888888888P"
            '"8888888888888888888888888P"'
                "Y888888888888888888P"
                   '"88888888888P"'
                       "Y8888P"

  """

  @ink ~S"""

                       00000000
                   0000000000000000
                0000000000000000000000
            000000000000000000000000000000
         000000000000000000000000000000000000
     00000000000000000001111110000000000000000000
    0000000000000001111111111111111000000000000003
    0000000000001111111111111111111111000000003333
    0000000000011111111111111111111111100003333333
    0000000001111111111100000011111111133333333333
    0000000001111111100000000000011133333333333333
    0000000011111111000000000000333333333333333333
    0000000011111110000000000333333333311333311333
    0000000011111110000002222333333333311333311333
    0000000011111111002222222222333333333333333333
    0000000001111111122222222222211133333333333333
    0000000001111111111122222211111111133333333333
    0000000222211111111111111111111111122223333333
    0000222222221111111111111111111111222222223333
    0222222222222221111111111111111222222222222223
      222222222222222222111111222222222222222222
         222222222222222222222222222222222222
            222222222222222222222222222222
                2222222222222222222222
                   2222222222222222
                       22222222

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
