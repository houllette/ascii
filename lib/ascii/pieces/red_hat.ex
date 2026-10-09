defmodule Ascii.Pieces.RedHat do
  @moduledoc """
  The man in the red hat, scanned now and then.

  The Red Hat logo, the man in the red hat, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from devicon's redhat-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from devicon's
  redhat-plain.svg (MIT). The logo is a trademark of its owner, shown here to
  name the distribution.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `scan` - seconds from one scan to the next, 0 to 3600; default 5. A line
      two rows deep takes two seconds to run down the logo, scrambling the
      characters it covers, with five rows of afterglow behind it, so it comes
      at most every two and a half; 0 keeps the logo still.

  The picture is always 56 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "red hat: the man in the red
  hat, scanned now and then". A player's or a component's `label` gives words
  of your own, as "the Red Hat logo".

  ## Example

  ```elixir
  still = Ascii.new!("red-hat", options: %{scan: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("red-hat", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="red-hat" label="the Red Hat logo" />
  <Ascii.Phoenix.player socket={@socket} id="red-hat" piece="red-hat" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/red-hat.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Distro

  @meta %Ascii.Meta{
    name: "red hat",
    category: :distros,
    note: "the man in the red hat, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#000000",
      "#ffffff",
      "#e93442",
      "#595959",
      "#ffffff",
      "#f17b84",
      "#b3b3b3",
      "#ffffff",
      "#f8c2c6",
      "#545454",
      "#ffffff",
      "#e93442",
      "#909090",
      "#ffffff",
      "#f17b84",
      "#cccccc",
      "#ffffff",
      "#f8c2c6"
    ]
  }

  # In one ink.
  @mono Enum.join(
          [
            "",
            "",
            "                     ____ppqqqq____",
            "                __pq8888888888888888qq__",
            "             _p88888888888888888888888888q_",
            "          _p8888888P\"\"\"\"YPPPP\"____\"Y88888888q,",
            "        _p88888888\"            _)88('888888888q,",
            "       p888888888P qq_____,    '''    Y888888888p",
            "     _p8888888888' \"88888PP\"           O888888888q,",
            "    _888888888888    \"'                 88888888888,",
            "   .88888P\"\"\"\"\"\\8q_                     \"88888888888,",
            "   d888P       \"8888qqq___               88888888888p",
            "  |8888p        'Y888888888qp           .8\"'\"Y8888888,",
            "  d88888q_         '\"Y8888888,          \"'     'O8888b",
            "  88888888q_            '\"\"\"YP\"                  88888",
            "  88888888888q_,                                .88888",
            "  888888888888P8bq_,                           _p88888",
            "  O8888888888\"   \"888q__,                    _p888888P",
            "  \"8888888888q,   '' \"8888qqq____________ppp888888888|",
            "   YPPP\"\"' 'Y88_,      \"8888888888888888888888888888P",
            "             '\"\"                       q888888888888'",
            "                             \\q__p     888888888888\"",
            "                              '\"\"'    q888PP\"\"\"\"\"Y'",
            "                                    _p88P\"",
            "                                   _8P\"",
            "                                  \"\"\"",
            "",
            ""
          ],
          "\n"
        ) <> "\n"

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __pppq88888888qqqq_,
                __p8888888888888888888888q_,
             ._p8888888888888888888888888888q_,
           _p8888888888888888888888888888888888q,
         .p88888888888888888888888888888888888888q,
        _888888888888888888888888888888888888888888_
       q88888888888888888888888888888888888888888888p
      q8888888888888888888888888888888888888888888888p
     q888888888888888888888888888888888888888888888888p
    .88888888888888888888888888888888888888888888888888,
    q88888888888888888888888888888888888888888888888888p
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    8888888888888888888888888888888888888888888888888888
    d88888888888888888888888888888888888888888888888888P
    '88888888888888888888888888888888888888888888888888'
     "888888888888888888888888888888888888888888888888(
      )8888888888888888888888888888888888888888888888P
       )88888888888888888888888888888888888888888888P
        "888888888888888888888888888888888888888888"
          Y88888888888888888888888888888888888888P'
           'Y8888888888888888888888888888888888P'
              "888888888888888888888888888888"'
                '"Y8888888888888888888888P"'
                     ""Y88888888888PP""'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000000000000000000000000000
           00000000002222222222222000220000000000
         000000000002222222222222200022200000000000
        00000000000220000000022222222222200000000000
       0000000000002222002222222222222222200000000000
      000000000000022222222222222222222222000000000000
     00000222222220002222222222222222222222000000000000
    0000022222222200000000002222222222222220000000000000
    0000002222222222200000000002222222222220222220000000
    0000000022222222222222000000222222222222222222200000
    0000000000222222222222222222222222222222222222200000
    0000000000000222222222222222222222222222222222200000
    0000000000001110022222222222222222222222222220000000
    0000000000011111101000022222222222222222222000000000
    0000000010001111111100000000000000000000000000000000
     11111111110001111111111001111111111110000000000000
      111111111111111111111111111111111110000000000000
       1111111111111111111111111000011111000000000000
        11111111111111111111111111111111000011111111
          11111111111111111111111111110001111111111
           11111111111111111111111111001111111111
              111111111111111111111111111111111
                1111111111111111111111111111
                     1111111111111111111

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
