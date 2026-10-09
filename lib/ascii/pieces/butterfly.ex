defmodule Ascii.Pieces.Butterfly do
  @moduledoc """
  A butterfly flapping and gliding along a wandering path.

  Seen from above, beating its wings in bursts and gliding between them. As
  a wing rises it turns edge on and narrows, its tip nearer the eye.

  Ported from `src/pieces/butterfly.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Ramp
  import Bitwise

  @meta %Ascii.Meta{
    name: "butterfly",
    category: :creatures,
    note: "a butterfly flapping and gliding along a wandering path",
    cols: 64,
    rows: 24,
    fps: 30,
    loop: 16
  }

  @cols 64
  @rows 24
  @ramp Ramp.new(" .:-=+*#%@")
  @ramp_n tuple_size(@ramp)
  # Seconds; the path and the bursts all divide it.
  @loop 16
  # Wingbeats a second.
  @beat 2.5
  # How far the eye is above the wings, in columns.
  @eye 120
  @two_pi 2 * :math.pi()
  @w 2 * :math.pi() / @loop

  # Each wing is a teardrop, wider at its outer end: centre, length, width,
  # tilt. The tilt's cosine and sine are constants, taken once.
  @fore_x 9.6
  @fore_y 5.6
  @fore_a 11.6
  @fore_b 7.2
  @hind_x 7
  @hind_y -4.6
  @hind_a 8.8
  @hind_b 7.4

  # A teardrop lies inside the circle of radius hypot(a, b) round its centre,
  # whatever the tilt: points well outside it miss without the division.
  @fore_far 11.6 * 11.6 + 7.2 * 7.2 + 1
  @hind_far 8.8 * 8.8 + 7.4 * 7.4 + 1

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{
      fore: {:math.cos(0.5), :math.sin(0.5)},
      hind: {:math.cos(-0.62), :math.sin(-0.62)},
      edges: List.to_tuple([nil | for(mask <- 1..63, do: edge(mask))])
    }
  end

  # An edge cell: the outline, facing the way the wing lies. Filled low in
  # the cell is the top of a wing, filled high its underside. The mask has a
  # bit for each of the six samples, j * 2 + i.
  # A cell with five or six samples on the wing is shaded instead.
  defp edge(mask) do
    {n, sx, sy} =
      for j <- 0..2, i <- 0..1, (mask >>> (j * 2 + i) &&& 1) == 1, reduce: {0, 0, 0} do
        {n, sx, sy} -> {n + 1, sx + (i - 0.5), sy + (1 - j)}
      end

    if n >= 5 do
      :shade
    else
      ux = sx / n
      uy = sy / n

      cond do
        abs(uy) > abs(ux) * 2 -> if uy < 0, do: low(n), else: high(n)
        abs(ux) > abs(uy) * 2 -> if ux > 0, do: "(", else: ")"
        ux * uy < 0 -> "/"
        true -> "\\"
      end
    end
  end

  defp low(n) when n < 3, do: "."
  defp low(_n), do: "_"
  defp high(n) when n < 3, do: "'"
  defp high(_n), do: "-"

  @compile {:inline, clamp01: 1, fore: 3, hind: 3}
  defp clamp01(v), do: min(1, max(0, v))

  # The teardrops' [p, q, p * p + q * q].
  defp fore(x, y, {c, s}) do
    dx = x - @fore_x
    dy = y - @fore_y
    p = (dx * c + dy * s) / @fore_a
    q = (dy * c - dx * s) / (@fore_b * (0.58 + 0.42 * clamp01((p + 1) / 2)))
    {p, q, p * p + q * q}
  end

  defp hind(x, y, {c, s}) do
    dx = x - @hind_x
    dy = y - @hind_y
    p = (dx * c + dy * s) / @hind_a
    q = (dy * c - dx * s) / (@hind_b * (0.58 + 0.42 * clamp01((p + 1) / 2)))
    {p, q, p * p + q * q}
  end

  # Whether (x, y) is on either wing: wing/4 is -1 exactly when it is not.
  defp hit?(x, y, state) do
    fdx = x - @fore_x
    fdy = y - @fore_y
    hdx = x - @hind_x
    hdy = y - @hind_y

    (fdx * fdx + fdy * fdy < @fore_far and elem(fore(x, y, state.fore), 2) < 1) or
      (hdx * hdx + hdy * hdy < @hind_far and elem(hind(x, y, state.hind), 2) < 1)
  end

  # How pale the wing is at (x, y) in its own plane, or -1 off the wing.
  defp wing(x, y, state) do
    case fore(x, y, state.fore) do
      {p, q, r} when r < 1 -> fore_shade(x, y, p, q, r)
      _ -> hind_shade(x, y, hind(x, y, state.hind))
    end
  end

  defp root?(x, y), do: JSMath.hypot(x, y * 0.8) < 3.6

  defp fore_shade(x, y, p, q, r) do
    rho = :math.sqrt(r)

    cond do
      # A dark margin round the tip, tapering towards the root, with one row
      # of pale spots in it.
      rho > 0.76 + 0.2 * clamp01((0.5 - p) / 0.8) ->
        if rho > 0.8 and rho < 0.95 and p > 0.3 and
             :math.cos(:math.atan2(q, p) * 7 + 0.3) > 0.45,
           do: 0.9,
           else: 0.24

      # One pale band slanting across the middle.
      abs(p * 0.85 + q * 0.5 - 0.02) < 0.17 ->
        0.9

      true ->
        if root?(x, y), do: 0.3, else: 0.55
    end
  end

  defp hind_shade(_x, _y, {_p, _q, r}) when r >= 1, do: -1

  defp hind_shade(x, y, {p, _q, r}) do
    # A round eyespot: a pale ring round a dark middle and a bright pupil.
    e = JSMath.hypot(x - 9.4, (y + 6.4) * 0.8)

    cond do
      e < 1 -> 1
      e < 2.3 -> 0.1
      e < 3.8 -> 0.9
      :math.sqrt(r) > 0.8 and p > -0.3 -> 0.24
      root?(x, y) -> 0.3
      true -> 0.55
    end
  end

  @impl true
  def frame(state, t, env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)
    # Flap for four seconds, glide for three; the glide starts with the wings low.
    g = JSMath.mod(u, 8)
    flap = flap(g)
    beat = :math.cos(@two_pi * @beat * u)
    th = flap * (0.6 - 0.72 * beat) - 0.06 * (1 - flap)
    # A slow, wide meander. Drifting sideways, it banks: the wing on that side dips.
    bx =
      JSMath.round(@cols / 2 + 9 * :math.sin(@w * u) + 2 * :math.sin(3 * @w * u + 0.6)) - 0.5

    by =
      @rows / 2 + 0.6 + 1.4 * :math.sin(2 * @w * u + 1) +
        0.35 * flap * :math.sin(@two_pi * @beat * u)

    # The bank shows most in the glide; mid-beat it would throw one wing edge on.
    bank =
      (0.16 - 0.1 * flap) * (:math.cos(@w * u) + 0.67 * :math.cos(3 * @w * u + 0.6)) / 1.67

    left = {:math.cos(th - bank), :math.sin(th - bank)}
    right = {:math.cos(th + bank), :math.sin(th + bank)}
    dim = 0.82 + 0.18 * :math.cos(th)

    # Where each sample column lands on the raised wing, undoing the
    # perspective: the left and right samples of each cell, and its middle.
    cols =
      for c <- 0..(@cols - 1) do
        {lens(c + 0.25 - bx, left, right), lens(c + 0.25 + 0.5 - bx, left, right),
         lens(c + 0.5 - bx, left, right)}
      end

    # The clubbed antennae go down first, so a raised wing hides them.
    col = bx - 0.5
    sway = 0.4 * :math.sin(@two_pi * 0.5 * u)

    out =
      for side <- [-1, 1], k <- 1..5, reduce: %{} do
        out ->
          f = k / 5
          ch = if k == 5, do: "o", else: if(side > 0, do: "/", else: "\\")
          put(out, col + side * (0.5 + 2.6 * f + sway * f * f), by - 2 - 5 * f, ch)
      end

    out =
      Enum.reduce(0..(@rows - 1), out, fn r, out ->
        ys = {(by - r - 0.5 / 3) * 2, (by - r - 1.5 / 3) * 2, (by - r - 2.5 / 3) * 2}
        mid = (by - r - 0.5) * 2
        row(out, r, cols, ys, mid, dim, env.paper, state)
      end)

    # The body, head to tail, over the wing roots.
    out =
      Enum.reduce(3..-9//-1, out, fn y, out -> put(out, col, by - y / 2, body(y)) end)

    lines =
      for r <- 0..(@rows - 1) do
        base = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(out, base + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp flap(g) when g < 4, do: 1
  defp flap(g) when g < 4.4, do: 1 - (g - 4) / 0.4
  defp flap(g) when g > 7.6, do: (g - 7.6) / 0.4
  defp flap(_g), do: 0

  defp body(y) when y > 1, do: "O"
  defp body(y) when y > -2, do: "#"
  defp body(y) when y > -8, do: "|"
  defp body(_y), do: "'"

  defp put(out, x, y, ch) do
    x = JSMath.round(x)
    y = JSMath.round(y)

    if x >= 0 and x < @cols and y >= 0 and y < @rows,
      do: Map.put(out, y * @cols + x, ch),
      else: out
  end

  # A sample column's place on its wing: its x there and the scale its y
  # shrinks by, or nil if it misses. The denominators stay positive: the
  # wings never tilt past upright, so cos(th +- bank) > 0.
  defp lens(x, left, right) do
    {ct, st} = if x < 0, do: left, else: right
    ax = abs(x)
    den = @eye * ct + ax * st

    if den <= 0 do
      nil
    else
      x = ax * @eye / den
      {x, @eye / (@eye - x * st)}
    end
  end

  defp row(out, r, cols, {y0, y1, y2}, mid, dim, paper, state) do
    {out, _} =
      Enum.reduce(cols, {out, r * @cols}, fn {a, b, m}, {out, at} ->
        mask =
          bit(a, y0, state, 1) ||| bit(b, y0, state, 2) ||| bit(a, y1, state, 4) |||
            bit(b, y1, state, 8) ||| bit(a, y2, state, 16) ||| bit(b, y2, state, 32)

        {cell(out, at, mask, m, mid, dim, paper, state), at + 1}
      end)

    out
  end

  defp bit(nil, _y, _state, _b), do: 0
  defp bit({x, k}, y, state, b), do: if(hit?(x, y / k, state), do: b, else: 0)

  defp cell(out, at, mask, m, mid, dim, paper, state) do
    case elem(state.edges, mask) do
      nil -> out
      :shade -> Map.put(out, at, shade(m, mid, dim, paper, state))
      glyph -> Map.put(out, at, glyph)
    end
  end

  defp shade(m, mid, dim, paper, state) do
    v =
      case m do
        nil -> -1
        {x, k} -> wing(x, mid / k, state)
      end

    i = max(1, JSMath.round(max(0, v) * dim * (@ramp_n - 1)))
    elem(@ramp, if(paper, do: @ramp_n - i, else: i))
  end
end
