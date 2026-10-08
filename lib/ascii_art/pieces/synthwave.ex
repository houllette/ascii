defmodule AsciiArt.Pieces.Synthwave do
  @moduledoc """
  A grid rolling toward a striped sun behind a mountain ridge.

  The eighties horizon. A grid floor rolls toward the viewer under a setting
  sun cut by thinning stripes, behind a ridge of mountains.

  Ported from `src/pieces/synthwave.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "synthwave",
    category: :effects,
    note: "a grid rolling toward a striped sun behind a mountain ridge",
    cols: 65,
    rows: 28,
    fps: 20
  }

  @cols 65
  @rows 28
  # The horizon: the first row of floor, where the rails meet.
  @hz 12
  # The sun's radius, in half rows (one cell wide, half tall), and its centre,
  # in half rows from the top.
  @sun_r 13
  @sun_y 2 * @hz - 6
  # Cross line n sits K / n rows below the horizon.
  @k 24
  # Rows down to where the lines are close enough to blur.
  @far 5
  # Rail k crosses k * S columns a row.
  @s 0.7
  # Rails each side of the middle one.
  @rails 6
  # Cross lines passed a second.
  @speed 0.9
  # A line at the top, middle or bottom of a cell.
  @level {"▔", "─", "▁"}
  @fr @rows - @hz
  @cx @cols / 2
  @mid 32
  @kinds ["░", "═", "─", "▔", "▁", " "]

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    {heights, rand} = ridge(Int32.to_int32(5))

    {stars, _} =
      Enum.map_reduce(1..24, rand, fn _, rand ->
        {a, rand} = Int32.mulberry32(rand)
        {b, rand} = Int32.mulberry32(rand)
        {c, rand} = Int32.mulberry32(rand)
        {{floor(a * @cols), floor(b * (@hz - 3)), c}, rand}
      end)

    mountains = mountains(heights)

    # Each sky cell: the mountain's character where the ridge covers it, else
    # its two sun pixels, top and bottom.
    sky =
      for r <- 0..(@hz - 1) do
        for c <- 0..(@cols - 1) do
          case mountains do
            %{{^r, ^c} => ch} -> ch
            _ -> {sun(c, 2 * r), sun(c, 2 * r + 1)}
          end
        end
      end

    # The stripes' edges for each half row of the sun's lower part.
    bands =
      for p <- 0..(2 * @hz - 1),
          into: %{},
          do: {p, {band(p - (@sun_y - 7) + 1), band(p - (@sun_y - 7))}}

    floor_rows =
      for y <- 0..(@fr - 1),
          k <- @kinds,
          into: %{},
          do: {{y, k}, IO.iodata_to_binary(floor_row(y, k))}

    %{stars: stars, sky: sky, bands: bands, floor: floor_rows}
  end

  # The ridge: heights in rows at each column boundary, a walk that climbs
  # toward the edges and keeps low under the sun.
  defp ridge(rand) do
    {hs, _, rand} =
      Enum.reduce(1..@cols, {[6], 6, rand}, fn c, {hs, h, rand} ->
        d = abs(c - @cx) / @cx
        want = 1 + 6 * (d - 0.25) + 1.5 * :math.sin(c * 0.45)
        {r, rand} = Int32.mulberry32(rand)

        step =
          cond do
            r < 0.6 -> JSMath.sign(JSMath.round(want - h))
            r < 0.8 -> 1
            true -> -1
          end

        step =
          cond do
            d < 0.25 -> if h > 0, do: -1, else: 0
            h + step < 0 or h + step > 7 -> 0
            true -> step
          end

        {[h + step | hs], h + step, rand}
      end)

    {hs |> Enum.reverse() |> List.to_tuple(), rand}
  end

  # The mountains: an outline over a dark mass that hides the sun.
  defp mountains(heights) do
    for c <- 0..(@cols - 1),
        a = elem(heights, c),
        b = elem(heights, c + 1),
        a != 0 or b != 0,
        top = @hz - 1 - min(a, b),
        r <- top..(@hz - 1),
        into: %{} do
      ch =
        cond do
          r > top -> " "
          b > a -> "/"
          b < a -> "\\"
          true -> "_"
        end

      {{r, c}, ch}
    end
  end

  defp band(k), do: 0.2 * k + 0.3 * k * k / 26

  # Half-row pixel (c, p): outside the sun (nil), always lit (true), or lit
  # unless a stripe passes, which depends on p only. The lower half is cut by
  # gaps one pixel thick that sink, closer together toward the horizon.
  defp sun(c, p) do
    dx = c + 0.5 - @cx
    dy = p + 0.5 - @sun_y

    cond do
      dx * dx + dy * dy > @sun_r * @sun_r -> nil
      p - (@sun_y - 7) < 0 -> true
      true -> p
    end
  end

  # Rails from the vanishing point, rail k crossing k * S columns a row.
  # Steep ones are a stroke a row; shallow ones a run along the bottom of
  # the row stepped by one slash, kept only where the next rail's run will
  # not touch it. On a row with a cross line only the step is drawn, so
  # rails and lines cross. Near the horizon, where they would crowd, only
  # every second or fourth rail is drawn.
  defp floor_row(y, k) do
    row = Tuple.duplicate(k, @cols)

    if y == 0 do
      Tuple.to_list(row)
    else
      mid =
        case k do
          "─" -> "┼"
          "═" -> "╪"
          _ -> "│"
        end

      row = put_elem(row, @mid, mid)
      vx = @mid + 0.5

      every =
        cond do
          @s * (y + 0.5) >= 2.4 -> 1
          2 * @s * (y + 0.5) >= 2.4 -> 2
          true -> 4
        end

      every
      |> Stream.iterate(&(&1 + every))
      |> Enum.take_while(&(&1 <= @rails))
      |> Enum.reduce_while(row, fn m, row ->
        sl = m * @s
        xt = vx - sl * y
        xb = vx - sl * (y + 1)

        cond do
          xt < 0 ->
            {:halt, row}

          sl < 1.3 ->
            {:cont, both(row, floor(vx - sl * (y + 0.5)), "/", "\\")}

          true ->
            hi = floor(xt - 1.0e-6)
            lo = floor(xb)

            row =
              if k == " " and y >= m,
                do: Enum.reduce(max(0, lo + 1)..(hi - 1)//1, row, &both(&2, &1, "_", "_")),
                else: row

            {:cont, both(row, hi, "/", "\\")}
        end
      end)
      |> Tuple.to_list()
    end
  end

  defp both(row, c, l, r) do
    row = if c >= 0 and c < @cols, do: put_elem(row, c, l), else: row
    m = 2 * @mid - c
    if m >= 0 and m < @cols, do: put_elem(row, m, r), else: row
  end

  @impl true
  def frame(%{stars: stars, sky: sky, bands: bands, floor: floor_rows} = state, t, _env) do
    # Later stars win a shared cell.
    lit =
      Map.new(stars, fn {c, r, p} ->
        tw = :math.sin(t * (0.8 + p) + p * 30)

        ch =
          cond do
            tw > 0.6 -> if p < 0.3, do: "+", else: "·"
            tw > -0.4 -> "."
            true -> " "
          end

        {{r, c}, ch}
      end)

    # The sun, two pixels to a cell.
    s = t * 0.6

    stripes =
      Map.new(bands, fn {p, {b1, b0}} ->
        {p, if(floor(b1 - s) == floor(b0 - s), do: 1, else: 0)}
      end)

    sky_lines =
      for {row, r} <- Enum.with_index(sky) do
        for {cell, c} <- Enum.with_index(row) do
          case cell do
            {top, bot} ->
              case pixel(top, stripes) + 2 * pixel(bot, stripes) do
                0 -> Map.get(lit, {r, c}, " ")
                1 -> "▀"
                2 -> "▄"
                3 -> "█"
              end

            ch ->
              ch
          end
        end
      end

    kind = kinds(t)
    floor_lines = for y <- 0..(@fr - 1), do: Map.fetch!(floor_rows, {y, elem(kind, y)})

    {Enum.intersperse(sky_lines ++ floor_lines, ?\n), nil, state}
  end

  defp pixel(nil, _stripes), do: 0
  defp pixel(true, _stripes), do: 1
  defp pixel(p, stripes), do: Map.fetch!(stripes, p)

  # Cross lines, K / n rows down, come on toward the viewer. Count them a
  # row: one is drawn at its height in the cell, two as a double line, and
  # past that, near the horizon, they blur into haze.
  defp kinds(t) do
    n0 = JSMath.mod(t * @speed, 1)

    seen =
      Enum.reduce_while(1..399, %{}, fn n, seen ->
        e = @k / (n - n0)

        cond do
          e >= @fr ->
            {:cont, seen}

          e < 1 ->
            {:halt, seen}

          true ->
            y = floor(e)
            level = min(2, floor(JSMath.mod(e, 1) * 3))
            {:cont, Map.update(seen, y, {1, level}, fn {n, _} -> {n + 1, level} end)}
        end
      end)

    List.to_tuple(
      for y <- 0..(@fr - 1) do
        cond do
          y == 0 -> "░"
          y == 1 -> "═"
          y < @far -> "─"
          true -> line(Map.get(seen, y))
        end
      end
    )
  end

  defp line(nil), do: " "
  defp line({1, level}), do: elem(@level, level)
  defp line(_), do: "═"
end
