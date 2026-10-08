defmodule AsciiArt.Pieces.Deepin do
  @moduledoc """
  The swirl in a blue ring, scanned now and then.

  The deepin logo, a swirl in a ring, with a scan line running down it every
  few seconds that scrambles what it passes.

  Drawn from Simple Icons' deepin.svg (CC0): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. On a canvas it takes the logo's colours, lifted on a dark page where
  they would sink into it; in a <pre> it is one ink, from the same drawing.
  The logo is a trademark of its owner, shown here to name the distribution.

  Ported from `src/pieces/deepin.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "deepin",
    category: :distros,
    note: "the swirl in a blue ring, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#007cff",
      "#59aaff",
      "#b3d8ff",
      "#007cff",
      "#59aaff",
      "#b3d8ff"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "                  .__ppq88888888qqqq__",
            "              __p8888888888888888888888q__",
            "           ._p88888888888888888P'   '\"Y888qq,",
            "         _p888\")8888888888888P          '\"888q_",
            "       _p88P\"  d88888888888P'           ._pp888q,",
            "      _888\"    88888888888\"         __pq888888888_",
            "     q88P      8888888888\"      _pp888888888888888p",
            "    q88\"       888888888'    _p88PP\"\"\"\"\"\"YY88888888p",
            "   q88\"        d8888888\"   _88\" )88\" q,       '\"\"888p",
            "  .88P         d888888P  _p8P\" q88P _8'q          888,",
            "  q88'         '888888' .P\"' _888\" .dP dp         \"88p",
            "  888           Y88888. |qpp888P' .p8\" d8,         888",
            "  88b            O8888| \"8888P\"  _p8P  88p         d88",
            "  88b             Y8888,  '    _p88P  \\88b         d88",
            "  888q_            \"8888qq___pp888\"  .d88P         888",
            "  d88888q_,          '\"88888888P\"   _p888\"        .88P",
            "  '88888888qq_,           '''     _p8888P         q88'",
            "   \"888888888888qq__,         __pp88888P         q88\"",
            "    Y8888888888888888888qqqq8888888888P         )88P",
            "     )888888888888888888888888888888P\"         q88P",
            "      \"888888888888888888888888888P'         _p88\"",
            "       'Y8888888888888888888888P\"          _p88P'",
            "         'Y88888888888888P^\"'           _pp88P'",
            "           '\"8888q__                __pp888\"'",
            "              '\"88888qqqq______pppp8888P\"'",
            "                  '\"\"Y88888888888PP\"\"'",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                  .__ppq88888888qqqq__",
           "              __p8888888888888888888888q__",
           "           ._p88888888888888888P'   '\"Y888qq,",
           "         _p888\")8888888888888P          '\"888q_",
           "       _p88P\"  d88888888888P'           ._pp888q,",
           "      _888\"    88888888888\"         __pq888888888_",
           "     q88P      8888888888\"      _pp888888888888888p",
           "    q88\"       888888888'    _p88PP\"\"\"\"\"\"YY88888888p",
           "   q88\"        d8888888\"   _88\" )88\" q,       '\"\"888p",
           "  .88P         d888888P  _p8P\" q88P _8'q          888,",
           "  q88'         '888888' .P\"' _888\" .dP dp         \"88p",
           "  888           Y88888. |qpp888P' .p8\" d8,         888",
           "  88b            O8888| \"8888P\"  _p8P  88p         d88",
           "  88b             Y8888,  '    _p88P  \\88b         d88",
           "  888q_            \"8888qq___pp888\"  .d88P         888",
           "  d88888q_,          '\"88888888P\"   _p888\"        .88P",
           "  '88888888qq_,           '''     _p8888P         q88'",
           "   \"888888888888qq__,         __pp88888P         q88\"",
           "    Y8888888888888888888qqqq8888888888P         )88P",
           "     )888888888888888888888888888888P\"         q88P",
           "      \"888888888888888888888888888P'         _p88\"",
           "       'Y8888888888888888888888P\"          _p88P'",
           "         'Y88888888888888P^\"'           _pp88P'",
           "           '\"8888q__                __pp888\"'",
           "              '\"88888qqqq______pppp8888P\"'",
           "                  '\"\"Y88888888888PP\"\"'",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000000000000000   000000000
           000000000000000000000          0000000
         000000  00000000000000           000000000
        00000    000000000000         00000000000000
       0000      00000000000      0000000000000000000
      0000       0000000000    00000000000000000000000
     0000        000000000   0000 0000 00       0000000
    0000         00000000  00000 0000 0000          0000
    0000         00000000 0000 00000 000 00         0000
    000           0000000 000000000 0000 000         000
    000            000000 0000000  0000  000         000
    000             000000  0    00000  0000         000
    00000            0000000000000000  00000         000
    000000000          000000000000   000000        0000
    0000000000000           000     0000000         0000
     000000000000000000         0000000000         0000
      00000000000000000000000000000000000         0000
       000000000000000000000000000000000         0000
        000000000000000000000000000000         00000
         00000000000000000000000000          000000
           00000000000000000000           0000000
             000000000                000000000
                0000000000000000000000000000
                    00000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
