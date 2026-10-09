defmodule Ascii.Pieces.FallingSand do
  @moduledoc """
  Sand pouring into a heap, then draining through the shelf.

  Sand pouring from a spout onto a shelf, as a cellular automaton two grains
  to a character. The heap grows at its angle of repose; then the shelf
  opens, it drains, and it pours again.

  Ported from `src/pieces/falling-sand.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}
  import Bitwise

  @meta %Ascii.Meta{
    name: "falling sand",
    category: :physics,
    note: "sand pouring into a heap, then draining through the shelf",
    cols: 55,
    rows: 22,
    fps: 20
  }

  # Automaton steps a frame; the chance a grain leaves the nozzle each step;
  # steps of pouring before the sand changes shade; steps played before the
  # first frame.
  @steps 4
  @rate 0.92
  @layer 150
  @warm 290

  # A character holds two grains, one above the other.
  @w 55
  @h 44
  # The shelf is the bottom row; sand that misses it leaves the frame.
  @shelf @h - 2
  # The nozzle's column, and the shelf runs from @end_ to @w - 1 - @end_.
  @mid div(@w - 1, 2)
  @end_ 5
  # How far each half slides back, into its end cap, to open.
  @open @mid - @end_ + 0.5
  # The row grains leave the spout from.
  @nozzle 5

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    sim = %{
      grid: %{},
      moved: %{},
      rand: Int32.to_int32(7),
      step: 0,
      phase: :pour,
      clock: 0,
      slide: 0,
      shade: 0,
      poured: 0,
      spilled: 0,
      held: 0
    }

    sim = Enum.reduce(1..@warm, sim, fn _, sim -> tick(sim) end)
    Map.put(sim, :last, 0)
  end

  # Opening, each half of the shelf slides back toward its end, from the middle out.
  defp solid?(x, y, slide),
    do: y >= @shelf and x >= @end_ and x <= @w - 1 - @end_ and abs(x - @mid) >= slide

  defp free?(sim, x, y) do
    y < @h and
      (x < 0 or x >= @w or
         (not Map.has_key?(sim.grid, y * @w + x) and not solid?(x, y, sim.slide)))
  end

  defp move(sim, a, x, y) do
    {shade, grid} = Map.pop!(sim.grid, a)

    if x >= 0 and x < @w do
      b = y * @w + x
      %{sim | grid: Map.put(grid, b, shade), moved: Map.put(sim.moved, b, sim.step)}
    else
      %{sim | grid: grid}
    end
  end

  defp moved(sim, a), do: Map.get(sim.moved, a, -9)

  defp rand(sim) do
    {x, r} = Int32.mulberry32(sim.rand)
    {x, %{sim | rand: r}}
  end

  defp tick(sim) do
    sim = %{sim | step: sim.step + 1, held: 0}

    {sim, top} =
      Enum.reduce((@h - 1)..0//-1, {sim, @h}, fn y, acc ->
        flip = band(sim.step + y, 1) == 1

        Enum.reduce(0..(@w - 1), acc, fn i, {sim, top} ->
          x = if flip, do: @w - 1 - i, else: i
          a = y * @w + x

          if Map.has_key?(sim.grid, a) and moved(sim, a) != sim.step,
            do: grain(%{sim | held: sim.held + 1}, a, x, y, top),
            else: {sim, top}
        end)
      end)

    sim |> spout() |> layer() |> phase(top)
  end

  defp grain(sim, a, _x, y, top) when y == @h - 1 do
    # Gone out of the bottom of the frame, off an end of the shelf or through it.
    {%{sim | grid: Map.delete(sim.grid, a), spilled: sim.spilled + 1}, top}
  end

  defp grain(sim, a, x, y, top) do
    if free?(sim, x, y + 1) do
      {move(sim, a, x, y + 1), top}
    else
      {r, sim} = rand(sim)
      d = if r < 0.5, do: -1, else: 1

      cond do
        free?(sim, x + d, y + 1) ->
          {move(sim, a, x + d, y + 1), top}

        free?(sim, x - d, y + 1) ->
          {move(sim, a, x - d, y + 1), top}

        true ->
          # A grain on a steep slope slides a step sideways before it rolls on down.
          {r, sim} = rand(sim)

          cond do
            r < 0.35 and free?(sim, x + d, y) and free?(sim, x + 2 * d, y + 1) ->
              {move(sim, a, x + d, y), top}

            moved(sim, a) < sim.step - 2 and y < top ->
              {sim, y}

            true ->
              {sim, top}
          end
      end
    end
  end

  # The spout never stops; while the shelf is open the stream runs straight through it.
  defp spout(sim) do
    {r, sim} = rand(sim)

    if r < @rate and free?(sim, @mid, @nozzle) do
      a = @nozzle * @w + @mid
      %{sim | grid: Map.put(sim.grid, a, 1 + sim.shade), moved: Map.put(sim.moved, a, sim.step)}
    else
      sim
    end
  end

  defp layer(sim) do
    poured = sim.poured + 1
    shade = if rem(poured, @layer) == 0, do: bxor(sim.shade, 1), else: sim.shade
    %{sim | poured: poured, shade: shade}
  end

  # Full once the heap runs off both ends of the shelf, or stands too near the spout.
  defp phase(%{phase: :pour} = sim, top) do
    if sim.spilled > 50 or top < @nozzle + 10, do: %{sim | phase: :hold, clock: 0}, else: sim
  end

  defp phase(%{phase: :hold} = sim, _top) do
    clock = sim.clock + 1
    %{sim | clock: clock, phase: if(clock > 40, do: :open, else: :hold)}
  end

  defp phase(%{phase: :open} = sim, _top) do
    slide = min(@open, sim.slide + 0.35)

    # Close again once the heap has run out and only the stream is left.
    if slide == @open and sim.held < 110,
      do: %{sim | slide: slide, phase: :close, spilled: 0},
      else: %{sim | slide: slide}
  end

  defp phase(%{phase: :close} = sim, _top) do
    slide = max(0, sim.slide - 0.5)
    if slide == 0, do: %{sim | slide: slide, phase: :pour}, else: %{sim | slide: slide}
  end

  @impl true
  def frame(sim, t, _env) do
    fps = @meta.fps
    n = min(12, max(0, JSMath.round((t - sim.last) * fps)))
    sim = %{sim | last: sim.last + n / fps}
    sim = Enum.reduce(1..(n * @steps)//1, sim, fn _, sim -> tick(sim) end)
    {draw(sim), nil, sim}
  end

  # A grain is in the air if it moved a moment ago and has no resting sand,
  # or shelf, under it to roll on.
  defp rests?(sim, x, y) do
    y < @h and
      (solid?(x, y, sim.slide) or
         (x >= 0 and x < @w and Map.has_key?(sim.grid, y * @w + x) and
            moved(sim, y * @w + x) < sim.step - 2))
  end

  defp air?(sim, x, y) do
    a = y * @w + x

    Map.has_key?(sim.grid, a) and moved(sim, a) >= sim.step - 2 and not rests?(sim, x, y + 1) and
      not rests?(sim, x - 1, y + 1) and not rests?(sim, x + 1, y + 1)
  end

  defp draw(sim) do
    rows = @meta.rows

    lines =
      for r <- 0..(rows - 1) do
        Enum.map_join(0..(@w - 1), fn c -> cell(sim, c, r) end)
      end

    # The spout: a hopper down from the top, sand showing inside it while it
    # pours; and the shelf's end caps.
    p = @mid - 2
    fill = "░"

    lines
    |> put(0, p - 1, "│" <> String.duplicate(fill, 5) <> "│")
    |> put(1, p - 1, "╰╮" <> String.duplicate(fill, 3) <> "╭╯")
    |> put(2, p, " ╰" <> fill <> "╯ ")
    |> put(rows - 1, @end_ - 1, "▐")
    |> put(rows - 1, @w - @end_, "▌")
    |> Enum.intersperse(?\n)
  end

  defp put(lines, r, at, s) do
    List.update_at(lines, r, fn line ->
      chars = String.codepoints(line)
      n = length(String.codepoints(s))
      Enum.join(Enum.take(chars, at)) <> s <> Enum.join(Enum.drop(chars, at + n))
    end)
  end

  defp cell(sim, c, r) do
    if solid?(c, 2 * r, sim.slide) do
      "▀"
    else
      a = 2 * r * @w + c
      b = a + @w
      fa = air?(sim, c, 2 * r)
      fb = air?(sim, c, 2 * r + 1)
      sa = Map.has_key?(sim.grid, a) and not fa
      sb = Map.has_key?(sim.grid, b) and not fb

      # The falling stream.
      if c == @mid and (fa or fb) and not sa and not sb,
        do: "┊",
        else: glyph(sa, sb, fa, fb, sim.grid[a])
    end
  end

  # Settled grains top and bottom, then grains in the air.
  defp glyph(true, sb, _fa, fb, shade) when sb or fb, do: if(shade == 1, do: "█", else: "▓")
  defp glyph(_sa, true, true, _fb, _shade), do: "█"
  defp glyph(true, _sb, _fa, _fb, _shade), do: "▀"
  defp glyph(_sa, true, _fa, _fb, _shade), do: "▄"
  defp glyph(_sa, _sb, true, true, _shade), do: ":"
  defp glyph(_sa, _sb, true, _fb, _shade), do: "'"
  defp glyph(_sa, _sb, _fa, true, _shade), do: "."
  defp glyph(_sa, _sb, _fa, _fb, _shade), do: " "
end
