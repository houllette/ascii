defmodule Ascii.Pieces.Bonsai do
  @moduledoc """
  A potted tree that sheds its leaves and leafs out again.

  A tree in a shallow pot through a year. Its leaf pads are shaded domes, lit
  from the upper left; in autumn they thin leaf by leaf and drop, the
  branches stand bare, then the pads bud again from the middle out.

  Ported from `src/pieces/bonsai.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "bonsai",
    category: :nature,
    note: "a potted tree that sheds its leaves and leafs out again",
    cols: 52,
    rows: 19,
    fps: 10
  }

  @cols 52
  @rows 19
  # Seconds: summer, autumn, bare, spring, summer.
  @loop 26
  # A leaf starts to turn in this span and is gone after @fade.
  @autumn {3, 8.5}
  @fade 2.5
  # A leaf buds in this span and is full after @grow.
  @spring {14, 18.5}
  @grow 2.5
  # Seconds a falling leaf takes per row.
  @drop 0.24
  @ramp {" ", ".", ",", ":", ";", "*", "%", "&", "@"}

  # Leaf pads: the middle of the widest row, half-width, the height of the
  # dome in rows, and where the branch under it splits into twigs.
  @pads [
    {27, 3, 7, 2.2, {2, 27}},
    {15, 5, 7.5, 1.3, {6, 15}},
    {39, 6, 7, 1.3, {7, 39}},
    {11, 9, 6.5, 1.3, {10, 11}},
    {40, 11, 6, 1.3, {12, 40}}
  ]
  # The trunk from the soil up: {row, first column, width}. It tapers 3, 2, 1
  # and leans right, back left, then right again into the top pad.
  @trunk [
    {15, 24, 3},
    {14, 24, 3},
    {13, 25, 3},
    {12, 26, 2},
    {11, 26, 2},
    {10, 25, 2},
    {9, 24, 2},
    {8, 24, 1},
    {7, 24, 1},
    {6, 25, 1},
    {5, 26, 1},
    {4, 26, 1},
    {3, 27, 1}
  ]
  # Branches, each a run of strokes from the trunk out to a pad.
  @wood [
    # To the lowest pad, right.
    {12, 28, "___________"},
    # Left.
    {11, 19, "\\______"},
    {10, 13, "______"},
    # Right.
    {8, 25, "_____/"},
    {7, 31, "______"},
    # Left.
    {7, 19, "\\____"},
    {6, 17, "__"}
  ]
  @pot [
    {15, 6, ".________________/   \\________________."},
    {16, 7, "\\___________________________________/"},
    {17, 9, "`\"\"\"`                       `\"\"\"`"}
  ]
  # Where a leaf lands in the pot: the row and its columns.
  @soil {14, 7, 43}

  @strays [{-1.2, 0}, {0.5, 0}, {2.0, 1}, {3.0, 0}, {22.6, 1}, {24.4, 3}]

  @impl true
  def meta, do: @meta

  defp hash(a, b) do
    h = Int32.imul(a * 374_761_393 + b * 668_265_263, 1_274_126_177)
    h = Int32.imul(Bitwise.bxor(h, Int32.ushr(h, 13)), 1_103_515_245)
    Int32.to_uint32(Bitwise.bxor(h, Int32.ushr(h, 16))) / 4_294_967_296
  end

  @impl true
  def init(_options) do
    leaves = leaves()
    %{wood: wood(), leaves: leaves, falls: falls(leaves)}
  end

  defp wood do
    {trunk, _} =
      Enum.map_reduce(@trunk, nil, fn {r, c, w} = seg, below ->
        shift = if below, do: c + w / 2 - (elem(below, 1) + elem(below, 2) / 2), else: 0

        ch =
          cond do
            shift > 0.2 -> "/"
            shift < -0.2 -> "\\"
            true -> "|"
          end

        {{r, c, String.duplicate(ch, w)}, seg}
      end)

    # Under each pad its branch splits into twigs, seen once the leaves are off.
    fans =
      Enum.flat_map(@pads, fn {_, _, _, _, {r, c}} ->
        [{r, c - 1, "\\|/"}, {r - 1, c - 2, "\\   /"}]
      end)

    cells =
      for {r, c, s} <- @pot ++ trunk ++ @wood ++ fans,
          {ch, i} <- Enum.with_index(String.codepoints(s)),
          ch != " ",
          reduce: %{} do
        cells -> Map.put(cells, {r, c + i}, ch)
      end

    List.to_tuple(
      for r <- 0..(@rows - 1) do
        List.to_tuple(for c <- 0..(@cols - 1), do: Map.get(cells, {r, c}, " "))
      end
    )
  end

  # Every leaf: where it is, how dense it is lit and in shadow, and when it
  # turns and buds. Outer leaves turn first; inner ones bud first.
  defp leaves do
    {a0, a1} = @autumn
    {s0, s1} = @spring

    for {{px, py, pw, ph, _}, n} <- Enum.with_index(@pads),
        r <- ceil(py - ph)..(py + 1),
        c <- floor(px - pw)..ceil(px + pw),
        dx = (c - px) / pw,
        dy = (r - py) / ph,
        # A dome above the widest row; one flat, tucked row below it.
        rho = if(r <= py, do: JSMath.hypot(dx, dy), else: max(abs(dx) / 0.85, 0.72)),
        rho <= 1 do
      h = hash(r * 97 + n, c)
      edge = if r <= py, do: JSMath.hypot(dx, dy * 0.85), else: rho
      mass = min(1, (1 - edge) * 2.6) * (0.85 + 0.3 * h)
      lit = max(0, min(1, 0.5 - 0.35 * dx - 0.55 * if(r <= py, do: dy, else: 1.1)))

      %{
        r: r,
        c: c,
        h: h,
        pad: n,
        under: r > py,
        day: mass * (0.5 + 0.5 * lit),
        night: mass * (0.5 + 0.5 * (1 - lit)),
        turn: a0 + (a1 - a0) * (0.7 * (1 - rho) + 0.3 * h),
        bud: s0 + (s1 - s0) * min(1, 0.75 * rho + 0.25 * h)
      }
    end
  end

  # Falling leaves: a few strays in summer, and in autumn some of each pad's
  # underside as it goes. Each drops near where it left, and one that lands in
  # the pot lies there, a stray for a while and an autumn leaf until spring.
  defp falls(leaves) do
    under =
      for n <- 0..(length(@pads) - 1) do
        Enum.filter(leaves, &(&1.pad == n and &1.under and &1.day > 0.15))
      end

    strays =
      for {{t0, n}, k} <- Enum.with_index(@strays) do
        from = Enum.at(under, n)
        leaf = Enum.at(from, floor(hash(k, 1) * length(from)))
        fall(leaf, JSMath.mod(t0 + @loop, @loop), k, nil)
      end

    autumn =
      under
      |> List.flatten()
      |> Enum.filter(&(hash(&1.r, &1.c * 3) < 0.22))
      |> Enum.with_index()
      |> Enum.map(fn {l, k} ->
        fall(l, l.turn + @fade * 0.8, k + 10, elem(@spring, 0) + 3 * hash(k, 3))
      end)

    strays ++ autumn
  end

  defp fall(l, t0, k, until) do
    drift = (hash(k, 7) - 0.5) * 1.2
    phase = hash(k, 9) * 6.3
    path = path(l, drift, phase, l.r + 1, 0, [])
    {last_r, _} = List.last(path)

    lie =
      if last_r == elem(@soil, 0) do
        until = until || t0 + length(path) * @drop + 3
        JSMath.mod(until - t0 + @loop, @loop)
      else
        0
      end

    %{t0: t0, path: List.to_tuple(path), lie: lie}
  end

  defp path(_l, _drift, _phase, r, _i, acc) when r >= @rows, do: Enum.reverse(acc)

  defp path(l, drift, phase, r, i, acc) do
    c = JSMath.round(l.c + drift * i * @drop + :math.sin(i * 0.9 + phase))
    {soil_r, soil_c0, soil_c1} = @soil

    if r == soil_r and c >= soil_c0 and c <= soil_c1,
      do: Enum.reverse([{r, c} | acc]),
      else: path(l, drift, phase, r + 1, i + 1, [{r, c} | acc])
  end

  @impl true
  def frame(state, t, env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)
    # A gust runs through the crown now and then, stirring the leaves.
    gust = :math.pow(max(0, :math.sin(u / @loop * :math.pi() * 8)), 3)

    over =
      Enum.reduce(state.leaves, %{}, fn l, over ->
        f = fullness(l, u)

        if f <= 0 do
          over
        else
          stir = gust * 0.12 * :math.sin(u * 5 - l.c * 0.5 + l.h * 3)
          v = if env.paper, do: l.night, else: l.day
          i = JSMath.round(max(0, min(1, v * f + stir)) * (tuple_size(@ramp) - 1))
          if i > 0, do: Map.put(over, {l.r, l.c}, elem(@ramp, i)), else: over
        end
      end)

    over = Enum.reduce(state.falls, over, &falling(&1, &2, u, state.wood))

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.wood, r)
        for c <- 0..(@cols - 1), do: Map.get(over, {r, c}, elem(row, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp fullness(%{turn: turn, bud: bud}, u) do
    spring = elem(@spring, 0)

    cond do
      u >= turn and u < spring -> max(0, 1 - (u - turn) / @fade)
      u >= spring and u < bud -> 0
      u >= bud and u < bud + @grow -> (u - bud) / @grow
      true -> 1
    end
  end

  defp falling(%{t0: t0, path: path, lie: lie}, over, u, wood) do
    age = JSMath.mod(u - t0 + @loop, @loop)
    step = floor(age / @drop)
    n = tuple_size(path)
    {r, c} = elem(path, min(step, n - 1))

    # Off the grid reads undefined, which is not a space.
    blank? = c >= 0 and c < @cols and Map.get(over, {r, c}, elem(elem(wood, r), c)) == " "

    cond do
      not blank? -> over
      step < n -> Map.put(over, {r, c}, if(Bitwise.band(step, 1) == 1, do: "'", else: ","))
      age < lie -> Map.put(over, {r, c}, ",")
      true -> over
    end
  end
end
