defmodule AsciiArt.Pieces.Ubuntu do
  @moduledoc """
  The circle of friends, in orange, scanned now and then.

  The Ubuntu logo, the circle of friends, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from Simple Icons' ubuntu.svg (CC0): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. On a canvas it takes the logo's colours, lifted on a dark page where
  they would sink into it; in a <pre> it is one ink, from the same drawing.
  The logo is a trademark of its owner, shown here to name the distribution.

  Ported from `src/pieces/ubuntu.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "ubuntu",
    category: :distros,
    note: "the circle of friends, in orange, scanned now and then",
    cols: 58,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#e95420",
      "#f1906e",
      "#f8ccbc",
      "#e95420",
      "#f1906e",
      "#f8ccbc"
    ]
  }

  # In one ink.
  @mono ~S'''

                         .___pppqq/   ._p88888qq,
                     _pp888888888P   q88888888888q,
                  _p8888888888888   q8888888888888q
               _p888888888888PPP"   888888888888888|
             _p888888888P"'         888888888888888'
            _88888888"'             "8888888888888P
           d8888888"                 "88888888888"   pp
               '""                     '"YPPPP"'   _p88p
        __pqqq_,                                 ~p88888(
     _p888888888q_                                O888888,
    _8888888888888p                                888888p
    888888888888888,                               d888888
    888888888888888|                               |888888
    d88888888888888                                |888888
     Y88888888888P'                                q888888
      '"8888888P"                                 .888888P
           '                                      q888888
         .____ppp                                q888888"
          Y888888q,                  ._pppqqq_   '88888"
           )8888888q,              .p8888888888p   "88"
            "88888888q_           _8888888888888q   "'
              "888888888q__,      q88888888888888p
                "888888888888qp   888888888888888P
                  "Y88888888888,  "88888888888888'
                     '"Y8888888b,  "88888888888P'
                           '""""^    "Y888888P"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                         .___pppqq/   ._p88888qq,
                     _pp888888888P   q88888888888q,
                  _p8888888888888   q8888888888888q
               _p888888888888PPP"   888888888888888|
             _p888888888P"'         888888888888888'
            _88888888"'             "8888888888888P
           d8888888"                 "88888888888"   pp
               '""                     '"YPPPP"'   _p88p
        __pqqq_,                                 ~p88888(
     _p888888888q_                                O888888,
    _8888888888888p                                888888p
    888888888888888,                               d888888
    888888888888888|                               |888888
    d88888888888888                                |888888
     Y88888888888P'                                q888888
      '"8888888P"                                 .888888P
           '                                      q888888
         .____ppp                                q888888"
          Y888888q,                  ._pppqqq_   '88888"
           )8888888q,              .p8888888888p   "88"
            "88888888q_           _8888888888888q   "'
              "888888888q__,      q88888888888888p
                "888888888888qp   888888888888888P
                  "Y88888888888,  "88888888888888'
                     '"Y8888888b,  "88888888888P'
                           '""""^    "Y888888P"

  '''

  @ink ~S"""

                         0000000000   00000000000
                     0000000000000   00000000000000
                  000000000000000   000000000000000
               000000000000000000   0000000000000000
             00000000000000         0000000000000000
            00000000000             000000000000000
           000000000                 0000000000000   00
               000                     000000000   00000
        00000000                                 00000000
     0000000000000                                00000000
    000000000000000                                0000000
    0000000000000000                               0000000
    0000000000000000                               0000000
    000000000000000                                0000000
     00000000000000                                0000000
      00000000000                                 00000000
           0                                      0000000
         00000000                                00000000
          000000000                  000000000   0000000
           0000000000              0000000000000   0000
            00000000000           000000000000000   00
              00000000000000      0000000000000000
                000000000000000   0000000000000000
                  00000000000000  0000000000000000
                     000000000000  00000000000000
                           000000    0000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
