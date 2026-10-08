defmodule AsciiArt.Pieces.Aurora do
  @moduledoc """
  An aurora curtain rippling over a treeline under stars.

  A curtain of light over a spruce treeline at night. Its lower hem is
  brightest and ripples; streaks rise from it and fade out below a clear sky
  of stars, and light drifts along it in slow surges.

  Ported from `src/pieces/aurora.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.{Hash, Rand}

  @meta %AsciiArt.Meta{
    name: "aurora",
    category: :nature,
    note: "an aurora curtain rippling over a treeline under stars",
    cols: 64,
    rows: 20,
    fps: 20
  }

  @cols 64
  @rows 20
  # Dim to bright, in upright strokes. The curtain is light, not shade, so on
  # paper it keeps the ramp and prints as a negative, like the stars.
  @ramp {" ", ".", ":", "!", "|", "I"}
  @tau :math.pi() * 2
  # The row the hem ripples about, and the row the trees stand on.
  @hem 12
  @ridge 18

  @impl true
  def meta, do: @meta

  @compile {:inline, ease: 1}
  defp ease(t), do: t * t * (3 - 2 * t)

  defp noise(x, y) do
    i = floor(x)
    j = floor(y)
    u = ease(x - i)
    v = ease(y - j)
    a = Hash.murmur(i, j)
    b = Hash.murmur(i + 1, j)
    c = Hash.murmur(i, j + 1)
    d = Hash.murmur(i + 1, j + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  @impl true
  def init(_options) do
    rand = Int32.to_int32(5)

    # The treeline: spruces in stepped quarter blocks, a tier of branches
    # every two rows, each standing apart with sky between, on a low ridge.
    land =
      for c <- 0..(@cols - 1), r <- @ridge..(@rows - 1), into: %{} do
        ch = if r == @ridge and :math.sin(c * 0.13 + 1) <= 0.3, do: "▄", else: "█"
        {c + r * @cols, ch}
      end

    {first, rand} = Int32.mulberry32(rand)
    {land, rand} = trees(land, 1 + floor(first * 2), rand)
    {stars, _} = stars([], rand)

    land =
      for r <- 0..(@rows - 1) do
        List.to_tuple(for c <- 0..(@cols - 1), do: Map.get(land, c + r * @cols))
      end

    statics =
      for c <- 0..(@cols - 1) do
        x = c + 0.5
        {x * 0.12, x * 0.31, x * 0.07, x * 0.9}
      end

    %{land: List.to_tuple(land), stars: stars, statics: statics}
  end

  defp trees(land, x, rand) when x >= @cols - 1, do: {land, rand}

  defp trees(land, x, rand) do
    {a, rand} = Int32.mulberry32(rand)
    {b, rand} = Int32.mulberry32(rand)
    {c, rand} = Int32.mulberry32(rand)
    # 2 to 5 rows.
    tall = 2 + floor(a * 2.2 + b * c * 2.5)
    half_tall = Bitwise.bsr(tall, 1)

    land =
      for k <- 0..(tall - 1),
          r = @ridge - tall + k,
          half = 1 + Bitwise.bsr(k, 1),
          c <- (x - half + 1)..(x + half)//1,
          c >= 0 and c < @cols,
          reduce: land do
        land -> Map.put(land, c + r * @cols, tier(c, x, half, Bitwise.band(k, 1) == 1))
      end

    land =
      for c <- (x - half_tall)..(x + 1 + half_tall)//1, c >= 0 and c < @cols, reduce: land do
        land -> Map.put(land, c + @ridge * @cols, "█")
      end

    {d, rand} = Int32.mulberry32(rand)
    trees(land, x + 2 + 2 * half_tall + 1 + floor(d * 3), rand)
  end

  defp tier(c, x, half, _odd) when c != x - half + 1 and c != x + half, do: "█"
  defp tier(c, x, half, true) when c == x - half + 1, do: "▟"
  defp tier(c, x, half, false) when c == x - half + 1, do: "▗"
  defp tier(_c, _x, _half, true), do: "▙"
  defp tier(_c, _x, _half, false), do: "▖"

  # Stars, a few of them bright, each twinkling on its own beat.
  defp stars(stars, rand) when length(stars) == 40, do: {Enum.reverse(stars), rand}

  defp stars(stars, rand) do
    {[a, b, c, d, e, f], rand} = Rand.take(rand, 6)
    k = floor(a * @cols) + floor(b * c * (@hem + 2)) * @cols
    stars([{k, d < 0.2, 0.3 + e * 1.1, f * @tau} | stars], rand)
  end

  @impl true
  def frame(state, t, _env) do
    cols = Enum.map(state.statics, &column(&1, t))

    out =
      for r <- 0..(@rows - 1), land_row = elem(state.land, r), y = r + 0.5 do
        for {col, c} <- Enum.with_index(cols) do
          case elem(land_row, c) do
            nil -> cell(col, y)
            ch -> ch
          end
        end
      end
      |> List.flatten()
      |> List.to_tuple()

    out =
      Enum.reduce(state.stars, out, fn {k, bright, rate, ph}, out ->
        if elem(out, k) == " " do
          tw = :math.sin(t * rate * @tau + ph)
          put_elem(out, k, star(bright, tw))
        else
          out
        end
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: elem(out, c + r * @cols)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp star(true, tw) when tw > 0.3, do: "+"
  defp star(true, _tw), do: "*"
  defp star(false, tw) when tw > -0.6, do: "."
  defp star(false, _tw), do: " "

  defp column({x012, x031, x007, x09}, t) do
    # The hem: a slow fold and a quicker ripple running along it.
    y0 = @hem + 1.2 * :math.sin(x012 + t * 0.35) + 0.55 * :math.sin(x031 - t * 0.7 + 1)

    slope =
      1.2 * 0.12 * :math.cos(x012 + t * 0.35) + 0.55 * 0.31 * :math.cos(x031 - t * 0.7 + 1)

    # Light surges along the curtain but never leaves it, and gathers where a
    # fold is seen edge on.
    lit =
      (0.62 + 0.4 * ease(noise(x007 - t * 0.25, 3.3))) * (1 + 0.9 * min(1, abs(slope) * 2))

    # Streaks stand on the hem, sliding along it, each fading as it rises.
    ray = ease(min(1, max(0, (noise(x09 - t * 1.4, 7 + t * 0.3) - 0.3) / 0.45)))
    height = 1.5 + 6.5 * ray * (0.6 + 0.6 * noise(x012 + t * 0.15, 11))
    {y0, lit, ray, height}
  end

  # A bright hem, the streaks above it, and below it a glow that settles on
  # the treetops, striped like the streaks.
  defp cell({y0, lit, ray, height}, y) do
    # Rows above the hem.
    d = y0 - y
    q = max(0, abs(d) - 0.5) / if(d > 0, do: 0.6, else: 0.35)
    hem = :math.exp(-(q * q))

    v =
      max(
        hem,
        if d >= 0 do
          (0.3 + 0.7 * ray) * :math.pow(max(0, 1 - d / height), 1.4)
        else
          :math.exp(d / 1.5) * (0.4 + 0.4 * ray)
        end
      )

    b = JSMath.fround(lit * v) - 0.12
    if b > 0, do: elem(@ramp, min(5, 1 + floor(b * 5))), else: " "
  end
end
