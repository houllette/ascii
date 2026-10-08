defmodule AsciiArt.Pieces.Flag do
  @moduledoc """
  A striped flag rippling on a pole, folds catching the light.

  A striped flag on a pole in a steady wind. Folds run from the pole to the
  free edge and grow as they go; faces turned to the light are bright, the
  far sides of folds dark.

  Ported from `src/pieces/flag.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "flag",
    category: :physics,
    note: "a striped flag rippling on a pole, folds catching the light",
    cols: 62,
    rows: 21,
    fps: 30,
    options: %{stripes: 5},
    bounds: %{stripes: {0, 100}},
    loop: 12
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # A top hem part way down a cell.
  @rise {"▁", "▂", "▃", "▄", "▅", "▆", "▇"}
  # Seconds; every rate below fits a whole number of times.
  @loop 12
  # Folds along the cloth.
  @waves 2.3
  # Radians the folds lag from the top hem to the bottom one, so they run on a slant.
  @skew 1.4
  # The cloth's length and its height at the pole, in rows (a column is half a row).
  @long 29
  @high 13
  # How far the free edge billows toward and away from us, in rows.
  @swing 4
  @strips 300

  @cols 62
  @rows 21
  # The pole's column, and the top hem at the pole, in rows.
  @pole 4
  @top 2.5
  @ground @rows - 1

  @compile {:inline, hypot1: 1, dz: 4}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{stripes: stripes}) do
    two_pi = 2 * :math.pi()

    # Per strip edge: WAVES * u, and u * 2 * PI * WAVES for the slope.
    edges =
      for i <- 0..@strips do
        u = i / @strips
        {u, @waves * u, u * 2 * :math.pi() * @waves, 1.2 * u * u, 0.8 * u}
      end

    # The middle of each strip, where its width is taken.
    mids =
      for i <- 1..@strips do
        u = (i - 0.5) / @strips
        {@waves * u, u * 2 * :math.pi() * @waves}
      end

    # Rows that share a place down the cloth share their strips' crossings.
    levels =
      0..(@rows - 1)
      |> Enum.map(&level/1)
      |> Enum.uniq()

    %{
      bands: max(2, JSMath.round(stripes)),
      two_pi: two_pi,
      edges: edges,
      mids: mids,
      levels: levels,
      width: 2 * @long / @strips
    }
  end

  # How far down the cloth row r is, at the pole; always a float, so rows
  # clamped to 0 or 1 share one key with the rows that land there exactly.
  defp level(r), do: min(1, max(0, (r + 0.5 - @top) / @high)) * 1.0

  # Math.hypot(1, s), step for step as JSMath.hypot/2 computes it, inlined.
  defp hypot1(s) do
    b = abs(s)

    if b > 1.0 do
      x = 1.0 / b
      :math.sqrt(x * x + 1.0) * b
    else
      :math.sqrt(1.0 + b * b)
    end
  end

  # The slope along the length, from the phase's sine and cosine.
  defp dz(g4, du, sin, cos), do: g4 * (sin + du * cos) / @long

  @impl true
  def frame(%{two_pi: two_pi} = state, t, %{paper: paper}) do
    gust = 0.85 + 0.15 * :math.sin(two_pi * t / @loop)
    rt = 17 / @loop * t
    g4 = gust * @swing

    # The cloth can't stretch, so a strip turned away from us takes less room
    # across the frame.
    crossings =
      Map.new(state.levels, fn v ->
        xs = crossings(state.mids, two_pi, rt, @skew * v, g4, state.width, @pole + 1, [])
        {v, List.to_tuple([@pole + 1 | xs])}
      end)

    rows_xs = List.to_tuple(for r <- 0..(@rows - 1), do: Map.fetch!(crossings, level(r)))
    at = %{rows_xs: rows_xs, two_pi: two_pi, rt: rt, gust: gust, g4: g4, bands: state.bands}

    {cells, _} =
      Enum.reduce(state.edges, {%{}, 0}, fn edge, {cells, i} ->
        {strip(cells, edge, i, at), i + 1}
      end)

    {render(cells, paper), nil, state}
  end

  defp crossings([], _two_pi, _rt, _skew, _g4, _width, _x, xs), do: Enum.reverse(xs)

  defp crossings([{wu, du} | mids], two_pi, rt, skew, g4, width, x, xs) do
    ph = two_pi * (wu - rt) - skew
    x = x + width / hypot1(dz(g4, du, :math.sin(ph), :math.cos(ph)))
    crossings(mids, two_pi, rt, skew, g4, width, x, [x | xs])
  end

  defp strip(cells, {u, wu, du, uu, u8}, i, %{g4: g4, gust: gust} = at) do
    base = at.two_pi * (wu - at.rt)
    ph = base - @skew * 0.5
    # Nearer parts look taller, the hems rise and fall with each fold, and the
    # free end droops.
    zm = g4 * u * :math.sin(ph)
    h = @high * (1 + 0.04 * zm) - u8
    top = @top + uu + u8 * gust * :math.sin(ph + 0.8) - (h - @high) / 2
    bottom = top + h
    hem = {i, du, base, top, h, bottom}
    rows(cells, max(0, floor(top)), ceil(min(@rows, bottom)) - 1, hem, at)
  end

  defp rows(cells, r, last, _hem, _at) when r > last, do: cells

  defp rows(cells, r, last, {i, du, base, top, h, bottom} = hem, at) do
    c = floor(elem(elem(at.rows_xs, r), i))

    if c >= @cols do
      rows(cells, r + 1, last, hem, at)
    else
      v = min(1, max(0, (r + 0.5 - top) / h))
      ph = base - @skew * v
      s = dz(at.g4, du, :math.sin(ph), :math.cos(ph))
      # Light comes from the left and in front, so a face turned toward the pole is lit.
      lit = max(0, min(1, (0.95 * s + 0.65) / hypot1(s) + 0.1))
      odd = rem(floor(v * at.bands * 0.9999), 2)
      cover = min(r + 1, bottom) - max(r, top)
      cells = add(cells, r * @cols + c, lit, odd, cover)
      rows(cells, r + 1, last, hem, at)
    end
  end

  # lit and cover are Float32Arrays, so each store rounds to single precision.
  defp add(cells, k, lit, odd, cover) do
    case cells do
      %{^k => {l, n, o, f}} ->
        %{cells | k => {JSMath.fround(l + lit), n + 1, o + odd, JSMath.fround(max(f, cover))}}

      _ ->
        Map.put(cells, k, {JSMath.fround(lit), 1, odd, JSMath.fround(max(0, cover))})
    end
  end

  defp render(cells, paper) do
    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: glyph(cells, r, c, paper)
      end

    Enum.intersperse(lines, ?\n)
  end

  # The pole, its cap, and the ground it stands in.
  defp glyph(_cells, 1, @pole, _paper), do: "o"
  defp glyph(_cells, r, @pole, _paper) when r >= 2 and r < @ground, do: "┃"
  defp glyph(_cells, @ground, @pole, _paper), do: "┸"
  defp glyph(_cells, @ground, c, _paper) when c >= @pole - 3 and c <= @pole + 3, do: "▁"

  defp glyph(cells, r, c, paper) do
    k = r * @cols + c

    case Map.get(cells, k) do
      nil -> " "
      cell -> cloth(cell, cover(cells, k + @cols) > 0.94, paper)
    end
  end

  defp cover(cells, k) do
    case Map.get(cells, k) do
      nil -> 0
      {_, _, _, f} -> f
    end
  end

  # A hem crossing the cell: a block filled to where the cloth reaches, from
  # below or above.
  defp cloth({_, _, _, f}, true, _paper) when f < 0.8,
    do: elem(@rise, min(6, JSMath.floor(f * 8)))

  defp cloth({_, _, _, f}, false, _paper) when f < 0.7, do: if(f < 0.3, do: "▔", else: "▀")

  # The light stripes take the top of the ramp and the dark ones the bottom,
  # so folds show in both.
  defp cloth({lit, hits, odd, _}, _below, paper) do
    l = lit / hits
    b = if odd * 2 > hits, do: 0.1 + 0.34 * l, else: 0.52 + 0.48 * l
    g = max(1, min(9, JSMath.round(b * 9)))
    elem(@ramp, if(paper, do: 10 - g, else: g))
  end
end
