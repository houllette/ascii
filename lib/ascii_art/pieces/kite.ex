defmodule AsciiArt.Pieces.Kite do
  @moduledoc """
  A diamond kite riding the wind, its string sagging in lulls.

  A diamond kite on a long string from off the bottom left. Gusts lift it and
  pull the string straight, lulls let it sag, and the tail flutters.

  Ported from `src/pieces/kite.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Grid

  @meta %AsciiArt.Meta{
    name: "kite",
    category: :objects,
    note: "a diamond kite riding the wind, its string sagging in lulls",
    cols: 64,
    rows: 24,
    fps: 15,
    loop: 40
  }

  @cols 64
  @rows 24
  # Seconds before the wind repeats.
  @p 40
  @tau :math.pi() * 2
  # Half the spar, in columns. Above the spar the edges climb two columns a
  # row, so the top is @b / 2 rows up; below they drop one a row, so the
  # bottom is @b rows down. Width to height is about 0.7, square for square.
  @b 8
  # Rows of tail.
  @tail 7
  @fill ":"

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options), do: nil

  # Where a shallow line sits inside its cell, as the glyph that sits there.
  defp level(f) when f < 0.3, do: "'"
  defp level(f) when f < 0.55, do: "-"
  defp level(f) when f < 0.78, do: "."
  defp level(_f), do: "_"

  defp put(g, r, c, ch), do: Grid.put(g, c, r, ch)

  @impl true
  def frame(state, t, _env) do
    ph = @tau * t / @p
    wind = 0.5 + 0.3 * :math.sin(2 * ph) + 0.2 * :math.sin(5 * ph + 1.3)

    # The kite rides up in a gust and drifts a little sideways, a whole cell
    # at a time and seldom, so its outline holds.
    mid = JSMath.floor(45 + 0.7 * :math.sin(ph + 0.4))
    # The spar's row.
    rs = JSMath.floor(6.5 + 1.4 * (0.5 - wind))
    # It rolls into the wind. A roll is drawn as the bottom half of the sail
    # standing a column off the top half, so every edge keeps an even step
    # and only the corners give.
    roll = :math.sin(5 * ph) + 0.35 * :math.sin(13 * ph + 1)
    # The top half's middle, and the bottom half's.
    up = mid

    lo =
      cond do
        roll > 0.55 -> mid - 1
        roll < -0.55 -> mid + 1
        true -> mid
      end

    a0 = min(up, lo) - @b

    Grid.new(@cols, @rows)
    |> sail(rs, up, lo)
    |> tail(rs, lo, wind, ph)
    |> string(a0, rs, wind)
    |> Grid.to_iodata()
    |> then(&{&1, nil, state})
  end

  # The sail, a row at a time out from the spar. Two opposite panels are
  # shaded, like a harlequin kite.
  defp sail(g, rs, up, lo) do
    g =
      Enum.reduce(1..(div(@b, 2) - 1), g, fn k, g ->
        r = rs - k
        e = @b - 2 * k

        g =
          g
          |> put(r, up - e - 1, ",")
          |> put(r, up - e, "'")
          |> put(r, up + e, "`")
          |> put(r, up + e + 1, ".")

        g = Enum.reduce((up - e + 1)..(up - 1)//1, g, &put(&2, r, &1, @fill))
        put(g, r, up, "|")
      end)

    top = rs - div(@b, 2)
    g = g |> put(top, up - 1, ".") |> put(top, up, "^") |> put(top, up + 1, ".")

    a0 = min(up, lo) - @b
    b0 = max(up, lo) + @b
    g = Enum.reduce((a0 + 1)..(b0 - 1)//1, g, &put(&2, rs, &1, "-"))
    g = g |> put(rs, a0, "<") |> put(rs, b0, ">") |> put(rs, up, "+")

    Enum.reduce(1..(@b - 1), g, fn j, g ->
      r = rs + j
      e = @b - j
      g = g |> put(r, lo - e, "\\") |> put(r, lo + e, "/")
      g = Enum.reduce((lo + 1)..(lo + e - 1)//1, g, &put(&2, r, &1, @fill))
      put(g, r, lo, "|")
    end)
  end

  # The tail streams downwind from the bottom corner, one glyph a row, its
  # flutter growing toward the free end, with a bow tied every few rows.
  defp tail(g, rs, lo, wind, ph) do
    vr = rs + @b - 1
    lean = 0.15 + 0.35 * wind
    amp = (0.35 + 0.3 * wind) / 3.5
    tx = fn s -> lo + 0.5 + lean * s + amp * s * :math.sin(2.2 * s - 15 * ph) end

    Enum.reduce((vr + 1)..(min(@rows, vr + 1 + @tail) - 1)//1, g, fn r, g ->
      s = r - vr - 0.5
      at = tx.(s)
      ahead = tx.(s + 0.5)
      behind = tx.(s - 0.5)
      slope = ahead - behind
      bend = ahead - 2 * at + behind
      c = JSMath.floor(at)

      ch =
        cond do
          slope > 0.6 -> "\\"
          slope < -0.6 -> "/"
          bend > 0 -> "("
          true -> ")"
        end

      g = put(g, r, c, ch)
      if rem(r - vr, 3) == 2, do: g |> put(r, c - 1, ">") |> put(r, c + 1, "<"), else: g
    end)
  end

  # The string comes in from a hand far off the bottom left, a glyph a column
  # at its height in the cell. It sags as the wind drops and pulls straighter
  # in a gust.
  defp string(g, a0, rs, wind) do
    {hx, hy} = {-20, @rows + 3}
    {kx, ky} = {a0, rs + 0.5}
    sag = 1.7 - 1.1 * wind

    Enum.reduce(0..(a0 - 1)//1, g, fn c, g ->
      u = (c + 0.5 - hx) / (kx - hx)
      y = hy + (ky - hy) * u + 4 * sag * u * (1 - u)
      put(g, JSMath.floor(y), c, level(JSMath.mod(y, 1)))
    end)
  end
end
