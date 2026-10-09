defmodule Ascii.Pieces.Fedora do
  @moduledoc """
  The f in its blue bubble, scanned now and then.

  The Fedora logo, an f in a blue speech bubble, with a scan line running down
  it every few seconds that scrambles what it passes.

  Drawn from devicon's fedora-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from devicon's
  fedora-plain.svg (MIT). The logo is a trademark of its owner, shown here to
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

  `Ascii.describe/1` gives its name and note, "fedora: the f in its blue
  bubble, scanned now and then". A player's or a component's `label` gives
  words of your own, as "the Fedora logo".

  ## Example

  ```elixir
  still = Ascii.new!("fedora", options: %{scan: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("fedora", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="fedora" label="the Fedora logo" />
  <Ascii.Phoenix.player socket={@socket} id="fedora" piece="fedora" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/fedora.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Distro

  @meta %Ascii.Meta{
    name: "fedora",
    category: :distros,
    note: "the f in its blue bubble, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#294172",
      "#ffffff",
      "#3c6eb4",
      "#7484a3",
      "#ffffff",
      "#80a1ce",
      "#bfc6d5",
      "#ffffff",
      "#c5d4e9",
      "#3b5da3",
      "#ffffff",
      "#3c6eb4",
      "#8096c3",
      "#ffffff",
      "#80a1ce",
      "#c4cee3",
      "#ffffff",
      "#c5d4e9"
    ]
  }

  # In one ink.
  @mono ~S'''

                    __pppq88888888qqq__,
                __p8888888888888888888888q_,
             ._p8888888888888888888888888888q_,
           _p8888888888888888888888888888888888q,
          p88888888888888888888888888888888888888q,
        _88888888888888888888888P""""^8888888888888,
       )888888888888888888888P'         "88888888888p
      q888888888888888888888"    _pq__    "8888888888p
     \888888888888888888888|   _8888888,   )8888888888,
     8888888888888888888888:   d8888888|   |88888888888
    |8888888888888888888888:   d8888888q_ _p88888888888|
    d8888888888888888888888:   d88888888888888888888888b
    88888888888888888PPPP88:   /PPPP88888888888888888888
    888888888888P"       d8:         8888888888888888888
    8888888888P      ____d8:   ______888888888888888888P
    888888888"   .p88888888:   d88888888888888888888888|
    88888888P   .8888888888:   d88888888888888888888888
    88888888|   |8888888888:   d8888888888888888888888"
    88888888p   '888888888P    d888888888888888888888P
    888888888,   'Y888888"    q888888888888888888888"
    8888888888p      ''     _p888888888888888888888"
    888888888888q_       ._p888888888888888888888P
    8888888888888888qqpq88888888888888888888888P'
    88888888888888888888888888888888888888888"
    "888888888888888888888888888888888888P"'
      "8888888888888888888888888888PP""'

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

                    __pppq88888888qqqq_,
                __p8888888888888888888888q_,
             __p8888888888888888888888888888q_,
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
    888888888888888888888888888888888888888888888888888P
    888888888888888888888888888888888888888888888888888'
    88888888888888888888888888888888888888888888888888(
    8888888888888888888888888888888888888888888888888P
    888888888888888888888888888888888888888888888888P
    88888888888888888888888888888888888888888888888"
    888888888888888888888888888888888888888888888P'
    8888888888888888888888888888888888888888888P'_
    88888888888888888888888888888888888888888"'  (YY
    "888888888888888888888888888888888888P"'
     '"8888888888888888888888888888PP""'

  """

  @ink ~S"""

                    00000000000000000000
                0000000000000000000000000000
             0000000000000000000000000000000000
           00000000000000000000001111111110000000
         000000000000000000000111111111111122000000
        00000000000000000000111111111111112222200000
       0000000000000000000011111110000000222222220000
      000000000000000000001111110000000000022222200000
     00000000000000000000011111000000000000022222200000
    0000000000000000000001111110000000000000222222000000
    0000000000000000000001111110000000000000222222000000
    0000000000000000000001111110000000000022222220000000
    0000000000002201111111111111111111222222222200000000
    0000000022222211111111111111111111122222220000000000
    0000002222222211111111111111111111122222000000000000
    0000222222222000000001111110000000000000000000000000
    0002222222000000000001111110000000000000000000000000
    000222222000000000000111111000000000000000000000000
    00022222200000000000011111100000000000000000000000
    0002222220000000000001111110000000000000000000000
    000222222200000000001111111000000000000000000000
    00002222222200000111111111000000000000000000000
    0000002222111111111111110000000000000000000002
    0000000022111111111111000000000000000000000  222
    0000000000000111100000000000000000000000
     00000000000000000000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
