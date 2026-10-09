defmodule AsciiArt.Pieces.Go do
  @moduledoc """
  Go with its speed lines, glinting now and then.

  The Go logo, the word GO with speed lines, with a glint crossing it every
  few seconds.

  Drawn from devicon's go-original-wordmark.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is the same drawing. The
  logo is a trademark of its owner, shown here to name the language.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `AsciiArt.loop/1`).

  The picture is always 79 by 16.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "go: go with its speed lines,
  glinting now and then". A player's or a component's `label` gives words of
  your own, as "the Go logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("go", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("go", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {79, 16, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="go" label="the Go logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="go" piece="go" options={%{shine: 10}} />
  ```

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
