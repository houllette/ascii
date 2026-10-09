defmodule Ascii.Pieces.Spider do
  @moduledoc """
  A spider lowering itself on silk, then climbing back up.

  A spider drops from the hub of its web in the corner on a line of silk,
  bounces at the end of it with its legs going, then climbs back up.

  Ported from `src/pieces/spider.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "spider",
    category: :creatures,
    note: "a spider lowering itself on silk, then climbing back up",
    cols: 28,
    rows: 24,
    fps: 15
  }

  @cols 28
  @rows 24
  @loop 10
  # The middle of the web, in columns and rows; the walls cut its outer ring.
  @hc 10
  @hr 4
  # Hexagonal rings, by how many rows they sit from the hub.
  @rings [3, 6]
  @outer 6
  # Rows the sprite's top hangs at, on the web and at the end of the line.
  @top 3
  @low 15.6
  # The left half of the spider, head down, in two leg poses; the right half
  # is the mirror. A side in one pose and the other side in the other is a
  # step, so both halves keep the same reach.
  @poses {
    [
      "  \\    .-",
      "   \\  (##",
      " ___\\_ `-",
      " |    \\(@",
      "   ___/ `",
      "  /   /  ",
      "      |  "
    ],
    ["   |   .-", "   \\  (##", " ___\\_ `-", "/     \\(@", "   ___/ `", "   |  /  ", "     /   "]
  }
  @mid "|#-@V  "
  @flip %{"/" => "\\", "\\" => "/", "(" => ")", ")" => "(", "`" => "'"}

  @impl true
  def meta, do: @meta

  defp ease(x) when x <= 0, do: 0
  defp ease(x) when x >= 1, do: 1
  defp ease(x), do: x * x * (3 - 2 * x)

  @impl true
  def init(_options) do
    sprites = Enum.map([{0, 0}, {0, 1}, {1, 0}], fn {l, r} -> sprite(l, r) end)
    w = sprites |> hd() |> hd() |> Text.length()

    %{
      web: web(),
      w: w,
      # Each pose's marks, {column, row, char}, spaces left out.
      sprites:
        sprites
        |> Enum.map(fn lines ->
          for {l, j} <- Enum.with_index(lines),
              {ch, i} <- Enum.with_index(Text.chars(l)),
              ch != " ",
              do: {i, j, ch}
        end)
        |> List.to_tuple()
    }
  end

  defp sprite(l, r) do
    [elem(@poses, l), elem(@poses, r), Text.chars(@mid)]
    |> Enum.zip_with(fn [s, m, ch] ->
      s <> ch <> (m |> Text.chars() |> Enum.reverse() |> Enum.map_join(&Map.get(@flip, &1, &1)))
    end)
  end

  defp set(out, c, r, ch) when c >= 0 and c < @cols and r >= 0 and r < @rows,
    do: Map.put(out, r * @cols + c, ch)

  defp set(out, _c, _r, _ch), do: out

  # The web never changes, so it is drawn once and copied under each frame:
  # hexagonal rings, then eight spokes over them, out to the ceiling and the
  # wall above and to the left and just past the last ring elsewhere.
  defp web do
    out =
      Enum.reduce(@rings, %{}, fn k, out ->
        out =
          Enum.reduce((@hc - k + 1)..(@hc + k - 1)//1, out, fn c, out ->
            out |> set(c, @hr - k, "_") |> set(c, @hr + k - 1, "_")
          end)

        Enum.reduce([-1, 1], out, fn s, out ->
          out =
            Enum.reduce(1..k//1, out, fn i, out ->
              set(out, @hc + s * (k + i - 1), @hr - k + i, if(s > 0, do: "\\", else: "/"))
            end)

          Enum.reduce(1..(k - 1)//1, out, fn i, out ->
            set(out, @hc + s * (2 * k - i), @hr + i, if(s > 0, do: "/", else: "\\"))
          end)
        end)
      end)

    out =
      Enum.reduce(1..(@cols - 1), out, fn j, out ->
        out = set(out, @hc, @hr - j, "|")
        out = if j <= @outer, do: set(out, @hc, @hr + j, "|"), else: out

        Enum.reduce([-1, 1], out, fn s, out ->
          out = set(out, @hc + s * j, @hr - j, if(s > 0, do: "/", else: "\\"))

          out =
            if j <= @outer,
              do: set(out, @hc + s * j, @hr + j, if(s > 0, do: "\\", else: "/")),
              else: out

          k = @hr * @cols + @hc + s * j
          reach? = if s < 0, do: @hc - j >= 0, else: j <= 2 * @outer

          if reach? and Map.get(out, k, " ") == " ", do: Map.put(out, k, "_"), else: out
        end)
      end)

    out = set(out, @hc, @hr, "*")
    List.to_tuple(for i <- 0..(@cols * @rows - 1), do: Map.get(out, i, " "))
  end

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t + 2.4, @loop) + @loop, @loop)
    # Where the sprite's top row is, and how fast the legs go.
    {y, rate, climb} = motion(u)

    sway =
      if u > 3 and u < 7,
        do: 0.8 * :math.sin((u - 3) * 2.1) * :math.exp(-(u - 3) * 0.6),
        else: 0

    half = Bitwise.bsr(state.w, 1)
    r0 = JSMath.round(y)
    c0 = @hc - half + JSMath.round(sway)

    # Legs step between poses, the two sides out of turn with each other.
    pose =
      cond do
        climb >= 0 -> 1 + climb
        rate != 0 -> 1 + rem(JSMath.floor(u * rate), 2)
        u > 0.3 and u < 0.55 -> 1
        true -> 0
      end

    marks = elem(state.sprites, pose)

    # Clear a cell's width of web round every mark, so no thread touches a leg.
    out =
      for {i, j, _} <- marks, dj <- -1..1, di <- -1..1, reduce: %{} do
        out -> set(out, c0 + i + di, r0 + j + dj, " ")
      end

    # Off the hub, the line hangs where the lower spoke ran.
    out =
      if r0 > @hr do
        out
        |> unspoke(state.web)
        |> silk(@hc + 0.5, @hr + 1, c0 + half + 0.5, r0)
      else
        out
      end

    out = Enum.reduce(marks, out, fn {i, j, ch}, out -> set(out, c0 + i, r0 + j, ch) end)

    lines =
      for r <- 0..(@rows - 1) do
        base = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(out, base + c, elem(state.web, base + c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp motion(u) when u >= 1 and u < 3.4 do
    f = (u - 1) / 2.4
    {@top + (@low - @top) * (f * f), 3, -1}
  end

  # The line stops paying out and the silk springs back: it leaves at the
  # speed it fell.
  defp motion(u) when u >= 3.4 and u < 6 do
    s = u - 3.4
    w = 6
    v = 2 * (@low - @top) / 2.4
    {@low + v / w * :math.exp(-s * 1.3) * :math.sin(s * w), if(s < 1.8, do: 6, else: 0), -1}
  end

  # Hand over hand: a lurch up with each pull, then a pause.
  defp motion(u) when u >= 6 and u < 9.4 do
    pull = (u - 6) / 3.4 * 8
    n = JSMath.floor(pull)
    {@low - (@low - @top) * ((n + ease(JSMath.mod(pull, 1) * 1.6)) / 8), 0, rem(n, 2)}
  end

  defp motion(_u), do: {@top, 0, -1}

  defp unspoke(out, web) do
    Enum.reduce(1..@outer, out, fn j, out ->
      k = (@hr + j) * @cols + @hc
      if Map.get(out, k, elem(web, k)) == "|", do: Map.put(out, k, " "), else: out
    end)
  end

  # A straight thread from the hub to the spinnerets: one glyph a row. With
  # no rows between them (y1 == y0, where upstream's slope is infinite or
  # NaN) nothing is drawn.
  defp silk(out, _x0, y0, _x1, y1) when y1 == y0, do: out

  defp silk(out, x0, y0, x1, y1) do
    k = (x1 - x0) / (y1 - y0)

    g =
      cond do
        abs(k) < 0.3 -> "|"
        k > 0 -> "\\"
        true -> "/"
      end

    Enum.reduce(JSMath.round(y0)..(JSMath.round(y1) - 1)//1, out, fn r, out ->
      set(out, JSMath.floor(x0 + k * (r + 0.5 - y0)), r, g)
    end)
  end
end
