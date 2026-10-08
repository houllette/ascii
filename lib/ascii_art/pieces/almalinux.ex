defmodule AsciiArt.Pieces.Almalinux do
  @moduledoc """
  Five coloured figures in a ring, scanned now and then.

  The AlmaLinux logo, five coloured figures in a ring, with a scan line
  running down it every few seconds that scrambles what it passes.

  Drawn from devicon's almalinux-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. On a canvas it takes the logo's colours, lifted on a dark
  page where they would sink into it; in a <pre> it is one ink, from devicon's
  almalinux-plain.svg (MIT). The logo is a trademark of its owner, shown here
  to name the distribution.

  Ported from `src/pieces/almalinux.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "almalinux",
    category: :distros,
    note: "five coloured figures in a ring, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#ff4546",
      "#0068d8",
      "#85d82e",
      "#ffc911",
      "#22c1ff",
      "#ff8687",
      "#599de6",
      "#b0e677",
      "#ffdc64",
      "#6fd7ff",
      "#ffc7c8",
      "#b3d2f3",
      "#daf3c0",
      "#ffefb8",
      "#bdecff",
      "#ff4546",
      "#0068d8",
      "#85d82e",
      "#ffc911",
      "#22c1ff",
      "#ff8687",
      "#599de6",
      "#b0e677",
      "#ffdc64",
      "#6fd7ff",
      "#ffc7c8",
      "#b3d2f3",
      "#daf3c0",
      "#ffefb8",
      "#bdecff"
    ]
  }

  # In one ink.
  @mono ~S'''

              _pq88q_                       ,
              8888888p _pq_       __p__  _p888q_
              8888888Pq88888.   _888888pq8888888,
              'Y8888(p88888"  _p88888888/8888888"
             qpqqqpp888888'  _8888888888q/8888P"
            q888888888888P   8888"   '88888qqqq,
            d88888P         |888'     '888888888
            '88888,         |88P       O8888888P
             '8888q,        |88'              '
           __, "8888q_,      88        ________
         _p888,  "Y8888qq_,  "8    _p88888888888qq,
         )88888q,   '"""YYYY' '  oPP""""""""Y888888q,
     _ppqq/888888p                            O88888p
    q888888p8888P          _p'  )q_           q88888P
    88888888d888         _p8P    "8q_      __8888P"___
    "888888\8888      __p88"      "88p   )888888\888888(
      """'q88888qqqppp888P'        O88p   O8888P88888888
          "888888888888P"          '888,  |8888b)888888P
           '"88888PP""    _pq,     .888p  |8888P '"PPP"
                     __pp88888q_,._p888P   ""'
                     888888888888888888"
                     '8888"""""8888888P
                         _p8888p"888P"
                        .8888888p
                         8888888P
                         'Y888P"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

              _pq88q_                       ,
              8888888p _pq_       __p__  _p888q_
              8888888Pq88888.   _888888pq8888888,
              'Y8888(p88888"  _p88888888/8888888"
             qpqqqpp888888'  _8888888888q/8888P"
            q888888888888P   8888"   '88888qqqq,
            d88888P         |888'     '888888888
            '88888,         |88P       O8888888P
             '8888q,        |88'              '
           __, "8888q_,      88        ________
         _p888,  "Y8888qq_,  "8    _p88888888888qq,
         )88888q,   '"""YYYY' '  oPP""""""""Y888888q,
     _ppqq/888888p                            O88888p
    q888888p8888P          _p'  )q_           q88888P
    88888888d888         _p8P    "8q_      __8888P"___
    "888888\8888      __p88"      "88p   )888888\888888(
      """'q88888qqqppp888P'        O88p   O8888P88888888
          "888888888888P"          '888,  |8888b)888888P
           '"88888PP""    _pq,     .888p  |8888P '"PPP"
                     __pp88888q_,._p888P   ""'
                     888888888888888888"
                     '8888"""""8888888P
                         _p8888p"888P"
                        .8888888p
                         8888888P
                         'Y888P"

  '''

  @ink ~S"""

              0000000                       3
              00000000 0000       33333  3333333
              000000000000000   33333333333333333
              00000000000000  3333333333333333333
             00000000000000  3333333333333333333
            00000000000000   33333   33333333333
            0000000         33333     3333333333
            0000000         3333       333333333
             0000000        3333              3
           111 00000000      33        22222222
         111111  0000000000  33    2222222222222222
         11111111   000000000 3  22222222222222222222
     1111111111111                            2222222
    1111111111111          111  444           2222222
    111111111111         1111    4444      22222222222
    111111111111      111111      4444   222222222222222
      111111111111111111111        4444   22222222222222
          111111111111111          44444  22222222222222
           11111111111    4444     44444  222222 222222
                     4444444444444444444   222
                     4444444444444444444
                     444444444444444444
                         4444444444444
                        444444444
                         44444444
                         4444444

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
