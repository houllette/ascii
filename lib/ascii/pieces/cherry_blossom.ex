defmodule Ascii.Pieces.CherryBlossom do
  @moduledoc """
  A flowering cherry branch shedding petals on the wind.

  A flowering cherry branch reaching in from the left. Each gust shakes the
  blossoms on their twigs, and petals come loose and tumble away on the
  wind.

  Ported from `src/pieces/cherry-blossom.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Hash

  @meta %Ascii.Meta{
    name: "cherry blossom",
    category: :nature,
    note: "a flowering cherry branch shedding petals on the wind",
    cols: 64,
    rows: 20,
    fps: 15
  }

  @cols 64
  @rows 20
  # Seconds; two gusts.
  @loop 24
  # Seconds between gusts, and how long one lasts.
  @gust 12
  @blow 4.5
  # Let go each loop.
  @petals 14

  # The wood: a limb tapering in from the left, a thin limb hanging from it,
  # and the twigs the blossoms sit on.
  @wood [
    "",
    "",
    "______",
    "      `----.___",
    "______         `---.__  |             /",
    "      `----.___       `-|.__      \\  /",
    "             | `---.___     `-.__  \\/",
    "             |         `--.__    `-.__                 /",
    "                             `-._     `--.___         /",
    "                                 \\           `---.___/",
    "                                  \\ \\                \\",
    "                                   ) )                \\",
    "                                  / /                  \\",
    "                                 / /",
    "                                ( (",
    "                                 \\ \\",
    "                                    \\_"
  ]

  # Blossoms open, side on, small, cupped and partly shed, and buds: {art,
  # row, column, how far a gust shakes it, the petal it lets go as {line,
  # column, length}}.
  @open [" _(_)_", "(_)@(_)", " (_)(_)"]
  @flowers [
    {@open, 1, 21, 1, {2, 4, 3}},
    {["    _", " _(_)", "(_)@", " (_)"], 1, 31, 1, {3, 1, 3}},
    {[" _ _", "(_@_)"], 2, 37, 2, {0, 3, 1}},
    {[" .-.", "(_@_)", " '|'"], 4, 54, 1, {0, 1, 3}},
    {[" _(_)", "(_)@(_)", "    (_)"], 12, 56, 2, {0, 1, 4}},
    {@open, 16, 30, 0, {2, 1, 3}},
    {[" _ _", "(_@_)", " (_)"], 15, 38, 0, {2, 1, 3}},
    {["(_)(_)", " (@)"], 8, 11, 1, {0, 3, 3}},
    {["o"], 19, 34, 1, nil}
  ]
  @flex @flowers |> Enum.map(&elem(&1, 3)) |> List.to_tuple()
  # A petal turning over.
  @tumble {"o", "°", "-", "~", "-", "°"}
  # The high blossoms shed most.
  @from {0, 1, 3, 2, 7, 0, 4, 1, 3, 7, 2, 0, 5, 6}

  @impl true
  def meta, do: @meta

  # How hard a gust is blowing, 0 to 1.
  defp gust(t) do
    x = JSMath.mod(JSMath.mod(t - 1, @gust) + @gust, @gust)

    if x < @blow do
      s = :math.sin(:math.pi() * x / @blow)
      s * s
    else
      0
    end
  end

  # How far gusts have carried the air since time 0, in gust-seconds.
  defp blown(t) do
    n = floor((t - 1) / @gust)
    x = t - 1 - n * @gust

    carried =
      if x < @blow,
        do: x / 2 - @blow / (2 * :math.pi()) * :math.sin(2 * :math.pi() * x / @blow),
        else: @blow / 2

    n * @blow * 0.5 + carried
  end

  # How far a blossom is shaken at time t: it trembles while a gust blows.
  defp shake(k, t) do
    flex = elem(@flex, k)
    JSMath.round(min(flex, flex * gust(t) * (0.8 + 0.35 * :math.sin(t * 8.5 + k * 2.3))))
  end

  @impl true
  def init(_options) do
    wood =
      for r <- 0..(@rows - 1) do
        chars = @wood |> Enum.at(r, "") |> String.pad_trailing(@cols) |> String.codepoints()
        List.to_tuple(chars)
      end

    # Each blossom's characters, and whether each is in the petal it lets go.
    flowers =
      for {{art, r0, c0, _flex, slot}, k} <- Enum.with_index(@flowers) do
        cells =
          for {line, i} <- Enum.with_index(art),
              {ch, j} <- Enum.with_index(String.codepoints(line)),
              ch != " " do
            {r0 + i, c0 + j, ch, in_slot?(slot, i, j)}
          end

        {k, cells}
      end

    # Petals leave blossoms at their own moments, more of them in the gusts,
    # and ride the wind down and away, turning over as they go.
    petals =
      for i <- 0..(@petals - 1) do
        t0 =
          if rem(i, 2) == 1,
            do: rem(div(i, 2), 2) * @gust + 1.2 + Hash.murmur(i, 2) * 2.2,
            else: Hash.murmur(i, 1) * @loop

        flower = elem(@from, rem(i, tuple_size(@from)))
        {_art, r0, c0, _flex, {s0, s1, _}} = Enum.at(@flowers, flower)

        %{
          t0: t0,
          flower: flower,
          fall: 0.42 + Hash.murmur(i, 5) * 0.22,
          drag: 0.8 + Hash.murmur(i, 6) * 0.5,
          spin: 1.2 + Hash.murmur(i, 8) * 0.8,
          ph: Hash.murmur(i, 9) * 6.3,
          x0: c0 + s1 + 1,
          y0: r0 + s0 + 0.5
        }
      end

    %{wood: List.to_tuple(wood), flowers: flowers, petals: petals}
  end

  defp in_slot?(nil, _i, _j), do: false
  defp in_slot?({line, from, n}, i, j), do: i == line and j >= from and j < from + n

  @compile {:inline, inside?: 2}
  defp inside?(r, c), do: r >= 0 and r < @rows and c >= 0 and c < @cols

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)

    # Blossoms sit over the wood; one that has just let a petal go shows the
    # gap for a few seconds.
    loose =
      for p <- state.petals, JSMath.mod(u - p.t0 + @loop, @loop) < 3, into: MapSet.new() do
        p.flower
      end

    over =
      Enum.reduce(state.flowers, %{}, fn {k, cells}, over ->
        dc = shake(k, t)
        gaps? = MapSet.member?(loose, k)

        Enum.reduce(cells, over, fn {r, c, ch, slot?}, over ->
          if inside?(r, c + dc),
            do: Map.put(over, {r, c + dc}, if(gaps? and slot?, do: " ", else: ch)),
            else: over
        end)
      end)

    blown_t = blown(t)

    over =
      for p <- state.petals, k <- 0..1, reduce: over do
        over -> petal(p, k, t, u, blown_t, over, state.wood)
      end

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.wood, r)
        for c <- 0..(@cols - 1), do: Map.get(over, {r, c}, elem(row, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp petal(p, k, t, u, blown_t, over, wood) do
    age = JSMath.mod(u - p.t0 + @loop, @loop) + k * @loop

    x =
      p.x0 + shake(p.flower, t - age) +
        p.drag * (0.16 * age + 2.2 * (blown_t - blown(t - age))) +
        1.1 * :math.sin(age * 0.9 + p.ph)

    y = p.y0 + p.fall * age + 0.3 * :math.sin(age * 1.9 + p.ph)
    c = floor(x)
    r = floor(y)

    if inside?(r, c) and Map.get(over, {r, c}, elem(elem(wood, r), c)) == " ",
      do: Map.put(over, {r, c}, elem(@tumble, rem(floor(age * p.spin + p.ph), 6))),
      else: over
  end
end
