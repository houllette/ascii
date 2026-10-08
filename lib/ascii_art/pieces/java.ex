defmodule AsciiArt.Pieces.Java do
  @moduledoc """
  The steaming cup, glinting now and then.

  The Java logo, a steaming cup, with a glint crossing it every few seconds.

  Drawn from devicon's java-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. On a canvas it takes the logo's colours, lifted on a dark page where
  they would sink into it; in a <pre> it is one ink, from java-plain.svg. The
  logo is a trademark of its owner, shown here to name the language.

  Ported from `src/pieces/java.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "java",
    category: :logos,
    note: "the steaming cup, glinting now and then",
    cols: 42,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#ef2e2f",
      "#0077c1",
      "#f57778",
      "#59a7d7",
      "#fac0c1",
      "#b3d6ec",
      "#ef2e2f",
      "#0077c1",
      "#f57778",
      "#59a7d7",
      "#fac0c1",
      "#b3d6ec"
    ],
    loop: 5
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "                          \\",
            "                          dp",
            "                         .8P",
            "                        _p8",
            "                      _p8P'",
            "                    _p88\"    __-",
            "                 _p88P\"  __pP\"",
            "               _p88P'  _p8\"'",
            "              \\888\"  _p8P",
            "              d88'   d88,",
            "              \"88,   888q,",
            "               \"8p   '8888,",
            "                 Yq,   Y888",
            "                  'Y(   d8\"",
            "        .__p=^'        )P'       ^\"\"Oqq,",
            "      q888__________________pp='     \"88",
            "       '\"\"\"\"^YYYYYYY^\"\"\"\"\"''         q8P",
            "          _p/              _       _p8\"",
            "          \"888qqqqqqqppq88888=  _)P\"\"",
            "              '\"\"\"\"\"\"\"\"''",
            "           .pq____,..______,",
            "        _,  \"88888888888888P\"",
            "  ._pd^\"''       ''''''             _p",
            "  8888qq_______,......_________ppod^\"  _",
            "     '\"\"\"\"\"^YYPPPPPPPPPPY^\"\"\"\"' ___pp0\"'",
            "         '^^==ooooooooooood00OPP\"\"\"'",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                          \\",
           "                          dp",
           "                         .8P",
           "                        _p8",
           "                      _p8P'",
           "                    _p88\"    __-",
           "                 _p88P\"  __pP\"",
           "               _p88P'  _p8\"'",
           "              \\888\"  _p8P",
           "              d88'   d88,",
           "              \"88,   888q,",
           "               \"8p   '8888,",
           "                 Yq,   Y888",
           "                  'Y(   d8\"",
           "        .__p=^'        )P'       ^\"\"Oqq,",
           "      q888__________________pp='     \"88",
           "       '\"\"\"\"^YYYYYYY^\"\"\"\"\"''         q8P",
           "          _p/              _       _p8\"",
           "          \"888qqqqqqqppq88888=  _)P\"\"",
           "              '\"\"\"\"\"\"\"\"''",
           "           .pq____,..______,",
           "        _,  \"88888888888888P\"",
           "  ._pd^\"''       ''''''             _p",
           "  8888qq_______,......_________ppod^\"  _",
           "     '\"\"\"\"\"^YYPPPPPPPPPPY^\"\"\"\"' ___pp0\"'",
           "         '^^==ooooooooooood00OPP\"\"\"'",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                            0
                            00
                           000
                          000
                        00000
                      00000    000
                   000000  00000
                 000000  00000
                00000  0000
                0000   0000
                0000   00000
                 000   000000
                   000   0000
                    000   000
          1111111        000       1111111
        11111111111111111111111111     111
         111111111111111111111         111
            111              1       1111
            11111111111111111111  11111
                11111111111
             11111111111111111
          11  11111111111111111
    11111111       111111             11
    11111111111111111111111111111111111  1
       11111111111111111111111111 11111111
           111111111111111111111111111

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
