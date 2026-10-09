defmodule Ascii.Pieces.Ubuntu do
  @moduledoc """
  The circle of friends, in orange, scanned now and then.

  The Ubuntu logo, the circle of friends, with a scan line running down it
  every few seconds that scrambles what it passes.

  Drawn from Simple Icons' ubuntu.svg (CC0): each cell holds the character
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

  The picture is always 58 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `Ascii.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "ubuntu: the circle of
  friends, in orange, scanned now and then". A player's or a component's
  `label` gives words of your own, as "the Ubuntu logo".

  ## Example

  ```elixir
  still = Ascii.new!("ubuntu", options: %{scan: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("ubuntu", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {58, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="ubuntu" label="the Ubuntu logo" />
  <Ascii.Phoenix.player socket={@socket} id="ubuntu" piece="ubuntu" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/ubuntu.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Distro

  @meta %Ascii.Meta{
    name: "ubuntu",
    category: :distros,
    note: "the circle of friends, in orange, scanned now and then",
    cols: 58,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#e95420",
      "#f1906e",
      "#f8ccbc",
      "#e95420",
      "#f1906e",
      "#f8ccbc"
    ]
  }

  # In one ink.
  @mono ~S'''

                         .___pppqq/   ._p88888qq,
                     _pp888888888P   q88888888888q,
                  _p8888888888888   q8888888888888q
               _p888888888888PPP"   888888888888888|
             _p888888888P"'         888888888888888'
            _88888888"'             "8888888888888P
           d8888888"                 "88888888888"   pp
               '""                     '"YPPPP"'   _p88p
        __pqqq_,                                 ~p88888(
     _p888888888q_                                O888888,
    _8888888888888p                                888888p
    888888888888888,                               d888888
    888888888888888|                               |888888
    d88888888888888                                |888888
     Y88888888888P'                                q888888
      '"8888888P"                                 .888888P
           '                                      q888888
         .____ppp                                q888888"
          Y888888q,                  ._pppqqq_   '88888"
           )8888888q,              .p8888888888p   "88"
            "88888888q_           _8888888888888q   "'
              "888888888q__,      q88888888888888p
                "888888888888qp   888888888888888P
                  "Y88888888888,  "88888888888888'
                     '"Y8888888b,  "88888888888P'
                           '""""^    "Y888888P"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                         .___pppqq/   ._p88888qq,
                     _pp888888888P   q88888888888q,
                  _p8888888888888   q8888888888888q
               _p888888888888PPP"   888888888888888|
             _p888888888P"'         888888888888888'
            _88888888"'             "8888888888888P
           d8888888"                 "88888888888"   pp
               '""                     '"YPPPP"'   _p88p
        __pqqq_,                                 ~p88888(
     _p888888888q_                                O888888,
    _8888888888888p                                888888p
    888888888888888,                               d888888
    888888888888888|                               |888888
    d88888888888888                                |888888
     Y88888888888P'                                q888888
      '"8888888P"                                 .888888P
           '                                      q888888
         .____ppp                                q888888"
          Y888888q,                  ._pppqqq_   '88888"
           )8888888q,              .p8888888888p   "88"
            "88888888q_           _8888888888888q   "'
              "888888888q__,      q88888888888888p
                "888888888888qp   888888888888888P
                  "Y88888888888,  "88888888888888'
                     '"Y8888888b,  "88888888888P'
                           '""""^    "Y888888P"

  '''

  @ink ~S"""

                         0000000000   00000000000
                     0000000000000   00000000000000
                  000000000000000   000000000000000
               000000000000000000   0000000000000000
             00000000000000         0000000000000000
            00000000000             000000000000000
           000000000                 0000000000000   00
               000                     000000000   00000
        00000000                                 00000000
     0000000000000                                00000000
    000000000000000                                0000000
    0000000000000000                               0000000
    0000000000000000                               0000000
    000000000000000                                0000000
     00000000000000                                0000000
      00000000000                                 00000000
           0                                      0000000
         00000000                                00000000
          000000000                  000000000   0000000
           0000000000              0000000000000   0000
            00000000000           000000000000000   00
              00000000000000      0000000000000000
                000000000000000   0000000000000000
                  00000000000000  0000000000000000
                     000000000000  00000000000000
                           000000    0000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
