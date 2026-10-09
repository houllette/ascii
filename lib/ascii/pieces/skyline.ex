defmodule Ascii.Pieces.Skyline do
  @moduledoc """
  A city at night, windows going on and off, a blinking mast.

  A city at night across a river. Office windows go on and off, sometimes a
  whole floor at once, the mast on the tallest tower blinks, and the low
  lights and the moon are drawn down into the water as streaks.

  Ported from `src/pieces/skyline.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Rand

  @meta %Ascii.Meta{
    name: "skyline",
    category: :objects,
    note: "a city at night, windows going on and off, a blinking mast",
    cols: 64,
    rows: 23,
    fps: 10
  }

  @cols 64
  @rows 23
  # The embankment row; towers stand on it, water below.
  @base 18
  # The share of windows lit, which the night drifts back toward.
  @share 0.4

  # Far towers in haze: left column, width, height in rows.
  @far [{3, 6, 9}, {14, 6, 12}, {25, 5, 9}, {36, 6, 12}, {48, 7, 10}, {57, 6, 12}]
  # Near towers: left column, width, height, then the setbacks stacked on
  # top, each as {inset, rows}, and what stands on the roof.
  @near [
    {-3, 8, 5, [], nil},
    {6, 7, 8, [], :tank},
    {13, 5, 6, [], nil},
    {19, 9, 10, [{1, 1}, {1, 1}, {1, 1}], nil},
    {29, 7, 13, [{1, 1}], :mast},
    {37, 5, 7, [], nil},
    {42, 7, 10, [], :spire},
    {50, 5, 5, [], nil},
    {55, 11, 8, [{1, 2}], :crown}
  ]
  # Rooftop things, bottom row first, centred over the top tier.
  @tops %{
    tank: ["╨ ╨", "▄▄▄"],
    mast: ["╱│╲", " │ ", " │ "],
    spire: ["╱   ╲", " ╱ ╲ ", "  ╿  "],
    crown: ["╭───╮", " ╭─╮ "]
  }
  @stars [
    {1, 18},
    {4, 23},
    {2, 27},
    {6, 40},
    {1, 45},
    {7, 61},
    {3, 56},
    {5, 50},
    {0, 36},
    {3, 38},
    {8, 1},
    {0, 59}
  ]
  # The moon's centre column, centre row, radius in rows.
  @mx 9
  @my 3.5
  @mr 1.9
  @quad {" ", "▗", "▖", "▄", "▝", "▐", "▞", "▟", "▘", "▚", "▌", "▙", "▀", "▜", "▛", "█"}
  @streak {"╎", "╎", "┊", "·"}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    rand = Rand.seed(19)
    {city, panes} = city()

    # A far pane only shows where no near tower stands in front of it.
    shown =
      for {r, c, far, _n} = pane <- panes,
          c >= 0 and c < @cols and (not far or Map.get(city, r * @cols + c) == "░"),
          do: pane

    {mast_x, w, h, _, _} = Enum.find(@near, &(elem(&1, 4) == :mast))

    # Every pane keeps whether it is lit.
    {lit, rand} =
      Enum.map_reduce(shown, rand, fn _, rand ->
        {x, rand} = Rand.next(rand)
        {x < @share, rand}
      end)

    %{
      city: List.to_tuple(for k <- 0..(@base * @cols - 1), do: Map.get(city, k, " ")),
      shown: List.to_tuple(shown),
      light: {@base - h - 5, mast_x + Bitwise.bsr(w, 1)},
      moon: moon(),
      lit: List.to_tuple(lit),
      rand: rand,
      next: 0.2,
      floor: 0.9,
      clock: 0
    }
  end

  # The still part of the city, drawn once: far towers as haze, near ones as
  # outlines round a grid of panes, each setback's walls landing on the tier
  # below it. Panes are {row, col, far, tower}.
  defp city do
    {city, panes} =
      Enum.reduce(@far, {%{}, []}, fn {x, w, h}, {city, panes} ->
        city =
          for r <- (@base - h)..(@base - 1), c <- x..(x + w - 1), reduce: city do
            city -> set(city, c, r, "░")
          end

        panes =
          for r <- (@base - h + 1)..(@base - 1)//2,
              c <- (x + 1)..(x + w - 2)//2,
              reduce: panes,
              do: (panes -> [{r, c, true, -1} | panes])

        {city, panes}
      end)

    {city, panes} =
      @near
      |> Enum.with_index()
      |> Enum.reduce({city, panes}, &near/2)

    {city, Enum.reverse(panes)}
  end

  defp near({{x, w, h, steps, top}, n}, {city, panes}) do
    l = x
    rgt = x + w - 1
    t = @base - h
    acc = Enum.reduce((t + 1)..(@base - 1)//1, {city, panes}, &tier(&2, &1, l, rgt, n))
    {city, panes} = acc
    city = roof(city, t, l, rgt)

    {city, panes, l, rgt, t} =
      Enum.reduce(steps, {city, panes, l, rgt, t}, fn {inset, tall}, {city, panes, l, rgt, t} ->
        l = l + inset
        rgt = rgt - inset
        city = city |> set(l, t, "┴") |> set(rgt, t, "┴")

        {city, panes} =
          Enum.reduce((t - tall + 1)..(t - 1)//1, {city, panes}, &tier(&2, &1, l, rgt, n))

        t = t - tall
        {roof(city, t, l, rgt), panes, l, rgt, t}
      end)

    city =
      @tops
      |> Map.get(top, [])
      |> Enum.with_index()
      |> Enum.reduce(city, fn {s, i}, city ->
        len = String.length(s)

        s
        |> String.codepoints()
        |> Enum.with_index()
        |> Enum.reduce(city, fn
          {" ", _}, city -> city
          {g, j}, city -> set(city, floor((l + rgt + 1 - len) / 2) + j, t - 1 - i, g)
        end)
      end)

    {city, panes}
  end

  defp tier({city, panes}, r, l, rgt, n) do
    city =
      Enum.reduce(l..rgt, city, fn c, city ->
        set(city, c, r, if(c == l or c == rgt, do: "│", else: " "))
      end)

    panes = Enum.reduce((l + 2)..(rgt - 1)//2, panes, &[{r, &1, false, n} | &2])
    {city, panes}
  end

  defp roof(city, t, l, rgt) do
    Enum.reduce(l..rgt, city, &set(&2, &1, t, roof_glyph(&1, l, rgt)))
  end

  defp roof_glyph(c, c, _rgt), do: "┌"
  defp roof_glyph(c, _l, c), do: "┐"
  defp roof_glyph(_c, _l, _rgt), do: "─"

  defp set(city, c, r, g) when c >= 0 and c < @cols and r >= 0,
    do: Map.put(city, r * @cols + c, g)

  defp set(city, _c, _r, _g), do: city

  # The moon, a crescent drawn in quadrant blocks: lit where inside its disc
  # and outside the shadow's.
  defp moon do
    for r <- floor(@my - @mr)..floor(@my + @mr),
        c <- floor(@mx - 2 * @mr)..floor(@mx + 2 * @mr),
        q = quadrants(r, c),
        q != 0,
        do: {r, c, elem(@quad, q)}
  end

  defp quadrants(r, c) do
    Enum.reduce([{8, 0.25, 0.25}, {4, 0.75, 0.25}, {2, 0.25, 0.75}, {1, 0.75, 0.75}], 0, fn
      {b, dx, dy}, q ->
        x = (c + dx - @mx) / 2
        y = r + dy - @my

        if JSMath.hypot(x, y) < @mr and JSMath.hypot(x - 1.1, y) > @mr * 0.95,
          do: Bitwise.bor(q, b),
          else: q
    end)
  end

  # One pane changes at a time, and below the share, lighting one is
  # likelier than putting one out; every couple of seconds a whole floor of
  # one near tower switches together.
  defp advance(%{next: next, floor: floor} = state, t) when next > t and floor > t, do: state

  defp advance(%{lit: lit, rand: rand} = state, t) do
    count = tuple_size(lit)
    share = Enum.count(Tuple.to_list(lit), & &1) / count
    {x, rand} = Rand.next(rand)
    on = x < 0.5 + (@share - share) * 4

    state =
      if state.floor < state.next do
        {w, rand} = pick(state, rand, on, true)
        {r, _, _, n} = elem(state.shown, w)

        lit =
          state.shown
          |> Tuple.to_list()
          |> Enum.zip(Tuple.to_list(lit))
          |> Enum.map(fn
            {{^r, _, _, ^n}, _} -> on
            {_, was} -> was
          end)
          |> List.to_tuple()

        {y, rand} = Rand.next(rand)
        %{state | lit: lit, rand: rand, floor: state.floor + (1.6 + y * 1.2)}
      else
        {w, rand} = pick(state, rand, on, false)
        {y, rand} = Rand.next(rand)
        %{state | lit: put_elem(lit, w, on), rand: rand, next: state.next + (0.12 + y * 0.3)}
      end

    advance(state, t)
  end

  defp pick(%{lit: lit, shown: shown}, rand, on, near) do
    {x, rand} = Rand.next(rand)
    count = tuple_size(lit)
    w = trunc(x * count)

    w =
      Enum.reduce_while(0..(count - 1)//1, w, fn _, w ->
        if elem(lit, w) == on or (near and elem(elem(shown, w), 2)),
          do: {:cont, rem(w + 1, count)},
          else: {:halt, w}
      end)

    {w, rand}
  end

  @impl true
  def frame(state, t, _env) do
    clock = state.clock + min(max(t - state.clock, 0), 1)
    state = advance(%{state | clock: clock}, clock)

    {grid, glow} =
      state.shown
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(state.lit))
      |> Enum.reduce({%{}, %{}}, fn {{r, c, far, _}, lit}, {grid, glow} ->
        g =
          cond do
            far and lit -> "▓"
            far -> "░"
            lit -> "▀"
            true -> "·"
          end

        glow =
          if lit and not far and r > @base - 4,
            do: Map.update(glow, c, r - (@base - 4), &max(&1, r - (@base - 4))),
            else: glow

        {Map.put(grid, r * @cols + c, g), glow}
      end)

    at = fn grid, k -> Map.get_lazy(grid, k, fn -> city_at(state.city, k) end) end

    # The sky: stars that twinkle, the moon, and the blinking mast.
    grid =
      Enum.reduce(@stars, grid, fn {r, c}, grid ->
        if at.(grid, r * @cols + c) == " ",
          do:
            Map.put(
              grid,
              r * @cols + c,
              if(:math.sin(clock * 1.3 + c * 2) > 0.7, do: "+", else: "·")
            ),
          else: grid
      end)

    grid =
      Enum.reduce(state.moon, grid, fn {r, c, g}, grid -> Map.put(grid, r * @cols + c, g) end)

    {lr, lc} = state.light
    grid = Map.put(grid, lr * @cols + lc, if(JSMath.mod(clock, 1.6) < 0.4, do: "*", else: "·"))
    grid = water(grid, glow, clock)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: at.(grid, r * @cols + c)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp moon_streak(1), do: "═"
  defp moon_streak(2), do: "="
  defp moon_streak(_k), do: "-"

  defp city_at(city, k) when k < @base * @cols, do: elem(city, k)
  defp city_at(_city, _k), do: " "

  # The embankment, then the water: under each low light and under the
  # moon, a streak running straight down, broken by ripples and thinning
  # with depth.
  defp water(grid, glow, clock) do
    grid = Enum.reduce(0..(@cols - 1), grid, &Map.put(&2, @base * @cols + &1, "▀"))

    for k <- 1..(@rows - @base - 1), c <- 0..(@cols - 1), reduce: grid do
      grid ->
        m = abs(c + 0.5 - (@mx - 1)) < 2.8 - k * 0.45
        g = Map.get(glow, c, 0)

        if m or g != 0 do
          ripple =
            :math.sin(c * 1.7 + k * 2.3 - clock * 3.1) +
              0.6 * :math.sin(c * 0.53 - k * 1.3 + clock * 1.9)

          cond do
            m and ripple > -1.1 + k * 0.35 ->
              Map.put(grid, (@base + k) * @cols + c, moon_streak(k))

            g != 0 and ripple > -0.9 + k * 0.45 - g * 0.2 ->
              Map.put(grid, (@base + k) * @cols + c, elem(@streak, k - 1))

            true ->
              grid
          end
        else
          grid
        end
    end
  end
end
