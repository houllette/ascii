defmodule AsciiArt.Pieces.Debian do
  @moduledoc """
  The red swirl, scanned now and then.

  The Debian logo, the swirl, with a scan line running down it every few
  seconds that scrambles what it passes.

  Drawn from devicon's debian-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. On a canvas it takes the logo's colours, lifted on a dark
  page where they would sink into it; in a <pre> it is one ink, from devicon's
  debian-plain.svg (MIT). The logo is a trademark of its owner, shown here to
  name the distribution.

  Ported from `src/pieces/debian.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "debian",
    category: :distros,
    note: "the red swirl, scanned now and then",
    cols: 46,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#a80030",
      "#c65978",
      "#e5b3c1",
      "#c20037",
      "#d7597d",
      "#edb3c3"
    ]
  }

  # In one ink.
  @mono ~S"""

                   _pppqq____q__
               _pp888888888888888qpqp,
            _p888888888PPPPYP8888888888q,
          _p8888888P"            "Y888888q,
         p888888"                   "888888p
     _  q888P"                        Y88888p
      _p88P"                           )888"O
    ,_888"             ._pp0OOo(,       O888 :
    'd88P             q8"'      ''      "888,
    q88P            .pP                  888,
    |88P            qP             ,     888"
    q88|            8|                  '88P
    |88'            8b           _.     q88'
    d88.            )8p      __        q88'
    |88p           ~,"8q,            _p8Y
    '88b            ""("8q__    __pq8P"
     d88,              "YdPP88888P""'
     '8888p                '"^^'
      "888q
       "888p
        '888p
          "88q,
           'Y88q_
             'Y88q,
                "Y8qq_
                   '"YOo___,

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                   __ppqq____q__
               _pp888888888888888qpqp,
            _p888888888PPPPYP8888888888q,
          _p8888888P"            "Y888888q,
         p888888"                   "888888p
     _  q8888"                        Y88888p
      _p888"                           )888"O
    ,_888"             ._pp0OOo(,       O888 :
    'd88P             q8"'      ''      "888,
    q888            .pP                  888,
    |88P            qP             ,     888"
    |88|            8|                  '88P
    |88'            8b           _.     q88'
    |88,            )8p      __        q88'
    |88p           ~,"8q,            _p8Y
    '88b            ""("8q__    __pq88"
     d88,              "YdPP88888PY"'
     '8888p                '"^^'
      "888q'
       "888p
        '888p
          "88q,
           'Y88q_
             'Y88q,
                "Y8qq_
                   '"YOo___,

  """

  @ink ~S"""

                   0000000000000
               00000000000000000000000
            00000000000000000000000000000
          00000000000            0000000000
         00000000                   00000000
     0  000000                        0000000
      000000                           000000
    000000             0000000000       0000 0
    00000             0000      00      00000
    0000            000                  0000
    0000            00             0     0000
    0000            00                  0000
    0000            00           00     0000
    0000            000      00        0000
    0000           000000            0000
    0000            00000000    0000000
     0000              00000000000000
     000000                00000
      000000
       00000
        00000
          00000
           000000
             000000
                000000
                   000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
