defmodule Ascii.Pieces.PluckedString do
  @moduledoc """
  A plucked string, slowed down, its harmonics fading.

  A string stretched over two bridges, slowed down. A finger pulls it into a
  corner and lets go; the corner splits in two and runs back and forth as the
  sum of its harmonics, the high ones dying first.

  Ported from `src/pieces/plucked-string.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "plucked string",
    category: :physics,
    note: "a plucked string, slowed down, its harmonics fading",
    cols: 64,
    rows: 14,
    fps: 30
  }

  # The string at rest, in rows from the top; the bridges, as column edges.
  @r0 6.5
  @a 9
  @b 55
  # Harmonics summed; seconds for the fundamental, slowed down; seconds
  # between plucks.
  @n 32
  @period 1.6
  @cycle 6
  # The finger coming down, then pulling; seconds in: the finger about to let go.
  @down 0.55
  @pull 0.6
  @t0 1.05
  # The string's glyph by where it crosses its cell, top to bottom.
  @line {"▔", "─", "▁"}

  @cols 64
  @rows 14
  @l @b - @a

  @impl true
  def meta, do: @meta

  # The piece's own hash, in unsigned 32-bit arithmetic (imul, ^ and >>> agree
  # modulo 2^32 whatever the signs).
  defp hash(i, s) do
    h =
      bxor(
        umul(bxor(band(i, 0xFFFFFFFF), 0x9E3779B9), 0x85EBCA6B),
        umul(band(s + 1, 0xFFFFFFFF), 0xC2B2AE35)
      )

    h = umul(bxor(h, bsr(h, 15)), 0x2C1B3C6D)
    bxor(h, bsr(h, 13)) / 4_294_967_296
  end

  defp umul(a, b),
    do:
      band(band(a, 0xFFFF) * b + bsl(band(bsr(a, 16) * band(b, 0xFFFF), 0xFFFF), 16), 0xFFFFFFFF)

  defp ease(u) when u <= 0, do: 0
  defp ease(u) when u >= 1, do: 1
  defp ease(u), do: u * u * (3 - 2 * u)

  @impl true
  def init(_options) do
    # sin(n pi u) at each column's middle.
    shape =
      for c <- 0..(@cols - 1) do
        u = (c + 0.5 - @a) / @l

        List.to_tuple(
          for n <- 0..(@n - 1),
              do: if(u > 0 and u < 1, do: :math.sin((n + 1) * :math.pi() * u), else: 0)
        )
      end

    %{shape: List.to_tuple(shape), base: base()}
  end

  # The box with an end block and a pin at each end, and a bridge near each.
  defp base do
    r0 = JSMath.floor(@r0)

    ends =
      for {pin, edge} <- [{1, @a}, {@cols - 2, @b}] do
        [{r0, pin, "o"}] ++
          for(
            r <- (r0 + 1)..11,
            {dc, ch} <- [{-1, "▐"}, {0, "█"}, {1, "▌"}],
            do: {r, pin + dc, ch}
          ) ++
          for d <- 1..5 do
            rr = r0 + d

            under =
              if d == 5, do: for(c <- (edge - d + 1)..(edge + d - 2), do: {rr, c, "_"}), else: []

            [{rr, edge - d, "/"}, {rr, edge + d - 1, "\\"} | under]
          end
      end

    writes =
      List.flatten([
        ends,
        for(c <- 2..(@a - 1), do: {r0, c, "─"}),
        for(c <- @b..(@cols - 3), do: {r0, c, "─"}),
        for(c <- 0..(@cols - 1), do: {12, c, "▀"}),
        for c <- 2..(@cols - 3) do
          {13, c,
           cond do
             c == 2 -> "\\"
             c == @cols - 3 -> "/"
             true -> "_"
           end}
        end
      ])

    Enum.reduce(writes, %{}, fn {r, c, ch}, base -> Map.put(base, r * @cols + c, ch) end)
  end

  # Pluck k: where along the string, which way and how far, and its triangle's
  # harmonics. Plucks take turns pulling up and pressing down.
  defp pluck(k) do
    near = hash(k, 1) < 0.5
    p = if near, do: 0.2 + 0.18 * hash(k, 2), else: 0.62 + 0.18 * hash(k, 2)
    h = if(rem(k, 2) != 0, do: -1, else: 1) * (3.3 + 0.5 * hash(k, 3))

    b =
      for n <- 0..(@n - 1) do
        m = n + 1
        2 * h * :math.sin(m * :math.pi() * p) / (m * m * :math.pi() * :math.pi() * p * (1 - p))
      end

    %{p: p, h: h, b: b, col: JSMath.floor(@a + p * @l)}
  end

  # The string's height in rows at every column, s seconds after pluck pk let
  # go. Damping grows gently with the harmonic, so the corner keeps its edge
  # for a few passes before it rounds off.
  defp ring(shape, pk, s) do
    terms =
      pk.b
      |> Enum.with_index()
      |> Enum.flat_map(fn {b, n} ->
        m = n + 1

        a =
          b * :math.cos(2 * :math.pi() * m * s / @period) *
            :math.exp(-(0.2 + 0.0022 * m * m) * s)

        if abs(a) < 1.0e-4, do: [], else: [{n, a}]
      end)

    List.to_tuple(
      for c <- 0..(@cols - 1) do
        column = elem(shape, c)
        Enum.reduce(terms, 0, fn {n, a}, y -> y + a * elem(column, n) end)
      end
    )
  end

  defp tri(c, pk) do
    u = (c + 0.5 - @a) / @l

    cond do
      u <= 0 or u >= 1 -> 0
      u < pk.p -> pk.h * (u / pk.p)
      true -> pk.h * ((1 - u) / (1 - pk.p))
    end
  end

  @impl true
  def frame(%{shape: shape, base: base} = state, time, _env) do
    t = @t0 + time
    k = JSMath.floor(t / @cycle)
    s = t - k * @cycle
    pk = pluck(k)
    held = @down + @pull
    under = if pk.h > 0, do: 1, else: 0
    fc = pk.col

    # Until the finger lets go, the last pluck rings on; then the new one.
    y =
      if s < held,
        do: ring(shape, pluck(k - 1), s + @cycle - held),
        else: ring(shape, pk, s - held)

    # The finger's tip row: it comes down to the string, hooking just under it
    # to pull up or resting on it to press down, then flicks away.
    {y, tip} =
      cond do
        s < @down ->
          {y,
           JSMath.floor(@r0 - elem(y, fc)) + under -
             JSMath.round(10 * (1 - ease(s / @down)))}

        s < held ->
          w = ease((s - @down) / @pull)
          y = List.to_tuple(for c <- 0..(@cols - 1), do: (1 - w) * elem(y, c) + w * tri(c, pk))
          {y, JSMath.floor(@r0 - elem(y, fc)) + under}

        s < held + 0.4 ->
          d = s - held
          {y, JSMath.floor(@r0 - pk.h) + under - JSMath.round(25 * d + 40 * d * d)}

        true ->
          {y, -1}
      end

    # The string: one glyph a column, slanted where it runs steep.
    g =
      Enum.reduce(@a..(@b - 1), base, fn c, g ->
        row = @r0 - elem(y, c)
        r = JSMath.floor(row)
        slope = (elem(y, min(@cols - 1, c + 1)) - elem(y, max(0, c - 1))) / 2

        ch =
          cond do
            abs(slope) <= 0.55 -> elem(@line, min(2, JSMath.floor((row - r) * 3)))
            slope > 0 -> "/"
            true -> "\\"
          end

        Map.put(g, r * @cols + c, ch)
      end)

    g = finger(g, tip, fc)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(g, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The finger, from above the frame down to its rounded tip, in front of the
  # string.
  defp finger(g, tip, _fc) when tip < 0, do: g

  defp finger(g, tip, fc) do
    g =
      Enum.reduce(0..(tip - 1)//1, g, fn r, g ->
        g
        |> Map.put(r * @cols + fc - 1, "│")
        |> Map.put(r * @cols + fc, " ")
        |> Map.put(r * @cols + fc + 1, "│")
      end)

    g
    |> Map.put(tip * @cols + fc - 1, "╰")
    |> Map.put(tip * @cols + fc, "─")
    |> Map.put(tip * @cols + fc + 1, "╯")
  end
end
