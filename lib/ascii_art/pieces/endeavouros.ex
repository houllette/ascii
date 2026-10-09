defmodule AsciiArt.Pieces.Endeavouros do
  @moduledoc """
  The violet sail, scanned now and then.

  The EndeavourOS logo, a sail, with a scan line running down it every few
  seconds that scrambles what it passes.

  Drawn from Simple Icons' endeavouros.svg (CC0): each cell holds the
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

  The picture is always 67 by 28.

  ## Colours

  In the logo's own colours, its palette: a set for a dark page, and with
  `paper: true` one for a light page, the scan lifting them as it passes.
  Drawn in one ink instead (`color: false`, or `mono` in Phoenix), `:ink` and
  `:gradient` colour it, one colour, a gradient, or on a page a CSS variable
  (see `AsciiArt.Ink`). It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "endeavouros: the violet
  sail, scanned now and then". A player's or a component's `label` gives words
  of your own, as "the EndeavourOS logo".

  ## Example

  ```elixir
  still = AsciiArt.new!("endeavouros", options: %{scan: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _still} = AsciiArt.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = AsciiArt.new!("endeavouros", color: false, ink: "var(--brand, #7c3aed)") |> AsciiArt.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {67, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="endeavouros" label="the EndeavourOS logo" />
  <AsciiArt.Phoenix.player socket={@socket} id="endeavouros" piece="endeavouros" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/endeavouros.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.Distro

  @meta %AsciiArt.Meta{
    name: "endeavouros",
    category: :distros,
    note: "the violet sail, scanned now and then",
    cols: 67,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#7f7fff",
      "#acacff",
      "#d9d9ff",
      "#7f7fff",
      "#acacff",
      "#d9d9ff"
    ]
  }

  # In one ink.
  @mono ~S'''

                                       ,':,
                                     _(_pp'\,
                                   _p"_888q,)q,
                                 _pP'p888888_"8p
                               .p8P_p88888888q,Y8_
                              _88"_888888888888,"8q,
                            _p8P'q88888888888888p'88q,
                          _p88P.p8888888888888888q,888_
                         q888"_8888888888888888888q,Y88q,
                       _p888")8888888888888888888888,"888_
                     _p888P'q888888888888888888888888,"888q
                    q8888P_p88888888888888888888888888,"888q,
                  _88888"_88888888888888888888888888888,"8888,
                _p88888")8888888888888888888888888888888,)8888p
               q88888P'q88888888888888888888888888888888b 88888p
             _p88888P.p8888888888888888888888888888888888p'88888p
           _p888888"_8888888888888888888888888888888888888,d88888,
          _8888888"_88888888888888888888888888888888888888||888888,
        _p888888P'q888888888888888888888888888888888888888P:888888p
      .p8888888P.p8888888888888888888888888888888888888888||888888b
     _88888888P_88888888888888888888888888888888888888888P.d8888888
    "Y8888888".O888888888888888888888888888888888888888P"_p8888888(
           _pqqqqqqq________""""""^YYPPP8888888888PP""_pp88888888P
          _888888888888888888888888qqqqqqqqqqqqqpppq88888888888P'
         q8888888888888888888888888888888888888888888888888P""
        d8888888888888888888888888888888888PPPP^"""""''

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                                       ,':,
                                     _(_pp'\,
                                   _p"_888q,)q,
                                 _pP'p888888_"8p
                               .p8P_p88888888q,Y8_
                              _88"_888888888888,"8q,
                            _p8P'q88888888888888p'88q,
                          _p88P.p8888888888888888q,888_
                         q888"_8888888888888888888q,Y88q,
                       _p888")8888888888888888888888,"888_
                     _p888P'q888888888888888888888888,"888q
                    q8888P_p88888888888888888888888888,"888q,
                  _88888"_88888888888888888888888888888,"8888,
                _p88888")8888888888888888888888888888888,)8888p
               q88888P'q88888888888888888888888888888888b 88888p
             _p88888P.p8888888888888888888888888888888888p'88888p
           _p888888"_8888888888888888888888888888888888888,d88888,
          _8888888"_88888888888888888888888888888888888888||888888,
        _p888888P'q888888888888888888888888888888888888888P:888888p
      .p8888888P.p8888888888888888888888888888888888888888||888888b
     _88888888P_88888888888888888888888888888888888888888P.d8888888
    "Y8888888".O888888888888888888888888888888888888888P"_p8888888(
           _pqqqqqqq________""""""^YYPPP8888888888PP""_pp88888888P
          _888888888888888888888888qqqqqqqqqqqqqpppq88888888888P'
         q8888888888888888888888888888888888888888888888888P""
        d8888888888888888888888888888888888PPPP^"""""''

  '''

  @ink ~S"""

                                       0000
                                     00000000
                                   000000000000
                                 000000000000000
                               0000000000000000000
                              0000000000000000000000
                            00000000000000000000000000
                          00000000000000000000000000000
                         00000000000000000000000000000000
                       00000000000000000000000000000000000
                     00000000000000000000000000000000000000
                    00000000000000000000000000000000000000000
                  00000000000000000000000000000000000000000000
                00000000000000000000000000000000000000000000000
               000000000000000000000000000000000000000000 000000
             0000000000000000000000000000000000000000000000000000
           0000000000000000000000000000000000000000000000000000000
          000000000000000000000000000000000000000000000000000000000
        00000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000
     00000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000000
           0000000000000000000000000000000000000000000000000000000
          0000000000000000000000000000000000000000000000000000000
         00000000000000000000000000000000000000000000000000000
        00000000000000000000000000000000000000000000000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
