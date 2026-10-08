defmodule AsciiArt.Pieces.Sundial do
  @moduledoc """
  Jaipur's samrat yantra, its shadow set by your local time.

  The Samrat Yantra at Jantar Mantar, Jaipur, seen from the south. The
  gnomon's shadow lies on the quadrants where the sun at Jaipur would put it
  at this hour of the viewer's own clock (not Jaipur solar time).

  Reads the clock from `env.now` (see `AsciiArt.Kit.Clock`) every frame, and
  redraws the face when the minute changes, as upstream does. The day of the
  year counts from local midnight on 1 January.

  Ported from `src/pieces/sundial.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Env, JSMath}
  alias AsciiArt.Kit.{Clock, Rand}

  @meta %AsciiArt.Meta{
    name: "sundial",
    category: :objects,
    note: "jaipur's samrat yantra, its shadow set by your local time",
    cols: 65,
    rows: 23,
    fps: 10,
    clock: true
  }

  @cols 65
  @rows 23
  @n 65 * 23
  # Jaipur.
  @lat 26.92 * :math.pi() / 180
  # The centre of the quadrants' arc, on the gnomon's edge; the arc's radius
  # across and down, a cell being twice as tall as wide; the inner edge of
  # the quadrants' face, as a share of the outer.
  @cx 32.5
  @yc 9.5
  @rx 26
  @ry 11.6
  @inner 0.77
  # The gnomon: ground row, top row, half width at the foot.
  @ground 22
  @apex 4
  @foot 2.9
  # How far down the rim stands upright, as a share of its depth.
  @up 0.22
  @rays_up [{0, -1, "|"}, {0, 1, "|"}, {-3, 0, "-"}, {3, 0, "-"}]
  @rays_slant [{-2, -1, "\\"}, {2, -1, "/"}, {-2, 1, "/"}, {2, 1, "\\"}]

  @impl true
  def meta, do: @meta

  # 0 straight down, east positive.
  defp angle(c, r), do: :math.atan2((c - @cx) / @rx, (r - @yc) / @ry)

  # The gnomon's half width on row r.
  defp half(r), do: 0.6 + (@foot - 0.6) * (r - @apex) / (@ground - 1 - @apex)

  @impl true
  def init(_options) do
    face = face()

    # The least angle of the face that shows beside the gnomon's foot.
    hidden =
      Enum.reduce(face, :math.pi() / 2, fn {k, psi, _, _, _}, hidden ->
        r = div(k, @cols)
        c = rem(k, @cols)

        if c < floor(@cx - half(r)) or c > floor(@cx + half(r)),
          do: min(hidden, abs(psi)),
          else: hidden
      end)

    {stars, _} =
      Enum.map_reduce(1..22, Rand.seed(5), fn _, rand ->
        {a, rand} = Rand.next(rand)
        {b, rand} = Rand.next(rand)
        {p, rand} = Rand.next(rand)
        {{trunc(a * @cols), trunc(b * 8), p * 6}, rand}
      end)

    %{face: face, rim: rim(), hidden: hidden, stars: stars, key: -1, h: nil, base: nil}
  end

  # The face of the quadrants, cell by cell: its angle round the arc, the
  # span of angles its corners cover, and whether an hour line crosses it.
  defp face do
    for r <- floor(@yc)..(@rows - 1),
        c <- 0..(@cols - 1),
        e = JSMath.hypot((c + 0.5 - @cx) / @rx, (r + 0.5 - @yc) / @ry),
        e < 1 and e > @inner do
      corners = for {x, y} <- [{c, r}, {c + 1, r}, {c, r + 1}, {c + 1, r + 1}], do: angle(x, y)
      {lo, hi} = Enum.min_max(corners)
      hour = floor(hi / (:math.pi() / 12)) != floor(lo / (:math.pi() / 12))
      {r * @cols + c, angle(c + 0.5, r + 0.5), lo, hi, hour}
    end
  end

  # The outer rim of the face, traced as a line: one cell a row where it
  # stands upright, otherwise each cell takes the glyph for the slope and
  # height of the arc inside it, and only one cell a row takes a slant.
  # Upstream's Maps iterate in insertion order, so the cells are kept in it.
  defp rim do
    upright =
      for r <-
            Stream.iterate(JSMath.ceil(@yc - 0.5), &(&1 + 1))
            |> Enum.take_while(&((&1 + 0.5 - @yc) / @ry < @up)),
          q = (r + 0.5 - @yc) / @ry,
          w = @rx * :math.sqrt(1 - q * q),
          k <- [r * @cols + floor(@cx - w), r * @cols + floor(@cx + w)],
          into: %{},
          do: {k, "|"}

    {acc, order} =
      Enum.reduce(0..1200, {%{}, []}, fn i, {acc, order} = state ->
        p = (i / 1200 * 2 - 1) * (:math.pi() / 2)
        sin = :math.sin(p)
        cos = :math.cos(p)
        x = @cx + @rx * sin
        y = @yc + @ry * cos

        if (floor(y) + 0.5 - @yc) / @ry < @up do
          state
        else
          k = floor(y) * @cols + floor(x)
          {n, fy, phi, west} = Map.get(acc, k, {0, 0, 0, p < 0})

          e =
            {n + 1, fy + (y - floor(y)), phi + :math.atan2(2 * @ry * abs(sin), @rx * cos), west}

          {Map.put(acc, k, e), if(Map.has_key?(acc, k), do: order, else: [k | order])}
        end
      end)

    order = Enum.reverse(order)
    id = fn k, west -> div(k, @cols) * 2 + if(west, do: 0, else: 1) end

    # The fullest steep cell on each row and side.
    most =
      Enum.reduce(order, %{}, fn k, most ->
        {n, _, phi, west} = Map.fetch!(acc, k)

        held =
          case Map.fetch(most, id.(k, west)) do
            {:ok, j} -> elem(Map.fetch!(acc, j), 0)
            :error -> 0
          end

        if phi / n > 1.08 and n > held, do: Map.put(most, id.(k, west), k), else: most
      end)

    Enum.reduce(order, upright, fn k, rim ->
      {n, fy, phi, west} = Map.fetch!(acc, k)

      case Map.fetch(most, id.(k, west)) do
        {:ok, ^k} ->
          Map.put(rim, k, if(west, do: "\\", else: "/"))

        {:ok, s} ->
          if n > elem(Map.fetch!(acc, s), 0) * 0.7,
            do: Map.put(rim, k, slope(fy / n, phi / n)),
            else: rim

        :error ->
          Map.put(rim, k, slope(fy / n, phi / n))
      end
    end)
  end

  defp slope(fy, _phi) when fy < 0.4, do: "'"
  defp slope(fy, phi) when fy > 0.6, do: if(phi > 0.2, do: ".", else: "_")
  defp slope(_fy, _phi), do: "-"

  defp put(grid, c, r, g) do
    c = floor(c)
    r = floor(r)

    if c >= 0 and c < @cols and r >= 0 and r < @rows,
      do: Map.put(grid, r * @cols + c, g),
      else: grid
  end

  defp text(grid, c, r, s) do
    s
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.reduce(grid, fn
      {" ", _}, grid -> grid
      {g, i}, grid -> put(grid, c + i, r, g)
    end)
  end

  # Everything but the sky, drawn once a minute for the hour angle `h` (nil
  # at night).
  defp draw(state, h) do
    grid = shade(state, h)
    grid = Map.merge(grid, state.rim)

    # Hour numbers just inside the face, morning on the west quadrant.
    grid =
      Enum.reduce(Enum.reject(-6..6, &(&1 == 0)), grid, fn hr, grid ->
        p = hr * :math.pi() / 12
        s = Integer.to_string(if hr < 0, do: 12 + hr, else: hr)

        text(
          grid,
          JSMath.round(@cx + @rx * (@inner - 0.09) * :math.sin(p) - String.length(s) / 2),
          @yc + @ry * (@inner - 0.12) * :math.cos(p),
          s
        )
      end)

    grid = grid |> walls() |> gnomon()
    List.to_tuple(for k <- 0..(@n - 1), do: Map.get(grid, k, " "))
  end

  # The face: lit marble with an hour line every fifteen degrees, and in
  # daylight the gnomon's shadow from its foot out to the hour angle on the
  # side away from the sun, its edge drawn hard. Near noon the edge would
  # fall behind the gnomon, so it is drawn against its foot.
  defp shade(state, h) do
    edge = if h, do: if(h == 0.0, do: -1, else: JSMath.sign(h)) * max(abs(h), state.hidden)

    Map.new(state.face, fn {k, psi, lo, hi, hour} ->
      # A soft fringe either side of the edge.
      d = (hi - lo) / 2

      g =
        cond do
          h == nil -> if hour, do: ":", else: "·"
          lo <= edge and edge <= hi -> "█"
          lo - d <= edge and edge <= hi + d -> "▓"
          psi * h >= 0 and abs(psi) <= abs(h) -> "▒"
          hour -> ":"
          true -> "·"
        end

      {k, g}
    end)
  end

  # The end walls the quadrants' tips stand on, and arches in the masonry.
  defp walls(grid) do
    top = floor(@yc) - 1

    grid =
      Enum.reduce([-1, 1], grid, fn s, grid ->
        wall = floor(@cx + s * @rx)
        grid = Enum.reduce(floor(@yc)..(@ground - 1), grid, &put(&2, wall, &1, "|"))
        grid = put(grid, wall, top, "_")

        grid =
          Stream.iterate(1, &(&1 + 1))
          |> Enum.take_while(&(&1 < @rx * (1 - @inner) - 0.5))
          |> Enum.reduce(grid, &put(&2, wall - s * &1, top, "_"))

        Enum.reduce([16, 21], grid, fn dx, grid ->
          at = floor(@cx + s * dx) - 1
          grid |> text(at, @ground - 2, "╭─╮") |> text(at, @ground - 1, "│ │")
        end)
      end)

    Enum.reduce(0..(@cols - 1), grid, &put(&2, &1, @ground, "▀"))
  end

  # The gnomon in front, narrowing as it climbs away: its stairs up the
  # middle between two rails, and the chhatri on top.
  defp gnomon(grid) do
    grid =
      Enum.reduce(@apex..(@ground - 1), grid, fn r, grid ->
        w = half(r)

        grid =
          Stream.iterate(JSMath.ceil(@cx - w), &(&1 + 1))
          |> Enum.take_while(&(&1 < @cx + w))
          |> Enum.reduce(grid, &put(&2, &1, r, "="))

        grid = grid |> put(@cx - w, r, "/") |> put(@cx + w, r, "\\")

        if w > 2,
          do: grid |> put(@cx - w + 1, r, "|") |> put(@cx + w - 1, r, "|"),
          else: grid
      end)

    grid
    |> text(floor(@cx) - 1, @apex - 2, "▗█▖")
    |> text(floor(@cx) - 1, @apex - 1, "│ │")
  end

  @impl true
  def frame(state, t, env) do
    ms = Clock.now_ms(env)
    now = Clock.local(env, ms)
    hours = now.hour + now.minute / 60
    day = (ms - jan1_ms(env, now.year)) / 864.0e5
    minute = floor(hours * 60)
    state = if minute != state.key, do: redraw(state, minute, hours, day), else: state

    out =
      if state.h == nil do
        Enum.reduce(state.stars, %{}, fn {c, r, ph}, out ->
          sky(out, state.base, c, r, if(:math.sin(t * 1.4 + ph) > 0.5, do: "+", else: "·"))
        end)
      else
        sun(state.base, state.h, t)
      end

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          k = r * @cols + c
          Map.get(out, k, elem(state.base, k))
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The hour angle, 15 degrees an hour from noon, and whether the sun is up
  # at Jaipur's latitude on this day of the year.
  defp redraw(state, minute, hours, day) do
    h = (hours - 12) * 15 * :math.pi() / 180
    dec = -23.44 * :math.pi() * :math.cos(2 * :math.pi() * (day + 10) / 365) / 180

    up =
      :math.cos(dec) * :math.cos(h) * :math.cos(@lat) + :math.sin(dec) * :math.sin(@lat) > 0

    h = if up, do: max(-:math.pi() / 2, min(:math.pi() / 2, h))
    %{state | key: minute, h: h, base: draw(state, h)}
  end

  # When local midnight on 1 January was, in milliseconds since the epoch:
  # in env.now's own offset, or the system's time zone.
  defp jan1_ms(%Env{now: nil}, year) do
    [utc | _] = :calendar.local_time_to_universal_time_dst({{year, 1, 1}, {0, 0, 0}})
    (:calendar.datetime_to_gregorian_seconds(utc) - 62_167_219_200) * 1000
  end

  defp jan1_ms(%Env{now: %DateTime{utc_offset: utc, std_offset: std}}, year) do
    wall =
      NaiveDateTime.diff(
        NaiveDateTime.new!(year, 1, 1, 0, 0, 0),
        ~N[1970-01-01 00:00:00],
        :millisecond
      )

    wall - (utc + std) * 1000
  end

  defp sky(out, base, c, r, g) do
    c = floor(c)
    r = floor(r)
    k = r * @cols + c

    if c >= 0 and c < @cols and r >= 0 and r < @rows and Map.get(out, k, elem(base, k)) == " ",
      do: Map.put(out, k, g),
      else: out
  end

  # The sun on its arc across the sky, east to the right, its rays
  # flickering between upright, all round and slanted.
  defp sun(base, h, t) do
    x = @cx - 24 * :math.sin(h)
    y = 1.5 + 4 * (1 - :math.cos(h))

    out =
      %{}
      |> sky(base, x, y, "O")
      |> sky(base, x - 1, y, "(")
      |> sky(base, x + 1, y, ")")

    rays =
      case rem(JSMath.floor(t / 0.45), 4) do
        0 -> @rays_up
        2 -> @rays_slant
        _ -> @rays_up ++ @rays_slant
      end

    Enum.reduce(rays, out, fn {dx, dy, g}, out -> sky(out, base, x + dx, y + dy, g) end)
  end
end
