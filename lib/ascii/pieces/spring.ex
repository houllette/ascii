defmodule Ascii.Pieces.Spring do
  @moduledoc """
  A weight bouncing on a coil spring, its coils bunching.

  A coil spring seen from a little above, a weight hanging from it and
  bouncing in simple harmonic motion. The coils bunch and stretch.

  Ported from `src/pieces/spring.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "spring",
    category: :shapes,
    note: "a weight bouncing on a coil spring, its coils bunching",
    cols: 40,
    rows: 28,
    fps: 30
  }

  @cols 40
  @rows 28
  @ramp {".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @cx @cols / 2
  # From the top of the coil at the back to its foot at the front.
  @turns 3.5
  # Coil radius, in columns.
  @rc 7.5
  # How far the near side of a coil sits below the far side, in rows.
  @bulge 1.75
  # Rows per turn at rest, and its swing.
  @p0 3.5
  @amp 0.6
  @period 1.4
  # The top of the coil.
  @top 3
  @steps 160
  @th0 -:math.pi() / 2

  # The weight, drawn once: a drum with its lid tipped toward the eye. Side
  # cells hold a digit, the place in the light ramp, lit from the left.
  @drum [
    "  .-----------.  ",
    " (      o      ) ",
    " |`-----------'| ",
    " |9887766543210| ",
    " |9887766543210| ",
    "  `-----------'  "
  ]

  @ceiling String.duplicate("/", 22)
  @plate String.duplicate("─", 11) <> "┬" <> String.duplicate("─", 10)

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    near =
      for i <- 0..@steps,
          into: %{},
          do: {i, :math.sin(@th0 + i / @steps * @turns * 6.2832) > 0}

    %{near: near}
  end

  @impl true
  def frame(state, t, env) do
    pitch = @p0 + @amp * :math.cos(t / @period * 6.2832)

    points =
      List.to_tuple(
        for i <- 0..@steps do
          th = @th0 + i / @steps * @turns * 6.2832

          {@cx + @rc * :math.cos(th),
           lift(pitch, (th - @th0) / 6.2832) + @bulge * (:math.sin(th) + 1)}
        end
      )

    {_, foot} = elem(points, @steps)
    lid = JSMath.round(foot + 2.3)

    # The wire turns the left side of each coil as one "(": the turn is too
    # tight there for the line art, which keeps to its right.
    edge = floor(@cx - @rc + 0.5)

    {out, front} =
      Enum.reduce(steps_below(@turns - 0.5), {%{}, MapSet.new()}, fn k, {out, front} ->
        r = floor(lift(pitch, k + 0.75) + @bulge)
        q = edge + r * @cols

        if inside?(edge, r),
          do: {Map.put(out, q, "("), MapSet.put(front, q)},
          else: {out, front}
      end)

    # Near strands next; far ones keep a cell clear either side of them, so
    # the near strand reads as passing in front.
    glyphs = curve(points)
    {out, front} = Enum.reduce(glyphs, {out, front}, &near_strand(&2, &1, state.near, edge))
    out = Enum.reduce(glyphs, out, &far_strand(&2, &1, front, state.near, edge))
    out = out |> Map.put(floor(@cx) + 2 * @cols, "|") |> drum(lid, env.paper)

    # The hook, from the foot of the coil to the eye on the lid.
    out =
      Enum.reduce((floor(foot) + 1)..(lid - 1)//1, out, fn r, out ->
        if inside?(0, r), do: Map.put(out, floor(@cx) + r * @cols, "|"), else: out
      end)

    # The ceiling the spring hangs from.
    left = floor(@cx - String.length(@ceiling) / 2)

    out =
      for {line, row} <- [{@ceiling, 0}, {@plate, 1}],
          {ch, i} <- line |> String.codepoints() |> Enum.with_index(),
          reduce: out,
          do: (out -> Map.put(out, row * @cols + left + i, ch))

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, c + r * @cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The values k takes in `for (k = 0; k < limit; k++)`.
  defp steps_below(limit), do: 0 |> Stream.iterate(&(&1 + 1)) |> Enum.take_while(&(&1 < limit))

  # Each turn starts on a whole row, so every coil is drawn alike and the
  # spring stretches by moving whole coils.
  defp lift(pitch, u) do
    k = min(floor(u), ceil(@turns) - 1)
    y0 = JSMath.round(k * pitch)
    @top + y0 + (JSMath.round((k + 1) * pitch) - y0) * (u - k)
  end

  defp inside?(c, r), do: c >= 0 and c < @cols and r >= 0 and r < @rows

  defp near_strand({out, front}, {c, r, ch, i}, near, edge) do
    q = c + r * @cols

    cond do
      not near[i] or not inside?(c, r) or c < edge -> {out, front}
      Map.get(out, q) == "(" -> {out, front}
      true -> {Map.put(out, q, ch), MapSet.put(front, q)}
    end
  end

  defp far_strand(out, {c, r, ch, i}, front, near, edge) do
    q = c + r * @cols

    cond do
      near[i] or not inside?(c, r) or c < edge -> out
      q in front or (c > 0 and (q - 1) in front) -> out
      c < @cols - 1 and (q + 1) in front -> out
      true -> Map.put(out, q, ch)
    end
  end

  defp drum(out, lid, paper) do
    dx = floor(@cx) - 8

    for {line, j} <- Enum.with_index(@drum),
        r = lid - 1 + j,
        r >= 0 and r < @rows,
        n = String.length(line),
        {ch, k} <- line |> String.codepoints() |> Enum.with_index(),
        ch = drum_glyph(ch, paper),
        # The drum's outline and inside replace whatever is behind; its corners do not.
        ch != " " or (k > 1 and k < n - 2),
        reduce: out,
        do: (out -> Map.put(out, dx + k + r * @cols, ch))
  end

  # A digit is a place in the light ramp.
  defp drum_glyph(<<d>>, paper) when d in ?0..?9 do
    last = tuple_size(@ramp) - 1
    i = JSMath.round((d - ?0) / 9 * last)
    elem(@ramp, if(paper, do: last - i, else: i))
  end

  defp drum_glyph(ch, _paper), do: ch

  # Draws a polyline (cells: x across, y down) as line art: one glyph per
  # column where it runs flat, one per row where it runs steep, each picked
  # from where the line crosses its cell. Each glyph comes as
  # {col, row, glyph, point}, the point of the polyline it sits nearest.
  defp curve(p) do
    last = tuple_size(p) - 1
    runs(p, 0, last, [])
  end

  defp runs(_p, s, last, acc) when s >= last, do: acc |> Enum.reverse() |> Enum.concat()

  defp runs(p, s, last, acc) do
    e = run_end(p, s, s + 1, last)
    runs(p, e, last, [run(p, s, e, steep?(p, s)) | acc])
  end

  defp run_end(p, s, e, last) do
    if e < last and steep?(p, e) == steep?(p, s) and dir(p, e) == dir(p, s),
      do: run_end(p, s, e + 1, last),
      else: e
  end

  defp steep?(p, i) do
    {x0, y0} = elem(p, i)
    {x1, y1} = elem(p, i + 1)
    abs(y1 - y0) > abs(x1 - x0)
  end

  defp dir(p, i) do
    a = axis(steep?(p, i))
    JSMath.sign(coord(elem(p, i + 1), a) - coord(elem(p, i), a))
  end

  defp axis(true), do: 1
  defp axis(false), do: 0

  defp coord({x, _}, 0), do: x
  defp coord({_, y}, 1), do: y

  # One stretch of the polyline that runs one way along its main axis.
  defp run(p, s, e, steep) do
    a = axis(steep)
    b = 1 - a
    lo = min(coord(elem(p, s), a), coord(elem(p, e), a))
    hi = max(coord(elem(p, s), a), coord(elem(p, e), a))
    at = fn m -> at(p, s, e, a, b, max(lo, min(hi, m))) end

    for k <- ceil(lo - 0.5)..floor(hi - 0.5)//1 do
      {v, d, i} = at.(k + 0.5)

      cond do
        steep ->
          {floor(v), k, steep_glyph(d), i}

        abs(d) < 0.38 ->
          # Half or quarter row heights: _ at the foot of a cell, . low, - middle, ' high.
          n = if abs(d) < 0.2, do: 2, else: 4

          g =
            if n == 4,
              do: {"_", if(d > 0, do: "`", else: "'"), "-", ".", "_"},
              else: {"_", "-", "_"}

          r = floor(v)
          j = JSMath.round((v - r) * n)
          {k, if(j != 0, do: r, else: r - 1), elem(g, j), i}

        true ->
          # Corner to corner: _ where the line holds its row, / or \ where it changes.
          {va, _, _} = at.(k)
          {vb, _, _} = at.(k + 1)
          ya = JSMath.round(va)
          yb = JSMath.round(vb)

          cond do
            yb > ya -> {k, ya, "\\", i}
            yb < ya -> {k, ya - 1, "/", i}
            true -> {k, ya - 1, "_", i}
          end
      end
    end
  end

  defp steep_glyph(d) when abs(d) < 0.48, do: "|"
  defp steep_glyph(d) when d < 0, do: "/"
  defp steep_glyph(_d), do: "\\"

  # The cross-axis value at m, the slope there, and the nearest point.
  defp at(p, s, e, a, b, m) do
    Enum.find_value(s..(e - 1)//1, {coord(elem(p, s), b), 0, s}, fn i ->
      pp = elem(p, i)
      q = elem(p, i + 1)
      pa = coord(pp, a)
      qa = coord(q, a)

      if m >= min(pa, qa) - 1.0e-9 and m <= max(pa, qa) + 1.0e-9 do
        diff = qa - pa
        d = if diff == 0, do: 1.0e-9, else: diff
        u = (m - pa) / d
        pb = coord(pp, b)
        qb = coord(q, b)
        {pb + (qb - pb) * u, (qb - pb) / d, if(u < 0.5, do: i, else: i + 1)}
      end
    end)
  end
end
