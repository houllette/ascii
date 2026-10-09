defmodule AsciiArt.Pieces.KaliLinux do
  @moduledoc """
  The blue dragon, scanned now and then.

  The Kali Linux logo, the dragon, with a scan line running down it every few
  seconds that scrambles what it passes.

  Drawn from devicon's kalilinux-original.svg (MIT): each cell holds the
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

  The picture is always 71 by 27.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "kali linux: the blue dragon,
  scanned now and then". A player's or a component's `label` gives words of
  your own, as "the Kali Linux logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("kali-linux", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("kali-linux", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {71, 27, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="kali-linux" label="the Kali Linux logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="kali-linux" piece="kali-linux" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/kali-linux.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "kali linux",
    category: :distros,
    note: "the blue dragon, scanned now and then",
    cols: 71,
    rows: 27,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#287aff",
      "#73a9ff",
      "#bfd7ff",
      "#287aff",
      "#73a9ff",
      "#bfd7ff"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "       ''''\"\"\"\"\"\"^YYY0bqqqq___,",
            "                          '\"\"^Y88qq__",
            "                ___________________\"Y8p",
            "       __,ooOYYY\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"YY/b",
            "  .'\"'''                 .___pppp88888O,        .",
            "                   __pp88PY\"\"\"'        8p,       ':-_",
            "              ._pdP\"\"'                 _888qqqqqq___'\"~_",
            "           _oY\"\"                     p88P\"\"\"\"\"\"\"Y888qp_|Y_",
            "        .\"\"                        _88\"             \"\"888qq,",
            "                                   d8\"                  \"888_",
            "                                  :88                    '\"Y8q_",
            "                                  '88,                       \"P\"",
            "                                   88q,",
            "                                    O88_,",
            "                                     \"888qq_______,",
            "                                        \"\"Y888888888888qpq__,",
            "                                                    ''\"^88q/Y0q_",
            "                                                          \"Yq_ \"Oq,",
            "                                                            'Oq, 'O_",
            "                                                              \"q,  \"(",
            "                                                               \"b   )",
            "                                                                ),",
            "                                                                 \\",
            "                                                                 |",
            "                                                                  '",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art Enum.join(
         [
           "",
           "       ''''\"\"\"\"\"\"^YYY0bqqqq___,",
           "                          '\"\"^Y88qq__",
           "                ___________________\"Y8p",
           "       __,ooOYYY\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"YY/b",
           "  .'\"'''                 .___pppp88888O,        .",
           "                   __pp88PY\"\"\"'        8p,       ':-_",
           "              ._pdP\"\"'                 _888qqqqqq___'\"~_",
           "           _oY\"\"                     p88P\"\"\"\"\"\"\"Y888qp_|Y_",
           "        .\"\"                        _88\"             \"\"888qq,",
           "                                   d8\"                  \"888_",
           "                                  :88                    '\"Y8q_",
           "                                  '88,                       \"P\"",
           "                                   88q,",
           "                                    O88_,",
           "                                     \"888qq_______,",
           "                                        \"\"Y888888888888qpq__,",
           "                                                    ''\"^88q/Y0q_",
           "                                                          \"Yq_ \"Oq,",
           "                                                            'Oq, 'O_",
           "                                                              \"q,  \"(",
           "                                                               \"b   )",
           "                                                                ),",
           "                                                                 \\",
           "                                                                 |",
           "                                                                  '",
           ""
         ],
         "\n"
       ) <> "\n"

  @ink ~S"""

         000000000000000000000000
                            00000000000
                  00000000000000000000000
         00000000000000000000000000000000
    000000                 000000000000000        0
                     000000000000        000       0000
                00000000                 00000000000000000
             00000                     000000000000000000000
          000                        0000             00000000
                                     000                  00000
                                    000                    000000
                                    0000                       000
                                     0000
                                      00000
                                       00000000000000
                                          000000000000000000000
                                                      000000000000
                                                            0000 0000
                                                              0000 000
                                                                000  00
                                                                 00   0
                                                                  00
                                                                   0
                                                                   0
                                                                    0

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
