defmodule AsciiArt.Pieces.KaliLinux do
  @moduledoc """
  The blue dragon, scanned now and then.

  The Kali Linux logo, the dragon, with a scan line running down it every few
  seconds that scrambles what it passes.

  Drawn from devicon's kalilinux-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. On a canvas it takes the logo's colours, lifted on a dark
  page where they would sink into it; in a <pre> it is one ink, from the same
  drawing. The logo is a trademark of its owner, shown here to name the
  distribution.

  Ported from `src/pieces/kali-linux.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "kali linux",
    category: :distros,
    note: "the blue dragon, scanned now and then",
    cols: 71,
    rows: 27,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#287aff",
      "#73a9ff",
      "#bfd7ff",
      "#287aff",
      "#73a9ff",
      "#bfd7ff"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "       ''''\"\"\"\"\"\"^YYY0bqqqq___,",
            "                          '\"\"^Y88qq__",
            "                ___________________\"Y8p",
            "       __,ooOYYY\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"YY/b",
            "  .'\"'''                 .___pppp88888O,        .",
            "                   __pp88PY\"\"\"'        8p,       ':-_",
            "              ._pdP\"\"'                 _888qqqqqq___'\"~_",
            "           _oY\"\"                     p88P\"\"\"\"\"\"\"Y888qp_|Y_",
            "        .\"\"                        _88\"             \"\"888qq,",
            "                                   d8\"                  \"888_",
            "                                  :88                    '\"Y8q_",
            "                                  '88,                       \"P\"",
            "                                   88q,",
            "                                    O88_,",
            "                                     \"888qq_______,",
            "                                        \"\"Y888888888888qpq__,",
            "                                                    ''\"^88q/Y0q_",
            "                                                          \"Yq_ \"Oq,",
            "                                                            'Oq, 'O_",
            "                                                              \"q,  \"(",
            "                                                               \"b   )",
            "                                                                ),",
            "                                                                 \\",
            "                                                                 |",
            "                                                                  '",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "       ''''\"\"\"\"\"\"^YYY0bqqqq___,",
           "                          '\"\"^Y88qq__",
           "                ___________________\"Y8p",
           "       __,ooOYYY\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"YY/b",
           "  .'\"'''                 .___pppp88888O,        .",
           "                   __pp88PY\"\"\"'        8p,       ':-_",
           "              ._pdP\"\"'                 _888qqqqqq___'\"~_",
           "           _oY\"\"                     p88P\"\"\"\"\"\"\"Y888qp_|Y_",
           "        .\"\"                        _88\"             \"\"888qq,",
           "                                   d8\"                  \"888_",
           "                                  :88                    '\"Y8q_",
           "                                  '88,                       \"P\"",
           "                                   88q,",
           "                                    O88_,",
           "                                     \"888qq_______,",
           "                                        \"\"Y888888888888qpq__,",
           "                                                    ''\"^88q/Y0q_",
           "                                                          \"Yq_ \"Oq,",
           "                                                            'Oq, 'O_",
           "                                                              \"q,  \"(",
           "                                                               \"b   )",
           "                                                                ),",
           "                                                                 \\",
           "                                                                 |",
           "                                                                  '",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

         000000000000000000000000
                            00000000000
                  00000000000000000000000
         00000000000000000000000000000000
    000000                 000000000000000        0
                     000000000000        000       0000
                00000000                 00000000000000000
             00000                     000000000000000000000
          000                        0000             00000000
                                     000                  00000
                                    000                    000000
                                    0000                       000
                                     0000
                                      00000
                                       00000000000000
                                          000000000000000000000
                                                      000000000000
                                                            0000 0000
                                                              0000 000
                                                                000  00
                                                                 00   0
                                                                  00
                                                                   0
                                                                   0
                                                                    0

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
