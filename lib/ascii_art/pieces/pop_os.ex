defmodule AsciiArt.Pieces.PopOs do
  @moduledoc """
  The p! in a teal circle, scanned now and then.

  Pop!_os: the Pop!_OS logo, a p and a ! in a circle, with a scan line running
  down it every few seconds that scrambles what it passes.

  Drawn from Simple Icons' popos.svg (CC0): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is the same drawing. The logo is a
  trademark of its owner, shown here to name the distribution.

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

  `AsciiArt.describe/1` gives its name and note, "pop!_os: the p! in a teal
  circle, scanned now and then". A player's or a component's `label` gives
  words of your own, as "the Pop!_OS logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("pop-os", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("pop-os", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="pop-os" label="the Pop!_OS logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="pop-os" piece="pop-os" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/pop-os.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "pop!_os",
    category: :distros,
    note: "the p! in a teal circle, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#48b9c7",
      "#88d2db",
      "#c8eaee",
      "#48b9c7",
      "#88d2db",
      "#c8eaee"
    ]
  }

  # In one ink.
  @mono ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
             _pp8888888888888888888888888888qq,
           _p88888888P""''""Y888888888888888888q,
         _p888888P"           "888888888888888888q,
        _888888"      __        "888888888888888888_
       q888888|      |888_       )888888888888888888p
      q8888888p       8888p      '8888888888888888888p
     q888888888q      "8888|      8888"    "Y888888888p
    .88888888888q      "888|     )888P      .8888888888,
    q888888888888q      '""     _8888|      p8888888888p
    88888888888888q,          _p88888'     p888888888888
    888888888888888q,      _pp8888888     p8888888888888
    8888888888888888q,     O888888888   .p88888888888888
    88888888888888888q,     888888888  _8888888888888888
    d888888888888888888,    "88888888_p8888888888888888P
    '8888888888888888888,    "8888888888888888888888888'
     )8888888888888888888p    88888"  8888888888888888(
      Y8888888888888888888q__p88888___d88888888888888P
       Y88888888888888888888888888888888888888888888P
        "8888888P                          )8888888"
         'Y88888p,                        .q88888P'
           'Y8888888888888888888888888888888888P'
             '"888888888888888888888888888888"'
                '"88888888888888888888888P"'
                    '""Y888888888888P""'

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __pppq88888888qqqq__
                __p8888888888888888888888q_,
             _pp8888888888888888888888888888qq,
           _p88888888P""''""Y888888888888888888q,
         _p888888P"           "888888888888888888q,
        _888888"      __        "888888888888888888_
       q888888|      |888_       )888888888888888888p
      q8888888p       8888p      '8888888888888888888p
     q888888888q      "8888|      8888"    "Y888888888p
    .88888888888q      "888|     )888P      .8888888888,
    q888888888888q      '""     _8888|      p8888888888p
    88888888888888q,          _p88888'     p888888888888
    888888888888888q,      _pp8888888     p8888888888888
    8888888888888888q,     O888888888   .p88888888888888
    88888888888888888q,     888888888  _8888888888888888
    d888888888888888888,    "88888888_p8888888888888888P
    '8888888888888888888,    "8888888888888888888888888'
     )8888888888888888888p    88888"  8888888888888888(
      Y8888888888888888888q__p88888___d88888888888888P
       Y88888888888888888888888888888888888888888888P
        "8888888P                          )8888888"
         'Y88888p,                        .q88888P'
           'Y8888888888888888888888888888888888P'
             '"888888888888888888888888888888"'
                '"88888888888888888888888P"'
                    '""Y888888888888P""'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000000000000000000000000000
           00000000000000000000000000000000000000
         0000000000           000000000000000000000
        00000000      00        00000000000000000000
       00000000      00000       00000000000000000000
      000000000       00000      000000000000000000000
     00000000000      000000      00000    000000000000
    0000000000000      00000     00000      000000000000
    00000000000000      000     000000      000000000000
    0000000000000000          00000000     0000000000000
    00000000000000000      0000000000     00000000000000
    000000000000000000     0000000000   0000000000000000
    0000000000000000000     000000000  00000000000000000
    00000000000000000000    0000000000000000000000000000
    000000000000000000000    000000000000000000000000000
     000000000000000000000    000000  00000000000000000
      000000000000000000000000000000000000000000000000
       0000000000000000000000000000000000000000000000
        000000000                          000000000
         000000000                        000000000
           00000000000000000000000000000000000000
             0000000000000000000000000000000000
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
