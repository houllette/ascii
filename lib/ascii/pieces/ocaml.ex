defmodule Ascii.Pieces.Ocaml do
  @moduledoc """
  The camel on an orange square, glinting now and then.

  The OCaml logo, a camel on an orange square, with a glint crossing it every
  few seconds.

  Drawn from devicon's ocaml-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from ocaml-plain.svg. The
  logo is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 64 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "ocaml: the camel on an
  orange square, glinting now and then". A player's or a component's `label`
  gives words of your own, as "the OCaml logo".

  ## Example

  ```elixir
  still = Ascii.new!("ocaml", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("ocaml", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {64, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="ocaml" label="the OCaml logo" />
  <Ascii.Phoenix.player socket={@socket} id="ocaml" piece="ocaml" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/ocaml.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "ocaml",
    category: :logos,
    note: "the camel on an orange square, glinting now and then",
    cols: 64,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#ee760a",
      "#f4a660",
      "#fad6b6",
      "#ee760a",
      "#f4a660",
      "#fad6b6"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S'''

       _pq888888888888888888888888888888888888888888888888qq_
     _88888888888888888888888888888888888888888888888888888888_
    q8888888888888888888888888888888888888888888888888888888888(
    88888888888888888888888888888888888888888888888888888888888b
    888888888888888888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888888888888888888
    888888P""Y8888888P"""Y88888888888888888888888888888888888888
    88888'    "88888P     '8888888888888888888888888888888888888
    8888"      '888P        8888888888888P"""""PPY88888888888888
    888"         "P'        '88888888888P            "8888888888
    8"                       "8888888888|           _ |888888888
                              'Y88888888       _ppq8888888888888
                                 '""YY"'      .88888888888888888
                                              p88888888888888888
                                            _p888888888888888888
       .__                               __p88888888888888888888
       q888q___          _,     :qqqqqpq888888888888888888888888
     .p8888888888qqp:  _p88q_   .8888888888888888888888888888888
    _88888888888888'  )888888q,  8888888888888888888888888888888
    88888888888888"  q88888888q  d888888888888888888888888888888
    8888888888888"  q8888888888p  888888888888888888888888888888
    888888888888b  _888888888888,  88888888888888888888888888888
    888888888888( q88888888888888, d8888888888888888888888888888
    888888888888 |8888888888888888,'8888888888888888888888888888
    '""YP888888" """""Y88888888888b "8PP""""""""""''"""^Y8888888

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

       _p88888888888888888888888888888888888888888888888888q_,
     _88888888888888888888888888888888888888888888888888888888_
    q8888888888888888888888888888888888888888888888888888888888p
    888888888888888888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888888888888888888
    888888888888888888888888888888888888888888888888888888888888
    888888P""Y8888888P"""Y88888888888888888888888888888888888888
    88888'    "88888P     '8888888888888888888888888888888888888
    8888"      '8888        88888888888888"""""PPY88888888888888
    888"         "P'        '88888888888P            "8888888888
    8"                       "8888888888|           . |888888888
                              'Y88888888       _ppp8888888888888
                                 '""YP"'      .88888888888888888
                                              q88888888888888888
                                            _p888888888888888888
       .__                               __p88888888888888888888
       d888q___          _,     .qqqqqpq888888888888888888888888
     .p8888888888qqp:  _p88q_   .8888888888888888888888888888888
    _88888888888888'  _888888q,  8888888888888888888888888888888
    88888888888888"  q88888888q  d888888888888888888888888888888
    8888888888888"  q8888888888p  888888888888888888888888888888
    888888888888b  _888888888888,  88888888888888888888888888888
    888888888888P q8888888888888q, d8888888888888888888888888888
    888888888888 |8888888888888888,'8888888888888888888888888888
    '""Y8888888P "^"""Y88888888888b "8PP"""""""""""""""YP8888888

  '''

  @ink ~S"""

       0000000000000000000000000000000000000000000000000000000
     0000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000
    000000    0000000     00000000000000000000000000000000000000
    00000      00000        000000000000000000000000000000000000
    0000         000        0000000000000            00000000000
    00                       000000000000           0 0000000000
                              0000000000       00000000000000000
                                 0000000      000000000000000000
                                              000000000000000000
                                            00000000000000000000
       000                               00000000000000000000000
       00000000          00     00000000000000000000000000000000
     0000000000000000  000000   00000000000000000000000000000000
    0000000000000000  000000000  0000000000000000000000000000000
    000000000000000  0000000000  0000000000000000000000000000000
    00000000000000  000000000000  000000000000000000000000000000
    0000000000000  00000000000000  00000000000000000000000000000
    0000000000000 0000000000000000 00000000000000000000000000000
    000000000000 00000000000000000000000000000000000000000000000
    000000000000 000000000000000000 0000000000000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
