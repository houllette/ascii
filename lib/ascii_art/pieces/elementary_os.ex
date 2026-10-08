defmodule AsciiArt.Pieces.ElementaryOs do
  @moduledoc """
  The e in a ring, scanned now and then.

  The elementary OS logo, an e in a ring, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from Simple Icons' elementary.svg (CC0): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. On a canvas it takes the logo's colours, lifted on a dark page where
  they would sink into it; in a <pre> it is one ink, from the same drawing.
  The logo is a trademark of its owner, shown here to name the distribution.

  Ported from `src/pieces/elementary-os.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "elementary os",
    category: :distros,
    note: "the e in a ring, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#64baff",
      "#9ad2ff",
      "#d1eaff",
      "#64baff",
      "#9ad2ff",
      "#d1eaff"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "                  __pppq88888888qqqq__",
            "              __p888PP\"\"\"''''''\"\"\"Y8888q_,",
            "           _pp88P\"'      _______     '\"Y88qq,",
            "         _p88P\"      _pp8PP^^Y888q_      'Y88q,",
            "       _p88\"      _p88\"'        'Y88_       \"88q,",
            "      _88P      _p8P\"             \"88p        \"88_",
            "     q88\"      p88\"                |88,        \"88p",
            "    q8P'     _p88\"                  88|         '88p",
            "   q88'     .888\"                  .88'          '88p",
            "  .88\"      q88\"                   q8P            \"88,",
            "  q8P      |88P                   q88            .p88p",
            "  88|      d88|                  q8P'           _p8888",
            "  88|      888'                _p8P            _88\"|88",
            "  88|      888,              _p8P\"           _p88\" |88",
            "  88|      )88p            _p88\"            q88P   |88",
            "  d8b       888,         _p88\"            _88P\"    d8P",
            "  '88,      '888_    ._p88P\"           _p888\"     \\88'",
            "   )88,      '888q_pp88P\"           ._p88P\"      .88(",
            "    Y8q,   ___p888888_,         __pp888P'       .p8P",
            "     Y88q888888P\"\"O88888qqqqpp88888P\"'         _88P",
            "      \"888\"\"\"       '\"YP888888P\"\"'            q88\"",
            "       'Y88_                                _88P'",
            "         'Y88q_                          _p88P'",
            "           '\"888q_,                  __p888\"'",
            "              '\"8888qq____________pp888P\"'",
            "                  '\"\"Y888888888888P\"\"'",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                  __pppq88888888qqqq__",
           "              __p888PP\"\"\"''''''\"\"\"Y8888q_,",
           "           _pp88P\"'      _______     '\"Y88qq,",
           "         _p88P\"      _pp8PP^^Y888q_      'Y88q,",
           "       _p88\"      _p88\"'        'Y88_       \"88q,",
           "      _88P      _p8P\"             \"88p        \"88_",
           "     q88\"      p88\"                |88,        \"88p",
           "    q8P'     _p88\"                  88|         '88p",
           "   q88'     .888\"                  .88'          '88p",
           "  .88\"      q88\"                   q8P            \"88,",
           "  q8P      |88P                   q88            .p88p",
           "  88|      d88|                  q8P'           _p8888",
           "  88|      888'                _p8P            _88\"|88",
           "  88|      888,              _p8P\"           _p88\" |88",
           "  88|      )88p            _p88\"            q88P   |88",
           "  d8b       888,         _p88\"            _88P\"    d8P",
           "  '88,      '888_    ._p88P\"           _p888\"     \\88'",
           "   )88,      '888q_pp88P\"           ._p88P\"      .88(",
           "    Y8q,   ___p888888_,         __pp888P'       .p8P",
           "     Y88q888888P\"\"O88888qqqqpp88888P\"'         _88P",
           "      \"888\"\"\"       '\"YP888888P\"\"'            q88\"",
           "       'Y88_                                _88P'",
           "         'Y88q_                          _p88P'",
           "           '\"888q_,                  __p888\"'",
           "              '\"8888qq____________pp888P\"'",
           "                  '\"\"Y888888888888P\"\"'",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             00000000      0000000     00000000
           000000      00000000000000      000000
         00000      000000        00000       00000
        0000      00000             0000        0000
       0000      0000                0000        0000
      0000     00000                  000         0000
     0000     00000                  0000          0000
    0000      0000                   000            0000
    000      0000                   000            00000
    000      0000                  0000           000000
    000      0000                0000            0000000
    000      0000              00000           00000 000
    000      0000            00000            0000   000
    000       0000         00000            00000    000
    0000      00000    0000000           000000     0000
     0000      000000000000           0000000      0000
      0000   000000000000         000000000       0000
       000000000000000000000000000000000         0000
        0000000       00000000000000            0000
         00000                                00000
           000000                          000000
             00000000                  00000000
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
