defmodule AsciiArt.Pieces.SolarSystem do
  @moduledoc """
  Four planets on dotted orbits, periods by kepler's third law.

  Planets seen from above on dotted circular orbits. Each period goes as the
  orbit's radius to the power 1.5, Kepler's third law.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `speed` - how fast the planets go round, -100 to 100: 2 twice as fast, a
      negative speed backwards, 0 holds them where they stand. Default 1, at
      which the innermost goes round in 3 seconds.

  The picture is always 61 by 29.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `AsciiArt.Ink`),
  or on a page a CSS variable. It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "solar system: four planets
  on dotted orbits, periods by kepler's third law". A player's or a
  component's `label` gives words of your own, as "planets on their orbits".

  ## Example

  ```elixir
  still = AsciiArt.new!("solar-system", options: %{speed: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _} = AsciiArt.frame(still, 5.0)
  first.text == later.text
  #=> true
  ```

  ```heex
  <AsciiArt.Phoenix.player socket={@socket} id="orbits" piece="solar-system" options={%{speed: 0.25}} />
  ```

  Ported from `src/pieces/solar-system.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "solar system",
    category: :space,
    note: "four planets on dotted orbits, periods by kepler's third law",
    cols: 61,
    rows: 29,
    fps: 20,
    options: %{speed: 1},
    bounds: %{speed: {-100, 100}}
  }

  @tau :math.pi() * 2

  # Orbit radius in columns, glyph, starting angle. Orbits open out with
  # distance, as they do; the second planet has a moon.
  @planets [
    %{a: 9.6, glyph: "o", at: 0.5, moon: false},
    %{a: 14.5, glyph: "O", at: 2.3, moon: true},
    %{a: 21, glyph: "(@)", at: 4.1, moon: false},
    %{a: 28, glyph: "-(O)-", at: 5.9, moon: false}
  ]
  # Seconds for the innermost orbit at speed 1.
  @t1 3
  # Trail cells behind the innermost planet; slower ones leave less.
  @trail 3.2

  # The centre, (cols - 1) / 2 and (rows - 1) / 2, falls on whole cells.
  @cx div(61 - 1, 2)
  @cy div(29 - 1, 2)

  @impl true
  def meta, do: @meta

  # Rounds away from the sun, so each orbit comes out symmetric.
  defp sym(v, o), do: o + JSMath.sign(v - o) * JSMath.round(abs(v - o))

  defp cell(x, y) do
    %{cols: cols, rows: rows} = @meta
    c = sym(x, @cx)
    r = sym(y, @cy)
    if c >= 0 and c < cols and r >= 0 and r < rows, do: c + r * cols, else: -1
  end

  defp at(%{a: a}, th), do: {@cx + a * :math.cos(th), @cy - a / 2 * :math.sin(th)}

  defp cell_at(p, th) do
    {x, y} = at(p, th)
    cell(x, y)
  end

  @impl true
  def init(%{speed: speed}) do
    # A dot every two columns of arc, rows counting double, so each orbit is
    # an even dotted curve.
    rings =
      for p <- @planets,
          n = JSMath.round(@tau * p.a / 2),
          k <- 0..(n - 1),
          kk = cell_at(p, k / n * @tau),
          kk >= 0,
          into: MapSet.new(),
          do: kk

    # The sun, shaded brighter toward its middle.
    sun =
      for r <- -2..2, c <- -5..5, d = JSMath.hypot(c, r * 2) / 4.4, d <= 1 do
        ch =
          cond do
            d < 0.35 -> "@"
            d < 0.6 -> "%"
            d < 0.82 -> "*"
            true -> "+"
          end

        {cell(@cx + c, @cy + r), ch}
      end

    sky = Enum.reduce(sun, Map.new(rings, &{&1, "."}), fn {k, ch}, sky -> Map.put(sky, k, ch) end)
    a0 = hd(@planets).a

    planets =
      for p <- @planets do
        Map.merge(p, %{
          period: @t1 * :math.pow(p.a / a0, 1.5),
          len: JSMath.round(@trail * :math.sqrt(a0 / p.a)),
          chars: p.glyph |> String.graphemes() |> List.to_tuple()
        })
      end

    %{sky: sky, planets: planets, speed: speed}
  end

  @impl true
  def frame(%{sky: sky, planets: planets, speed: speed} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    grid = Enum.reduce(planets, sky, &planet(&2, &1, t, speed))

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(grid, c + r * cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp planet(grid, p, t, speed) do
    th = p.at + @tau * t * speed / p.period
    {x, y} = at(p, th)
    n = tuple_size(p.chars)
    x0 = JSMath.round(x - (n - 1) / 2)
    r0 = JSMath.round(y)
    grid = trail(grid, p, th, cell(x, y), {x0, r0, n})

    # The planet, with the orbit dots either side cleared so it stands out.
    grid =
      Enum.reduce(-1..n, grid, fn i, grid ->
        k = cell(x0 + i, r0)

        cond do
          k < 0 -> grid
          i >= 0 and i < n -> Map.put(grid, k, elem(p.chars, i))
          Map.get(grid, k) == "." -> Map.put(grid, k, " ")
          true -> grid
        end
      end)

    if p.moon do
      m = @tau * t * speed / 1.1
      k = cell(x + 2.4 * :math.cos(m), y - 1.2 * :math.sin(m))
      if k >= 0, do: Map.put(grid, k, "°"), else: grid
    else
      grid
    end
  end

  # The trail walks back along the orbit, one cell at a time: a stroke the way
  # the planet is heading, then a fading dot. Orbital speed goes as one over
  # the root of the radius, so outer trails are shorter.
  defp trail(grid, p, th, last, mine), do: trail(grid, p, th, th, last, 0, mine)

  defp trail(grid, %{len: len} = p, th, u, last, drawn, mine) when drawn < len and u > th - 1 do
    k = cell_at(p, u)

    cond do
      k == last or mine?(k, mine) ->
        trail(grid, p, th, u - 0.01, last, drawn, mine)

      k < 0 ->
        grid

      true ->
        cu = :math.cos(u)
        su = :math.sin(u)
        # Slope, rows counted double.
        s = abs(cu) / max(1.0e-6, abs(su))

        g =
          cond do
            s < 0.6 -> "-"
            s > 2.4 -> "|"
            su * cu > 0 -> "\\"
            true -> "/"
          end

        grid = Map.put(grid, k, if(drawn < len - 1, do: g, else: "·"))
        trail(grid, p, th, u - 0.01, k, drawn + 1, mine)
    end
  end

  defp trail(grid, _p, _th, _u, _last, _drawn, _mine), do: grid

  defp mine?(k, {x0, r0, n}) do
    cols = @meta.cols
    k >= 0 and div(k, cols) == r0 and rem(k, cols) >= x0 and rem(k, cols) < x0 + n
  end
end
