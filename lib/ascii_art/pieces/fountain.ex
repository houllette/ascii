defmodule AsciiArt.Pieces.Fountain do
  @moduledoc """
  Arcs of water from a nozzle falling as drops into a basin.

  A tall jet and two pairs of arcs leave a nozzle, break into drops on the
  way down and splash into a brim-full basin, rippling its surface.

  Ported from `src/pieces/fountain.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "fountain",
    category: :physics,
    note: "arcs of water from a nozzle falling as drops into a basin",
    cols: 57,
    rows: 22,
    fps: 30
  }

  # Gravity, rows a second squared; drops leaving each jet a second; the row
  # of the water line; the nozzle's mouth above the water, rows; seconds in,
  # so every arc is already full.
  @g 30
  @rate 80
  @water 17
  @noz 6.5
  @t0 8
  # Each jet: angle from upright in degrees, where its middle meets the water
  # in rows from the post (0 for the upright jet, which is aimed by height),
  # how much its drops wander in angle and speed, and one drop in how many
  # stays in sight once it breaks up on the way down.
  @jets [
    {0, 0, 0.004, 0.035, 3},
    {-17, -7, 0.006, 0.008, 4},
    {17, 7, 0.006, 0.008, 4},
    {-42, -10.4, 0.005, 0.006, 5},
    {42, 10.4, 0.005, 0.006, 5}
  ]
  # How far the upright jet climbs above the nozzle.
  @top 8.4
  @basin [
    String.duplicate("▀", 49),
    "\\" <> String.duplicate("_", 45) <> "/",
    "|" <> String.duplicate(" ", 13) <> "|",
    "___|" <> String.duplicate("_", 13) <> "|___"
  ]
  # "#" is the post's hollow middle: blank, and drops pass behind it.
  @post ["_/^\\_", " |#| ", " |#| ", " |#| ", " |#| ", " |#| ", "_/#\\_"]

  @cols 57
  @rows 22
  # The middle of the nozzle's cell.
  @cx div(@cols, 2) + 0.5
  @lo div(@cols, 2) - 23
  @hi div(@cols, 2) + 23

  @compile {:inline, umul: 2}

  @impl true
  def meta, do: @meta

  defp umul(a, b),
    do:
      band(band(a, 0xFFFF) * b + bsl(band(bsr(a, 16) * band(b, 0xFFFF), 0xFFFF), 16), 0xFFFFFFFF)

  # The piece's own hash, in unsigned 32-bit arithmetic (imul, ^ and >>> agree
  # modulo 2^32 whatever the signs).
  defp hash(i, s) do
    h =
      bxor(
        umul(bxor(band(i, 0xFFFFFFFF), 0x9E3779B9), 0x85EBCA6B),
        umul(band(s + 1, 0xFFFFFFFF), 0xC2B2AE35)
      )

    h = umul(bxor(h, bsr(h, 15)), 0x2C1B3C6D)
    h = umul(bxor(h, bsr(h, 12)), 0x297A2D39)
    bxor(h, bsr(h, 15)) / 4_294_967_296
  end

  # Seconds from leaving the nozzle with upward speed vy until meeting the water.
  defp flight(vy), do: (vy + :math.sqrt(vy * vy + 2 * @g * @noz)) / @g

  @impl true
  def init(_options) do
    # The launch speed that lands each arc where it should, by bisection.
    jets =
      @jets
      |> Enum.with_index()
      |> Enum.map(fn {{deg, land, wa, wv, keep}, j} ->
        a = deg * :math.pi() / 180
        v = if deg == 0, do: :math.sqrt(2 * @g * @top), else: aim(a, land)
        %{a: a, v: v, wa: wa, wv: wv, keep: keep, j: j}
      end)

    # The upright jet is drawn last, so it runs whole down to the nozzle.
    jets = tl(jets) ++ [hd(jets)]

    {base, solid} =
      {%{}, MapSet.new()}
      |> stamp(@basin, @water + 1)
      |> stamp(@post, @water - length(@post) + 1)

    %{jets: jets, base: base, solid: solid}
  end

  defp aim(a, land) do
    {v, _, _} =
      Enum.reduce(1..40, {nil, 1, 60}, fn _, {_, lo, hi} ->
        v = (lo + hi) / 2

        if abs(v * :math.sin(a) * flight(v * :math.cos(a))) < abs(land),
          do: {v, v, hi},
          else: {v, lo, v}
      end)

    v
  end

  defp stamp(acc, art, r0) do
    art
    |> Enum.with_index(r0)
    |> Enum.reduce(acc, fn {line, r}, acc ->
      chars = String.codepoints(line)
      # Every line is odd and centred on the post.
      c0 = div(@cols, 2) - div(length(chars) - 1, 2)

      chars
      |> Enum.with_index(c0)
      |> Enum.reduce(acc, fn
        {" ", _c}, acc -> acc
        {"#", c}, {g, solid} -> {Map.put(g, r * @cols + c, " "), MapSet.put(solid, r * @cols + c)}
        {ch, c}, {g, solid} -> {Map.put(g, r * @cols + c, ch), MapSet.put(solid, r * @cols + c)}
      end)
    end)
  end

  # Drop i of a jet: when it left, its velocity, and how long it flies. The
  # upright jet's pressure swells and eases every five seconds.
  defp drop(jet, i) do
    s = jet.j * 7 + 1
    pulse = if jet.j != 0, do: 1, else: 0.95 + 0.05 * :math.sin(i / @rate * 1.2566)
    a = jet.a + (hash(i, s) - 0.5) * 2 * jet.wa * :math.pi()
    v = jet.v * pulse * (1 + (hash(i, s + 1) - 0.5) * 2 * jet.wv)
    vx = v * :math.sin(a)
    vy = v * :math.cos(a)
    {(i + hash(i, s + 2) * 0.6) / @rate, vx, vy, flight(vy)}
  end

  @impl true
  def frame(%{jets: jets, base: base, solid: solid} = state, time, _env) do
    t = @t0 + time
    from = JSMath.floor((t - 3.2) * @rate)
    to = JSMath.ceil(t * @rate)

    {grid, rings, hits, crowns} =
      for jet <- jets, i <- from..to//1, reduce: {base, [], [], []} do
        acc -> drop_at(acc, jet, i, t, solid)
      end

    rings = Enum.reverse(rings)

    # The water line: calm, with a wavelet running out each way from a landing.
    grid =
      Enum.reduce(@lo..@hi, grid, fn c, grid ->
        k = @water * @cols + c

        if MapSet.member?(solid, k) do
          grid
        else
          Map.put(grid, k, if(swell(rings, (c + 0.5 - @cx) / 2) > 0.3, do: "~", else: "-"))
        end
      end)

    # Where a drop strikes, the surface jumps; a crown of two drops is thrown
    # up either side and falls back in.
    grid =
      hits
      |> Enum.reverse()
      |> Enum.reduce(grid, fn x, grid ->
        c = JSMath.floor(@cx + 2 * x)
        k = @water * @cols + c

        if c >= @lo and c <= @hi and not MapSet.member?(solid, k),
          do: Map.put(grid, k, "^"),
          else: grid
      end)

    grid = crowns |> Enum.reverse() |> Enum.reduce(grid, &crown(&1, &2, solid))

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(grid, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp drop_at({grid, rings, hits, crowns} = acc, jet, i, t, solid) do
    {t0, vx, dvy, fly} = drop(jet, i)
    age = t - t0

    cond do
      age < 0 ->
        acc

      age >= fly ->
        k = age - fly
        x = vx * fly
        j = jet.j
        rings = if k < 1.4 and hash(i, j + 60) < 0.018, do: [{x, k} | rings], else: rings
        hits = if k < 0.07 and rem(i, jet.keep) == 0, do: [x | hits], else: hits
        crowns = if k < 0.4 and hash(i, j + 70) < 0.03, do: [{x, k, i, j} | crowns], else: crowns
        {grid, rings, hits, crowns}

      true ->
        {flying(grid, jet, i, age, vx, dvy, solid), rings, hits, crowns}
    end
  end

  defp flying(grid, jet, i, age, vx, dvy, solid) do
    vy = dvy - @g * age
    row = @water - @noz - dvy * age + @g * age * age / 2

    cond do
      # The stream rises whole and breaks into drops past the top, a few in sight.
      vy < 0 and rem(i, jet.keep) != 0 ->
        grid

      # Fallen back into the nozzle's throat.
      vy < 0 and jet.j == 0 and row > @water - @noz - 1 ->
        grid

      true ->
        put(
          grid,
          JSMath.floor(@cx + 2 * vx * age),
          JSMath.floor(row),
          glyph(jet, vx, vy, row),
          solid
        )
    end
  end

  # Rising, the stream's glyph runs along it, and the upright one stays
  # upright, beading where it slows at the top. Falling, a drop is a dot,
  # drawn out once it is fast.
  defp glyph(_jet, vx, vy, _row) when vy < 0,
    do: if(JSMath.hypot(vx, vy) > 17, do: ":", else: "·")

  defp glyph(%{j: 0}, vx, vy, _row) do
    speed = JSMath.hypot(vx, vy)

    cond do
      speed > 7 -> "|"
      speed > 3 -> "·"
      true -> "°"
    end
  end

  defp glyph(_jet, vx, vy, row) do
    ang = :math.atan2(vy, vx) * 180 / :math.pi()

    cond do
      abs(ang - 90) < 22 -> "|"
      ang < 28 or ang > 152 -> if JSMath.mod(row, 1) < 0.5, do: "-", else: "_"
      ang < 90 -> "/"
      true -> "\\"
    end
  end

  defp put(grid, c, r, ch, solid) do
    k = r * @cols + c

    if r >= 0 and r < @rows and c >= 0 and c < @cols and not MapSet.member?(solid, k),
      do: Map.put(grid, k, ch),
      else: grid
  end

  defp swell(rings, x) do
    Enum.reduce(rings, 0, fn {x0, k}, h ->
      d = abs(abs(x - x0) - 0.5 - 2.6 * k)
      if d < 0.4, do: h + (1 - d * 2.5) * (1 - k / 1.4), else: h
    end)
  end

  defp crown({x, k, i, j}, grid, solid) do
    Enum.reduce([-1, 1], grid, fn side, grid ->
      vx = side * (1.2 + hash(i, j + 40) * 1.4)
      vy = 7 + hash(i, j + 50 + side) * 4
      y = vy * k - @g * k * k / 2

      if y <= 0.2 do
        grid
      else
        put(
          grid,
          JSMath.floor(@cx + 2 * (x + vx * k)),
          JSMath.floor(@water - y),
          if(vy - @g * k > 0, do: "'", else: "."),
          solid
        )
      end
    end)
  end
end
