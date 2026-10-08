defmodule AsciiArt.Pieces.PondRipples do
  @moduledoc """
  Raindrops opening rings that cross and fade on a pond.

  A pond from above in light rain. Each drop lands with a splash and opens a
  ring, a fainter one following it in, that weakens to dashes and dots
  before it reaches the bank. Where two rings cross they peak.

  Ported from `src/pieces/pond-ripples.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "pond ripples",
    category: :physics,
    note: "raindrops opening rings that cross and fade on a pond",
    cols: 64,
    rows: 20,
    fps: 20
  }

  # A cell in em; distances are in em.
  @cw 0.6
  @ch 1.2
  # Seconds into the rain: two rings open and a third drop about to land.
  @start 7.35
  # Seconds between drops, on average; seconds a ring lasts; em per second;
  # em from the ring to the fainter one inside it.
  @every 1.5
  @life 4
  @speed 2.6
  @wave 1.5

  @cols 64
  @rows 20
  @n @cols * @rows

  @impl true
  def meta, do: @meta

  defp umul(a, b),
    do:
      band(band(a, 0xFFFF) * b + bsl(band(bsr(a, 16) * band(b, 0xFFFF), 0xFFFF), 16), 0xFFFFFFFF)

  # A hash of (drop, salt) into [0, 1), integer maths only; unsigned here, as
  # imul, ^ and >>> agree modulo 2^32 whatever the signs.
  defp rand(i, salt) do
    h =
      bxor(
        umul(bxor(band(i, 0xFFFFFFFF), 0x9E3779B9), 0x85EBCA6B),
        umul(band(salt + 1, 0xFFFFFFFF), 0xC2B2AE35)
      )

    h = umul(bxor(h, bsr(h, 15)), 0x2C1B3C6D)
    h = umul(bxor(h, bsr(h, 12)), 0x297A2D39)
    bxor(h, bsr(h, 15)) / 4_294_967_296
  end

  # An ellipse with half widths ax and ay around (x0, y0), as cells and marks:
  # one mark a column where it runs flat, set at the height it crosses the
  # cell, and one a row where it runs steep. Each comes as {cell, mark, a, b},
  # its angle being atan2(a, b). Small rings let the two overlap, so no corner
  # goes missing.
  defp ellipse(x0, y0, ax, ay, small) do
    {flat, steep} = if small, do: {1.05, 1.25}, else: {0.9, 1.1}

    across =
      for c <- 0..(@cols - 1),
          x = ((c + 0.5) * @cw - x0) / ax,
          abs(x) < 1,
          s = :math.sqrt(1 - x * x),
          ay / ax * abs(x) / s <= flat,
          sign <- [-1, 1],
          y = (y0 + sign * ay * s) / @ch,
          r = JSMath.floor(y),
          r >= 0 and r < @rows do
        {r * @cols + c, flat_mark(y - r), sign * s, x}
      end

    down =
      for r <- 0..(@rows - 1),
          y = ((r + 0.5) * @ch - y0) / ay,
          abs(y) < 1,
          s = :math.sqrt(1 - y * y),
          lean = ax / ay * abs(y) / s,
          lean <= steep,
          sign <- [-1, 1],
          c = JSMath.floor((x0 + sign * ax * s) / @cw),
          c >= 0 and c < @cols do
        {r * @cols + c, steep_mark(lean, sign, y), y, sign * s}
      end

    across ++ down
  end

  defp flat_mark(f) when f < 0.3, do: "'"
  defp flat_mark(f) when f < 0.6, do: "-"
  defp flat_mark(f) when f < 0.85, do: "."
  defp flat_mark(_f), do: "_"

  defp steep_mark(lean, -1, _y) when lean < 0.45, do: "("
  defp steep_mark(lean, _sign, _y) when lean < 0.45, do: ")"
  defp steep_mark(_lean, sign, y), do: if(sign < 0 == y < 0, do: "/", else: "\\")

  @impl true
  def init(_options) do
    cx = @cols * @cw / 2
    cy = @rows * @ch / 2
    # The bank, its top and bottom flat along a row's edge.
    ax = cx - 1.2
    ay = cy - 1.12

    bank =
      ellipse(cx, cy, ax, ay, false)
      |> Enum.reduce(%{}, fn {i, mark, _, _}, bank -> Map.put(bank, i, mark) end)

    # How far in from the bank, 1 well inside, falling to 0 just short of it.
    open =
      List.to_tuple(
        for i <- 0..(@n - 1) do
          x = (rem(i, @cols) + 0.5) * @cw
          y = (div(i, @cols) + 0.5) * @ch
          dx = (x - cx) / ax
          dy = (y - cy) / ay
          e = min(1, max(0, (1 - dx * dx - dy * dy) / 0.35))
          e * e * (3 - 2 * e)
        end
      )

    %{bank: bank, open: open, cx: cx, cy: cy, ax: ax, ay: ay}
  end

  # The drops alive at time t: where each fell, its age and how hard it struck.
  defp drops(t, %{cx: cx, cy: cy, ax: ax, ay: ay}) do
    from = JSMath.floor((t - @life) / @every) - 1
    to = JSMath.floor(t / @every) + 1

    for i <- from..to//1,
        age = t - (i + 0.7 * (rand(i, 0) - 0.5)) * @every,
        age >= 0 and age <= @life do
      r = 0.62 * :math.sqrt(rand(i, 1))
      p = 2 * :math.pi() * rand(i, 2)

      %{
        x: cx + ax * r * :math.cos(p),
        y: cy + ay * r * :math.sin(p),
        age: age,
        a: 0.8 + 0.2 * rand(i, 3)
      }
    end
    |> Enum.sort_by(& &1.age, :desc)
  end

  # Level 1 is the faint ring, 2 a weakening one, 3 a full one; two full
  # rings crossing peak.
  defp kind(m) when m in ["'", "-", ".", "_"], do: 0
  defp kind(m) when m in ["(", ")"], do: 1
  defp kind("/"), do: 2
  defp kind(_m), do: 3

  defp draw(cells, i, _mark, _lv, _who) when i < 0 or i >= @n, do: cells

  defp draw(cells, i, mark, lv, who) do
    {ink, level, owner} = Map.get(cells, i, {" ", 0, -1})

    cond do
      lv == 3 and level == 3 and owner != who and kind(ink) != kind(mark) ->
        Map.put(cells, i, {"x", 4, owner})

      lv >= level and level < 4 ->
        Map.put(cells, i, {mark, lv, who})

      true ->
        cells
    end
  end

  @impl true
  def frame(%{bank: bank, open: open} = state, time, _env) do
    t = @start + time

    {cells, _} =
      t
      |> drops(state)
      |> Enum.reduce({%{}, 0}, fn dp, {cells, who} -> {drop(cells, dp, who, open), who + 1} end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          i = r * @cols + c

          case bank do
            %{^i => mark} -> mark
            _ -> cells |> Map.get(i, {" ", 0, -1}) |> elem(0)
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp drop(cells, %{x: x, y: y, age: age} = dp, who, open) do
    at = JSMath.floor(y / @ch) * @cols + JSMath.floor(x / @cw)

    cond do
      # The splash: a drop, then a small ring.
      age < 0.15 ->
        draw(cells, at, "o", 3, who)

      age < 0.4 ->
        cells |> draw(at - 1, "(", 3, who) |> draw(at + 1, ")", 3, who)

      true ->
        rings(cells, dp, who, open)
    end
  end

  defp rings(cells, %{x: x, y: y, age: age, a: a}, who, open) do
    r = 0.5 + @speed * age
    life = a * (1 - age / @life)

    # The ring: drawn whole while strong, in spaced dots as it weakens.
    cells =
      x
      |> ellipse(y, r, r, true)
      |> Enum.reduce(cells, fn {i, mark, sa, sb}, cells ->
        near = elem(open, i)

        cond do
          life > 0.45 and near > 0.6 ->
            draw(cells, i, mark, 3, who)

          life > 0.2 and near > 0.45 and
              rem(JSMath.floor((:math.atan2(sa, sb) + :math.pi()) * r / 0.9), 2) != 0 ->
            draw(cells, i, if(mark == "_" or mark == ".", do: ".", else: "·"), 2, who)

          true ->
            cells
        end
      end)

    # The fainter ring following it in, only while the first is strong; a dot
    # every other step.
    r2 = r - @wave

    if life > 0.55 and r2 > 1.4 do
      x
      |> ellipse(y, r2, r2, true)
      |> Enum.reduce(cells, fn {i, _mark, sa, sb}, cells ->
        if rem(JSMath.floor((:math.atan2(sa, sb) + :math.pi()) * r2 / 1.1), 2) != 0,
          do: draw(cells, i, "·", 1, who),
          else: cells
      end)
    else
      cells
    end
  end
end
