defmodule AsciiArt.Pieces.Whale do
  @moduledoc """
  A whale blows, arches its back and dives, fluke last.

  A whale swimming left comes up, blows, rolls its back over and dives,
  lifting its tail fluke clear of the water before it slips under.

  Ported from `src/pieces/whale.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "whale",
    category: :creatures,
    note: "a whale blows, arches its back and dives, fluke last",
    cols: 72,
    rows: 18,
    fps: 15
  }

  @cols 72
  @rows 18

  # Seen from the side, heading left. Outlines only, with # for bare body:
  # the rest of the body under each outline is shaded in below.
  @surf [
    "                 _.-''-._",
    "          __..--'        `--.....______",
    "     _.--'                             ``--.._/|",
    "   .'       #o#                              `-.._",
    "  (____..--''                                     `-.._"
  ]
  @arch [
    "                __..--.._/|",
    "           _.-''           `-._",
    "        .-'                    `-._",
    "      .'                           `-._",
    "     /                                 `-._",
    "    /                                      `-._"
  ]
  @fluke [
    " ._                          _.",
    "  \\`-.._                _..-'/",
    "   `.   ``--.._    _.--''   .'",
    "     `-._      `\\/'      _.-'",
    "         ``--.._||_..--''",
    "                ||",
    "                ||",
    "                ||"
  ]
  # Each row's shade, top down: a darker back over a paler flank.
  @shade " :::.."

  # The row of the water line.
  @sea 13
  # Seconds.
  @loop 10
  # The first frame: the blow at its height.
  @t0 1.5
  # Columns a second.
  @swim 2.6
  # The snout's column as the whale first breaks the water.
  @x0 13
  # The blow starts.
  @blow 0.7
  # Columns a second the blow drifts downwind.
  @wind 1.5
  # When each shape comes up, is fully up, starts down and is under, in seconds.
  @up_surf {0, 1, 3, 3.8}
  @up_arch {3.1, 3.8, 4.6, 5.2}
  @up_fluke {5, 5.9, 7.5, 8.5}
  @dive 5.2
  # Water streams off the fluke's trailing edge at these columns, from the
  # lowest mark on its wings.
  @drip_cols [3, 6, 10, 13, 19, 22, 26, 29]
  @spray {" ", ".", "'", ":", ";"}

  @impl true
  def meta, do: @meta

  # A fixed number in [0, 1) for each i and salt. Only ^, >>> and Math.imul,
  # which agree modulo 2^32 whatever the signs, so it runs unsigned.
  defp hash(i, s) do
    h =
      bxor(
        Int32.umul(bxor(Int32.u32(i), 0x2C1B3C6D), 0x297A2D39),
        Int32.umul(Int32.u32(s + 7), 0x9E3779B1)
      )

    h = Int32.umul(bxor(h, h >>> 15), 0x85EBCA77)
    bxor(h, h >>> 13) / 4_294_967_296
  end

  defp ease(u) when u <= 0, do: 0
  defp ease(u) when u >= 1, do: 1
  defp ease(u), do: u * u * (3 - 2 * u)

  # How far a shape is sunk, in its own heights: 1 under, 0 fully up.
  defp depth(u, {up, _, _, under}) when u < up or u > under, do: 1
  defp depth(u, {up, top, _, _}) when u < top, do: 1 - ease((u - up) / (top - up))
  defp depth(u, {_, _, down, _}) when u < down, do: 0
  defp depth(u, {_, _, down, under}), do: ease((u - down) / (under - down))

  @impl true
  def init(_options) do
    # The blowhole, in columns from the snout; the arch keeps the back's fin
    # in place; the fluke comes up behind the fin.
    hole = index(hd(@surf), "''") + 1
    arch_fin = index(hd(@arch), "|")
    fin = index(Enum.at(@surf, 2), "|") - arch_fin
    fluke_x = @x0 - @swim * @dive - 2 + fin + arch_fin + 4

    drips =
      for {k, j} <- Enum.with_index(@drip_cols) do
        row =
          Enum.find(4..1//-1, 0, fn row ->
            @fluke |> Enum.at(row) |> Text.chars() |> Enum.at(k, " ") != " "
          end)

        {k, row, hash(j, 9)}
      end

    %{
      surf: solidify(@surf, @shade),
      arch: solidify(@arch, @shade),
      fluke: solidify(@fluke, ""),
      arch_lead: for(l <- @arch, do: l |> Text.chars() |> Enum.find_index(&(&1 != " "))),
      hole: hole,
      fin: fin,
      fluke_x: fluke_x,
      from: @x0 - @swim * @blow - 2 + hole,
      drips: drips,
      splash: for(j <- 0..5, do: {hash(j, 3), hash(j, 4)}),
      surface: for(c <- 0..(@cols - 1), do: {c, c * 0.61, c * 0.27, c * 0.45, c * 0.06})
    }
  end

  defp index(s, sub) do
    {at, _} = :binary.match(s, sub)
    at
  end

  # Each shape as rows of cells: the outline as drawn, the body under it
  # shaded, and nothing where the shape is open. Here a shape is its height
  # and its marks, {row, column, char}.
  defp solidify(art, shade) do
    w = art |> Enum.map(&Text.length/1) |> Enum.max()
    h = length(art)
    shade = Text.chars(shade)

    g =
      art
      |> Enum.with_index()
      |> Map.new(fn {l, r} ->
        {r, l |> Text.pad_end(w) |> Text.chars() |> Enum.map(&if(&1 == " ", do: nil, else: &1))}
      end)

    g =
      if shade == [] do
        g
      else
        Enum.reduce(0..(w - 1), g, fn k, g ->
          case Enum.find(0..(h - 1), &(Enum.at(g[&1], k) != nil)) do
            nil -> g
            top -> fill(g, k, top + 1, h, shade)
          end
        end)
      end

    marks =
      for r <- 0..(h - 1), {ch, k} <- Enum.with_index(g[r]), ch != nil do
        {r, k, if(ch == "#", do: " ", else: ch)}
      end

    {h, marks}
  end

  defp fill(g, k, from, h, shade) do
    Enum.reduce(from..(h - 1)//1, g, fn r, g ->
      Map.update!(g, r, fn row ->
        List.update_at(row, k, &(&1 || Enum.at(shade, r + length(shade) - h)))
      end)
    end)
  end

  defp put(g, r, c, ch) when r >= 0 and r < @rows and c >= 0 and c < @cols,
    do: Map.put(g, r * @cols + c, ch)

  defp put(g, _r, _c, _ch), do: g

  defp open?(g, r, c),
    do: r >= 0 and r < @sea and c >= 0 and c < @cols and Map.get(g, r * @cols + c, " ") == " "

  # Draws a shape standing on the water, sunk by `sink` of its height. Only
  # what is above the water shows. Returns the row of its top.
  defp stamp(g, {h, marks}, left, sink) do
    drop = JSMath.round(sink * h)
    x = JSMath.round(left)

    g =
      Enum.reduce(marks, g, fn {i, k, ch}, g ->
        r = @sea - h + i + drop
        if r < @sea, do: put(g, r, x + k, ch), else: g
      end)

    {g, @sea - h + drop}
  end

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t + @t0, @loop) + @loop, @loop)

    g = surface(state.surface, t)

    # The snout.
    hx = @x0 - @swim * min(u, @dive)
    {g, top} = stamp(g, state.surf, hx - 2, depth(u, @up_surf))
    arch = depth(u, @up_arch)
    {g, _} = stamp(g, state.arch, hx - 2 + state.fin, arch)

    g = if arch < 0.7, do: splash(g, state, u, hx, arch), else: g

    g =
      if u > @blow and u < @blow + 3,
        do: blow(g, top, JSMath.round(hx - 2 + state.hole), state.from, u - @blow),
        else: g

    # The fluke rises, streams water from its edge, and slides straight down.
    sink = depth(u, @up_fluke)
    fx = JSMath.round(state.fluke_x - 16)
    {g, _} = stamp(g, state.fluke, fx, sink)

    g =
      if sink < 1 and u > elem(@up_fluke, 1) - 0.2,
        do: drips(g, state.drips, u, fx, sink),
        else: g

    g = smooth_water(g, u, state.fluke_x)

    lines =
      for r <- 0..(@rows - 1) do
        base = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(g, base + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A calm surface with the odd crest, and faint swells beneath it.
  defp surface(cols, t) do
    t14 = t * 1.4
    t08 = t * 0.8

    Enum.reduce(cols, %{}, fn {c, c61, c27, c45, c06}, g ->
      h = :math.sin(c61 - t14) + 0.7 * :math.sin(c27 + t08)

      g
      |> Map.put(@sea * @cols + c, if(h > 1.45, do: "-", else: "~"))
      |> swell(@sea + 2, 0.6, c, c45, c06, t)
      |> swell(@sea + 4, -0.4, c, c45, c06, t)
    end)
  end

  defp swell(g, r, k, c, c45, c06, t) do
    v = :math.sin(c45 + t * k * 2 + r) * :math.sin(c06 - t * k * 0.3 + r)
    if v > 0.6, do: Map.put(g, r * @cols + c, "~"), else: g
  end

  # White water thrown off ahead of the head as it goes under.
  defp splash(g, state, u, hx, arch) do
    # The lowest row still showing.
    low = length(@arch) - 1 - JSMath.round(arch * length(@arch))
    lip = JSMath.round(hx - 2 + state.fin) + Enum.at(state.arch_lead, low)

    Enum.reduce(state.splash, g, fn {h3, a}, g ->
      p = JSMath.mod(u * 1.4 + h3, 1)
      r = JSMath.round(@sea - 1 - (0.6 + 1.6 * a) * :math.sin(:math.pi() * p))
      c = JSMath.round(lip - 1 - p * (1 + 2 * a))
      if open?(g, r, c), do: Map.put(g, r * @cols + c, if(p < 0.5, do: "'", else: ".")), else: g
    end)
  end

  # The blow: a column from the blowhole that opens into a bushy head, then
  # hangs, thins and drifts off downwind. It starts at row `br`, column
  # `bc`; `from` is where the blowhole was when the blow began.
  defp blow(g, br, bc, from, s) do
    # Rows the column has climbed; the column lets go from the bottom.
    top = 6.6 * :math.sqrt(min(1, s / 0.5))
    cut = if s < 0.8, do: 0, else: (s - 0.8) * 7
    # The head: wider as it opens, settling and thinning once the jet stops.
    hw = 1 + 3.6 * min(1, s / 0.8) + 2.4 * max(0, s - 0.8)
    hh = 1 + 0.6 * min(1, s / 0.8) + 0.5 * max(0, s - 0.8)
    hy0 = top - 0.6 - 0.5 * max(0, s - 1)
    amp = min(1, s / 0.2) * if(s < 1, do: 1, else: :math.exp(-(s - 1) / 1.2))
    drift = @wind * s
    head = {cut, top, hw, hh, hy0, amp}

    Enum.reduce((br - 1)..max(0, br - 9)//-1, g, fn r, g ->
      # Rows above the blowhole.
      y = br - r
      # The column leans back to where the whale was when the spray left it.
      lean = min(1, y / max(1, top))
      mid = bc + (from - bc) * lean + drift * lean * lean
      spray_row(g, r, y, JSMath.floor(mid - 12), mid, head)
    end)
  end

  defp spray_row(g, r, y, c, mid, head) when c <= mid + 12 do
    g = if open?(g, r, c), do: spray(g, r, y, c, mid, head), else: g
    spray_row(g, r, y, c + 1, mid, head)
  end

  defp spray_row(g, _r, _y, _c, _mid, _head), do: g

  defp spray(g, r, y, c, mid, {cut, top, hw, hh, hy0, amp}) do
    dx = c - mid
    dy = (y - hy0) / hh

    d =
      if y > cut and y <= top do
        q = dx / (0.3 + 0.17 * y)
        :math.exp(-(q * q))
      else
        0
      end

    q = dx / hw
    d = max(d, amp * :math.exp(-(q * q) - dy * dy))
    d = d * (0.92 + 0.16 * hash(c * 31 + r, 5))
    i = min(tuple_size(@spray) - 1, JSMath.floor(d * tuple_size(@spray)))
    if i > 0, do: Map.put(g, r * @cols + c, elem(@spray, i)), else: g
  end

  defp drips(g, drips, u, fx, sink) do
    ft = @sea - length(@fluke) + JSMath.round(sink * length(@fluke))

    for {dx, row, h9} <- drips, lag <- [0, 0.5], reduce: g do
      g ->
        p = JSMath.mod(u * 1.6 + h9 + lag, 1)
        r = JSMath.floor(ft + row + 1 + p * p * (@sea - ft - row - 1))
        c = fx + dx

        if open?(g, r, c),
          do: Map.put(g, r * @cols + c, if(p < 0.25, do: "'", else: ".")),
          else: g
    end
  end

  # Where the fluke went down, a patch of smooth water spreads and fades.
  defp smooth_water(g, u, fluke_x) do
    gone = elem(@up_fluke, 3) - 0.2

    if u > gone and u < gone + 1.2 do
      w = JSMath.round(4 + 5 * (u - gone))
      fade = (u - gone) / 1.2
      salt = JSMath.floor(u * 4)
      at = JSMath.round(fluke_x)

      Enum.reduce(-w..w//1, g, fn c, g ->
        if hash(c + 40, salt) > fade, do: put(g, @sea, at + c, "_"), else: g
      end)
    else
      g
    end
  end
end
