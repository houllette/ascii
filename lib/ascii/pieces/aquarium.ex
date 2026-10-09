defmodule Ascii.Pieces.Aquarium do
  @moduledoc """
  Fish swimming and turning in a tank, bubbles and weed.

  A fish tank. Fish of a few kinds swim its length, drift between depths and
  turn about, bubbles stream up from a stone, and weed sways.

  Ported from `src/pieces/aquarium.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Hash, Text}

  @meta %Ascii.Meta{
    name: "aquarium",
    category: :creatures,
    note: "fish swimming and turning in a tank, bubbles and weed",
    cols: 60,
    rows: 20,
    fps: 15
  }

  @cols 60
  @rows 20
  # Seconds; every period below divides it.
  @loop 48
  @tau :math.pi() * 2
  @surface 1
  @floor 17
  # Where the bubbles leave the stone.
  @nozzle 46

  @flip %{
    "<" => ">",
    ">" => "<",
    "(" => ")",
    ")" => "(",
    "/" => "\\",
    "\\" => "/",
    "`" => "'",
    "'" => "`",
    "{" => "}",
    "}" => "{"
  }

  # Fish, facing right, with the face-on view shown while they turn, farthest
  # first: {art, face-on art, row, from column, to column, seconds there and
  # back, phase, rows it drifts up and down over the loop, drift phase}.
  @fish [
    {["><>"], ["<o>"], 5.2, 6, 54, 12, 0.8, 1.5, 1},
    {["><>"], ["<o>"], 6.6, 3, 51, 12, 0.775, 1.5, 1.1},
    {["><>"], ["<o>"], 8, 8, 56, 12, 0.79, 1.5, 0.9},
    {["><(((°>"], ["<(°o°)>"], 3.3, 3, 50, 24, 0.1, 1.2, 1},
    {["><(°>"], ["(°o°)"], 15.6, 4, 40, 48, 0.55, 0.4, 3},
    {["    /\\", " ><(  °>", "    \\/"], ["/^\\", "(°o°)", "\\v/"], 9.8, 10, 51, 24, 0.35, 0.9,
     4},
    {["   _.-._", "><(     °)", "   `-.-'"], [".-^-.", "(°o°)", "`-v-'"], 12.8, 2, 46, 16, 0.6,
     0.9, 4}
  ]

  # Clumps of weed, {root column, [{height, lean} for each blade], phase}.
  @weeds [
    {6, [{11, 0.6}, {8, -1.6}, {6, 2}], 0},
    {13, [{6, 1.2}, {4, -1.2}], 1.7},
    {25, [{4, -1}, {3, 1}], 0.9},
    {37, [{9, 1.2}, {6, -1.4}, {4, 2.2}], 2.4},
    {55, [{7, -1.2}, {5, 0.8}], 0.4}
  ]

  @stone [{15, 43, " .--._"}, {16, 42, "(  .  `)"}]

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # Gravel: a fine bed with coarser stones lying in it here and there.
    gravel =
      for k <- 0..1 do
        for c <- 0..(@cols - 3), do: gravel(k, Hash.murmur(c, k + 3))
      end

    side = ["│", List.duplicate(" ", @cols - 2), "│"]

    base =
      for r <- 0..(@rows - 1) do
        cond do
          r == 0 -> ["┌", List.duplicate("─", @cols - 2), "┐"]
          r == @rows - 1 -> ["└", List.duplicate("─", @cols - 2), "┘"]
          r >= @floor -> ["│", Enum.at(gravel, r - @floor), "│"]
          true -> side
        end
        |> List.flatten()
        |> List.to_tuple()
      end
      |> List.to_tuple()

    weeds = Enum.map(@weeds, &weed_prep/1)

    %{
      base: base,
      surface: for(c <- 1..(@cols - 2), do: {c * 0.55, c * 0.23}),
      back_weeds: Enum.drop(weeds, -1),
      front_weed: List.last(weeds),
      stone: Enum.flat_map(@stone, fn {r, c, s} -> marks(r, c, prep(s)) end),
      fish: Enum.map(@fish, &fish_prep/1),
      bubbles:
        for(
          k <- 0..79,
          do: {k, k * (@loop / 80), 2.6 + Hash.murmur(k, 1), Hash.murmur(k, 2) - 0.5}
        )
    }
  end

  defp gravel(0, n) when n < 0.55, do: "."
  defp gravel(0, n) when n < 0.75, do: ","
  defp gravel(0, _n), do: "·"
  defp gravel(1, n) when n < 0.14, do: "o"
  defp gravel(1, n) when n < 0.2, do: "O"
  defp gravel(1, n) when n < 0.27, do: "°"
  defp gravel(1, n) when n < 0.4, do: "."
  defp gravel(1, _n), do: " "

  # Art is opaque from its first mark to its last on each line: a line
  # becomes the {offset, character} pairs it writes.
  defp prep(s) do
    chars = Text.chars(s)
    first = Enum.find_index(chars, &(&1 != " ")) || 0
    last = s |> String.trim_trailing() |> Text.length()
    for {ch, i} <- Enum.with_index(chars), i >= first and i < last, do: {i, ch}
  end

  defp marks(r, c, line), do: for({i, ch} <- line, do: {r, c + i, ch})

  defp mirror(art) do
    w = art |> Enum.map(&Text.length/1) |> Enum.max()

    Enum.map(art, fn l ->
      l
      |> Text.pad_end(w)
      |> Text.chars()
      |> Enum.reverse()
      |> Enum.map_join(&Map.get(@flip, &1, &1))
    end)
  end

  defp fish_prep({art, turn, row, from, to, period, phase, drift, dp}) do
    w = art |> Enum.map(&Text.length/1) |> Enum.max()

    view = fn a ->
      tw = a |> Enum.map(&Text.length/1) |> Enum.max()
      # (w - tw) >> 1 and art.length >> 1, both floor halves.
      {Enum.map(a, &prep/1), Integer.floor_div(w - tw, 2), div(length(a), 2)}
    end

    %{
      art: view.(art),
      back: view.(mirror(art)),
      turn: view.(turn),
      row: row,
      from: from,
      span: to - from,
      period: period,
      phase: phase,
      drift: drift,
      dp: dp,
      dp3: dp * 3
    }
  end

  # Each blade's steps, with what does not move precomputed: the root's
  # column plus the lean, f * 0.7 and lean * 0.2.
  defp weed_prep({c0, blades, ph}) do
    {c0 + 0.5, ph,
     for {h, lean} <- blades do
       for k <- 1..h do
         f = k / h
         {@floor - k, f, c0 + 0.5 + lean * :math.pow(f, 1.5), f * 0.7, lean * 0.2}
       end
     end}
  end

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)
    ut = u * @tau

    g =
      %{}
      |> weeds(state.back_weeds, ut)
      |> put_marks(state.stone)
      |> fishes(state.fish, u)
      |> bubbles(state.bubbles, u, state.base)
      |> weed(state.front_weed, ut / 6)

    # The water's surface rippling under the rim.
    a = ut / 4
    b = ut / 6

    surface =
      for {c55, c23} <- state.surface do
        if :math.sin(c55 - a) + 0.5 * :math.sin(c23 + b) > 0.3, do: "~", else: "-"
      end

    lines =
      for r <- 0..(@rows - 1) do
        if r == @surface do
          ["│", surface, "│"]
        else
          row = elem(state.base, r)
          base = r * @cols
          for c <- 0..(@cols - 1), do: Map.get(g, base + c, elem(row, c))
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp put(g, r, c, ch)
       when r > @surface and r < @rows - 1 and c > 0 and c < @cols - 1,
       do: Map.put(g, r * @cols + c, ch)

  defp put(g, _r, _c, _ch), do: g

  defp put_marks(g, marks), do: Enum.reduce(marks, g, fn {r, c, ch}, g -> put(g, r, c, ch) end)

  defp put_line(g, r, c, line),
    do: Enum.reduce(line, g, fn {i, ch}, g -> put(g, r, c + i, ch) end)

  defp weeds(g, weeds, ut) do
    a = ut / 6
    Enum.reduce(weeds, g, &weed(&2, &1, a))
  end

  # Weed: blades that rise straight from the root and bend further toward
  # the tip, the tip swinging two or three columns as the water moves.
  defp weed(g, {root, ph, blades}, a) do
    a = a + ph

    Enum.reduce(blades, g, fn steps, g ->
      {g, _} =
        Enum.reduce(steps, {g, root}, fn {r, f, lean_x, f7, l2}, {g, px} ->
          sway = 1.4 * :math.sin(a - f7 + l2)
          x = lean_x + sway * f * f
          {put(g, r, JSMath.floor(x), stroke(x - px)), x}
        end)

      g
    end)
  end

  defp stroke(d) when d > 0.5, do: "/"
  defp stroke(d) when d > 0.17, do: "("
  defp stroke(d) when d < -0.5, do: "\\"
  defp stroke(d) when d < -0.17, do: ")"
  defp stroke(_d), do: "|"

  # Each fish swims there and back, easing into each turn, and drifts up
  # and down over the loop; for a moment mid-turn it faces out of the glass.
  defp fishes(g, fish, u) do
    a = @tau * u / @loop
    b = @tau * u / 6

    Enum.reduce(fish, g, fn f, g ->
      th = @tau * (u / f.period + f.phase)
      p = :math.asin(0.995 * :math.sin(th)) / (:math.pi() / 2)
      x = JSMath.round(f.from + (p + 1) / 2 * f.span)

      y =
        JSMath.round(f.row + f.drift * :math.sin(a + f.dp) + 0.35 * :math.sin(b + f.dp3))

      cos = :math.cos(th)

      {lines, dx, half} =
        cond do
          abs(cos) < 0.09 -> f.turn
          cos > 0 -> f.art
          true -> f.back
        end

      {g, _} =
        Enum.reduce(lines, {g, 0}, fn line, {g, i} ->
          {put_line(g, y + i - half, x + dx, line), i + 1}
        end)

      g
    end)
  end

  # Bubbles leave the stone in a stream, wobbling and swelling as they rise,
  # and break at the surface.
  defp bubbles(g, bubbles, u, base) do
    Enum.reduce(bubbles, g, fn {k, k6, rise, wob}, g ->
      age = JSMath.mod(u - k6 + @loop, @loop)
      y = 14.6 - age * rise

      if y < @surface + 1 do
        g
      else
        x = @nozzle + JSMath.round(0.7 * :math.sin(age * 3.5 + k) + wob)
        r = JSMath.floor(y)
        i = r * @cols + x

        if Map.get(g, i, elem(elem(base, r), x)) == " ",
          do: Map.put(g, i, bubble(y)),
          else: g
      end
    end)
  end

  defp bubble(y) when y > 11, do: "."
  defp bubble(y) when y > 6, do: "o"
  defp bubble(_y), do: "O"
end
