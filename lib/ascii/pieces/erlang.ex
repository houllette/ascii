defmodule Ascii.Pieces.Erlang do
  @moduledoc """
  The red e in brackets, glinting now and then.

  The Erlang logo, an e between brackets, with a glint crossing it every few
  seconds.

  Drawn from devicon's erlang-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from
  erlang-plain.svg. The logo is a trademark of its owner, shown here to name
  the language.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `Ascii.loop/1`).

  The picture is always 70 by 23.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "erlang: the red e in
  brackets, glinting now and then". A player's or a component's `label` gives
  words of your own, as "the Erlang logo".

  ## Example

  ```elixir
  still = Ascii.new!("erlang", options: %{shine: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("erlang", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {70, 23, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="erlang" label="the Erlang logo" />
  <Ascii.Phoenix.player socket={@socket} id="erlang" piece="erlang" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/erlang.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Logo

  @meta %Ascii.Meta{
    name: "erlang",
    category: :logos,
    note: "the red e in brackets, glinting now and then",
    cols: 70,
    rows: 23,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#ad0534",
      "#ca5d7b",
      "#e6b4c2",
      "#bc0538",
      "#d35d7e",
      "#ebb4c3"
    ],
    loop: 5
  }

  # In one ink.
  @mono ~S"""

    88888888"                    .__pqqq_,                   '88888888
    888888P'                   _p888888888q_                  '8888888
    88888P                   _p8888888888888p                   888888
    8888P                   .8888888888888888p                  "88888
    8888'                   d88888888888888888                   d8888
    888(                                                         '8888
    888                                                           8888
    88P                                                           8888
    88|                                                           8888
    88|                    .______________________________________8888
    88|                    |888888888888888888888888888888888888888888
    88|                    '888888888888888888888888888888888888888888
    88p                     888888888888888888888888888888888888888888
    888                     d88888888888888888888888888888888888888888
    888|                    '8888888888888888888888888888PY88888888888
    8888,                    "88888888888888888888888888"    "Y8888888
    8888p                     "88888888888888888888888P          "Y888
    88888p                     "88888888888888888888P'            _888
    888888q                      "888888888888888P"              q8888
    8888888q,                       ""Y88888PP"'               _p88888
    888888888q,                                               p8888888

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

    88888888"                     ___qq__                    '88888888
    888888P'                   _p888888888q_                  '8888888
    88888P                   _p8888888888888p                   888888
    8888P                   .8888888888888888p                  "88888
    8888'                   d88888888888888888                   d8888
    888(                                                         |8888
    888                                                           8888
    88P                                                           8888
    88|                                                           8888
    88|                    .______________________________________8888
    88|                    |888888888888888888888888888888888888888888
    88|                    '888888888888888888888888888888888888888888
    88b                     888888888888888888888888888888888888888888
    888                     d88888888888888888888888888888888888888888
    888|                    '8888888888888888888888888888""88888888888
    8888,                    "88888888888888888888888888"    ""8888888
    8888p                     "88888888888888888888888"          ""888
    88888p                     "88888888888888888888P'            _888
    888888q,                     "888888888888888P"              q8888
    8888888q,                       ""YP8888PP"'               _p88888
    888888888q                                                p8888888

  """

  @ink ~S"""

    000000000                     0000000                    000000000
    00000000                   0000000000000                  00000000
    000000                   0000000000000000                   000000
    00000                   000000000000000000                  000000
    00000                   000000000000000000                   00000
    0000                                                         00000
    000                                                           0000
    000                                                           0000
    000                                                           0000
    000                    0000000000000000000000000000000000000000000
    000                    0000000000000000000000000000000000000000000
    000                    0000000000000000000000000000000000000000000
    000                     000000000000000000000000000000000000000000
    000                     000000000000000000000000000000000000000000
    0000                    000000000000000000000000000000000000000000
    00000                    0000000000000000000000000000    000000000
    00000                     0000000000000000000000000          00000
    000000                     00000000000000000000000            0000
    00000000                     000000000000000000              00000
    000000000                       000000000000               0000000
    0000000000                                                00000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
