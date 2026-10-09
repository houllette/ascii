defmodule AsciiArt.Pieces.Starfield do
  @moduledoc """
  Stars rush out from the centre and streak at the edges.

  Flying through stars at warp. Each star drifts out from the vanishing point
  as a dot, then streaks as it rushes past the edge.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `stars` - how many, 0 to 1000, taken as a whole number. Default 60.
    * `speed` - how fast you fly, -100 to 100: at 1 a star takes 4 seconds to
      come from the far plane past the edge, at 2 half that; a negative speed
      flies backwards, and 0 holds them still. Default 1.

  The picture is always 64 by 24.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `AsciiArt.Ink`),
  or on a page a CSS variable. It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "starfield: stars rush out
  from the centre and streak at the edges". A player's or a component's
  `label` gives words of your own, as "flying through stars".

  ## Example

  ```elixir
  still = AsciiArt.new!("starfield", options: %{stars: 200, speed: 0})
  {first, still} = AsciiArt.frame(still, 0.0)
  {later, _} = AsciiArt.frame(still, 3.0)
  first.text == later.text
  #=> true
  ```

  ```heex
  <AsciiArt.Phoenix.player socket={@socket} id="warp" piece="starfield" options={%{stars: 150, speed: 3}} />
  ```

  Ported from `src/pieces/starfield.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "starfield",
    category: :space,
    note: "stars rush out from the centre and streak at the edges",
    cols: 64,
    rows: 24,
    fps: 30,
    options: %{stars: 60, speed: 1},
    bounds: %{stars: {0, 1000}, speed: {-100, 100}}
  }

  # Focal length, in columns per unit at depth 1; the near and far planes; a
  # star shows once nearer than @seen. The streak is where the star was
  # @shutter depth ago.
  @f 10
  @near 0.04
  @far 1.3
  @seen 1.05
  @shutter 0.16

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{stars: stars, speed: speed}) do
    # Counts are whole stars here; upstream's arrays take the integer part.
    stars = trunc(stars)

    {phase, _} = Enum.map_reduce(1..stars//1, 7, fn _, r -> Int32.mulberry32(r) end)

    # Seconds from the far plane to the near one: 4 / speed, infinite at rest.
    life = if speed == 0, do: nil, else: 4 / speed
    %{stars: stars, life: life, phase: List.to_tuple(phase)}
  end

  # Where star i is on its k-th pass: a direction inside its own slice of the
  # circle, so the field stays even, and a distance off the axis that is never
  # too small, so the vanishing point stays clear.
  defp place(i, k, stars) do
    {a, r} = Int32.mulberry32(i * 7919 + k * 104_729 + 13)
    {b, _} = Int32.mulberry32(r)
    a = (i + a) / stars * :math.pi() * 2
    d = 0.25 + 0.75 * :math.sqrt(b)
    {:math.cos(a) * d, :math.sin(a) * d}
  end

  # Plots a cell unless a nearer star already holds it.
  defp put(cells, c, r, ch) do
    %{cols: cols, rows: rows} = @meta

    if c < 0 or c >= cols or r < 0 or r >= rows,
      do: cells,
      else: Map.put_new(cells, c + r * cols, ch)
  end

  @impl true
  def frame(%{stars: stars, life: life, phase: phase} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    cx = cols / 2
    cy = rows / 2

    order =
      for i <- 0..(stars - 1)//1 do
        u = elem(phase, i) + if(life, do: t / life, else: 0)
        k = JSMath.floor(u)
        {@far - (@far - @near) * (u - k), i, k}
      end

    # Near stars first, so they keep their cells.
    cells =
      order
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce(%{}, fn
        {z, _, _}, cells when z > @seen -> cells
        {z, i, k}, cells -> star(cells, z, place(i, k, stars), cx, cy)
      end)

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(cells, c + r * cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp star(cells, z, {x, y}, cx, cy) do
    hx = cx + x / z * @f
    hy = cy + y / z * @f * 0.5
    zt = z + @shutter
    c1 = JSMath.floor(hx)
    r1 = JSMath.floor(hy)
    c0 = JSMath.floor(cx + x / zt * @f)
    r0 = JSMath.floor(cy + y / zt * @f * 0.5)

    head =
      cond do
        z > 0.5 -> "."
        z > 0.25 -> "+"
        true -> "*"
      end

    cells = put(cells, c1, r1, head)

    # Far stars are single dots.
    if z > 0.5, do: cells, else: trail(cells, c0, r0, c1, r1)
  end

  # Walk tail to head, one cell per step. Each cell's glyph is the step it
  # takes to the next one, and the oldest cells of the trail fade.
  defp trail(cells, c0, r0, c1, r1) do
    n = max(abs(c1 - c0), abs(r1 - r0))
    fade = min(2, JSMath.floor(n / 3))

    Enum.reduce(0..(n - 1)//1, cells, fn s, cells ->
      c = JSMath.round(c0 + (c1 - c0) * s / n)
      r = JSMath.round(r0 + (r1 - r0) * s / n)
      dc = JSMath.round(c0 + (c1 - c0) * (s + 1) / n) - c
      dr = JSMath.round(r0 + (r1 - r0) * (s + 1) / n) - r

      g =
        cond do
          dr == 0 -> "-"
          dc == 0 -> "|"
          dc * dr > 0 -> "\\"
          true -> "/"
        end

      put(cells, c, r, if(s < fade, do: ".", else: g))
    end)
  end
end
