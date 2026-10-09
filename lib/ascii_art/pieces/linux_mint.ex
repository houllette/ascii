defmodule AsciiArt.Pieces.LinuxMint do
  @moduledoc """
  Lm in a green circle, scanned now and then.

  The Linux Mint logo, lm in a green circle, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from devicon's linuxmint-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from Simple
  Icons' linuxmint.svg (CC0). The logo is a trademark of its owner, shown here
  to name the distribution.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
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
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "linux mint: lm in a green
  circle, scanned now and then". A player's or a component's `label` gives
  words of your own, as "the Linux Mint logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("linux-mint", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("linux-mint", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="linux-mint" label="the Linux Mint logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="linux-mint" piece="linux-mint" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/linux-mint.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "linux mint",
    category: :distros,
    note: "lm in a green circle, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#fcfcfc",
      "#69b53f",
      "#fdfdfd",
      "#9ecf82",
      "#fefefe",
      "#d2e9c5",
      "#fcfcfc",
      "#69b53f",
      "#fdfdfd",
      "#9ecf82",
      "#fefefe",
      "#d2e9c5"
    ]
  }

  # In one ink.
  @mono ~S"""

                    __pppq88888888qqqq_,
                __p8888888888888888888888q_,
             ._p888888PP""''    ''""Y8888888q_,
           _p88888P"'                  '"888888q,
         .p8888P"                          "88888q,
        _8888P"                              "88888_
       q8888"  .qqqp                           "8888p
      q8888'   |8888      ._ppqq_, _ppqq_,      '8888p
     q8888'    |8888    .p8888888888888888q,     '8888p
    .8888"     |8888    q8888""888888Y"88888      "8888,
    q888P      |8888   .8888    8888'   8888|      O888p
    8888|      |8888   .8888    8888.   8888|      |8888
    8888'      |8888   .8888    8888.   8888|      '8888
    8888.      |8888   .8888    8888.   8888|      .8888
    8888,      |8888   .8888    8888.   8888|      |8888
    d888p      |8888   'YYYY    YYYY'   8888|      q888P
    '8888,      8888_                  _8888      \8888'
     )8888,     "8888qqq____________ppp8888"     _8888(
      Y8888,     'Y8888888888888888888888P'     _8888P
       Y8888_       ""YPPPPPPPPPPPPPPP""       _8888P
        "8888q_                              _p8888"
         'Y8888q_                          _p8888P'
           'Y88888q_,                  __p88888P'
             '"8888888qq____.  .____pp8888888"'
                '"88888888888888888888888P"'
                    '""Y888888888888P""'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
             _pp8888888888888888888888888888qq,
           _p8888888888888888888888888888888888q,
         _p88888888888888888888888888888888888888q,
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
     )888888888888888888888888888888888888888888888888(
      Y8888888888888888888888888888888888888888888888P
       Y88888888888888888888888888888888888888888888P
        "888888888888888888888888888888888888888888"
         'Y88888888888888888888888888888888888888P'
           'Y8888888888888888888888888888888888P'
             '"888888888888888888888888888888"'
                '"88888888888888888888888P"'
                    '""Y888888888888P""'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000011111111111100000000000
           00000000111111111111111111111100000000
         000000011111111111111111111111111110000000
        00000011111111111111111111111111111111000000
       0000011110000111111111111111111111111111100000
      000001111100001111111110011111100111111111100000
     00000111111000011111000000000000000000111111100000
    0000011111110000111100000110000000100000111111100000
    0000011111110000111100001111000011110000111111100000
    0000111111110000111100001111000011110000111111110000
    0000111111110000111100001111000011110000111111110000
    0000111111110000111100001111000011110000111111110000
    0000111111110000111100001111000011110000111111110000
    0000011111110000111100001111000011110000111111100000
    0000011111110000111111111111111111110000111111100000
     00000111111100000011111111111111000000111111100000
      000001111111000000000000000000000000111111100000
       0000011111111110000000000000000111111111100000
        00000011111111111111111111111111111111000000
         000000011111111111111111111111111110000000
           00000000111111111111111111111100000000
             0000000000011111111111100000000000
                0000000000000000000000000000
                    00000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
