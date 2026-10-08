defmodule AsciiArt.Pieces.Python do
  @moduledoc """
  Two snakes, blue and yellow, glinting now and then.

  The Python logo, two snakes, one blue and one yellow, with a glint crossing
  it every few seconds.

  Drawn from devicon's python-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. On a canvas it takes the logo's colours, lifted on a dark
  page where they would sink into it; in a <pre> it is one ink, from
  python-plain.svg. The logo is a trademark of its owner, shown here to name
  the language.

  Ported from `src/pieces/python.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "python",
    category: :logos,
    note: "two snakes, blue and yellow, glinting now and then",
    cols: 51,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#417fb0",
      "#ffe05c",
      "#336d9d",
      "#84accc",
      "#ffeb95",
      "#7aa0bf",
      "#c6d9e7",
      "#fff6ce",
      "#c2d3e2",
      "#417fb0",
      "#ffe05c",
      "#336d9d",
      "#84accc",
      "#ffeb95",
      "#7aa0bf",
      "#c6d9e7",
      "#fff6ce",
      "#c2d3e2"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''


                  __pppqq88888qqqqq_
                _p8888888888888888888p
                d88"  '888888888888888p
                888_, _8888888888888888
                88888888888888888888888
                """""""""""O88888888888
       _ppqq888888888888888888888888888 q8888qq_
     .p88888888888888888888888888888888 d8888888q,
     p888888888888888888888888888888888 d88888888b
    q888888888888888888888888888888888P 8888888888|
    d88888888888888888888888888888888P_p8888888888b
    8888888888888888PPPPPPPPPPPPPPY"_p8888888888888
    8888888888888"_ppqqqqqqqqqqqqq88888888888888888
    88888888888P.p888888888888888888888888888888888
    |8888888888 q888888888888888888888888888888888"
     888888888b 888888888888888888888888888888888P
      Y8888888b 88888888888888888888888888888888P
       '"YPPPPY 88888888888PPPPPPPPPPPPPPPPPPP"'
                88888888888qqqqqqqqqqqp
                88888888888888888888888
                8888888888888888'  "888
                "888888888888888_ .q88"
                 "O88888888888888888P"
                    ""Y88888888PP""


  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                _pppq888888888qqq_,",
           "              \\88888888888888888888p",
           "              d88'  '888888888888888p",
           "              888q___8888888888888888",
           "              88888888888888888888888",
           "              \"\"\"\"\"\"\"\"\"\"\"O88888888888",
           "     _pp88888888888888888888888888888 888888qq,",
           "   _p88888888888888888888888888888888 888888888,",
           "  .8888888888888888888888888888888888 888888888b",
           "  q888888888888888888888888888888888P.8888888888|",
           "  888888888888888888888888888888888\"_88888888888b",
           "  888888888888888P^\"\"\"\"\"\"\"\"\"\"\"\"\"\"'_p8888888888888",
           "  888888888888P\"_pp888888888888888888888888888888",
           "  O8888888888\"_p88888888888888888888888888888888P",
           "  \"8888888888 d888888888888888888888888888888888\"",
           "   O88888888b 888888888888888888888888888888888P",
           "    Y8888888b 88888888888888888888888888888888\"",
           "      \"\"YYYY\" 88888888888PYYYYYYYYYYYYYYYYY^\"",
           "              888888888888qqqqqqqqqqp",
           "              88888888888888888888888",
           "              8888888888888888   \"888",
           "              \"888888888888888___p88\"",
           "               'Y88888888888888888P'",
           "                  '\"\"YP8888PPY\"\"",
           "                  ..::::|||::::..",
           "                     '''''''''",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                  0000000000000000000
                0000000000000000000022
                0000  00000000000022222
                00000000000000002222222
                00000000000000022222222
                00000000000002222222222
       00000000000000000000222222222222 111111111
     0000000000000000000022222222222222 1111111111
    00000000000000000000222222222222222 1111111111
    00000000000000000022222222222222222111111111111
    00000000000000002222222222222222221111111111111
    00000000000000022222222222222222111111111111111
    00000000000000111111111111111111111111111111111
    00000000000011111111111111111111111111111111111
    00000000022 11111111111111111111111111111111111
     0000000222 1111111111111111111111111111111111
      000022222 111111111111111111111111111111111
        0222222 1111111111111111111111111111111
                11111111111111111111111
                11111111111111111111111
                1111111111111111   1111
                11111111111111111111111
                 111111111111111111111
                    11111111111111
                    000000000000000
                       000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
