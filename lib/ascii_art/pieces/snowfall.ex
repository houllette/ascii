defmodule AsciiArt.Pieces.Snowfall do
  @moduledoc """
  Snow swaying down, building drifts on the ground and a fence.

  Snow drifting down in three depths on a light wind, swaying as it falls.
  Flakes settle where they land, building a drift in the fence's lee, a
  ridge along each rail and a cap on every post.

  Ported from `src/pieces/snowfall.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "snowfall",
    category: :nature,
    note: "snow swaying down, building drifts on the ground and a fence",
    cols: 64,
    rows: 22,
    fps: 20
  }

  @cols 64
  @rows 22
  @eighths {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
  # On paper the drift's surface is a line, by where it crosses a cell.
  @line {"▔", "─", "▁"}
  # The fence posts' columns, the posts' top row, the rails' rows, and a bare
  # rail's thickness in eighths of a row.
  @posts [9, 20, 31, 42]
  @top 10
  @rails [11, 14]
  @rail 2
  # Each depth: flakes, fall speed and drift in cells a second, sway, glyph.
  @layers {
    %{n: 44, v: 1.1, wind: 0.6, sway: 0.5, glyph: "."},
    %{n: 30, v: 1.8, wind: 1.1, sway: 1, glyph: "+"},
    %{n: 13, v: 2.8, wind: 1.8, sway: 1.6, glyph: "*"}
  }

  @impl true
  def meta, do: @meta

  defp smooth(a, b, x) do
    u = min(1, max(0, (x - a) / (b - a)))
    u * u * (3 - 2 * u)
  end

  @impl true
  def init(_options) do
    rand = Int32.to_int32(7)

    # The ground's snow in rows at each column: rolling, swept into a long
    # drift in the fence's lee that ends in a steep face.
    ground =
      for c <- 0..(@cols - 1) do
        lee = 3.6 * smooth(36, 55, c) * (1 - smooth(55, 59, c))
        1 + 0.55 * :math.sin(c * 0.19 + 1.3) + 0.3 * :math.sin(c * 0.47 + 0.4) + lee
      end

    wind =
      for c <- 0..(@cols - 1) do
        q = (c - 52) / 7
        0.7 + 1.6 * :math.exp(-(q * q))
      end

    {rails, rand} =
      @rails
      |> Enum.with_index()
      |> Enum.map_reduce(rand, fn {_, k}, rand ->
        {row, rand} =
          Enum.map_reduce(0..(@cols - 1), rand, fn c, rand ->
            {r, rand} = Int32.mulberry32(rand)
            {2 + 0.7 * :math.sin(c * 0.45 + k * 2) + 0.4 * r, rand}
          end)

        {List.to_tuple(row), rand}
      end)

    {flakes, rand} =
      for li <- 0..2, _ <- 1..elem(@layers, li).n, reduce: {[], rand} do
        {flakes, rand} ->
          {f, rand} = new_flake(li, false, rand)
          {[f | flakes], rand}
      end

    sim = %{
      flakes: Enum.reverse(flakes),
      rand: rand,
      ground: List.to_tuple(ground),
      wind: List.to_tuple(wind),
      extra: List.to_tuple(List.duplicate(0.3, @cols)),
      rails: List.to_tuple(rails),
      caps: {7, 7, 7, 7}
    }

    # Twenty seconds of snow before the first frame.
    sim = Enum.reduce(0..399, sim, fn i, sim -> step(sim, 0.05, i * 0.05) end)
    Map.put(sim, :last, 0)
  end

  defp new_flake(li, top, rand) do
    {x, rand} = Int32.mulberry32(rand)
    {y, rand} = Int32.mulberry32(rand)
    {ph, rand} = Int32.mulberry32(rand)
    {w, rand} = Int32.mulberry32(rand)
    y = if top, do: -y * 2, else: y * @rows
    {{li, x * @cols, y, ph * 6.283, 0.8 + w * 0.45}, rand}
  end

  defp step(sim, dt, t) do
    {flakes, sim} = Enum.map_reduce(sim.flakes, sim, &fall(&1, &2, dt, t))
    extra = sim.extra

    # Fresh snow evens out between neighbours and packs down slowly.
    extra =
      for c <- 0..(@cols - 1) do
        e = elem(extra, c)
        left = if c > 0, do: elem(extra, c - 1), else: e
        right = if c < @cols - 1, do: elem(extra, c + 1), else: e
        (e + 1.5 * dt * (left + right - 2 * e)) * (1 - 0.02 * dt)
      end

    rails =
      sim.rails
      |> Tuple.to_list()
      |> Enum.map(fn row ->
        row |> Tuple.to_list() |> Enum.map(&(&1 - &1 * 0.004 * dt)) |> List.to_tuple()
      end)

    caps = sim.caps |> Tuple.to_list() |> Enum.map(&(&1 - &1 * 0.01 * dt))

    %{
      sim
      | flakes: flakes,
        extra: List.to_tuple(extra),
        rails: List.to_tuple(rails),
        caps: List.to_tuple(caps)
    }
  end

  defp fall({li, x, y, ph, w}, sim, dt, t) do
    l = elem(@layers, li)
    y0 = y
    y = y + l.v * w * dt

    x =
      JSMath.mod(
        JSMath.mod(x + (l.wind + l.sway * :math.cos(t * w * 1.3 + ph)) * dt, @cols) + @cols,
        @cols
      )

    c = floor(x)
    fence(li, {li, x, y, ph, w}, y0, c, sim)
  end

  # Flakes at the fence's depth may come to rest on a rail or a post top.
  defp fence(1, f, y0, c, sim) do
    y = elem(f, 2)
    k = Enum.find_index(@rails, &(y0 < &1 + 0.5 and y >= &1 + 0.5))

    {rest, sim} =
      if k != nil and c > hd(@posts) and c < List.last(@posts) and c not in @posts do
        {r, rand} = Int32.mulberry32(sim.rand)
        {r < 0.7, %{sim | rand: rand}}
      else
        {false, sim}
      end

    p = Enum.find_index(@posts, &(&1 == c))

    cond do
      rest ->
        row =
          Enum.reduce([{-1, 0.3}, {0, 0.6}, {1, 0.3}], elem(sim.rails, k), fn {d, a}, row ->
            put_elem(row, c + d, min(5, elem(row, c + d) + a))
          end)

        respawn(1, %{sim | rails: put_elem(sim.rails, k, row)})

      p != nil and y0 < @top and y >= @top ->
        respawn(1, %{sim | caps: put_elem(sim.caps, p, min(13, elem(sim.caps, p) + 1))})

      true ->
        settle(f, c, sim)
    end
  end

  defp fence(_li, f, _y0, c, sim), do: settle(f, c, sim)

  # The two nearer depths settle where they land, more where the wind drops
  # them.
  defp settle({li, _, y, _, _} = f, c, sim) do
    cond do
      y < @rows - elem(sim.ground, c) - elem(sim.extra, c) ->
        {f, sim}

      li > 0 ->
        extra = put_elem(sim.extra, c, elem(sim.extra, c) + 0.3 * elem(sim.wind, c))
        respawn(li, %{sim | extra: extra})

      true ->
        respawn(li, sim)
    end
  end

  defp respawn(li, sim) do
    {f, rand} = new_flake(li, true, sim.rand)
    {f, %{sim | rand: rand}}
  end

  @impl true
  def frame(sim, time, env) do
    dt = min(0.1, max(0, time - sim.last))
    sim = run(%{sim | last: time}, dt, 20 + time)

    g = draw(%{}, sim.flakes, 0)

    # The fence: posts, rails thickened by the snow lying on them, a cap on
    # each post.
    g =
      for {r, k} <- Enum.with_index(@rails),
          c <- (hd(@posts) + 1)..(List.last(@posts) - 1),
          reduce: g do
        g -> Map.put(g, {r, c}, elem(@eighths, @rail + floor(elem(elem(sim.rails, k), c))))
      end

    g = @posts |> Enum.with_index() |> Enum.reduce(g, &post(&1, &2, sim.caps))
    g = drift(g, sim, env.paper)
    g = g |> draw(sim.flakes, 1) |> draw(sim.flakes, 2)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(g, {r, c}, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, sim}
  end

  defp run(sim, dt, t) when dt > 1.0e-9, do: run(step(sim, min(dt, 0.05), t), dt - 0.05, t)
  defp run(sim, _dt, _t), do: sim

  # A flake shows only in open air, in front of any farther flake.
  defp draw(g, flakes, li) do
    glyph = elem(@layers, li).glyph

    for {^li, x, y, _, _} <- flakes,
        r = floor(y),
        c = floor(x),
        r >= 0 and r < @rows,
        reduce: g do
      g ->
        if farther?(Map.get(g, {r, c}, " "), li), do: Map.put(g, {r, c}, glyph), else: g
    end
  end

  defp farther?(" ", _li), do: true
  defp farther?(".", li), do: li > 0
  defp farther?("+", li), do: li > 1
  defp farther?(_, _li), do: false

  defp post({c, p}, g, caps) do
    g = Enum.reduce(@top..(@rows - 1), g, &Map.put(&2, {&1, c}, "┃"))
    n = floor(elem(caps, p))
    g = Map.put(g, {@top - 1, c}, elem(@eighths, min(8, 1 + div(n, 2))))

    if n > 8,
      do:
        g
        |> Map.put({@top - 1, c - 1}, elem(@eighths, n - 8))
        |> Map.put({@top - 1, c + 1}, elem(@eighths, n - 8)),
      else: g
  end

  # The drift: on a dark ground, solid under an eighth-block surface; on
  # paper, a line over a light fill, with an edge down any step of two rows.
  defp drift(g, sim, paper) do
    top =
      List.to_tuple(for c <- 0..(@cols - 1), do: @rows - elem(sim.ground, c) - elem(sim.extra, c))

    g =
      for c <- 0..(@cols - 1), reduce: g do
        g ->
          s = elem(top, c)
          r = floor(s)
          f = s - r

          g =
            Enum.reduce(
              (r + 1)..(@rows - 1)//1,
              g,
              &Map.put(&2, {&1, c}, if(paper, do: "░", else: "█"))
            )

          ch =
            if paper,
              do: elem(@line, min(2, floor(f * 3))),
              else: elem(@eighths, max(1, JSMath.round((1 - f) * 8)))

          Map.put(g, {r, c}, ch)
      end

    if paper do
      for c <- 0..(@cols - 2), reduce: g do
        g ->
          a = floor(elem(top, c))
          b = floor(elem(top, c + 1))
          g = Enum.reduce((a + 1)..(b - 1)//1, g, &Map.put(&2, {&1, c + 1}, "▏"))
          Enum.reduce((b + 1)..(a - 1)//1, g, &Map.put(&2, {&1, c}, "▕"))
      end
    else
      g
    end
  end
end
