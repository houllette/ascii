defmodule Ascii.Pieces.Owl do
  @moduledoc """
  An owl on a branch, blinking slowly and turning its head.

  A horned owl on a branch at night. It blinks slowly, and now and then turns
  its head to look off to one side before facing front again.

  Ported from `src/pieces/owl.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "owl",
    category: :creatures,
    note: "an owl on a branch, blinking slowly and turning its head",
    cols: 41,
    rows: 24,
    fps: 12,
    loop: 12
  }

  @cols 41
  @rows 24
  @loop 12
  # The middle column.
  @cx 20
  # Head turns as {start, end, from, to} in seconds and pose steps; blinks as
  # start times.
  @turns [{2, 2.5, 0, -2}, {4.4, 5.1, -2, 0}, {7.4, 7.9, 0, 2}, {9.8, 10.5, 2, 0}]
  @blinks [0.6, 6.1, 6.9, 11.2]
  @blink 0.7

  # The top of the head in three poses, facing front and turning to the
  # viewer's right: the near tuft slides in, the far one narrows against the
  # edge and the crown slides with them. Each pose also places the two eyes
  # {column, sprite} and the beak.
  @heads [
    {[
       "          /\\                 /\\",
       "         /  \\_.--'''''''--._/  \\",
       "        /                       \\"
     ], [{11, 0}, {22, 0}], 20},
    {[
       "           /\\                 /\\",
       "         _/  \\_.--'''''''--._/  \\",
       "        /                        |"
     ], [{12, 0}, {24, 1}], 22},
    {[
       "            /\\                  /|",
       "         _./  \\_.--''''''''--._/ |",
       "        /                        |"
     ], [{13, 0}, {26, 1}], 24}
  ]

  # Eye sprites by how square-on they are: rim, iris top, pupil, iris foot, rim.
  @eyes {
    [" .----. ", "/ .--. \\", "| (@@) |", "\\ `--' /", " `----' "],
    [" .--. ", "/.--.\\", "|(@@)|", "\\`--'/", " `--' "]
  }

  # The left half of the body, columns 0 to 20; the right half is its
  # mirror. Scalloped coverts at the shoulder, then the flight feathers,
  # their tips breaking the hatch.
  @half [
    "       (\\",
    "      /  \\.",
    "     /  ( (\\",
    "    |  ( ( (|",
    "    |  ( ( ( \\",
    "    |  \\\\\\\\\\  \\",
    "    |  \\\\\\\\ \\  \\",
    "     \\  \\\\\\\\ \\  \\",
    "      \\  \\\\\\\\ \\  \\",
    "       `. \\\\\\\\ \\  `.",
    "         `-.\\\\\\ \\____"
  ]
  @flip %{"/" => "\\", "\\" => "/", "(" => ")", ")" => "(", "`" => "'"}
  @branch [
    "=-==-===-==-==-=====-=-=====-==-=-==-=-=)",
    " `-.__.-'~~`--.__.--'   `--.__.-'~`-.__/ "
  ]
  @stars [{2, 1}, {5, 0}, {1, 5}, {37, 0}, {39, 3}, {36, 6}, {39, 11}]

  @impl true
  def meta, do: @meta

  defp ease(x) when x <= 0, do: 0
  defp ease(x) when x >= 1, do: 1
  defp ease(x), do: x * x * (3 - 2 * x)

  defp pose_at(u) do
    @turns
    |> Enum.reduce(0, fn {a, b, from, to}, p ->
      if u >= a, do: from + (to - from) * ease((u - a) / (b - a)), else: p
    end)
    |> JSMath.round()
  end

  # How shut the eyes are, 0 open to 1 shut: they close slowly and open slower.
  defp lid_at(u) do
    Enum.find_value(@blinks, 0, fn s ->
      d = u - s

      cond do
        d < 0 or d >= @blink -> nil
        d < 0.3 -> ease(d / 0.25)
        true -> 1 - ease((d - 0.3) / (@blink - 0.3))
      end
    end)
  end

  @impl true
  def init(_options) do
    body =
      Enum.map(@half, fn l ->
        l = Text.pad_end(l, 21)
        l <> (l |> Text.slice(0, 20) |> Text.chars() |> Enum.reverse() |> flip_all(@flip))
      end)

    # The body, branch, feet and tail never move.
    g =
      body
      |> Enum.with_index(9)
      |> Enum.reduce(%{}, fn {l, y}, g -> put(g, 0, y, l) end)

    # Chevrons down the breast, staggered row to row and closer set lower down.
    g =
      Enum.reduce(10..18, g, fn r, g ->
        gap = if r < 13, do: 4, else: if(r < 16, do: 3, else: 2)
        off = if rem(r, 2) == 1, do: div(gap, 2), else: 0
        {a, b} = span(&(Map.get(g, r * @cols + &1, " ") == " "), 0, @cols - 1)

        Enum.reduce((a + 1)..(b - 1)//1, g, fn c, g ->
          if Integer.mod(c - @cx + off, gap) == 0, do: set(g, r, c, "v"), else: g
        end)
      end)

    g =
      Enum.reduce(10..30//2, g, fn c, g ->
        set(g, 9, c, if(Bitwise.band(c, 2) != 0, do: "'", else: "`"))
      end)

    [b0, b1] = @branch

    g =
      g
      |> put(0, 20, b0)
      |> put(0, 21, b1)
      |> put(@cx - 7, 20, "mm")
      |> put(@cx + 6, 20, "mm")
      |> put(@cx - 2, 21, "|||||")
      |> put(@cx - 2, 22, "'''''")

    base =
      for r <- 0..(@rows - 1) do
        List.to_tuple(for c <- 0..(@cols - 1), do: Map.get(g, r * @cols + c, " "))
      end

    %{base: List.to_tuple(base), poses: Map.new(-2..2, &{&1, pose(&1)})}
  end

  defp flip_all(chars, flip), do: Enum.map_join(chars, &Map.get(flip, &1, &1))

  # A pose turned the other way is the mirror image.
  defp pose(k) do
    {top, eyes, beak} = Enum.at(@heads, abs(k))

    if k >= 0 do
      {top, eyes, beak}
    else
      eyes =
        eyes
        |> Enum.map(fn {x, e} -> {@cols - x - eye_width(e), e} end)
        |> Enum.reverse()

      {Enum.map(top, &mirror/1), eyes, @cols - 1 - beak}
    end
  end

  defp mirror(s) do
    s
    |> Text.pad_end(@cols)
    |> Text.chars()
    |> Enum.reverse()
    |> flip_all(Map.delete(@flip, "`"))
  end

  defp eye_width(e), do: @eyes |> elem(e) |> hd() |> Text.length()

  # Every character of s, spaces too, from column x of row y, inside the frame.
  defp put(g, x, y, s) do
    s
    |> Text.chars()
    |> Enum.with_index(x)
    |> Enum.reduce(g, fn {ch, c}, g ->
      if c >= 0 and c < @cols, do: set(g, y, c, ch), else: g
    end)
  end

  defp set(g, r, c, ch), do: Map.put(g, r * @cols + c, ch)

  # The open run either side of the middle column, inside whatever bounds
  # it, given whether a column of the row is blank.
  defp span(blank?, lo, hi), do: {run(blank?, @cx, lo, -1), run(blank?, @cx, hi, 1)}

  defp run(blank?, a, stop, step) do
    if a != stop and blank?.(a + step), do: run(blank?, a + step, stop, step), else: a
  end

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)
    {top, eyes, beak} = Map.fetch!(state.poses, pose_at(u))
    lid = lid_at(u)

    # The frame starts from the base: here an overlay on it, so reads look
    # through to the base where nothing is written yet.
    g =
      for {{c, r}, i} <- Enum.with_index(@stars), into: %{} do
        w = u * (2 * :math.pi() / @loop) * (rem(i, 3) + 1) + i * 2
        {r * @cols + c, if(:math.sin(w) > 0.6, do: "+", else: ".")}
      end

    g =
      top
      |> Enum.with_index(1)
      |> Enum.reduce(g, fn {l, y}, g ->
        l
        |> Text.chars()
        |> Enum.with_index()
        |> Enum.reduce(g, fn
          {" ", _}, g -> g
          {ch, c}, g -> set(g, y, c, ch)
        end)
      end)

    g = Enum.reduce(4..8, g, fn r, g -> g |> set(r, 7, "|") |> set(r, 33, "|") end)

    g =
      g
      |> band(state.base, eyes)
      |> eyes(eyes, lid)
      |> set(7, beak, "V")

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.base, r)
        at = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(g, at + c, elem(row, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A band of speckled feathers round the facial disc, kept a cell off the
  # outline and clear of the eyes and the beak between them.
  defp band(g, base, [{x0, e0}, {x1, e1}]) do
    w0 = eye_width(e0)
    w1 = eye_width(e1)

    eye_at? = fn r, c ->
      r >= 4 and c >= x0 and c < x1 + w1 and (r > 4 or c < x0 + w0 or c >= x1)
    end

    Enum.reduce(3..8, g, fn r, g ->
      # Reads look through the overlay to the base.
      row = elem(base, r)
      {a, b} = span(&(Map.get(g, r * @cols + &1, elem(row, &1)) == " "), 6, 34)

      Enum.reduce((a + 1)..(b - 1)//1, g, fn c, g ->
        if rem(r + c, 2) == 1 or eye_at?.(r, c) do
          g
        else
          set(g, r, c, if(rem(Bitwise.bsr(c, 1) + r, 2) == 1, do: "'", else: "`"))
        end
      end)
    end)
  end

  defp eyes(g, eyes, lid) do
    Enum.reduce(eyes, g, fn {x, e}, g ->
      [r0, r1, r2, r3, r4] = elem(@eyes, e)
      n = Text.length(r0)
      m = n - 4
      r1 = if lid > 0.2, do: lidded(r1, n, m, "_"), else: r1
      r2 = if lid > 0.6, do: lidded(r2, n, m, "-"), else: r2

      [r0, r1, r2, r3, r4]
      |> Enum.with_index(4)
      |> Enum.reduce(g, fn {s, y}, g -> put(g, x, y, s) end)
    end)
  end

  defp lidded(s, n, m, ch),
    do: Text.slice(s, 0, 2) <> String.duplicate(ch, m) <> Text.slice(s, n - 2)
end
