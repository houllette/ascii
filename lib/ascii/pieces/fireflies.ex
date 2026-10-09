defmodule Ascii.Pieces.Fireflies do
  @moduledoc """
  Fireflies over night grass, a flash spreading through them.

  A meadow at night, tufts of grass under a far treeline and a crescent moon.
  Fireflies drift over it, each flashing on its own slow beat, until one
  lights early and the flash runs fly to fly across the meadow.

  Upstream keeps the last few sweeps in a cache; a sweep depends on nothing
  but its number, so this port works out the ones a frame needs each frame.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `count` - fireflies over the meadow, 0 to 500, taken as a whole number.
      Default 44.
    * `seed` - the meadow's luck: where the stars and the fireflies are, and
      the beat each flashes to. The same seed draws the same meadow every
      time, another seed another. Default 7.

  The picture is always 60 by 18.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `Ascii.Ink`),
  or on a page a CSS variable. It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "fireflies: fireflies over
  night grass, a flash spreading through them". A player's or a component's
  `label` gives words of your own, as "fireflies over a meadow at night".

  ## Example

  ```elixir
  draw = fn options -> "fireflies" |> Ascii.new!(options: options) |> Ascii.frame(2.0) |> elem(0) end
  draw.(%{seed: 3}).text == draw.(%{seed: 3}).text
  #=> true

  draw.(%{seed: 3}).text == draw.(%{seed: 4}).text
  #=> false
  ```

  ```heex
  <Ascii.Phoenix.player socket={@socket} id="meadow" piece="fireflies" options={%{count: 80, seed: 11}} ink="#d4e157" />
  ```

  Ported from `src/pieces/fireflies.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "fireflies",
    category: :nature,
    note: "fireflies over night grass, a flash spreading through them",
    cols: 60,
    rows: 18,
    fps: 15,
    options: %{seed: 7, count: 44},
    bounds: %{count: {0, 500}}
  }

  @cols 60
  @rows 18
  @moon ["   _.._", " .' .-'", "/  /", "|  |", "\\  \\", " `._`-."]
  @trees [
    "                  .-.                         _",
    "     .-.   .--. .'   `.  .-.       .--.    .-' `-.   .-.",
    "__.-'   `-'    `       `-'   `-.__.'    `--'      `-'   `-._"
  ]
  # A fly's light, brightest first.
  @glow [{0.6, "*"}, {0.34, "+"}, {0.17, "·"}, {0.07, "."}]
  @halo [
    {0, 0, 1},
    {-1, 0, 0.45},
    {1, 0, 0.45},
    {-2, 0, 0.13},
    {2, 0, 0.13},
    {0, -1, 0.16},
    {0, 1, 0.16}
  ]
  # Seconds between flashes that sweep the meadow; how fast one runs, in
  # columns a second; seconds into a sweep at t = 0.
  @wave 11
  @speed 13
  @start 2.4
  # The ground row, and where the treeline meets the meadow.
  @ground 17
  @horizon 8
  @tau :math.pi() * 2
  @fans {[-1, 0, 1], [-1, 0, 1], [0, 1], [-1, 0], [-1, 1]}

  @impl true
  def meta, do: @meta

  defp hash(a, b) do
    seed = Bitwise.bxor(Int32.imul(a, 0x9E3779B1), Int32.imul(b + 1, 0x85EBCA6B))
    seed |> Int32.mulberry32() |> elem(0)
  end

  @impl true
  def init(%{seed: seed, count: count}) do
    # mulberry32 takes the seed as given; its first step truncates it.
    rnd = seed

    # The sky, drawn once: stars, the moon, and the far treeline.
    {stars, rnd} =
      Enum.map_reduce(1..16, rnd, fn _, rnd ->
        {[a, b, p], rnd} = take(rnd, 3)
        {{floor(a * 5), floor(b * (@cols - 14)), p}, rnd}
      end)

    sky =
      [
        for({line, i} <- Enum.with_index(@moon), do: {i, @cols - 12, line}),
        for({line, i} <- Enum.with_index(@trees), do: {@horizon - 3 + i, 0, line})
      ]
      |> Enum.concat()
      |> Enum.reduce(%{}, fn {r, c0, line}, sky ->
        line
        |> String.codepoints()
        |> Enum.with_index(c0)
        |> Enum.reduce(sky, fn
          {" ", _}, sky -> sky
          {ch, c}, sky -> Map.put(sky, {r, c}, ch)
        end)
      end)

    sky =
      for r <- 0..(@rows - 1) do
        List.to_tuple(
          for c <- 0..(@cols - 1),
              do: if(r == @ground, do: "_", else: Map.get(sky, {r, c}, " "))
        )
      end

    {first, rnd} = Int32.mulberry32(rnd)
    {blades, rnd} = tufts(2 + first * 3, rnd, [])

    # Each fly wanders on a few slow waves over the meadow and the grass tips.
    {flies, _} =
      Enum.map_reduce(1..trunc(count)//1, rnd, fn _, rnd ->
        {[x, y, w0, w1, w2, p0, p1, p2], rnd} = take(rnd, 8)

        {%{
           x: 3 + x * (@cols - 6),
           y: 9.3 + y * 4.6,
           w: {0.05 + w0 * 0.08, 0.11 + w1 * 0.1, 0.07 + w2 * 0.08},
           p: {p0 * @tau, p1 * @tau, p2 * @tau}
         }, rnd}
      end)

    %{
      seed: seed,
      sky: List.to_tuple(sky),
      stars: stars,
      blades: blades,
      flies: List.to_tuple(flies)
    }
  end

  defp take(rnd, n), do: Enum.map_reduce(1..n, rnd, fn _, r -> Int32.mulberry32(r) end)

  # Grass in tufts with room between them: blades fanning out from one root,
  # a straight one in the middle the tallest.
  defp tufts(x, rnd, blades) when x >= @cols - 2, do: {Enum.reverse(blades), rnd}

  defp tufts(x, rnd, blades) do
    {a, rnd} = Int32.mulberry32(rnd)
    h = 2 + floor(a * 4)
    c = floor(x)
    ph = x * 0.23
    {b, rnd} = Int32.mulberry32(rnd)
    fan = elem(@fans, floor(b * tuple_size(@fans)))

    {blades, rnd} =
      Enum.reduce(fan, {blades, rnd}, fn
        0, {blades, rnd} ->
          {[{c, h, 0, ph} | blades], rnd}

        lean, {blades, rnd} ->
          {d, rnd} = Int32.mulberry32(rnd)
          {[{c, max(1, h - 1 - floor(d * 1.6)), lean, ph} | blades], rnd}
      end)

    {e, rnd} = Int32.mulberry32(rnd)
    tufts(x + (4 + e * 7), rnd, blades)
  end

  defp place(%{x: x, y: y, w: {w0, w1, w2}, p: {p0, p1, p2}}, s) do
    {x + 6 * :math.sin(w0 * s + p0) + 2.5 * :math.sin(w1 * s + p1),
     y + 1.4 * :math.sin(w2 * s + p2) + 0.6 * :math.sin(w1 * 1.7 * s + p0)}
  end

  # How bright a fly is a fraction ph through its beat: a quick rise, then a
  # slower fade.
  defp glow(ph) when ph < 0.04, do: ph / 0.04
  defp glow(ph), do: :math.exp(-(ph - 0.04) / 0.13)

  # Each sweep starts at the fly furthest to one side, the sides taking
  # turns, and reaches every other fly as the flash travels; after it, each
  # fly keeps a beat of its own until the next.
  defp sweep(%{flies: flies, seed: seed}, w) do
    at = flies |> Tuple.to_list() |> Enum.map(&place(&1, w * @wave))
    odd = Bitwise.band(w, 1) == 1

    {ox, oy} =
      Enum.reduce(tl(at), hd(at), fn {px, _} = p, {bx, _} = b ->
        if (odd and px > bx) or (not odd and px < bx), do: p, else: b
      end)

    at
    |> Enum.with_index()
    |> Enum.map(fn {{x, y}, i} ->
      {w * @wave + JSMath.hypot(x - ox, 2 * (y - oy)) / @speed, 1 / (5 + 3.5 * hash(seed + i, w))}
    end)
    |> List.to_tuple()
  end

  defp bright(sweeps, i, s) do
    w = floor(s / @wave)
    {at, rate} = elem(Map.fetch!(sweeps, w), i)
    {at, rate} = if s < at, do: elem(Map.fetch!(sweeps, w - 1), i), else: {at, rate}
    ph = (s - at) * rate
    if ph < 0, do: 0, else: glow(ph - floor(ph))
  end

  @impl true
  def frame(state, t, _env) do
    s = @wave * 3 + @start + t
    w = floor(s / @wave)

    sweeps =
      if tuple_size(state.flies) == 0,
        do: %{},
        else: Map.new((w - 2)..w, &{&1, sweep(state, &1)})

    g =
      Enum.reduce(state.stars, %{}, fn {r, c, p}, g ->
        ch = if p < 0.25 and :math.sin(t * 1.3 + p * 50) > 0.3, do: "+", else: "."
        Map.put(g, {r, c}, ch)
      end)

    g = Enum.reduce(state.blades, g, &blade(&1, &2, s))

    # Each fly's light, with a faint trail where it was brighter a moment
    # ago; the glow's faint edge stays behind the grass.
    field =
      state.flies
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {f, i}, field -> fly(field, sweeps, f, i, s) end)

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.sky, r)

        for c <- 0..(@cols - 1) do
          ch = Map.get(g, {r, c}, elem(row, c))
          v = Map.get(field, r * @cols + c, 0)

          case Enum.find(@glow, fn {min, _} -> v >= min end) do
            {_, light} when r >= @horizon and r < @ground and (ch == " " or v >= 0.34) -> light
            _ -> ch
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp blade({c, h, lean, ph}, g, s) do
    sway = 0.6 * :math.sin(s * 0.8 - ph)

    {g, _} =
      Enum.reduce(1..h, {g, c + 0.5}, fn k, {g, px} ->
        q = k / h
        x = c + 0.5 + lean * k + sway * (q * q)
        d = x - px
        col = floor(x)

        ch =
          cond do
            d > 0.5 -> "/"
            d < -0.5 -> "\\"
            true -> "|"
          end

        {if(col >= 0 and col < @cols, do: Map.put(g, {@ground - k, col}, ch), else: g), x}
      end)

    g
  end

  defp fly(field, sweeps, f, i, s) do
    v = bright(sweeps, i, s)

    field =
      if v > 0.05 do
        {x, y} = place(f, s)
        light(field, x, y, v)
      else
        field
      end

    Enum.reduce(1..4, field, fn k, field ->
      sk = s - k * 0.3
      old = bright(sweeps, i, sk)

      if old > v do
        {x, y} = place(f, sk)
        c = floor(x)
        r = floor(y)

        if c >= 0 and c < @cols and r >= @horizon and r < @ground,
          do: raise_to(field, r * @cols + c, 0.25 * old),
          else: field
      else
        field
      end
    end)
  end

  defp light(field, x, y, v) do
    c = floor(x)
    r = floor(y)

    for {dc, dr, k} <- @halo,
        cc = c + dc,
        rr = r + dr,
        cc >= 0 and cc < @cols and rr >= @horizon and rr < @ground,
        reduce: field do
      field -> raise_to(field, rr * @cols + cc, v * k)
    end
  end

  # A store of the larger into the Float32Array.
  defp raise_to(field, at, v),
    do: Map.put(field, at, JSMath.fround(max(Map.get(field, at, 0), v)))
end
