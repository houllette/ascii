defmodule AsciiArt.Pieces.Train do
  @moduledoc """
  A steam train crossing on its track, smoke puffing behind.

  A steam train crossing the frame on its track, a coach and tender behind
  the engine. Smoke puffs from the stack in time with the beat of the
  wheels, whose rods turn as they roll; it leaves on the right and comes
  back.

  Ported from `src/pieces/train.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Hash

  @meta %AsciiArt.Meta{
    name: "train",
    category: :objects,
    note: "a steam train crossing on its track, smoke puffing behind",
    cols: 76,
    rows: 26,
    fps: 15
  }

  @cols 76
  @rows 26

  # The train side on as blocks of {top row, left column, lines}. Spaces are
  # see-through.
  @parts [
    {14, 0,
     [
       ~S" ________________ ",
       ~S"/________________\ ",
       ~S"| __  __  __  __ | ",
       ~S"||  ||  ||  ||  || ",
       ~S"||__||__||__||__|| ",
       ~S"|________________|=",
       ~S" |=|=|      |=|=|  "
     ]},
    {15, 19,
     [
       ~S"  _.-^^^^-._  ",
       ~S" |^^^^^^^^^^| ",
       ~S" |          | ",
       ~S" |          | ",
       ~S" |__________|=",
       ~S"  |=|=||=|=|  "
     ]},
    {9, 33,
     [
       ~S"                           _____ ",
       ~S"                           \   / ",
       ~S" _________      .-.  _      | |  ",
       ~S" \_______/_____/   \| |_____| |__[]",
       ~S"  | ___ |  ||      ||      ||    \ ",
       ~S"  ||   ||  ||      ||      ||     )",
       ~S"  ||___||  ||      ||      ||     )",
       ~S"  |     |__||______||______||____/ ",
       ~S"  |_____|=========================[]",
       ~S"  | |                             |\ ",
       ~S"  |_|                       ____  |\\ ",
       ~S"                           |____| |\\\ ",
       ~S"                                  | \\\ ",
       ~S"                                  |__\\\ "
     ]}
  ]
  # The train's length, rear buffer to the tip of the cowcatcher.
  @len 73
  @rail 23
  # Columns a second.
  @speed 8
  # The coupled wheels' centre columns, and the small wheels' columns.
  @drive [42, 52]
  @small [3, 6, 12, 15, 22, 25, 28, 31]
  # Where the main rod meets the crosshead, mid stroke; the back of the
  # cylinder; the chimney's column.
  @cross 58
  @cyl 60
  @stack 62
  # The driving wheels' radius, in rows.
  @rim 2.5
  # Seconds the smoke lasts, and columns a second it drifts back.
  @life 5.5
  @wind 2.4
  # Thin to thick.
  @smoke {" ", ".", ":", "-", "=", "+", "*"}
  # A driving wheel: the rim, then the spokes square on and an eighth of a
  # turn on.
  @wheel [~S"  .---.  ", ~S" /     \ ", ~S"|  (o)  |", ~S" \     / ", ~S"  '---'  "]
  @spokes {[~S"    |    ", ~S" --   -- ", ~S"    |    "],
           [~S"   \ /   ", ~S"         ", ~S"   / \   "]}

  # A lap: in from the left, across and out.
  @span @cols + @len + 1
  # At t = 0 the engine and tender are in, the coach coming.
  @x0 @len - 16
  # Radians a second the wheels turn; four beats to a turn.
  @omega @speed / (2 * @rim)
  @beat :math.pi() / 2 / @omega

  @impl true
  def meta, do: @meta

  # The track and the ballast under it, which never move.
  @impl true
  def init(_options) do
    track =
      for c <- 0..(@cols - 1),
          {r, ch} <- [
            {@rail, "="},
            {@rail + 1, if(rem(c, 3) != 0, do: "_", else: "|")},
            {@rail + 2, ballast(Hash.short(c, 5))}
          ],
          do: {r * @cols + c, ch}

    %{track: track}
  end

  defp ballast(h) when h < 0.16, do: ":"
  defp ballast(h) when h < 0.34, do: ","
  defp ballast(h) when h < 0.44, do: "'"
  defp ballast(h) when h < 0.7, do: "."
  defp ballast(_h), do: " "

  # The train's left edge.
  defp left(t), do: floor(JSMath.mod(JSMath.mod(@x0 + @speed * t, @span) + @span, @span)) - @len

  defp put(out, r, c, ch) when r >= 0 and r < @rows and c >= 0 and c < @cols,
    do: Map.put(out, r * @cols + c, ch)

  defp put(out, _r, _c, _ch), do: out

  defp text(out, r, c, s) do
    s
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.reduce(out, fn
      {" ", _}, out -> out
      {ch, i}, out -> put(out, r, c + i, ch)
    end)
  end

  @impl true
  def frame(state, t, _env) do
    ox = left(t)

    out =
      t
      |> smoke()
      |> Enum.reduce(%{}, fn {j, v}, out ->
        if v > 0.08,
          do: Map.put(out, j, elem(@smoke, min(tuple_size(@smoke) - 1, ceil(v * 7)))),
          else: out
      end)

    out = Enum.reduce(state.track, out, fn {k, ch}, out -> Map.put(out, k, ch) end)

    out =
      for {r0, c0, lines} <- @parts, {s, i} <- Enum.with_index(lines), reduce: out do
        out -> text(out, r0 + i, ox + c0, s)
      end

    # The wheels turn as far as they roll.
    a = @omega * t
    eighth = rem(JSMath.floor(a / (:math.pi() / 4)), 2)

    out =
      Enum.reduce(@drive, out, fn c, out ->
        out =
          @wheel
          |> Enum.with_index()
          |> Enum.reduce(out, fn {s, i}, out -> text(out, @rail - 5 + i, ox + c - 4, s) end)

        @spokes
        |> elem(eighth)
        |> Enum.with_index()
        |> Enum.reduce(out, fn {s, i}, out -> text(out, @rail - 4 + i, ox + c - 4, s) end)
      end)

    roll = rem(JSMath.floor(@speed * t / 1.4), 2)

    out =
      Enum.reduce(@small, out, fn c, out ->
        out
        |> text(@rail - 2, ox + c - 1, ".-.")
        |> text(@rail - 1, ox + c - 1, if(roll != 0, do: "(+)", else: "(x)"))
      end)

    out = rods(out, ox, a)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Smoke: let go from the stack, left where it was let go, rising, swelling
  # and thinning as it drifts back on the wind. Each cell keeps its densest
  # billow, as a Float32Array keeps it.
  defp smoke(t) do
    Stream.iterate(JSMath.ceil((t - @life) / @beat), &(&1 + 1))
    |> Enum.take_while(&(&1 * @beat <= t))
    |> Enum.reduce(%{}, fn k, dens ->
      age = t - k * @beat
      u = age / @life

      # Past its life upstream's power is NaN, and NaN draws nothing.
      if 1 - u < 0, do: dens, else: puff(dens, k, age, u)
    end)
  end

  defp puff(dens, k, age, u) do
    x = left(k * @beat) + @stack - @wind * age + 0.8 * :math.sin(k * 1.7)
    y = 8.4 - 7.2 * (1 - :math.exp(-age / 2)) + 0.5 * :math.sin(k * 2.9)
    rad = 1.5 + 0.75 * :math.pow(age, 0.8)
    w = :math.pow(1 - u, 1.2)

    for r <- floor(y - rad)..floor(y + rad)//1,
        c <- floor(x - 2 * rad)..floor(x + 2 * rad)//1,
        r >= 0 and r < @rows and c >= 0 and c < @cols,
        reduce: dens do
      dens ->
        dx = (c + 0.5 - x) / 2 / rad
        dy = (r + 0.5 - y) / rad
        q = dx * dx + dy * dy

        if q >= 1 do
          dens
        else
          # Lit from above, so each billow keeps its round top where it
          # overlaps the last.
          v = w * :math.sqrt(1 - q) * (0.6 - 0.4 * dy - 0.1 * dx)
          j = r * @cols + c
          if v > Map.get(dens, j, 0), do: Map.put(dens, j, JSMath.fround(v)), else: dens
        end
    end
  end

  # The crank pins go round together with the rod between them, and the main
  # rod runs on to the crosshead. Rods pass behind the rims and the hubs.
  defp rods(out, ox, a) do
    [d0, d1] = @drive
    hub = @rail - 3
    dr = -JSMath.round(1.2 * :math.sin(a))
    dc = JSMath.round(if(dr != 0, do: 2.4, else: 3) * :math.cos(a))
    pr = hub + dr

    out =
      Enum.reduce((d0 + dc)..(d1 + dc), out, fn c, out ->
        if free?(pr, c, hub),
          do: put(out, pr, ox + c, if(c == d0 + dc or c == d1 + dc, do: "o", else: "=")),
          else: out
      end)

    x0 = d1 + dc
    xh = @cross + JSMath.round(:math.cos(a))

    out =
      Enum.reduce((x0 + 1)..(xh - 1)//1, out, fn c, out ->
        r = JSMath.round(pr + (hub - pr) * (c - x0) / (xh - x0))
        if free?(r, c, hub), do: put(out, r, ox + c, if(r == pr, do: "=", else: "-")), else: out
      end)

    out = put(out, hub, ox + xh, "#")
    Enum.reduce((xh + 1)..(@cyl - 1)//1, out, &put(&2, hub, ox + &1, "="))
  end

  defp free?(r, c, hub) do
    Enum.all?(@drive, fn d ->
      abs(c - d) != if(r == hub, do: 4, else: 3) and (r != hub or abs(c - d) > 1)
    end)
  end
end
