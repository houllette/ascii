defmodule Ascii.Pieces.LavaLamp do
  @moduledoc """
  Wax blobs rising, merging and sinking in a lit glass.

  A lava lamp on its base. Wax pools on the floor of the glass, blobs swell
  off it, climb, meet and part, and sink again, lit from the bulb
  underneath.

  Ported from `src/pieces/lava-lamp.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "lava lamp",
    category: :objects,
    note: "wax blobs rising, merging and sinking in a lit glass",
    cols: 30,
    rows: 27,
    fps: 15
  }

  @cols 30
  @rows 27
  @ramp {".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # A cell in em; the wax is measured in em.
  @cw 0.6
  @ch 1.2
  # Seconds in: one blob near the cap, one climbing, one leaving the pool.
  @t0 9
  @thresh 0.3
  # The highest a blob's centre goes, and the glass floor, in em.
  @top 8.6
  @floor 24.4
  # Seconds per trip, where in the trip, side of the middle, sway, reach.
  @blobs [
    {24, 0.42, -0.5, 0.7, 3.0},
    {27, 0.08, 0.6, 0.6, 2.7},
    {31, 0.74, 0.1, 0.8, 3.3}
  ]
  # The rows of the glass, its floor row last.
  @glass0 4
  @glass1 21
  @mid 30 / 2

  @flip %{"/" => "\\", "\\" => "/", "▏" => "▕", "▕" => "▏", "│" => "│", "_" => "_"}

  @impl true
  def meta, do: @meta

  # The lamp's half width at each row, in columns: cap, glass, waist, base.
  defp half(r) when r < 1, do: 1.9
  defp half(r) when r < 4, do: 0.9 + r
  defp half(r) when r < 20, do: 4.1 + 0.26 * (r - 4)
  defp half(r) when r < 21, do: 7.6
  defp half(r), do: 6.8 + (r - 21)

  @compile {:inline, fall: 1, smooth: 1}
  defp fall(q) when q < 1, do: (1 - q) * (1 - q)
  defp fall(_q), do: 0

  defp smooth(e) when e <= 0, do: 0
  defp smooth(e) when e >= 1, do: 1
  defp smooth(e), do: e * e * (3 - 2 * e)

  # The inside of the glass, in em from the middle, at a row.
  defp room(r), do: (half(min(@glass1 - 1, max(@glass0, r))) - 1.1) * @cw

  @impl true
  def init(_options) do
    m = JSMath.hypot(0, 0.5, 0.85)
    shell = shell()
    room = room(@glass1 - 1)

    # The meniscus' rise at a column, and a step either side of it.
    rise = fn x ->
      edge = min(1, abs(x) / room)
      2 * :math.pow(edge, 4)
    end

    columns =
      List.to_tuple(
        for c <- 0..(@cols - 1) do
          x = (c + 0.5 - @mid) * @cw
          {x, rise.(x), rise.(x + 0.3), rise.(x - 0.3)}
        end
      )

    # The glass's inside, which the wax fills.
    inside =
      for r <- @glass0..(@glass1 - 1),
          c <- 0..(@cols - 1),
          elem(elem(shell, r), c) == "~",
          do: {r, c}

    %{shell: shell, columns: columns, inside: inside, light: {0.5 / m, 0.85 / m}}
  end

  # The lamp, drawn once: an edge per row from the half width, a thin bar set
  # where the glass actually stands in the cell, a slash where it leans.
  defp shell do
    for r <- 0..(@rows - 1) do
      x = @mid - half(r)
      lean = half(r + 0.5) - half(r - 0.5)
      c = floor(x)

      g =
        cond do
          r == 0 -> "_"
          r < @glass0 or r >= @glass1 - 1 -> if lean > 0 or r < @glass0, do: "/", else: "\\"
          x - c < 0.34 -> "▏"
          x - c < 0.67 -> "│"
          true -> "▕"
        end

      row = %{}
      row = if r == 0, do: fill(row, c, @cols - c - 1, "_"), else: row
      row = row |> Map.put(c, g) |> Map.put(@cols - 1 - c, Map.fetch!(@flip, g))
      # The cap's rim, the glass's floor sitting in the base, and the base's foot.
      row = if r in [3, 21, @rows - 1], do: fill(row, c + 1, @cols - 2 - c, "_"), else: row
      row = if r >= @glass0 and r < @glass1, do: fill(row, c + 1, @cols - 2 - c, "~"), else: row
      List.to_tuple(for k <- 0..(@cols - 1), do: Map.get(row, k, " "))
    end
    |> List.to_tuple()
  end

  defp fill(row, from, to, ch), do: Enum.reduce(from..to//1, row, &Map.put(&2, &1, ch))

  @impl true
  def frame(state, t, env) do
    tt = @t0 + t
    balls = Enum.map(@blobs, &blob(&1, tt))

    # The pool: three low lumps either side of the middle, shifting their weight.
    pool =
      for j <- -1..1 do
        {j * 2.5 + 0.35 * :math.sin(tt * 0.31 + j * 2.1),
         @floor + 0.6 + 0.3 * :math.sin(tt * 0.43 + j * 1.3), 2.6 * 2.6, 0.3, 1}
      end

    balls = balls ++ pool

    field =
      Map.new(state.inside, fn {r, c} ->
        {x, rise, _, _} = elem(state.columns, c)
        {r * @cols + c, field(balls, x, (r + 0.5) * @ch, rise)}
      end)

    wax? = fn r, c ->
      elem(elem(state.shell, r), c) != "~" or Map.fetch!(field, r * @cols + c) >= @thresh
    end

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.shell, r)

        for c <- 0..(@cols - 1) do
          case elem(row, c) do
            "~" -> wax(state, balls, field, wax?, r, c, env.paper)
            ch -> ch
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp blob({period, phase, side, sway, rad}, tt) do
    a = 2 * :math.pi() * (tt / period + phase)
    y = @top + (@floor - @top) * (1 + :math.cos(a)) / 2
    # Drawn out by the climb, round again at the turns.
    stretch = 1 + 0.3 * abs(:math.sin(a))
    sx = stretch
    sy = 1 / (stretch * stretch)
    # Kept clear of the glass at the narrowest row it reaches, and smaller
    # where the glass is.
    top = floor((y - 0.67 * rad / :math.sqrt(sy)) / @ch)
    fit = room(top)
    r = min(rad, fit * :math.sqrt(sx) / 0.85)
    reach = 0.8 * r / :math.sqrt(sx)
    x = side + sway * :math.sin(a * 0.5 + phase * 9)
    {max(reach - fit, min(fit - reach, x)), y, r * r, sx, sy}
  end

  # The wax's field at x, y, with the meniscus' rise for x: the pool climbs a
  # little up the glass at either side.
  defp field(balls, x, y, rise) do
    f =
      Enum.reduce(balls, 0, fn {bx, by, r2, sx, sy}, f ->
        dx = x - bx
        dy = y - by
        f + fall((dx * dx * sx + dy * dy * sy) / r2)
      end)

    f + 0.55 * smooth((y - @floor + 0.9 + rise) / 1.1)
  end

  defp wax(state, balls, field, wax?, r, c, paper) do
    f = Map.fetch!(field, r * @cols + c)

    if f < @thresh do
      " "
    else
      # Where the wax meets clear oil, an outline that follows the way the edge faces.
      up = not wax?.(r - 1, c)
      dn = not wax?.(r + 1, c)
      lf = not wax?.(r, c - 1)
      rt = not wax?.(r, c + 1)

      if up or dn or lf or rt,
        do: outline(up, dn, lf, rt),
        else: lit(state, balls, f, r, c, paper)
    end
  end

  defp outline(true, true, lf, rt), do: if(lf, do: "(", else: if(rt, do: ")", else: "-"))
  defp outline(true, false, lf, rt), do: if(lf or rt, do: ".", else: "-")
  defp outline(false, true, lf, rt), do: if(lf or rt, do: "'", else: "-")
  defp outline(false, false, true, true), do: "|"
  defp outline(false, false, true, false), do: "("
  defp outline(false, false, false, _rt), do: ")"

  # The wax as a dome over its outline, its slope from the field's.
  defp lit(state, balls, f, r, c, paper) do
    {ly, lz} = state.light
    {x, rise, rise_r, rise_l} = elem(state.columns, c)
    y = (r + 0.5) * @ch
    gx = (field(balls, x + 0.3, y, rise_r) - field(balls, x - 0.3, y, rise_l)) / 0.6
    gy = (field(balls, x, y + 0.3, rise) - field(balls, x, y - 0.3, rise)) / 0.6
    k = 0.8 / :math.sqrt(f - @thresh + 0.04)
    nx = -gx * k
    ny = -gy * k
    lit = max(0, (ny * ly + lz) / JSMath.hypot(nx, ny, 1))
    # Brighter nearer the bulb.
    warm = smooth((y - @top) / (@floor - @top))
    last = tuple_size(@ramp) - 1
    i = 1 + JSMath.round(min(1, 0.05 + 0.75 * lit + 0.2 * warm) * (tuple_size(@ramp) - 2))
    elem(@ramp, if(paper, do: last - i, else: i))
  end
end
