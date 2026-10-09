defmodule Ascii.Pieces.FractalTree do
  @moduledoc """
  A recursive branching tree swaying in the wind.

  A trunk that forks, and forks again, seven times over, each limb a little
  shorter than its parent, the outer twigs gathered into lobes of leaves lit
  from the upper left. Wind bends every limb, the tips most.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `seed` - the tree's shape: each limb's length and angle are drawn from
      it, so another seed grows another tree, and the same seed the same one.
      Default 4.

  The picture is always 60 by 24. At the default it closes a loop every 12
  seconds, which a player draws once and repeats (see `Ascii.loop/1`).

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `Ascii.Ink`),
  or on a page a CSS variable. On a light page, give it `paper: true`: its
  shading reads from the other end of its ramp, so dense characters still mean
  dark. It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "fractal tree: a recursive
  branching tree swaying in the wind". A player's or a component's `label`
  gives words of your own, as "a tree swaying in the wind".

  ## Example

  ```elixir
  draw = fn seed -> "fractal-tree" |> Ascii.new!(options: %{seed: seed}) |> Ascii.frame(0.0) |> elem(0) end
  draw.(4).text == draw.(9).text
  #=> false
  ```

  ```heex
  <Ascii.Phoenix.player socket={@socket} id="tree" piece="fractal-tree" options={%{seed: 9}} ink="#7cb342" />
  ```

  Ported from `src/pieces/fractal-tree.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}
  alias Ascii.Kit.Hash

  @meta %Ascii.Meta{
    name: "fractal tree",
    category: :nature,
    note: "a recursive branching tree swaying in the wind",
    cols: 60,
    rows: 24,
    fps: 15,
    options: %{seed: 4},
    loop: 12
  }

  @cols 60
  @rows 24
  @depth 7
  # Each limb this deep carries a lobe of leaves over its twigs.
  @lobe 6
  # Leaves in shadow to leaves in light.
  @leaf {" ", ".", ":", "o", "O"}
  # Seconds; every wind term repeats within it.
  @loop 12
  @tau :math.pi() * 2
  # No limb leans further than this from upright, in radians.
  @max_lean 1.1
  # The row the trunk stands on, and the row it first forks at.
  @ground @rows - 1
  @fork 15
  @x0 @cols / 2 - 0.5

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{seed: seed}) do
    # The limbs, parents before children: depth, turn from the parent, length
    # (in columns; a row is two). The first forks are the widest. mulberry32
    # takes the seed as given; its first step truncates it.
    {limbs, rand} = grow([], seed, -1, 1, 6)
    limbs = limbs |> Enum.reverse() |> List.to_tuple()

    # A lobe is the twigs above one limb: it sits over their ends.
    {lobes, _} =
      Enum.reduce(0..(tuple_size(limbs) - 1), {[], rand}, fn i, {lobes, rand} ->
        if elem(elem(limbs, i), 1) == @lobe do
          twigs = [i | twigs(limbs, i + 1)]
          {ph, rand} = Int32.mulberry32(rand)
          {bump, rand} = Int32.mulberry32(rand)
          {[{twigs, ph * @tau, 0.12 + bump * 0.1} | lobes], rand}
        else
          {lobes, rand}
        end
      end)

    %{limbs: limbs, lobes: Enum.reverse(lobes)}
  end

  defp grow(limbs, rand, parent, depth, len) do
    Enum.reduce([-1, 1], {limbs, rand}, fn side, {limbs, rand} ->
      {fan, rand} =
        case depth do
          1 -> {0.58, rand}
          2 -> {0.48, rand}
          _ -> rand |> Int32.mulberry32() |> then(fn {r, rand} -> {0.4 + r * 0.14, rand} end)
        end

      {r1, rand} = Int32.mulberry32(rand)
      spread = fan * side + (r1 - 0.5) * 0.12
      {r2, rand} = Int32.mulberry32(rand)
      i = length(limbs)
      limbs = [{parent, depth, spread, len * (0.92 + r2 * 0.16)} | limbs]
      if depth < @depth, do: grow(limbs, rand, i, depth + 1, len * 0.84), else: {limbs, rand}
    end)
  end

  defp twigs(limbs, j) do
    if j < tuple_size(limbs) and elem(elem(limbs, j), 1) > @lobe,
      do: [j | twigs(limbs, j + 1)],
      else: []
  end

  # The wind: a slow sway, a quicker shiver and a gust, all within @loop,
  # reaching each limb a moment after its parent.
  defp wind(u) do
    0.65 * :math.sin(@tau * u / 6) + 0.25 * :math.sin(@tau * u / 2.4 + 1) +
      0.2 * :math.pow(:math.sin(@tau * u / @loop), 3)
  end

  @impl true
  def frame(state, t, env) do
    # The trunk: two cells of heartwood between its edges, flaring into
    # roots at the foot.
    c = JSMath.round(@x0 - 1)

    ink =
      Enum.reduce(@fork..@ground, %{}, fn r, ink ->
        flare = max(0, r - @ground + 2)
        ink = Enum.reduce(-flare..(1 + flare), ink, &put(&2, c + &1, r, "#", 1))
        ink = put(ink, c - 1 - flare, r, if(flare != 0, do: "/", else: "|"), 1)
        put(ink, c + 2 + flare, r, if(flare != 0, do: "\\", else: "|"), 1)
      end)

    bends =
      for d <- 1..@depth, into: %{} do
        {d, (0.02 + 0.035 * d) * (0.25 + wind(t - d * 0.12))}
      end

    {ink, tips} = limbs(state.limbs, bends, ink)
    {shade, inner} = lobes(state, tips, t)

    # Leaves hide the twigs; the main limbs show where the leaves are dark.
    # At the rim of the crown light shows between the leaves, on any page;
    # inside it, on paper, the shaded side takes the dense glyphs.
    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          k = c + r * @cols
          {ch, d} = Map.get(ink, k, {" ", 0})
          ch = leaf(Map.get(shade, k, -1), d, Map.get(inner, k, 0), env.paper, ch)

          # The ground either side of the roots.
          if r == @ground and c >= 3 and c < @cols - 3 and ch == " ",
            do: if(c < 6 or c > @cols - 7, do: ".", else: "_"),
            else: ch
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp leaf(v, d, _inner, _paper, ch) when v < 0 or (d != 0 and d <= 3) or (d == 4 and v < 0.45),
    do: ch

  defp leaf(v, _d, inner, paper, _ch) do
    i = min(2, floor(v * 3))

    cond do
      inner < 0.22 -> elem(@leaf, if(v < 0.4, do: 1, else: 2))
      paper -> elem(@leaf, 4 - i)
      true -> elem(@leaf, 2 + i)
    end
  end

  # A cell keeps the shallowest limb drawn into it.
  defp put(ink, c, r, _ch, _d) when c < 0 or c >= @cols or r < 0 or r >= @rows, do: ink

  defp put(ink, c, r, ch, d) do
    k = c + r * @cols

    case ink do
      %{^k => {_, dk}} when dk != 0 and dk <= d -> ink
      _ -> Map.put(ink, k, {ch, d})
    end
  end

  # Each limb from its parent's tip (as the Float32Arrays hold it), turned
  # by its own turn and the wind; drawn unless it is a twig under a lobe.
  defp limbs(limbs, bends, ink) do
    Enum.reduce(0..(tuple_size(limbs) - 1), {ink, %{}}, fn i, {ink, tips} ->
      {parent, depth, turn, len} = elem(limbs, i)

      {x, y, a} =
        if parent < 0, do: {@x0 + 0.5, @fork + 0.5, 0}, else: Map.fetch!(tips, parent)

      # Limbs reach for the light: each turns a little back toward upright.
      a =
        max(
          -@max_lean,
          min(@max_lean, a * if(depth > 2, do: 0.85, else: 1) + turn + bends[depth])
        )

      x1 = x + :math.sin(a) * len
      y1 = y - :math.cos(a) * len / 2
      ink = if depth < @lobe + 1, do: stroke(ink, x, y, x1, y1, depth), else: ink
      {ink, Map.put(tips, i, {JSMath.fround(x1), JSMath.fround(y1), JSMath.fround(a)})}
    end)
  end

  # A limb, one cell a row where the line crosses the middle of the row, in
  # a glyph by its slant. A shallow limb steps with underscores between rows;
  # a thick one has a heavy core on its inner side.
  defp stroke(ink, x0, y0, x1, y1, depth) do
    # Columns a row, rightward going up.
    s = (x1 - x0) / (y0 - y1)

    ch =
      cond do
        abs(s) < 0.42 -> "|"
        s > 0 -> "/"
        true -> "\\"
      end

    r_top = JSMath.round(y1)
    r_bot = JSMath.round(y0) - 1

    {ink, _} =
      Enum.reduce(r_bot..r_top//-1, {ink, nil}, fn r, {ink, last} ->
        c = floor(x0 + s * (y0 - (r + 0.5)))
        ink = put(ink, c, r, ch, depth + 1)

        ink =
          if depth == 1,
            do: put(ink, c - JSMath.sign(if(s == 0, do: 1, else: s)), r, "#", depth + 1),
            else: ink

        ink =
          if last == nil,
            do: ink,
            else:
              Enum.reduce((min(c, last) + 1)..(max(c, last) - 1)//1, ink, fn b, ink ->
                put(ink, if(s > 0, do: b - 1, else: b + 1), r + 1, "_", depth + 1)
              end)

        {ink, c}
      end)

    ink
  end

  # The lobes, highest first, so each lower one stands in front of the
  # shaded underside of the one above it. The light falls on the crown as a
  # whole from the upper left, and on each lobe the same way.
  defp lobes(%{limbs: limbs, lobes: lobes}, tips, t) do
    ends = for {twigs, _, _} <- lobes, j <- twigs, do: Map.fetch!(tips, j)
    {x0, x1, y0, y1} = Enum.reduce(ends, {@cols, 0, @rows, 0}, &extend/2)

    crown =
      {(x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 + 3, (y1 - y0) / 2 + 1.5}

    lobes
    |> Enum.map(&lobe_shape(&1, limbs, tips))
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.reduce({%{}, %{}}, &lobe(&1, &2, crown, @tau * t / @loop))
  end

  defp extend({x, y, _}, {x0, x1, y0, y1}), do: {min(x0, x), max(x1, x), min(y0, y), max(y1, y)}

  # Over the twigs' ends and the fork they spring from.
  defp lobe_shape({[first | _] = twigs, ph, bump}, limbs, tips) do
    parent = elem(elem(limbs, first), 0)
    ends = Enum.map(twigs ++ [parent], &Map.fetch!(tips, &1))
    n = length(ends)
    {sx, sy} = Enum.reduce(ends, {0, 0}, fn {x, y, _}, {sx, sy} -> {sx + x, sy + y} end)
    cx = sx / n
    cy = sy / n

    {wx, wy} =
      Enum.reduce(ends, {0, 0}, fn {x, y, _}, {wx, wy} ->
        {max(wx, abs(x - cx)), max(wy, abs(y - cy))}
      end)

    {cx, cy - 0.4, 1.8 + wx * 0.9, 1.0 + wy * 0.9, ph, bump}
  end

  defp lobe({cx, cy, rx, ry, ph, bump}, {shade, inner}, {gx, gy, grx, gry}, turn) do
    for r <- floor(cy - ry - 1)..floor(cy + ry + 1)//1,
        c <- floor(cx - rx - 1)..floor(cx + rx + 1)//1,
        c >= 0 and c < @cols and r >= 0 and r < @rows,
        nx = (c + 0.5 - cx) / rx,
        ny = (r + 0.5 - cy) / ry,
        edge = 1 + bump * :math.sin(:math.atan2(ny, nx) * 3 + ph + turn),
        d2 = (nx * nx + ny * ny) / (edge * edge),
        d2 < 1,
        reduce: {shade, inner} do
      {shade, inner} ->
        gnx = (c + 0.5 - gx) / grx
        gny = (r + 0.5 - gy) / gry
        k = c + r * @cols

        v =
          0.36 - 0.12 * gnx - 0.16 * gny - 0.24 * nx - 0.4 * ny +
            0.16 * (Hash.short(c, r) - 0.5)

        {Map.put(shade, k, JSMath.fround(max(0, min(1, v)))),
         Map.put(inner, k, JSMath.fround(max(Map.get(inner, k, 0), 1 - d2)))}
    end
  end
end
