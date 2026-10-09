defmodule Ascii.Pieces.Wind do
  @moduledoc """
  Gusts streaming along bending lines, curling at the head.

  Gusts drawn as streamlines of a slowly bending flow, shown only where a
  gust is passing. The streamlines are contours of one stream function, so
  they bend together and never cross; the long gusts curl over at their
  heads.

  The stream function is sampled 2,752 times a frame, each sample two
  three-dimensional noises of eight hashes. A frame's samples share a few
  dozen lattice points, so this port hashes each of those once a frame and
  reads them from a table; the noise is otherwise upstream's, step for step.

  Ported from `src/pieces/wind.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.Hash

  @meta %Ascii.Meta{
    name: "wind",
    category: :nature,
    note: "gusts streaming along bending lines, curling at the head",
    cols: 64,
    rows: 14,
    fps: 15
  }

  @cols 64
  @rows 14
  # Rows between streamlines.
  @gap 2
  # Top, middle, bottom third of a row; and a gust's trailing tip, by the
  # same thirds.
  @bar {"▔", "─", "▁"}
  @end_ {"'", "·", "."}
  # Gusts shorter than @min are dropped; only gusts @tip long trail a tip; a
  # gust @curl columns long may curl over at its head, and only the longest
  # @max_curls do; @flat cells before a curl are drawn level, so it joins
  # its line cleanly.
  @min 8
  @tip 14
  @curl 16
  @max_curls 3
  @flat 4

  @impl true
  def meta, do: @meta

  @compile {:inline, ease: 1, mix: 3}
  defp ease(t), do: t * t * (3 - 2 * t)
  defp mix(a, b, t), do: a + (b - a) * t

  # The hashes of one lattice layer: for each i from imin, the corners
  # {(i, j, k), (i, j + 1, k), (i, j, k + 1), (i, j + 1, k + 1)}.
  defp plane(imin, imax, j, k) do
    List.to_tuple(
      for i <- imin..(imax + 1) do
        {Hash.murmur(i, j, k), Hash.murmur(i, j + 1, k), Hash.murmur(i, j, k + 1),
         Hash.murmur(i, j + 1, k + 1)}
      end
    )
  end

  # Upstream's noise at lattice cell ii (counted from the plane's first i),
  # with the eased offsets into it.
  defp noise(plane, ii, u, v, w) do
    {a00, a10, a01, a11} = elem(plane, ii)
    {b00, b10, b01, b11} = elem(plane, ii + 1)
    mix(mix(mix(a00, b00, u), mix(a10, b10, u), v), mix(mix(a01, b01, u), mix(a11, b11, u), v), w)
  end

  # Where a coordinate falls in the lattice, and the eased offset.
  defp cell(x) do
    i = floor(x)
    {i, ease(x - i)}
  end

  @impl true
  def init(_options) do
    # Down each column a third of a row at a time, from the top: the depth,
    # and where it falls in each noise of the stream function.
    depths =
      for n <- 0..(@rows * 3) do
        y = if n == 0, do: 0, else: n / 3
        {j1, v1} = cell(y * 0.18)
        {j2, v2} = cell(y * 0.4)
        {y, j1, v1, j2, v2}
      end

    # The second noise does not drift across.
    across =
      for c <- 0..(@cols - 1) do
        cell((c + 0.5) * 0.07 + 4)
      end

    %{depths: depths, across: List.to_tuple(across)}
  end

  @impl true
  def frame(state, t, _env) do
    psi = stream(state, t)

    # Walk down each column a third of a row at a time; a streamline crosses
    # wherever the stream function passes a multiple of @gap.
    {g, lines} =
      Enum.reduce(0..(@cols - 1), {%{}, %{}}, fn c, acc ->
        [first | rest] = elem(psi, c)
        {acc, _} = Enum.reduce(Enum.with_index(rest), {acc, first}, &cross(&1, &2, c, t))
        acc
      end)

    lines = lines |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, l} -> {k, finish(l)} end)
    g = Enum.reduce(lines, g, fn {_, line}, g -> drop(g, line) end)
    g = curls(g, lines)

    out =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(g, {r, c}, " ")
      end

    {Enum.intersperse(out, ?\n), nil, state}
  end

  # The stream function, in rows: depth plus a slow bend that drifts right.
  # For each column, floor(psi / @gap) at each third of a row down it.
  defp stream(state, t) do
    {k1, w1} = cell(t * 0.02)
    {k2, w2} = cell(t * 0.04)
    drift = t * 0.05

    firsts = for c <- 0..(@cols - 1), do: cell((c + 0.5) * 0.04 - drift)
    {imin1, imax1} = firsts |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {imin2, imax2} = state.across |> Tuple.to_list() |> Enum.map(&elem(&1, 0)) |> Enum.min_max()

    planes1 = Map.new(0..3, &{&1, plane(imin1, imax1, &1, k1)})
    planes2 = Map.new(0..6, &{&1, plane(imin2, imax2, &1, k2)})

    firsts
    |> Enum.with_index()
    |> Enum.map(fn {{i1, u1}, c} ->
      {i2, u2} = elem(state.across, c)

      for {y, j1, v1, j2, v2} <- state.depths do
        n1 = noise(Map.fetch!(planes1, j1), i1 - imin1, u1, v1, w1)
        n2 = noise(Map.fetch!(planes2, j2), i2 - imin2, u2, v2, w2)
        floor((y + 5 * (n1 + 0.35 * n2)) / @gap)
      end
    end)
    |> List.to_tuple()
  end

  defp cross({now, j}, {{g, lines}, was}, c, t) do
    if now == was do
      {{g, lines}, now}
    else
      k = max(now, was)
      r = div(j, 3)
      line = Map.get_lazy(lines, k, fn -> gusts(k, t) end)
      line = if Map.has_key?(line.row, c), do: line, else: %{line | row: Map.put(line.row, c, r)}

      {g, line} =
        case elem(line.mask, c) do
          0 ->
            {g, line}

          on ->
            ch = elem(if(on == 1, do: @end_, else: @bar), rem(j, 3))
            {Map.put(g, {r, c}, ch), %{line | cells: [{c, r} | line.cells]}}
        end

      {{g, Map.put(lines, k, line)}, now}
    end
  end

  # Where gusts are passing along streamline k: 0 calm, 1 a long gust's
  # trailing tip, 2 inside it, and each gust's span. Gusts thin out over the
  # last 8 columns at either edge, and short ones are dropped as dust.
  defp gusts(k, t) do
    {kk, w} = cell(t * 0.05)
    {j, v} = cell(k * 1.7)
    xs = for c <- 0..(@cols - 1), do: cell(c * 0.09 - t * 0.5)
    {imin, imax} = xs |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    plane = plane(imin, imax, j, kk)

    on =
      for {{i, u}, c} <- Enum.with_index(xs) do
        noise(plane, i - imin, u, v, w) * Enum.min([1, (c + 1) / 8, (@cols - c) / 8]) > 0.5
      end

    spans =
      (on ++ [false])
      |> Enum.with_index()
      |> Enum.chunk_by(&elem(&1, 0))
      |> Enum.flat_map(fn
        [{true, from} | _] = run when length(run) >= @min -> [{from, from + length(run) - 1}]
        _ -> []
      end)

    mask =
      for {from, to} <- spans, c <- from..to, into: %{} do
        {c, if(c == from and to - from + 1 >= @tip, do: 1, else: 2)}
      end

    %{
      mask: List.to_tuple(for(c <- 0..(@cols - 1), do: Map.get(mask, c, 0))),
      spans: spans,
      row: %{},
      cells: []
    }
  end

  defp finish(line), do: %{line | cells: Enum.reverse(line.cells)}

  # A gust that shows five cells or fewer is seen edge on, or mostly out of
  # the frame: drop it.
  defp drop(g, %{spans: spans, cells: cells}) do
    {g, _} =
      Enum.reduce(spans, {g, cells}, fn {from, to}, {g, cells} ->
        cells = Enum.drop_while(cells, fn {c, _} -> c < from end)
        {shown, rest} = Enum.split_while(cells, fn {c, _} -> c <= to end)

        g =
          if length(shown) <= 5,
            do: Enum.reduce(shown, g, fn {c, r}, g -> Map.put(g, {r, c}, " ") end),
            else: g

        {g, rest}
      end)

    g
  end

  # The longest gusts curl over at their heads, up or down by turns.
  defp curls(g, lines) do
    heads =
      for {k, line} <- lines,
          {from, to} <- line.spans,
          to - from + 1 >= @curl and Map.has_key?(line.row, to),
          do: {to - from, k, to, line}

    {g, _} =
      heads
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.reduce({g, []}, fn {_, k, to, line}, acc -> curl(acc, k, to, line) end)

    g
  end

  defp curl({g, curls}, k, to, line) do
    r = Map.fetch!(line.row, to)
    d = if rem(k, 2) == 1, do: 1, else: -1

    cond do
      length(curls) >= @max_curls or to < @flat + 2 or r + d < 0 or r + d >= @rows ->
        {g, curls}

      not level?(g, line, r, to) or not room?(g, r, to, d) ->
        {g, curls}

      # Two curls near each other read as a knot, so they keep well apart.
      Enum.any?(curls, fn {cr, cc} -> abs(cr - r) < 5 and abs(cc - to) < 16 end) ->
        {g, curls}

      true ->
        g = Enum.reduce((to - @flat)..(to - 1), g, &Map.put(&2, {r, &1}, "─"))

        g =
          g
          |> Map.put({r, to}, if(d > 0, do: "╮", else: "╯"))
          |> Map.put({r + d, to}, if(d > 0, do: "╯", else: "╮"))
          |> Map.put({r + d, to - 1}, "─")
          |> Map.put({r + d, to - 2}, if(d > 0, do: "╰", else: "╭"))

        {g, curls ++ [{r, to}]}
    end
  end

  defp level?(g, line, r, to) do
    Enum.all?((to - @flat)..(to - 1), fn c ->
      Map.get(line.row, c) == r and Map.get(g, {r, c}, " ") in Tuple.to_list(@bar)
    end)
  end

  defp free?(g, r, c),
    do: r >= 0 and r < @rows and c >= 0 and c < @cols and Map.get(g, {r, c}, " ") == " "

  # The curl's own row and the next one past it must be clear around it.
  defp room?(g, r, to, d) do
    free?(g, r + d, to - 2) and free?(g, r, to + 1) and
      Enum.all?([r + d, r + 2 * d], fn rr ->
        Enum.all?((to - 5)..(to + 2), fn c ->
          rr < 0 or rr >= @rows or c < 0 or c >= @cols or Map.get(g, {rr, c}, " ") == " "
        end)
      end)
  end
end
