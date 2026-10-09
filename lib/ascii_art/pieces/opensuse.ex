defmodule AsciiArt.Pieces.Opensuse do
  @moduledoc """
  The green chameleon, scanned now and then.

  The openSUSE logo, the green chameleon, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from devicon's opensuse-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is the same drawing. The
  logo is a trademark of its owner, shown here to name the distribution.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `scan` - seconds from one scan to the next, 0 to 3600; default 5. A line
      two rows deep takes two seconds to run down the logo, scrambling the
      characters it covers, with five rows of afterglow behind it, so it comes
      at most every two and a half; 0 keeps the logo still.

  The picture is always 69 by 18.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "opensuse: the green
  chameleon, scanned now and then". A player's or a component's `label` gives
  words of your own, as "the openSUSE logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("opensuse", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("opensuse", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {69, 18, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="opensuse" label="the openSUSE logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="opensuse" piece="opensuse" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/opensuse.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "opensuse",
    category: :distros,
    note: "the green chameleon, scanned now and then",
    cols: 69,
    rows: 18,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#76be26",
      "#a6d572",
      "#d6ecbe",
      "#76be26",
      "#a6d572",
      "#d6ecbe"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "                    .__pppq888888888888qqqqq___   qqq___,",
            "                _pp888888888888888888888888888888q88888888qqq__",
            "            __p888888888888888888888888888888888888888888P\"__\"Y8_",
            "         ._p88888888888888888888888888888888888888888888P\\8P\"Yp\"8p",
            "       _p88888888888888888888888888888888888888888888888p/88q8P.88,",
            "     .p888888888888888888888888888888888888888888888(\"888q_\"\"\"_8888",
            "    _888888888888888888888888888888888888888888888888qq_,\"Y8888PP\"_",
            "   q888888P\"\"\"\"\"\"Y8888888888888888888888888888888888888888qqqpppq8\"",
            "  \\88888\"  __pq__, '\"88888888888888888888888888888888888888888P\"\"",
            "  d888P  _88888888q_  \"88888888P\"\"\"\"\"Y888888888\"    '''''''",
            "  8888| |888\"''\"Y888p   888888'        \"888888P",
            "  8888p \"888q_q_ \"888,   8888P           \"88888",
            "  \"8888_ \"88888P .888|   '\"88p             \"888q  ,",
            "   \"8888q_, ''  _p888'       '                '\"Y'|'",
            "    'Y8888888q88888P'",
            "       \"Y8888888P\"'",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                    .__pppq888888888888qqqqq___   qqq___,",
           "                _pp888888888888888888888888888888q88888888qqq__",
           "            __p888888888888888888888888888888888888888888P\"__\"Y8_",
           "         ._p88888888888888888888888888888888888888888888P\\8P\"Yp\"8p",
           "       _p88888888888888888888888888888888888888888888888p/88q8P.88,",
           "     .p888888888888888888888888888888888888888888888(\"888q_\"\"\"_8888",
           "    _888888888888888888888888888888888888888888888888qq_,\"Y8888PP\"_",
           "   q888888P\"\"\"\"\"\"Y8888888888888888888888888888888888888888qqqpppq8\"",
           "  \\88888\"  __pq__, '\"88888888888888888888888888888888888888888P\"\"",
           "  d888P  _88888888q_  \"88888888P\"\"\"\"\"Y888888888\"    '''''''",
           "  8888| |888\"''\"Y888p   888888'        \"888888P",
           "  8888p \"888q_q_ \"888,   8888P           \"88888",
           "  \"8888_ \"88888P .888|   '\"88p             \"888q  ,",
           "   \"8888q_, ''  _p888'       '                '\"Y'|'",
           "    'Y8888888q88888P'",
           "       \"Y8888888P\"'",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                      000000000000000000000000000   0000000
                  00000000000000000000000000000000000000000000000
              00000000000000000000000000000000000000000000000000000
           000000000000000000000000000000000000000000000000000000000
         000000000000000000000000000000000000000000000000000000000000
       00000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000000000000000000000000000000
     0000000000000000000000000000000000000000000000000000000000000000
    0000000  0000000 0000000000000000000000000000000000000000000000
    00000  00000000000  00000000000000000000000000    0000000
    00000 0000000000000   0000000        00000000
    00000 00000000 00000   00000           000000
    000000 0000000 00000   00000             00000  0
     00000000 00  000000       0                000000
      00000000000000000
         000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
