defmodule Ascii.Pieces.Rocket do
  @moduledoc """
  A rocket lifting off its pad at night, then landing back.

  A night launch. Boil-off vents from the upper stage, the arm swings back,
  the engine lights, exhaust billows out of the trench and the rocket climbs
  out of the frame. It comes back down on a landing burn and settles.

  Ported from `src/pieces/rocket.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Rand

  @meta %Ascii.Meta{
    name: "rocket",
    category: :space,
    note: "a rocket lifting off its pad at night, then landing back",
    cols: 48,
    rows: 28,
    fps: 20
  }

  # w is white paint, k the dark interstage, g the bare metal of the bell;
  # each is shaded as a cylinder lit from the tower's floodlights on the left.
  @rocket [
    "      /\\      ",
    "     /ww\\     ",
    "    /wwww\\    ",
    "   /wwwwww\\   ",
    "   |wwwwww|   ",
    "   |wwwwww|   ",
    "   \\wwwwww/   ",
    "    |wwww|    ",
    "    |wwww|    ",
    "   /kkkkkk\\   ",
    "   |wwwwww|   ",
    "   |wwwwww|   ",
    "   |wwwwww|   ",
    "   |wwwwww|   ",
    "   |wwwwww|   ",
    "  /|wwwwww|\\  ",
    " /f|wwwwww|f\\ ",
    "/ff|wwwwww|ff\\",
    "    \\gggg/    ",
    "    /gggg\\    ",
    "   /gggggg\\   "
  ]
  @tone %{"w" => 1, "k" => 0.42, "g" => 0.62, "f" => 0.6}
  @body {" ", ".", ":", "-", "=", "+", "*", "#", "%"}
  # Smoke is drawn as how much of it there is, not as light, so its ramp keeps
  # its sense on paper, and it stops at % so the clouds stay soft.
  @smoke {" ", ".", ":", "-", "=", "+", "*", "#", "%"}
  @flame {"░", "▒", "▓", "█"}
  @loop 18
  # The service arm starts to swing away.
  @arm 0.8
  # Engine lights.
  @ignite 1.5
  # The clamps let go.
  @lift 3
  # Rows per second squared on the way up.
  @climb 2.6
  # Rows above the pad where it is well out of sight.
  @out 40
  # Touchdown.
  @land 14.6
  # Braking on the landing burn, which starts out of sight.
  @decel 4.4
  # Exhaust puffs a second.
  @rate 36

  @w 14
  @ht 21
  @left div(48 - @w, 2)
  @mid @left + @w / 2 - 0.5
  # The pad's deck; the base of the rocket sits on the row above.
  @pad 28 - 2
  @tower @left - 8
  # Level with the upper stage.
  @arm_row @pad - @ht + 8

  @impl true
  def meta, do: @meta

  defp burn, do: :math.sqrt(2 * @out / @decel)

  # Rows the rocket's base stands above the pad at time t in the loop, or -1
  # while it is out of sight.
  defp height(t) when t < @lift or t >= @land, do: 0

  defp height(t) do
    d = t - @lift
    up = 0.5 * @climb * (d * d)
    left = @land - t

    cond do
      up < @out -> up
      left < burn() -> 0.5 * @decel * left * left
      true -> -1
    end
  end

  defp burning?(t), do: t >= @ignite and t < @land and height(t) >= 0
  defp on_pad?(t), do: t < @arm - 0.3 or t >= @land + 1

  @impl true
  def init(_options) do
    %{cols: cols} = @meta
    rand = Rand.seed(3)

    # The sprite, shaded once for a dark page and once for paper.
    sprite = for paper <- [false, true], do: List.to_tuple(Enum.map(@rocket, &shade(&1, paper)))

    # The rocket is solid from its first mark to its last on every row.
    span =
      for line <- @rocket do
        chars = String.graphemes(line)
        {Enum.find_index(chars, &(&1 != " ")), String.length(String.trim_trailing(line))}
      end

    # Stars, kept off the rocket, its vapour and the tower's top so none reads
    # as a spark.
    {stars, rand} =
      for r <- 0..(@pad - 10), c <- 0..(cols - 1), reduce: {[], rand} do
        {stars, rand} ->
          by_rocket =
            c >= @left - 2 and c <= @left + @w + 1 + if(abs(r - @arm_row) < 4, do: 12, else: 0) and
              r >= @pad - @ht - 2

          by_tower = abs(c - @tower - 1) < 4 and r >= @pad - 24
          {a, rand} = Rand.next(rand)

          if a < 0.026 and not by_rocket and not by_tower do
            {ph, rand} = Rand.next(rand)
            {big, rand} = Rand.next(rand)
            {[{c, r, ph * 6.283, big < 0.2} | stars], rand}
          else
            {stars, rand}
          end
      end

    # Every puff of exhaust keeps its own spread, speed and life.
    {puffs, _} =
      Enum.map_reduce(1..ceil(@loop * @rate), rand, fn _, rand ->
        {[jx, side, fan, rise, life, grow], rand} = Rand.take(rand, 6)

        {%{
           jx: (jx - 0.5) * 2.4,
           side: if(side < 0.5, do: -1, else: 1),
           fan: 14 + fan * 12,
           rise: 0.5 + rise * 0.9,
           life: 2.2 + life * 1.4,
           grow: 0.6 + grow * 0.6
         }, rand}
      end)

    %{
      sprite: List.to_tuple(sprite),
      span: span,
      stars: Enum.reverse(stars),
      puffs: puffs |> Enum.with_index() |> Enum.map(fn {p, k} -> Map.put(p, :born, k / @rate) end)
    }
  end

  defp shade(line, paper) do
    chars = String.graphemes(line)
    a = Enum.find_index(chars, &(&1 in ["w", "k", "g"]))
    b = if a, do: last_index(chars, Enum.at(chars, a)) + 1, else: 0

    chars
    |> Enum.with_index()
    |> Enum.map(fn {ch, c} ->
      case @tone do
        %{^ch => tone} ->
          x = (c + 0.5 - @w / 2) / ((b - (a || -1)) / 2 + 0.5)
          i = max(1, JSMath.round(tone * (0.12 + 0.88 * lit(ch, x)) * (tuple_size(@body) - 1)))
          elem(@body, if(paper, do: tuple_size(@body) - i, else: i))

        _ ->
          ch
      end
    end)
    |> List.to_tuple()
  end

  defp last_index(chars, ch) do
    chars |> Enum.with_index() |> Enum.filter(&(elem(&1, 0) == ch)) |> List.last() |> elem(1)
  end

  # The fins are flat, so each takes one tone.
  defp lit("f", x), do: if(x < 0, do: 0.75, else: 0.3)
  defp lit(_ch, x), do: max(0, -0.72 * x + 0.69 * :math.sqrt(max(0, 1 - x * x)))

  @impl true
  def frame(state, time, env) do
    %{cols: cols, rows: rows} = @meta
    t = JSMath.mod(JSMath.mod(time, @loop) + @loop, @loop)

    grid =
      Enum.reduce(state.stars, %{}, fn {c, r, ph, big}, grid ->
        tw = :math.sin(time * 1.7 + ph)

        ch =
          cond do
            big -> if tw > 0.3, do: "+", else: "*"
            tw > -0.6 -> "."
            true -> " "
          end

        put(grid, c, r, ch)
      end)

    grid = grid |> tower(time, t) |> smoke(exhaust(state.puffs, t))

    # The two stands the fins rest on.
    grid =
      Enum.reduce((@pad - 3)..(@pad - 1), grid, fn r, grid ->
        grid |> put(@left, r, "[") |> put(@left + @w - 1, r, "]")
      end)

    h = height(t)
    grid = if h >= 0, do: rocket(grid, state, h, time, t, env.paper), else: grid

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(grid, r * cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp put(grid, x, y, ch) do
    %{cols: cols, rows: rows} = @meta
    c = JSMath.round(x)
    r = JSMath.round(y)

    if c >= 0 and c < cols and r >= 0 and r < rows,
      do: Map.put(grid, r * cols + c, ch),
      else: grid
  end

  # Tower, its beacon and the service arm; the deck, with the flame trench
  # under the engine.
  defp tower(grid, time, t) do
    %{cols: cols, rows: rows} = @meta

    grid =
      Enum.reduce((@pad - 20)..@pad, grid, fn r, grid ->
        grid
        |> put(@tower, r, "|")
        |> put(@tower + 2, r, "|")
        |> put(@tower + 1, r, if(rem(r, 2) == 1, do: "/", else: "\\"))
      end)

    grid =
      grid
      |> put(@tower + 1, @pad - 21, "|")
      |> put(
        @tower + 1,
        @pad - 22,
        if(rem(JSMath.floor(time * 1.25), 2) == 1, do: "*", else: ".")
      )

    swing =
      cond do
        t < @arm -> 1
        t < @ignite -> 1 - (t - @arm) / (@ignite - @arm)
        t < @land + 1 -> 0
        true -> min(1, (t - @land - 1) / 0.6)
      end

    grid =
      Enum.reduce(0..(JSMath.round(swing * (@left + 1 - @tower)) - 1)//1, grid, fn i, grid ->
        put(grid, @tower + 3 + i, @arm_row, "=")
      end)

    grid = Enum.reduce(0..(cols - 1), grid, &put(&2, &1, rows - 1, "▀"))

    Enum.reduce(2..(cols - 3), grid, fn c, grid ->
      put(grid, c, @pad, if(abs(c - @mid) < 4, do: " ", else: "_"))
    end)
  end

  # Exhaust, from every puff still alive. Births are on a fixed beat, so a
  # puff's age and where it was born follow from t alone. Each puff is a
  # splat of fog, in upstream's order.
  defp exhaust(puffs, t) do
    for %{born: born, life: life} = p <- puffs,
        age = t - born,
        age >= 0 and age <= life and burning?(born),
        h = height(born),
        # Coming down it flies into its own plume, so only the last rows of
        # the burn leave smoke.
        @pad - 1 - h >= -2 do
      puff(
        p,
        @mid,
        @pad - 0.5 - h,
        age,
        :math.exp(-h / if(born > @land - burn(), do: 4, else: 9))
      )
    end
  end

  # A puff leaves the nozzle going down; where it meets the deck it fans out
  # sideways, and either way it slows, swells, rises and thins.
  defp puff(p, x0, y0, age, thick) do
    down = 26 * 0.2 * (1 - :math.exp(-age / 0.2))
    y = y0 + down

    {x, y} =
      if y > @pad do
        hit = -0.2 * :math.log(1 - (@pad - y0) / (26 * 0.2))

        {x0 + p.jx + p.side * p.fan * 0.7 * (1 - :math.exp(-(age - hit) / 0.7)), @pad - 0.2}
      else
        {x0 + p.jx * (1 + age), y}
      end

    y = y - (p.rise * age * age * 0.5 + 0.3 * age)
    fade = max(0, 1 - age / p.life)
    splat(x + 0.8 * age, y, 1.2 + p.grow * age * 2.2, 0.9 * thick * fade * fade)
  end

  defp splat(x, y, rad, s) do
    %{cols: cols, rows: rows} = @meta
    ry = rad / 2

    {x, y, rad, ry, s, max(0, JSMath.ceil(y - ry)), min(rows - 1, JSMath.floor(y + ry)),
     max(0, JSMath.ceil(x - rad)), min(cols - 1, JSMath.floor(x + rad))}
  end

  # The fog the splats leave, a Float32Array summed splat by splat, row by
  # row here; where it is thick enough it is drawn as smoke.
  defp smoke(grid, splats) do
    %{cols: cols, rows: rows} = @meta
    last = tuple_size(@smoke) - 2

    Enum.reduce(0..(rows - 1), grid, fn r, grid ->
      over =
        for {x, y, rad, ry, s, r0, r1, c0, c1} <- splats, r >= r0 and r <= r1 do
          b = (r - y) / ry
          {x, rad, b * b, s, c0, c1}
        end

      if over == [] do
        grid
      else
        Enum.reduce(0..(cols - 1), grid, fn c, grid ->
          fog = fog(over, c, 0)

          if fog > 0.06 do
            i =
              1 + min(last, JSMath.floor((1 - :math.exp(-fog / 0.9)) * (tuple_size(@smoke) - 1)))

            Map.put(grid, r * cols + c, elem(@smoke, i))
          else
            grid
          end
        end)
      end
    end)
  end

  defp fog([], _c, fog), do: fog

  defp fog([{x, rad, bb, s, c0, c1} | rest], c, fog) when c >= c0 and c <= c1 do
    a = (c - x) / rad
    q = a * a + bb
    fog(rest, c, if(q < 1, do: JSMath.fround(fog + s * (1 - q)), else: fog))
  end

  defp fog([_ | rest], c, fog), do: fog(rest, c, fog)

  defp rocket(grid, state, h, time, t, paper) do
    base = @pad - 1 - JSMath.round(h)
    art = elem(state.sprite, if(paper, do: 1, else: 0))

    grid =
      state.span
      |> Enum.with_index()
      |> Enum.reduce(grid, fn {{c0, c1}, r}, grid ->
        line = elem(art, r)

        Enum.reduce(c0..(c1 - 1)//1, grid, fn c, grid ->
          put(grid, @left + c, base - @ht + 1 + r, elem(line, c))
        end)
      end)

    grid = Enum.reduce(23..0//-1, grid, &vapour(&2, &1, base, time))
    if burning?(t), do: flame(grid, base, time, t), else: grid
  end

  # While it waits on the pad, liquid oxygen boils off through a vent on the
  # upper stage in a thin wisp that drifts away on the wind.
  defp vapour(grid, k, base, time) do
    born = (JSMath.floor(time / 0.1) - k) * 0.1
    age = time - born

    if not on_pad?(JSMath.mod(JSMath.mod(born, @loop) + @loop, @loop)) or age > 2.4 do
      grid
    else
      f = age / 2.4
      gust = 1 + 0.3 * :math.sin(0.9 * born)

      y =
        base - @ht + 9 - 0.4 * age - 0.2 * age * age + 1.1 * :math.sin(2.3 * born) * f

      ch =
        cond do
          f < 0.2 -> "~"
          f < 0.45 -> "-"
          f < 0.75 -> "."
          true -> "·"
        end

      put(grid, @left + @w - 4 + gust * (3 * age + 0.6 * age * age), y, ch)
    end
  end

  # Short at ignition, long in the climb, shorter braking.
  defp flame(grid, base, time, t) do
    len =
      cond do
        t < @lift -> 1 + 2.5 * ((t - @ignite) / (@lift - @ignite))
        t < @land - burn() -> 6
        true -> 4.5
      end

    f = JSMath.floor(time * 20)

    1
    |> Stream.iterate(&(&1 + 1))
    |> Enum.take_while(&(&1 <= len + rem(f * 7, 3) - 1))
    |> Enum.reduce(grid, fn k, grid ->
      heat = 1 - (k - 1) / (len + 1)
      half = 0.4 + 2.8 * :math.pow(heat, 0.6)

      Enum.reduce(JSMath.ceil(@mid - half)..JSMath.floor(@mid + half)//1, grid, fn c, grid ->
        edge = abs(c - @mid) / (half + 0.5)

        i =
          JSMath.floor(
            (heat * 0.8 + 0.35 - edge * 0.5 + rem((f + c * 3 + k) * 13, 5) * 0.03) *
              tuple_size(@flame)
          )

        if i >= 0,
          do: put(grid, c, base + k, elem(@flame, min(tuple_size(@flame) - 1, i))),
          else: grid
      end)
    end)
  end
end
