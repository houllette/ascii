defmodule AsciiArt.Pieces.DoomFire do
  @moduledoc """
  The psx fire spread, tongues climbing off a white-hot bed.

  The PSX fire spread. Each step every cell climbs one row, drifts a column
  either way and cools a little, on a grid of square cells two across and
  four down to a character. Columns cool at different rates, so the fire
  stands up in separate tongues over a bed that never dims.

  Ported from `src/pieces/doom-fire.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Hash
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "doom fire",
    category: :effects,
    note: "the psx fire spread, tongues climbing off a white-hot bed",
    cols: 60,
    rows: 18,
    fps: 24
  }

  @sx 2
  @sy 4
  @max 36
  # Coolest to hottest, upright strokes in the middle.
  @ramp {" ", ".", ":", ";", "!", "+", "*", "#", "%", "@"}
  # Spread steps a second, and the share of the width that burns.
  @rate 24
  @bed 0.72
  # Tongues: {place across the bed from -1 to 1, tallest as a share of the
  # frame, half width in cells}. Between them the fire cools fast.
  @tongues [{-0.66, 1.05, 11}, {-0.18, 2.1, 15}, {0.3, 1.6, 13}, {0.73, 0.95, 9}]
  # Steps for a tongue's height to wander through one knot.
  @drift 34
  @floor 0.16

  @w 60 * @sx
  @h 18 * @sy + 1

  @impl true
  def meta, do: @meta

  defp hash(x, y), do: Hash.murmur(x, y)

  defp ease(t), do: t * t * (3 - 2 * t)

  defp noise(x, y) do
    i = floor(x)
    j = floor(y)
    u = ease(x - i)
    v = ease(y - j)
    a = hash(i, j)
    b = hash(i + 1, j)
    c = hash(i, j + 1)
    d = hash(i + 1, j + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  @impl true
  def init(_options) do
    # The bed: white hot right across, dropping off over the last few columns.
    bed =
      for x <- 0..(@w - 1) do
        d = abs((2 * x + 1) / @w - 1) / @bed

        cond do
          d < 0.88 -> 1
          d < 1 -> JSMath.fround(ease((1 - d) / 0.12))
          true -> 0
        end
      end

    zero_row = List.to_tuple(List.duplicate(0, @w))

    sim = %{
      rand: 9,
      n: 0,
      bed: List.to_tuple(bed),
      heat: List.to_tuple(List.duplicate(zero_row, @h)),
      tears: %{}
    }

    sim = Enum.reduce(1..200, sim, fn _, sim -> step(sim) end)
    Map.merge(sim, %{last: 0, acc: 0})
  end

  defp step(sim) do
    n = sim.n + 1
    rows = @meta.rows

    # Each column cools at the rate that lets the nearest tongue reach its
    # height, and each tongue's height wanders on its own, so they stand apart
    # and rise and fall out of step.
    tall =
      @tongues
      |> Enum.with_index()
      |> Enum.reduce(:array.new(@w, default: JSMath.fround(0.28)), fn {{at, top, half}, i},
                                                                      tall ->
        lift =
          top *
            (0.55 +
               0.45 *
                 (noise(i * 7.3, n / @drift) * 0.7 + noise(i * 3.1 + 40, n / (@drift * 0.4)) * 0.3))

        mid = @w / 2 * (1 + at * @bed) + 6 * (noise(i * 5.7 + 90, n / (@drift * 2)) - 0.5)

        Stream.iterate(max(0, floor(mid - half)), &(&1 + 1))
        |> Enum.take_while(&(&1 < min(@w, mid + half)))
        |> Enum.reduce(tall, fn x, tall ->
          d = (x + 0.5 - mid) / half

          :array.set(
            x,
            JSMath.fround(max(:array.get(x, tall), lift * (1 - :math.pow(abs(d), 1.3)))),
            tall
          )
        end)
      end)

    cool =
      List.to_tuple(
        for x <- 0..(@w - 1), do: JSMath.fround(@max / (rows * @sy * :array.get(x, tall)))
      )

    base = List.to_tuple(for x <- 0..(@w - 1), do: JSMath.fround(@max * elem(sim.bed, x)))
    heat = put_elem(sim.heat, @h - 1, base)
    tears = tears(sim.tears, n)

    # The spread runs in place, so the last writer wins; alternating the scan
    # keeps that from turning into a wind. Pockets of extra cooling rise with
    # the flame, so near the top the tips tear off and fade on their own.
    # Row y - 1 takes writes made from row y as it was before this step.
    {heat, rand} =
      Enum.reduce(1..(@h - 1), {heat, sim.rand}, fn y, {heat, rand} ->
        up = 1 - y / @h
        flip = band(y + n, 1) == 1
        src = elem(heat, y)
        tear_row = Map.fetch!(tears, y + n)

        {writes, rand} =
          Enum.reduce(0..(@w - 1), {%{}, rand}, fn i, {writes, rand} ->
            x = if flip, do: @w - 1 - i, else: i
            {r, rand} = Int32.mulberry32(rand)

            to =
              cond do
                r < 0.3 -> x - 1
                r > 0.7 -> x + 1
                true -> x
              end

            if to < 0 or to >= @w do
              {writes, rand}
            else
              tear = 1 + 2.2 * up * up * max(0, elem(tear_row, x) - 0.45)
              {r2, rand} = Int32.mulberry32(rand)
              v = elem(src, x) - r2 * 2 * elem(cool, x) * tear
              {Map.put(writes, to, if(v > 0, do: JSMath.fround(v), else: 0)), rand}
            end
          end)

        dst = elem(heat, y - 1)
        row = List.to_tuple(for x <- 0..(@w - 1), do: Map.get(writes, x, elem(dst, x)))
        {put_elem(heat, y - 1, row), rand}
      end)

    %{sim | n: n, heat: heat, rand: rand, tears: tears}
  end

  # noise(x / 5, k / 6) for each column, by k = y + n: a row a step is new,
  # the rest were computed in earlier steps.
  defp tears(cache, n) do
    cache = Map.reject(cache, fn {k, _} -> k <= n end)

    Enum.reduce((n + 1)..(n + @h - 1), cache, fn k, cache ->
      Map.put_new_lazy(cache, k, fn ->
        List.to_tuple(for x <- 0..(@w - 1), do: noise(x / 5, k / 6))
      end)
    end)
  end

  @impl true
  def frame(sim, t, _env) do
    acc = sim.acc + min(max(t - sim.last, 0), 0.25)
    sim = run(%{sim | last: t}, acc)
    {draw(sim.heat), nil, sim}
  end

  defp run(sim, acc) do
    if acc >= 1 / @rate - 1.0e-6,
      do: run(step(sim), acc - 1 / @rate),
      else: %{sim | acc: acc}
  end

  defp draw(heat) do
    %{cols: cols, rows: rows} = @meta
    last = tuple_size(@ramp) - 1
    scale = @sx * @sy * @max

    lv =
      for cy <- 0..(rows - 1) do
        List.to_tuple(
          for cx <- 0..(cols - 1) do
            sum =
              Enum.reduce(0..(@sy - 1), 0, fn j, sum ->
                row = elem(heat, cy * @sy + j)
                Enum.reduce(0..(@sx - 1), sum, fn i, sum -> sum + elem(row, cx * @sx + i) end)
              end)

            v = (sum / scale - @floor) / (1 - @floor)
            if v <= 0, do: 0, else: min(last, 1 + Int32.to_int32(v * last))
          end
        )
      end
      |> List.to_tuple()

    at = fn x, y -> elem(elem(lv, y), x) end

    # A faint glyph only stands with flame beside or below it, and a lone one
    # not at all, so the tips keep clean edges instead of a haze of specks.
    lines =
      for cy <- 0..(rows - 1) do
        for cx <- 0..(cols - 1) do
          k = at.(cx, cy)

          k =
            if k > 0 and k < 5 do
              {any, under} =
                for dy <- -1..1,
                    dx <- -1..1,
                    dy != 0 or dx != 0,
                    y = cy + dy,
                    x = cx + dx,
                    y >= 0 and y < rows and x >= 0 and x < cols,
                    reduce: {0, 0} do
                  {any, under} ->
                    o = at.(x, y)

                    {if(o != 0, do: any + 1, else: any),
                     if(dy >= 0 and o > under, do: o, else: under)}
                end

              if any < 2 or (k < 3 and under < 3), do: 0, else: k
            else
              k
            end

          elem(@ramp, k)
        end
      end

    Enum.intersperse(lines, ?\n)
  end
end
