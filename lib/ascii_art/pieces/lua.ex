defmodule AsciiArt.Pieces.Lua do
  @moduledoc """
  A planet and its moon, glinting now and then.

  The Lua logo, a moon beside a planet lettered Lua, with a glint crossing it
  every few seconds.

  Drawn from devicon's lua-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. On a canvas it takes the logo's colours, lifted on a dark page where
  they would sink into it; in a <pre> it is one ink, from lua-plain.svg. The
  logo is a trademark of its owner, shown here to name the language.

  Ported from `src/pieces/lua.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "lua",
    category: :logos,
    note: "a planet and its moon, glinting now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#818186",
      "#ffffff",
      "#000080",
      "#adadb0",
      "#ffffff",
      "#5959ac",
      "#d9d9db",
      "#ffffff",
      "#b3b3d9",
      "#818186",
      "#ffffff",
      "#3e3eff",
      "#adadb0",
      "#ffffff",
      "#8282ff",
      "#d9d9db",
      "#ffffff",
      "#c5c5ff"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

                      ~o= '""  """ :o-        _ppqqqq_
                  ="'                   "=  _p88888888q,
              ~Y'                           d8888888888p
           _p         __ppq888888qqq__      88888888888P
           "      __p888888888888888888qq,  "8888888888'
        _Y      _p888888888888888888888888q_  "88888P"
              _p888888888888888888P"'   ""88q_
      p"     q8888888888888888888"         O88p     '(
            p8888888888888888888P           888q     '
    .P     q88888888888888888888p          .8888p     q,
          |8888888888888888888888p        _p88888,    ''
    p     d88888P"88888888888888888q____pp8888888b     q
    "     888888P 88888888888888888888888888888888     "
    p     888888P 88888888")8888")888""__""8888888     _
    "     d88888P 88888888||8888||88_p8888 d88888P     O
    _,    "88888P 88888888||8888||888P""__ d88888"     ,
    'b     O8888P 88888888||8888'|88 q8888 d8888P     d'
      ,     8888P """""")8p,"^"_,|88_"^Y"_,"888P
      ).     Y888888888888888q88888888q8888q88P     _P
        _     "888888888888888888888888888888"
        "(      "88888888888888888888888888"      )"
          ._      '"88888888888888888888"'      _
           '"         ""Y8888888888P""         ^'
              "o                           _o^
                  o(                   _p=
                      ^Y: .__  __. ~Y"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                      ~o=  ""  """ :o~        _pp88qq_
                  ="'                   "=  _p88888888q,
              ~Y'                           d8888888888p
           _p         __ppq888888qqq__      88888888888P
           "      _pp888888888888888888qq,  "8888888888'
        _(      _p888888888888888888888888q_  "88888P"
              _p8888888888888888888888888888q_
      p"     q88888888888888888888888888888888p     'q
            p8888888888888888888888888888888888q     '
    .P     q888888888888888888888888888888888888p     q,
          |88888888888888888888888888888888888888,    ''
    p     d88888888888888888888888888888888888888b     q
    "     8888888888888888888888888888888888888888     "
    /     8888888888888888888888888888888888888888     _
    "     d88888888888888888888888888888888888888P     O
    _,    "88888888888888888888888888888888888888"
    'b     O888888888888888888888888888888888888P     d'
      ,     88888888888888888888888888888888888P
      ).     Y88888888888888888888888888888888P     _P
        _     "888888888888888888888888888888"
        "(      "8888888888888888888888888P"      )"
          ._      '"88888888888888888888"'      _
           '"         ""Y888888888PP""         ^'
              ^o                           _o"
                  =(                   _)=
                      ^Y: .__  __. ~Y"

  '''

  @ink ~S"""

                      000  00  000 000        22222222
                  000                   00  222222222222
              000                           222222222222
           00         2222222222222222      222222222222
           0      222222222222222222222222  222222222222
        00      2222222222222222222222222222  22222222
              22222222222222222222211111112222
      00     2222222222222222222211111111112222     00
            222222222222222222221111111111112222     0
    00     22222222222222222222221111111111122222     00
          2222222222222222222222211111111112222222    00
    0     2222222122222222222222222211111222222222     0
    0     2222222122222222222222222222222222222222     0
    0     2222222122222222122222122221111112222222     0
    0     2222222122222222112222112211222212222222     0
    00    2222222122222222112222112222111112222222
    00     22222212222222211222211221122221222222     00
      0     222221111111222112111122111211112222
      00     2222222222222222222222222222222222     00
        0     22222222222222222222222222222222
        00      2222222222222222222222222222      00
          00      222222222222222222222222      0
           00         2222222222222222         00
              00                           000
                  00                   000
                      000 000  000 000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
