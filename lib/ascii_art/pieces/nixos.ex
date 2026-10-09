defmodule AsciiArt.Pieces.Nixos do
  @moduledoc """
  The snowflake of lambdas, scanned now and then.

  The NixOS logo, the snowflake of lambdas, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from devicon's nixos-original.svg (MIT): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is drawn from devicon's
  nixos-plain.svg (MIT). The logo is a trademark of its owner, shown here to
  name the distribution.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `scan` - seconds from one scan to the next, 0 to 3600; default 5. A line
      two rows deep takes two seconds to run down the logo, scrambling the
      characters it covers, with five rows of afterglow behind it, so it comes
      at most every two and a half; 0 keeps the logo still.

  The picture is always 64 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "nixos: the snowflake of
  lambdas, scanned now and then". A player's or a component's `label` gives
  words of your own, as "the NixOS logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("nixos", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("nixos", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {64, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="nixos" label="the NixOS logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="nixos" piece="nixos" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/nixos.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "nixos",
    category: :distros,
    note: "the snowflake of lambdas, scanned now and then",
    cols: 64,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#5277c3",
      "#81bfea",
      "#8fa7d8",
      "#add5f1",
      "#cbd6ed",
      "#d9ecf9",
      "#5277c3",
      "#81bfea",
      "#8fa7d8",
      "#add5f1",
      "#cbd6ed",
      "#d9ecf9"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "                q8888,       \"888888(     _8888p",
            "               )888888,       \"888888p   _888888(",
            "                \"888888_       \"888888p _888888\"",
            "                 \"888888p       '888888q888888\"",
            "           ________888888p________88888888888\"",
            "          _88888888888888888888888pO88888888'       q,",
            "         )8888888888888888888888888q)888888,       q88_",
            "        )888888888888888888888888888b\"888888(    .p8888p",
            "                  q888888\"            \"888888p  _p88888P",
            "                 p888888'              \"888888p_888888P",
            "               .p88888P'                '88888\\888888P",
            "   _qqqqqqqqqqq888888P                    888)888888qqqqqqqq,",
            "  _88888888888888888P                      \"q8888888888888888,",
            "  \"8888888888888888(p                      q88888888888888888\"",
            "   \"\"\"\"\"\"\"\"8888888\\88q,                  .p888888\"\"\"\"\"\"\"\"\"\"\"'",
            "          q888888\\8888q,                _p88888P",
            "         p888888'O888888,              _888888P",
            "       .p88888P'  Y888888,            |888888P",
            "        Y8888P     \"888888pqqqqqqqqqqqqqqqqqqqqqqqqqqqp(",
            "         \"88P       \"888888p88888888888888888888888888\"",
            "          \"\"       _p8888888pO88888888888888888888888\"",
            "                  _8888888888q''''''''Y888888,'''''''",
            "                 _888888888888q,       \"888888,",
            "                q888888\" O888888,       \"888888(",
            "               )888888\"   )888888,       \"888888(",
            "                \"8888'     \"888888(       \"8888\"",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "                q8888,       \"888888(     _8888p",
           "               )888888,       \"888888p   _888888(",
           "                \"888888_       \"888888p _888888\"",
           "                 \"888888p       '888888q888888\"",
           "           ________888888p________88888888888\"",
           "          _88888888888888888888888pO88888888'       q,",
           "         )8888888888888888888888888q)888888,       q88_",
           "        )888888888888888888888888888b\"888888(    .p8888p",
           "                  q888888\"            \"888888p  _p88888P",
           "                 p888888'              \"888888p_888888P",
           "               .p88888P'                '88888\\888888P",
           "   _qqqqqqqqqqq888888P                    888)888888qqqqqqqq,",
           "  _88888888888888888P                      \"q8888888888888888,",
           "  \"8888888888888888(p                      q88888888888888888\"",
           "   \"\"\"\"\"\"\"\"8888888\\88q,                  .p888888\"\"\"\"\"\"\"\"\"\"\"'",
           "          q888888\\8888q,                _p88888P",
           "         p888888'O888888,              _888888P",
           "       .p88888P'  Y888888,            |888888P",
           "        Y8888P     \"888888/qqqqqqqqqqqqqqqqqqqqqqqqqqqp(",
           "         \"88P       \"888888p88888888888888888888888888\"",
           "          \"\"       _p8888888pO88888888888888888888888\"",
           "                  _8888888888q''''''''Y888888,'''''''",
           "                 _888888888888q,       \"888888,",
           "                q888888\" Y888888,       \"888888(",
           "               )888888\"   )888888,       \"888888(",
           "                \"8888'     \"888888(       \"8888\"",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

                  000000       11111111     111111
                 00000000       11111111   11111111
                  00000000       11111111 11111111
                   00000000       111111111111111
             00000000000000000000000111111111111
            00000000000000000000000001111111111       00
           00000000000000000000000000011111111       0000
          0000000000000000000000000000011111111    0000000
                    11111111            11111111  00000000
                   11111111              1111111100000000
                 111111111                11111100000000
     1111111111111111111                    1110000000000000000
    1111111111111111111                      1000000000000000000
    1111111111111111110                      0000000000000000000
     11111111111111110000                  00000000000000000000
            11111111000000                00000000
           1111111100000000              00000000
         111111111  00000000            00000000
          111111     0000000011111111111111111111111111111
           1111       00000000111111111111111111111111111
            11       00000000001111111111111111111111111
                    00000000000011111111111111111111111
                   000000000000000       11111111
                  00000000 00000000       11111111
                 00000000   00000000       11111111
                  000000     00000000       111111

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
