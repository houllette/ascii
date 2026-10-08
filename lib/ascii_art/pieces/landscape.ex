defmodule AsciiArt.Pieces.Landscape do
  @moduledoc """
  A range and a lake under the sun or moon of the local hour.

  A range over a still lake, under the sky as it is right now for whoever is
  looking: the sun climbing or sinking by the local hour, or the moon in its
  real phase among the stars, with the range mirrored in the water.

  Reads the clock from `env.now` (see `AsciiArt.Kit.Clock`) every frame, as
  upstream reads `new Date()`. `hour` (0 to 24) and `phase` (the moon's age
  in lunations, 0 to 1) default to `nil`, the local time and the moon's real
  phase now.

  Ported from `src/pieces/landscape.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Clock, Hash}

  @meta %AsciiArt.Meta{
    name: "landscape",
    category: :nature,
    note: "a range and a lake under the sun or moon of the local hour",
    cols: 64,
    rows: 18,
    fps: 8,
    options: %{hour: nil, phase: nil},
    clock: true
  }

  @cols 64
  @rows 18
  # The bottom edge of this row is the waterline.
  @shore 11
  # The sun with its rays, centred on row 2, column 5; rows 1 to 3 are its disc.
  @sun ["  \\  |  /  ", "   .---.   ", "--(     )--", "   '---'   ", "  /  |  \\  "]
  # The moon's rim, drawn where it is lit, round a face (#) that takes the light.
  @moon ["  .-''-.  ", " /######\\ ", "|########|", " \\######/ ", "  '-..-'  "]
  # Face cells in its darker seas.
  @maria MapSet.new([{1, 4}, {2, 6}, {2, 7}, {3, 3}])
  # Clouds with flat bases: # is a cloud's body, which hides what is behind it.
  @cloud [
    "        .-~~-.          ",
    "   .-~~'######'-.  .-.  ",
    " .'##############'~###'.",
    "(______________________)"
  ]
  @puff ["   .-~~-.   ", " .'######'. ", "(__________)"]
  # Each cloud: {shape, row, columns behind the first}. They keep their
  # spacing as they drift, clear of each other and of the highest peak.
  @clouds [{@cloud, 0, 0}, {@puff, 2, 32}]
  # Columns a second.
  @drift 0.4
  @flip %{"/" => "\\", "\\" => "/"}

  # {x, height, west, east} peaks.
  @peaks [{13, 5, 10, 5}, {33, 4, 5, 6}, {43, 6, 6, 11}, {56, 3, 4, 5}]
  # Stars as {row, col, glyph, how dark it must be}: the Plough first, its
  # brightest out first after sunset, then fainter ones.
  @stars [
    {0, 45, "*", 0},
    {2, 45, ".", 0.15},
    {3, 50, ".", 0.15},
    {2, 52, ".", 0.3},
    {2, 56, "*", 0},
    {3, 59, ".", 0.1},
    {4, 61, "*", 0},
    {0, 7, ".", 0.5},
    {1, 24, "'", 0.7},
    {0, 34, ".", 0.4},
    {2, 3, ".", 0.8},
    {3, 13, "'", 0.6},
    {2, 30, ".", 0.9},
    {4, 37, ".", 0.75},
    {1, 39, "'", 0.55},
    {3, 21, ".", 0.85},
    {5, 4, ".", 0.65},
    {0, 17, ".", 0.45}
  ]

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{hour: hour, phase: phase}) do
    # A ridge from the peaks, steep at the summit and easing out, as one
    # stroke per column (up, down or along) with the row it sits in.
    e =
      0..@cols
      |> Enum.map_reduce(nil, fn x, prev ->
        f =
          Enum.reduce(@peaks, 0, fn {px, h, w, o}, f ->
            max(f, h * :math.pow(max(0, 1 - abs(x - px) / if(x < px, do: w, else: o)), 1.3))
          end)

        e = if prev, do: max(prev - 1, min(prev + 1, JSMath.round(f))), else: JSMath.round(f)
        {e, e}
      end)
      |> elem(0)
      |> List.to_tuple()

    range =
      for c <- 0..(@cols - 1) do
        a = elem(e, c)
        b = elem(e, c + 1)

        cond do
          b > a -> {@shore - a, "/"}
          b < a -> {@shore - b, "\\"}
          true -> {@shore - a, "_"}
        end
      end

    # The first row of land in each column.
    top = range |> Enum.map(&elem(&1, 0)) |> List.to_tuple()

    # The land: the ridge stroke, stippled below so it sits back.
    land =
      for r <- 0..@shore do
        range
        |> Enum.with_index()
        |> Enum.map(fn
          {{^r, ch}, _c} -> ch
          {{first, _}, c} -> if r > first and rem(c + r, 2) == 1, do: ".", else: " "
        end)
        |> List.to_tuple()
      end

    # Its outline upside down in the water: the slopes only, the flats along
    # the shore left out.
    mirror =
      for {{r, ch}, c} <- Enum.with_index(range),
          Map.has_key?(@flip, ch) or r < @shore,
          do: {2 * @shore + 1 - r, c, Map.get(@flip, ch, "-")}

    # Ripples: {row, start column, length, columns a second}, one short one
    # a row below the first, a little longer toward the near shore.
    ripples =
      for k <- 2..(@rows - @shore - 1) do
        {@shore + k, floor(Hash.short(k, 7) * @cols), if(k > 4, do: 3, else: 2),
         if(rem(k, 2) == 1, do: 0.3, else: -0.25)}
      end

    %{
      hour: hour,
      phase: phase,
      top: top,
      land: List.to_tuple(land),
      mirror: mirror,
      ripples: ripples
    }
  end

  # Where a body stands for its hour on a 12 hour arc that starts at 0, as
  # the column and row of its middle.
  defp place(u) do
    alt = :math.sin(:math.pi() * u)

    {JSMath.round(5 + (@cols - 11) * u),
     JSMath.round(@shore + 2 - @shore * :math.pow(max(0, alt), 0.45))}
  end

  # The moon's age in lunations from a known new moon (6 Jan 2000, 18:14 UTC).
  defp lunation(ms) do
    JSMath.mod(JSMath.mod((ms / 864.0e5 - 10_962.76) / 29.530588853, 1) + 1, 1)
  end

  @impl true
  def frame(state, t, env) do
    ms = Clock.now_ms(env)
    now = Clock.local(env, ms)
    h = state.hour || now.hour + now.minute / 60
    age = state.phase || lunation(ms)

    # 0 at six in the morning, 1 at six in the evening.
    sun_u = JSMath.mod(JSMath.mod(h - 6, 24) + 24, 24) / 12
    day = sun_u < 1
    dark = if day, do: 0, else: min(1, :math.sin(:math.pi() * (sun_u - 1)) * 5)
    # The water's glints change twice a second.
    step = floor(t * 2)
    # The moon keeps the sun's hours, late by its age: full moons rise at dusk.
    moon_u = JSMath.mod(JSMath.mod(sun_u - age * 2, 2) + 2, 2)
    {cx, cy} = if day, do: place(sun_u), else: place(min(moon_u, 1.5))
    up = day or moon_u < 1

    sc = %{
      top: state.top,
      cloud: clouds(state.top, cx, t),
      day: day,
      up: up,
      cx: cx,
      cy: cy,
      age: age
    }

    g = Enum.reduce(@stars, %{}, &star(&1, &2, sc, dark, step))
    {g, lit, full} = body(g, sc)

    g =
      for {{r, c}, ch} <- sc.cloud, r <= @shore, reduce: g do
        g -> Map.put(g, {r, c}, ch)
      end

    # The water: the range's outline upside down, a few ripples drifting
    # along it, and a path of light under the sun or moon kept clear of the
    # rest.
    g =
      for {r, c, ch} <- state.mirror, r < @rows, reduce: g do
        g -> Map.put(g, {r, c}, ch)
      end

    g = Enum.reduce(state.ripples, g, &ripple(&1, &2, t, state.land))
    g = if lit > 2, do: path(g, cx, full, step), else: g

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(g, {r, c}, base(state.land, r, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp base(land, r, c) when r <= @shore, do: elem(elem(land, r), c)
  defp base(_land, _r, _c), do: " "

  defp sky?(top, r, c), do: r >= 0 and c >= 0 and c < @cols and r < elem(top, c)
  defp ground?(top, r, c), do: c >= 0 and c < @cols and r >= elem(top, c) and r <= @shore

  # Clouds drift across in front of it all, and come round again. They set
  # out from across the sky, so the first frame shows the sun or moon clear.
  defp clouds(top, cx, t) do
    w0 = String.length(hd(@cloud))
    span = @cols + w0

    for {shape, r0, d} <- @clouds,
        x = floor(JSMath.mod(cx + 15 + d + w0 + @drift * t, span) - w0),
        {line, i} <- Enum.with_index(shape),
        {ch, k} <- Enum.with_index(String.codepoints(line)),
        ch != " " and sky?(top, r0 + i, x + k),
        reduce: %{} do
      cloud -> Map.put(cloud, {r0 + i, x + k}, if(ch == "#", do: " ", else: ch))
    end
  end

  defp clouded?(cloud, r, c) do
    Enum.any?(-1..1, fn dr -> Enum.any?(-1..1, &Map.has_key?(cloud, {r + dr, c + &1})) end)
  end

  # Stars keep a cell clear of clouds and of the moon; the faint ones
  # twinkle.
  defp star({row, col, ch, need}, g, sc, dark, step) do
    near =
      clouded?(sc.cloud, row, col) or
        (sc.up and not sc.day and abs(col - sc.cx) <= 6 and abs(row - sc.cy) <= 3)

    cond do
      dark <= need or not sky?(sc.top, row, col) or near -> g
      need > 0.3 and Hash.short(col, step) < 0.15 -> Map.put(g, {row, col}, " ")
      true -> Map.put(g, {row, col}, ch)
    end
  end

  # Draws a cell of the sun or moon, counting what shows of its body. A ray
  # or rim stroke beside land or cloud would read as part of it, so it goes.
  defp put({g, lit}, sc, r, c, ch, solid, body) do
    cond do
      not sky?(sc.top, r, c) or Map.has_key?(sc.cloud, {r, c}) ->
        {g, lit}

      not solid and crowded?(sc, r, c) ->
        {g, lit}

      true ->
        {Map.put(g, {r, c}, ch), if(body, do: lit + 1, else: lit)}
    end
  end

  defp crowded?(sc, r, c) do
    Enum.any?(-1..1, fn dr ->
      Enum.any?(-1..1, fn dc ->
        ground?(sc.top, r + dr, c + dc) or Map.has_key?(sc.cloud, {r + dr, c + dc})
      end)
    end)
  end

  defp body(g, %{day: true} = sc) do
    {g, lit} =
      for {line, i} <- Enum.with_index(@sun),
          {ch, k} <- Enum.with_index(String.codepoints(line)),
          ch != " ",
          reduce: {g, 0} do
        acc ->
          disc = if i == 2, do: k > 1 and k < 9, else: rem(i, 2) == 1 and k > 2 and k < 8
          put(acc, sc, sc.cy - 2 + i, sc.cx - 5 + k, ch, disc, disc)
      end

    {g, lit, 1}
  end

  defp body(g, %{up: true, age: age} = sc) do
    # Lit where the sunward side is: waxing on the right, waning on the left.
    k = :math.cos(2 * :math.pi() * JSMath.mod(age, 0.5))

    edge =
      cond do
        k > 0.25 -> ")"
        k < -0.25 -> "("
        true -> "|"
      end

    full = (1 - :math.cos(2 * :math.pi() * age)) / 2

    {g, lit} =
      for {line, i} <- Enum.with_index(@moon),
          {ch, j} <- Enum.with_index(String.codepoints(line)),
          ch != " ",
          reduce: {g, 0} do
        acc -> moon_cell(acc, sc, i, j, ch, k, edge)
      end

    {g, lit, full}
  end

  defp body(g, _sc), do: {g, 0, 1}

  defp shine(x, y, age, k) do
    x * x + y * y <= 1 and age < 0.5 == x > k * :math.sqrt(max(0, 1 - y * y))
  end

  defp moon_cell({g, lit} = acc, sc, i, j, ch, k, edge) do
    r = sc.cy - 2 + i
    c = sc.cx - 5 + j
    x = (j + 0.5 - 5) / 5
    y = (i + 0.5 - 2.5) / 2.5

    if ch != "#" do
      # A rim cell is lit by the edge of the face it lies on.
      s = 0.97 / JSMath.hypot(x, y)
      if shine(x * s, y * s, sc.age, k), do: put(acc, sc, r, c, ch, false, true), else: acc
    else
      on =
        Enum.count(0..8, fn q ->
          shine(x + (rem(q, 3) - 1) / 15, y + (div(q, 3) - 1) / 7.5, sc.age, k)
        end)

      cond do
        on >= 6 ->
          put(acc, sc, r, c, if(MapSet.member?(@maria, {i, j}), do: ".", else: ":"), true, true)

        on >= 2 ->
          put(acc, sc, r, c, edge, true, true)

        sky?(sc.top, r, c) ->
          {Map.put(g, {r, c}, " "), lit}

        true ->
          acc
      end
    end
  end

  # A ripple keeps a cell clear of the reflection on either side.
  defp ripple({r, c0, n, v}, g, t, land) do
    x = floor(JSMath.mod(JSMath.mod(c0 + v * t, @cols + 4) + @cols + 4, @cols + 4)) - 2

    clear =
      Enum.all?((x - 1)..(x + n)//1, fn c ->
        c < 0 or c >= @cols or Map.get(g, {r, c}, base(land, r, c)) == " "
      end)

    if clear,
      do: Enum.reduce(max(0, x)..(min(@cols, x + n) - 1)//1, g, &Map.put(&2, {r, &1}, "-")),
      else: g
  end

  # A thin moon lays a narrow, broken path; the sun or a full moon a broad one.
  defp path(g, cx, full, step) do
    mid = cx + 0.5

    for r <- (@shore + 1)..(@rows - 1),
        w = 0.6 + (r - @shore) * (0.15 + full * 0.45),
        c <- floor(mid - w - 1)..floor(mid + w + 1)//1,
        c >= 0 and c < @cols,
        reduce: g do
      g ->
        d = abs(c + 0.5 - mid)

        ch =
          cond do
            d > w or Hash.short(c * 31 + r, step) < 0.2 + 0.4 * (1 - full) -> " "
            d < w * 0.5 and full > 0.5 -> "="
            true -> "-"
          end

        Map.put(g, {r, c}, ch)
    end
  end
end
