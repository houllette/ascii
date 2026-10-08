defmodule AsciiArt.Pieces.Go do
  @moduledoc """
  Go with its speed lines, glinting now and then.

  The Go logo, the word GO with speed lines, with a glint crossing it every
  few seconds.

  Drawn from devicon's go-original-wordmark.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. On a canvas it takes the logo's colours, lifted on a dark
  page where they would sink into it; in a <pre> it is one ink, from the same
  drawing. The logo is a trademark of its owner, shown here to name the
  language.

  Ported from `src/pieces/go.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "go",
    category: :logos,
    note: "go with its speed lines, glinting now and then",
    cols: 79,
    rows: 16,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#00b0db",
      "#59cce8",
      "#b3e7f4",
      "#00b0db",
      "#59cce8",
      "#b3e7f4"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                                ._ppq888888qq__            __pppqqqqqqq_,
                             ._p888888888888888q_       _p888888888888888qq,
                           .p88888888888888888888q,   p888888888888888888888p
          _qqqqqqqqqqqq,  _8888888888PY^Y8888888888._8888888888PPYY8888888888q
         '"""""""""""""  q88888888"'       "8P"""' q88888888"'       "88888888p
    )88888888888888888  \8888888P     _____________8888888P            88888888
              _______   88888888     q88888888888888888888             |8888888
             YPPPPPPP' .8888888b    q88888888888888888888P             q8888888
                        88888888,   YPPPPPP888888888888888,           q8888888"
                        O88888888_       _p888888888888888q_       ._p8888888P
                        '8888888888qqqpp888888888"'8888888888qqqppp888888888"
                         'O88888888888888888888P'   Y888888888888888888888P'
                           "Y8888888888888888"'      'Y8888888888888888P"
                              ""88888888PP"'            ""888888888P""

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                                ._ppq888888qq__            __pppqqqqqqq_,
                             ._p888888888888888q_       _p888888888888888qq,
                           .p88888888888888888888q,   p888888888888888888888p
          _qqqqqqqqqqqq,  _8888888888PY^Y8888888888._8888888888PPYY8888888888q
         '"""""""""""""  q88888888"'       "8P"""' q88888888"'       "88888888p
    )88888888888888888  \8888888P     _____________8888888P            88888888
              _______   88888888     q88888888888888888888             |8888888
             YPPPPPPP' .8888888b    q88888888888888888888P             q8888888
                        88888888,   YPPPPPP888888888888888,           q8888888"
                        O88888888_       _p888888888888888q_       ._p8888888P
                        '8888888888qqqpp888888888"'8888888888qqqppp888888888"
                         'O88888888888888888888P'   Y888888888888888888888P'
                           "Y8888888888888888"'      'Y8888888888888888P"
                              ""88888888PP"'            ""888888888P""

  '''

  @ink ~S"""

                                000000000000000            00000000000000
                             00000000000000000000       00000000000000000000
                           000000000000000000000000   00000000000000000000000
          00000000000000  0000000000000000000000000000000000000000000000000000
         00000000000000  00000000000       0000000 00000000000       0000000000
    000000000000000000  000000000     000000000000000000000            00000000
              0000000   00000000     000000000000000000000             00000000
             000000000 000000000    0000000000000000000000             00000000
                        000000000   00000000000000000000000           000000000
                        0000000000       0000000000000000000       00000000000
                        00000000000000000000000000000000000000000000000000000
                         000000000000000000000000   000000000000000000000000
                           00000000000000000000      00000000000000000000
                              00000000000000            00000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
