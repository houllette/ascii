defmodule Ascii.Pieces.Manjaro do
  @moduledoc """
  Three green blocks, scanned now and then.

  The Manjaro logo, three green blocks, with a scan line running down it every
  few seconds that scrambles what it passes.

  Drawn from Simple Icons' manjaro.svg (CC0): each cell holds the character
  whose shape best matches the logo's edge through it, and 8 where the logo is
  solid. In colour it takes the logo's colours, lifted on a dark page where
  they would sink into it; in one ink it is the same drawing. The logo is a
  trademark of its owner, shown here to name the distribution.

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

  `Ascii.describe/1` gives its name and note, "manjaro: three green blocks,
  scanned now and then". A player's or a component's `label` gives words of
  your own, as "the Manjaro logo".

  ## Example

  ```elixir
  still = Ascii.new!("manjaro", options: %{scan: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("manjaro", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="manjaro" label="the Manjaro logo" />
  <Ascii.Phoenix.player socket={@socket} id="manjaro" piece="manjaro" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/manjaro.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Distro

  @meta %Ascii.Meta{
    name: "manjaro",
    category: :distros,
    note: "three green blocks, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#35bfa4",
      "#7cd5c4",
      "#c2ece4",
      "#35bfa4",
      "#7cd5c4",
      "#c2ece4"
    ]
  }

  # In one ink.
  @mono ~S"""

     _p888888888888888888888888888888.   |88888888888q_
    q88888888888888888888888888888888.   |8888888888888p
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    88888888888888|''''''''''''''''''    |88888888888888
    88888888888888|                      |88888888888888
    88888888888888|   .qqqqqqqqqqqqqq.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    O8888888888888|   .88888888888888.   |8888888888888P
     "888888888888|   .88888888888888.   |88888888888P"

  """

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S"""

     _p888888888888888888888888888888.   |88888888888q_
    q88888888888888888888888888888888.   |8888888888888p
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    888888888888888888888888888888888.   |88888888888888
    88888888888888|''''''''''''''''''    |88888888888888
    88888888888888|                      |88888888888888
    88888888888888|   .qqqqqqqqqqqqqq.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    88888888888888|   .88888888888888.   |88888888888888
    O8888888888888|   .88888888888888.   |8888888888888P
     "888888888888|   .88888888888888.   |88888888888P"

  """

  @ink ~S"""

     000000000000000000000000000000000   00000000000000
    0000000000000000000000000000000000   000000000000000
    0000000000000000000000000000000000   000000000000000
    0000000000000000000000000000000000   000000000000000
    0000000000000000000000000000000000   000000000000000
    0000000000000000000000000000000000   000000000000000
    0000000000000000000000000000000000   000000000000000
    000000000000000000000000000000000    000000000000000
    000000000000000                      000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
    000000000000000   0000000000000000   000000000000000
     00000000000000   0000000000000000   00000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
