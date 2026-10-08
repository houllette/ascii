defmodule AsciiArt.Pieces.Radar do
  @moduledoc """
  Rotating sweep with afterglow, contacts fade between passes.

  A round scope with range rings and a sweep turning clockwise. Its
  afterglow trails behind; contacts light as the beam crosses them, then fade.

  Ported from `src/pieces/radar.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Text
  import Bitwise, only: [>>>: 2, <<<: 2, |||: 2]

  @meta %AsciiArt.Meta{
    name: "radar",
    category: :data,
    note: "rotating sweep with afterglow, contacts fade between passes",
    cols: 53,
    rows: 25,
    fps: 30,
    options: %{range: 24, unit: "nm"}
  }

  # Scope radius in pixels; a pixel is a cell wide and half a cell tall.
  @r 19
  # Seconds per revolution; radians of afterglow behind the beam; seconds for
  # a return to fade to a third.
  @turn 4
  @trail 0.8
  @fade 2.4
  @half {" ", "▀", "▄", "█"}
  @shade {" ", "░", "▒", "▓", "█"}
  # The centre in pixels: a column, and between two pixel rows.
  @cx 26
  @cy 24.5
  # The mirror row, 2 * @cy, a whole number of pixels.
  @cy2 trunc(2 * @cy)

  # Contacts on straight tracks across the scope; each leaves, stays out for a
  # few pixels of travel, and comes back in on the far side. Heading, offset
  # from the centre, speed in pixels a second, start along the track, size, gap.
  @tracks [
    {1.05, -5, 1.1, 15, 2, 8},
    {3.45, 6, 0.9, -1, 2, 10},
    {5.3, 9, 1.2, 4, 1, 6},
    {2.1, -11, 0.8, -9, 1, 8},
    {0.4, 3, 1.3, -21, 1, 8},
    {4.75, 13, 0.7, 2, 1, 6}
  ]

  @impl true
  def meta, do: @meta

  defp tau, do: :math.pi() * 2

  defp cell(x, y), do: JSMath.round(x) + (JSMath.round(y - 0.01) >>> 1) * @meta.cols

  defp bearing(x, y), do: JSMath.mod(:math.atan2(x - @cx, @cy - y) + tau(), tau())

  # Each point and its mirror images across both axes, so every ring is symmetric.
  defp four(x, y) do
    c = JSMath.round(x)
    p = JSMath.round(y - 0.01)
    [{c, p}, {2 * @cx - c, p}, {c, @cy2 - p}, {2 * @cx - c, @cy2 - p}]
  end

  @impl true
  def init(%{range: range, unit: unit}) do
    %{cols: cols, rows: rows} = @meta
    back = rings(bezel()) |> Map.put(cell(@cx, @cy), "+")

    back =
      [{"000", @cx - 1, 1}, {"180", @cx - 1, rows - 2}, {"270", 1, 12}, {"090", cols - 4, 12}]
      |> Enum.reduce(back, fn {s, c, r}, back ->
        s
        |> Text.chars()
        |> Enum.with_index(c + r * cols)
        |> Enum.into(back, fn {ch, i} -> {i, ch} end)
      end)

    back = for i <- 0..(cols * rows - 1), do: Map.get(back, i, " ")

    # Every cell inside the scope, with its bearing.
    inside =
      for r <- 0..(rows - 1),
          c <- 0..(cols - 1),
          JSMath.hypot(c - @cx, 2 * r + 0.5 - @cy) < @r - 0.3,
          do: {c + r * cols, bearing(c, 2 * r + 0.5)}

    land =
      for {i, b} <- inside,
          c = rem(i, cols),
          y = 2 * div(i, cols) + 0.5,
          land?(c, y) do
        {i, b,
         Enum.any?([{1, 0}, {-1, 0}, {0, 2}, {0, -2}], fn {dx, dy} ->
           not land?(c + dx, y + dy)
         end)}
      end

    tracks =
      for {h, off, v, u, size, gap} <- @tracks do
        l = 2 * :math.sqrt(@r * @r - off * off) + gap

        %{
          sin: :math.sin(h),
          cos: :math.cos(h),
          off: off,
          v: v,
          l: l,
          u0: u + l / 2,
          size: size
        }
      end

    %{
      back: List.to_tuple(back),
      inside: inside,
      land: land,
      tracks: tracks,
      top: [" brg ", "°", "rng #{JSMath.to_string(range)} #{unit} "],
      bottom: "rings #{JSMath.round(range / 3)} #{unit} "
    }
  end

  # The bezel, a ring of half-block pixels just outside the scope.
  defp bezel do
    %{cols: cols, rows: rows} = @meta
    rb = @r + 1.5

    points =
      Enum.flat_map(0..20, fn dx -> four(@cx + dx, @cy - :math.sqrt(rb * rb - dx * dx)) end) ++
        Enum.flat_map(0..20, fn j ->
          dy = j + 0.5
          four(@cx + :math.sqrt(rb * rb - dy * dy), @cy - dy)
        end)

    ring =
      for {c, p} <- points,
          c >= 0 and c < cols and p >= 0 and p < rows * 2,
          into: MapSet.new(),
          do: c + p * cols

    on = fn i -> if MapSet.member?(ring, i), do: 1, else: 0 end

    for i <- 0..(cols * rows - 1),
        c = rem(i, cols),
        p = 2 * div(i, cols),
        k = on.(c + p * cols) ||| on.(c + (p + 1) * cols) <<< 1,
        k != 0,
        into: %{},
        do: {i, elem(@half, k)}
  end

  # Two range rings, a dot in each cell they pass through, dropping the inner
  # corner of every step so the ring stays one cell thick.
  defp rings(back) do
    cols = @meta.cols

    for rr <- [@r / 3, 2 * @r / 3], reduce: back do
      back ->
        path =
          Enum.dedup(
            for i <- 0..200 do
              a = :math.pi() / 2 * (i / 200)
              x = @cx + rr * :math.sin(a)
              y = @cy - rr * :math.cos(a)
              {JSMath.round(x), JSMath.round(y - 0.01) >>> 1}
            end
          )

        nexts = Enum.drop(path, 2) ++ [nil]

        kept =
          path
          |> tl()
          |> Enum.zip(nexts)
          |> Enum.reduce([hd(path)], fn {cur, n}, [p | _] = kept ->
            if far?(p, n), do: [cur | kept], else: kept
          end)
          |> Enum.reverse()

        for {c, r} <- kept, {cc, pp} <- four(c, 2 * r + 0.5), reduce: back do
          back -> Map.put(back, cc + (pp >>> 1) * cols, "·")
        end
    end
  end

  defp far?(_p, nil), do: true
  defp far?({pc, pr}, {nc, nr}), do: abs(pc - nc) > 1 or abs(pr - nr) > 1

  # A coast along the south-west edge: land lies beyond this range at each bearing.
  defp shore(b),
    do:
      @r *
        (0.66 + 0.09 * :math.sin(b * 5 + 0.6) + 0.05 * :math.sin(b * 13) +
           2.2 * max(0, abs(b - 4.15) - 0.62))

  defp land?(x, y) do
    b = bearing(x, y)
    b > 3.3 and b < 5.0 and JSMath.hypot(x - @cx, y - @cy) > shore(b)
  end

  defp where(%{sin: sin, cos: cos, off: off, v: v, l: l, u0: u0}, t) do
    u = JSMath.mod(JSMath.mod(u0 + v * t, l) + l, l) - l / 2
    {@cx + u * sin + off * cos, @cy - (u * cos - off * sin)}
  end

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    tau = tau()
    sweep = JSMath.mod(t / @turn * tau, tau)
    # Seconds since the beam passed.
    ago = fn b -> JSMath.mod(JSMath.mod(sweep - b, tau) + tau, tau) / tau * @turn end
    back = state.back

    # Land is a faint fill; its coast flares for a moment after each pass.
    out =
      Map.new(state.land, fn {i, b, edge} ->
        {i, elem(@shade, if(edge and ago.(b) < 1.2, do: 2, else: 1))}
      end)

    # Afterglow: the beam itself, then a fading wedge behind it.
    out =
      Enum.reduce(state.inside, out, fn {i, b}, out ->
        a = ago.(b) / @turn * tau

        cond do
          a >= @trail ->
            out

          a < 0.08 ->
            Map.put(out, i, elem(@shade, 3))

          a < 0.3 ->
            Map.put(out, i, elem(@shade, 2))

          true ->
            Map.put(out, i, elem(@shade, max(1, shade_index(Map.get(out, i, elem(back, i))))))
        end
      end)

    # A contact shows where it was when the beam last crossed it, fading from
    # full to a mid shade, above anything the land or the trail can reach.
    {out, seen} =
      Enum.reduce(state.tracks, {out, 0}, fn track, {out, seen} ->
        {x0, y0} = where(track, t)
        s = ago.(bearing(x0, y0))
        {x, y} = where(track, t - s)

        if JSMath.hypot(x - @cx, y - @cy) > @r - 1.2 or land?(x, y) do
          {out, seen}
        else
          g = :math.exp(-s / @fade)
          ch = elem(@shade, if(g > 0.7, do: 4, else: if(g > 0.42, do: 3, else: 2)))
          i = cell(x, y)
          out = Map.put(out, i, ch)
          {if(track.size > 1, do: Map.put(out, i + 1, ch), else: out), seen + 1}
        end
      end)

    lines =
      for r <- 0..(rows - 1) do
        Enum.map_join((r * cols)..(r * cols + cols - 1), &Map.get(out, &1, elem(back, &1)))
      end

    deg =
      (sweep * 180 / :math.pi())
      |> JSMath.round()
      |> rem(360)
      |> Integer.to_string()
      |> Text.pad_start(3, "0")

    [brg, degree, rng] = state.top

    lines =
      lines
      |> List.update_at(1, &corner(&1, brg <> deg <> degree, rng))
      |> List.update_at(rows - 2, &corner(&1, " contacts #{seen}", state.bottom))

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp shade_index(ch) do
    Enum.find_index(Tuple.to_list(@shade), &(&1 == ch)) || -1
  end

  # Text in both corners of a line. Upstream lets a line overflow when the two
  # meet; here it is cut to the width.
  defp corner(line, l, rt) do
    cols = @meta.cols
    (l <> Text.slice(line, Text.length(l), cols - Text.length(rt)) <> rt) |> Text.slice(0, cols)
  end
end
