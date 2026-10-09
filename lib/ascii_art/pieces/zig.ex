defmodule AsciiArt.Pieces.Zig do
  @moduledoc """
  The slanted z in brackets, glinting now and then.

  The Zig logo, a slanted Z between brackets, with a glint crossing it every
  few seconds.

  Drawn from devicon's zig-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is the same drawing. The logo is a
  trademark of its owner, shown here to name the language.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `shine` - seconds from one glint to the next, 0 to 3600; default 5. A
      glint takes two seconds to cross the logo, so it comes at most every two
      and a half; 0 keeps the logo still. At the default the piece closes a
      loop every 5 seconds, which a player draws once and repeats (see
      `AsciiArt.loop/1`).

  The picture is always 61 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the glint lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "zig: the slanted z in
  brackets, glinting now and then". A player's or a component's `label` gives
  words of your own, as "the Zig logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("zig", options: %{shine: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("zig", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {61, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="zig" label="the Zig logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="zig" piece="zig" options={%{shine: 10}} />
  ```

  Ported from `src/pieces/zig.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Logo

  @meta %AsciiArt.Meta{
    name: "zig",
    category: :logos,
    note: "the slanted z in brackets, glinting now and then",
    cols: 61,
    rows: 28,
    fps: 30,
    options: %{shine: 5},
    bounds: %{shine: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the glint.
    palette: [
      "#fba81e",
      "#fcc66d",
      "#fee5bc",
      "#fba81e",
      "#fcc66d",
      "#fee5bc"
    ],
    loop: 5
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "                                                     ._pp'",
            "                                                 __pp88\"",
            "                                             _pp88888P",
            "                                        __pp8888888P\"",
            "  8888888888888888P  _p888888888888888888888888888\"  _88888",
            "  88888888888888P' .p888888888888888888888888888P  _p888888",
            "  8888888888888\"  _888888888888888888888888888P\"  p88888888",
            "  88888888888P  _p888888888888888888888888888\"  _8888888888",
            "  88888888|''   '''''''''''''''_p8888888888P   '\"\"\"88888888",
            "  88888888|                   q8888888888P'       |88888888",
            "  88888888|                 _p8888888888\"         |88888888",
            "  88888888|               _p8888888888P           |88888888",
            "  88888888|              q8888888888P'            |88888888",
            "  88888888|            _p8888888888\"              |88888888",
            "  88888888|          _p8888888888P                |88888888",
            "  88888888|         _8888888888P'                 |88888888",
            "  88888888|       _p8888888888\"                   |88888888",
            "  88888888q__,  _p88888888888________________   __p88888888",
            "  8888888888\"  _888888888888888888888888888P' _p88888888888",
            "  88888888\"  _p88888888888888888888888888P\" _p8888888888888",
            "  888888P' .p888888888888888888888888888\"  q888888888888888",
            "  8888P\"  _888888888888888888888888888P  -88888888888888888",
            "        _p8888888P\"'",
            "      .p88888P\"'",
            "     _888P\"",
            "   .d\"\"",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                                                     ._pp'",
           "                                                 __pp88\"",
           "                                             _pp88888P",
           "                                        __pp8888888P\"",
           "  8888888888888888P  _p888888888888888888888888888\"  _88888",
           "  88888888888888P' .p888888888888888888888888888P  _p888888",
           "  8888888888888\"  _888888888888888888888888888P\"  p88888888",
           "  88888888888P  _p888888888888888888888888888\"  _8888888888",
           "  88888888|''   '''''''''''''''_p8888888888P   '\"\"\"88888888",
           "  88888888|                   q8888888888P'       |88888888",
           "  88888888|                 _p8888888888\"         |88888888",
           "  88888888|               _p8888888888P           |88888888",
           "  88888888|              q8888888888P'            |88888888",
           "  88888888|            _p8888888888\"              |88888888",
           "  88888888|          _p8888888888P                |88888888",
           "  88888888|         _8888888888P'                 |88888888",
           "  88888888|       _p8888888888\"                   |88888888",
           "  88888888q__,  _p88888888888________________   __p88888888",
           "  8888888888\"  _888888888888888888888888888P' _p88888888888",
           "  88888888\"  _p88888888888888888888888888P\" _p8888888888888",
           "  888888P' .p888888888888888888888888888\"  q888888888888888",
           "  8888P\"  _888888888888888888888888888P  -88888888888888888",
           "        _p8888888P\"'",
           "      .p88888P\"'",
           "     _888P\"",
           "   .d\"\"",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                                                       00000
                                                   0000000
                                               000000000
                                          0000000000000
    00000000000000000  000000000000000000000000000000  000000
    0000000000000000 000000000000000000000000000000  00000000
    00000000000000  000000000000000000000000000000  000000000
    000000000000  000000000000000000000000000000  00000000000
    00000000000   0000000000000000000000000000   000000000000
    000000000                   0000000000000       000000000
    000000000                 0000000000000         000000000
    000000000               0000000000000           000000000
    000000000              0000000000000            000000000
    000000000            0000000000000              000000000
    000000000          0000000000000                000000000
    000000000         0000000000000                 000000000
    000000000       0000000000000                   000000000
    000000000000  00000000000000000000000000000   00000000000
    00000000000  000000000000000000000000000000 0000000000000
    000000000  000000000000000000000000000000 000000000000000
    00000000 000000000000000000000000000000  0000000000000000
    000000  00000000000000000000000000000  000000000000000000
          000000000000
        0000000000
       000000
     0000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{shine: shine}), do: Logo.init(@meta, shine, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Logo.frame(state, t, env)
end
