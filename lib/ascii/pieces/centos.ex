defmodule Ascii.Pieces.Centos do
  @moduledoc """
  Four coloured squares in a star, scanned now and then.

  The CentOS logo, four coloured squares in a star, with a scan line running
  down it every few seconds that scrambles what it passes.

  Drawn from devicon's centos-original.svg (MIT): each cell holds the
  character whose shape best matches the logo's edge through it, and 8 where
  the logo is solid. In colour it takes the logo's colours, lifted on a dark
  page where they would sink into it; in one ink it is drawn from devicon's
  centos-plain.svg (MIT). The logo is a trademark of its owner, shown here to
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

  `Ascii.describe/1` gives its name and note, "centos: four coloured
  squares in a star, scanned now and then". A player's or a component's
  `label` gives words of your own, as "the CentOS logo".

  ## Example

  ```elixir
  still = Ascii.new!("centos", options: %{scan: 0})
  {first, still} = Ascii.frame(still, 0.0)
  {later, _still} = Ascii.frame(still, 4.0)
  first.text == later.text
  #=> true

  {frame, _} = Ascii.new!("centos", color: false, ink: "var(--brand, #7c3aed)") |> Ascii.frame(0.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {56, 28, ["var(--brand, #7c3aed)"]}
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="centos" label="the CentOS logo" />
  <Ascii.Phoenix.player socket={@socket} id="centos" piece="centos" options={%{scan: 10}} />
  ```

  Ported from `src/pieces/centos.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Distro

  @meta %Ascii.Meta{
    name: "centos",
    category: :distros,
    note: "four coloured squares in a star, scanned now and then",
    cols: 56,
    rows: 28,
    fps: 30,
    options: %{scan: 5},
    bounds: %{scan: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the scan.
    palette: [
      "#fefefe",
      "#262577",
      "#9ccd2c",
      "#93237a",
      "#efa725",
      "#fefefe",
      "#7271a7",
      "#bfdf76",
      "#b970a9",
      "#f5c671",
      "#ffffff",
      "#bebed6",
      "#e1f0c0",
      "#dfbdd7",
      "#fae5be",
      "#fefefe",
      "#504ec8",
      "#9ccd2c",
      "#a8288b",
      "#efa725",
      "#fefefe",
      "#8d8cdb",
      "#bfdf76",
      "#c673b4",
      "#f5c671",
      "#ffffff",
      "#cbcaef",
      "#e1f0c0",
      "#e5bfdc",
      "#fae5be"
    ]
  }

  # In one ink.
  @mono ~S'''

                            _pq_
                          _p8888q_
                        .d88888888b,
           \qqqqqqqqp-_pqqq.d888 qqqq_ __________
           d8888888P_p88888.d888 88888q_"88888888
           d88888P'q8888888.d888 8888888p."888888
           d888P88q_"888888.d888 888888P_p88P8888
           d8P_q,Y88q_"8888.d888 8888P_p88P_p_"88
           "_p888q,Y88q_"88.d888 88P'p88P'p888q_"
           q8888888q,Y88q_"'d888 P'p88P'p8888888p
        _p:d888888888q,Y88q."88P q88P'p8888888888 q_
      _p88:""""""""""""''""   '  """ """""""""""" 88q,
    _p8888888888888888888q,       q8888888888888888888q,
    '88888888888888888888P'       Y8888888888888888888P"
      '888:\qqqqqqqqqqp-._q. .,  qq,-qqqqqqqqqqqp 88P"
        'O:d888888888P'p88P q88p Y88q,Y8888888888 P"
           d8888888P'p88P'p.d888 q,Y88q,Y8888888P
           _'O888P'p88P'p88.d888 88q,Y88q,Y888P"_
           d8q'Y'p88P'p8888.d888 8888q,Y88q,Y"_88
           d888q88P'p888888.d888 888888q,Y88q8888
           d88888_'88888888.d888 8888888P'_888888
           d8888888_"888888.d888 88888P"_88888888
           "^^^^^^^^^ "^^^^'d888 "^^^" '"""""""""
                        "888888888P"
                          "88888P"
                            "8P"

  '''

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ~S'''

                            _pq_
                          _p8888q_
                        _p88888888q_
           \qqqqqqqqqqqp888888888888qqqqqqqqqqqqp
           d8qqqqqqqqq88888888888888888________p8
           d8888888888888888888888888888888888888
           d8888888888888888888888888888888888888
           d8888888888888888888888888888888888888
           d8888888888888888888888888888888888888
          _d8888888888888888888888888888888888888_
        _p8888888888888888888888888888888888888888q_
      _p88888888888888888888P88P88888888888888888888q,
    _p888888888888888888888q, ' _888888888888888888888q,
    "8888888888888888888888P,   )888888888888888888888P"
      "888888888888888888888q88q88888888888888888888P"
        '88888888888888888888888888888888888888888P"
          '88888888888888888888888888888888888888"
           d888888888888888888888888888888888888b
           d888888888888888888888888888888888888b
           d888888888888888888888888888888888888b
           d888888888888888888888888888888888888b
           d888888888888888888888888888888888888b
           """"""""""""8888888888888P""""""""""""
                        "888888888P"
                          "88888P"
                            "8P"

  '''

  @ink ~S"""

                            0000
                          00044000
                        000444444000
           00000000000000004444444000000000000000
           00222222220022220444404443000333333300
           00222222002222220444403333330033333330
           00222222022222220444403333333033333330
           00220002220222220444403333303333003330
           00002220022202220444403330033303330030
          0002222222002220204444030033303333333000
        00000222222222002220044400333033333333330000
      000330022222222200002000000330033333333330011000
    0003333333333333333333000 0 001111111111111111111000
    0003333333333333333333000   001111111111111111111000
      000330011111111110001000000440044444444440011000
        00000111111111001110022204444044444444440000
          0001111111001110102222040444404444444000
           00001110011101110222204440444404440000
           00110001110111110222204444404440004440
           00111111011111110222204444444044444440
           00111111001111110222204444440044444440
           00111111110011110222204444004444444440
           00000000000000022222222000000000000000
                        000222222000
                          00022000
                            0000

  """

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{scan: scan}), do: Distro.init(@meta, scan, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: Distro.frame(state, t, env)
end
