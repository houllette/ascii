defmodule AsciiArt.Pieces.Spinners do
  @moduledoc """
  Twelve loading spinners side by side, each with its name.

  Twelve classic loading spinners in a grid, each drawn in a three-row box
  with its name underneath. Pick some of them with `names`, and the frame
  shrinks to fit just those: one spinner is an 11-column widget for a
  terminal UI or a page.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it is laid
  out anew, at its new size, and the spinners carry on, being a function of
  play time.

    * `names` - the spinners to show, in that order: `line`, `dots`, `pipe`,
      `arc`, `bounce`, `clock`, `bar`, `loop`, `scan`, `wave`, `slide` and
      `orbit`. Names it does not know are left out, and if none is left it
      shows all twelve (upstream would draw nothing, which a frame cannot
      be). Default `[]`: all twelve.
    * `labels` - each spinner's name under it. With `names`, `false` leaves
      the names out and the frame two rows a line shorter. Default `true`.
    * `speed` - how fast they turn, upstream's pace times this, -60 to 60:
      0 holds them, and a negative speed turns them backwards. Default 1.

  The frame is 11 columns a spinner, six to a line, and 6 rows a line of
  them with names (4 without), and one more; all twelve fill 66 by 13.

  ## Colours

  It has no parts to colour one by one: in one ink, or a gradient, with
  `:ink` and `:gradient` (see `AsciiArt.Ink`). A gradient across several
  spinners gives each its own colour.

  ## Keys and clicks

  It takes none: it says something is loading, and
  `AsciiArt.handle_event/2` ignores every event. A Phoenix player given
  `interactive` and `notify` still tells your LiveView where it was
  clicked.

  ## Screen readers

  `AsciiArt.describe/1` gives the piece's name and note, "spinners: twelve
  loading spinners side by side, each with its name"; give a player a
  `label` of your own, as "saving", to say what is loading.

  ## Example

  ```elixir
  spinner = AsciiArt.new!("spinners", options: %{names: ["dots"]}, ink: "#58a6ff")
  {frame, _spinner} = AsciiArt.frame(spinner, 0.5)
  {frame.cols, frame.rows}
  #=> {11, 7}

  two = AsciiArt.new!("spinners", options: %{names: ["dots", "clock"], labels: false, speed: 2})
  {frame, _two} = AsciiArt.frame(two, 0.0)
  {frame.cols, frame.rows}
  #=> {22, 5}
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="saving" piece="spinners" options={%{names: ["dots"], labels: false}} label="saving" />
  ```

  Ported from `src/pieces/spinners.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Grid

  @meta %AsciiArt.Meta{
    name: "spinners",
    category: :ui,
    note: "twelve loading spinners side by side, each with its name",
    cols: 66,
    rows: 13,
    fps: 12,
    options: %{names: [], labels: true, speed: 1},
    bounds: %{speed: {-60, 60}}
  }

  # Each spinner's name and frames a step at 12 fps.
  @spinners [
    {"line", 2},
    {"dots", 2},
    {"pipe", 2},
    {"arc", 1},
    {"bounce", 1},
    {"clock", 3},
    {"bar", 1},
    {"loop", 1},
    {"scan", 1},
    {"wave", 1},
    {"slide", 1},
    {"orbit", 1}
  ]

  # Slots eleven columns wide, six to a row; a block is the art's three rows,
  # a blank row and the label.
  @slot 11

  @impl true
  def meta, do: @meta

  @impl true
  def size(options) do
    %{cols: cols, height: height} = layout(options)
    {cols, height}
  end

  @impl true
  def init(options) do
    %{chosen: chosen, per: per, block: block, cols: cols, height: height} = layout(options)
    %{labels: labels, speed: speed} = options

    %{
      chosen: chosen,
      per: per,
      block: block,
      cols: cols,
      height: height,
      labels: labels,
      speed: speed
    }
  end

  # The spinners shown, six to a row, and the frame they fill.
  defp layout(%{names: names, labels: labels}) do
    chosen = for n <- names, s = List.keyfind(@spinners, n, 0), do: s
    all? = chosen == []
    chosen = if all?, do: @spinners, else: chosen
    per = if all?, do: 6, else: min(6, length(chosen))
    block = if labels or all?, do: 5, else: 3

    {cols, height} =
      if all?,
        do: {@meta.cols, @meta.rows},
        else: {per * @slot, ceil(length(chosen) / per) * (block + 1) + 1}

    %{chosen: chosen, per: per, block: block, cols: cols, height: height}
  end

  # Every spinner's steps repeat within this many, so a step taken modulo it
  # draws the same, and a negative one (a negative speed) runs backwards.
  @steps 9240

  @impl true
  def frame(state, t, _env) do
    %{chosen: chosen, per: per, block: block, speed: speed} = state

    grid =
      chosen
      |> Enum.with_index()
      |> Enum.reduce(Grid.new(state.cols, state.height), fn {{name, frames}, n}, grid ->
        x0 = rem(n, per) * @slot
        y0 = 1 + div(n, per) * (block + 1)

        art =
          draw(name, Integer.mod(JSMath.floor(t * @meta.fps * speed / frames + 1.0e-3), @steps))

        top = y0 + Integer.floor_div(3 - length(art), 2)

        grid =
          art
          |> Enum.with_index(top)
          |> Enum.reduce(grid, fn {line, y}, g ->
            Grid.put_string(g, x0 + Integer.floor_div(@slot - String.length(line), 2), y, line)
          end)

        if state.labels,
          do:
            Grid.put_string(
              grid,
              x0 + Integer.floor_div(@slot - String.length(name), 2),
              y0 + 4,
              name
            ),
          else: grid
      end)

    {Grid.to_iodata(grid), nil, state}
  end

  # 0, 1, ... n - 1, ... 1, 0, ...
  defp ping(n, i) do
    m = rem(i, 2 * n - 2)
    if m < n, do: m, else: 2 * n - 2 - m
  end

  # A w-by-h picture with the given cells written, as rows.
  defp plot(w, h, cells) do
    grid = Enum.reduce(cells, Grid.new(w, h), fn {x, y, ch}, g -> Grid.put(g, x, y, ch) end)
    for y <- 0..(h - 1), do: Enum.map_join(0..(w - 1), &Grid.get(grid, &1, y))
  end

  # Quadrant blocks by which of upper left, upper right, lower left, lower
  # right are filled.
  @quad {" ", "▗", "▖", "▄", "▝", "▐", "▞", "▟", "▘", "▚", "▌", "▙", "▀", "▜", "▛", "█"}
  defp quad(ul, ur, ll, lr), do: elem(@quad, ul * 8 + ur * 4 + ll * 2 + lr)

  @lines {
    [{2, 0, "│"}, {2, 1, "│"}, {2, 2, "│"}],
    [{3, 0, "╱"}, {2, 1, "╱"}, {1, 2, "╱"}],
    [{0, 1, "─"}, {1, 1, "─"}, {2, 1, "─"}, {3, 1, "─"}, {4, 1, "─"}],
    [{1, 0, "╲"}, {2, 1, "╲"}, {3, 2, "╲"}]
  }

  @arms {{1, 1, 0, 1}, {1, 1, 0, 0}, {1, 1, 1, 0}, {1, 0, 1, 0}, {1, 0, 1, 1}, {0, 0, 1, 1},
         {0, 1, 1, 1}, {0, 1, 0, 1}}
  @hubs {"┼", "├", "┤", "│", "┴", "└", "┘", "╵", "┬", "┌", "┐", "╷", "─", "╶", "╴", " "}

  @ring [
    {0, 0, "╭"},
    {1, 0, "─"},
    {2, 0, "─"},
    {3, 0, "─"},
    {4, 0, "╮"},
    {4, 1, "│"},
    {4, 2, "╯"},
    {3, 2, "─"},
    {2, 2, "─"},
    {1, 2, "─"},
    {0, 2, "╰"},
    {0, 1, "│"}
  ]

  @hands {
    [{3, 0, "┬"}, {3, 1, "╵"}],
    [{3, 1, "╶"}, {4, 1, "─"}, {5, 1, "─"}, {6, 1, "┤"}],
    [{3, 1, "╷"}, {3, 2, "┴"}],
    [{0, 1, "├"}, {1, 1, "─"}, {2, 1, "─"}, {3, 1, "╴"}]
  }

  @bars {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
  @loop {{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}, {5, 1}, {4, 1}, {3, 1}, {2, 1}, {1, 1},
         {0, 1}}
  @orbit [{1, 0}, {2, 0}, {3, 0}, {4, 1}, {3, 2}, {2, 2}, {1, 2}, {0, 1}]

  # Each spinner's picture at step i, as one to three rows.
  defp draw("line", i), do: plot(5, 3, elem(@lines, rem(i, 4)))

  defp draw("dots", i) do
    # Three dots hopping in turn, half a row at a time.
    cells =
      for d <- 0..2 do
        h = Enum.at([0, 1, 2, 1, 0, 0, 0], rem(i - d * 2 + 70, 7))
        {d * 2, if(h == 2, do: 0, else: 1), if(h == 1, do: "▀", else: "▄")}
      end

    plot(5, 2, cells)
  end

  defp draw("pipe", i) do
    # A junction turning, its arms reaching out from the middle.
    {u, l, r, d} = elem(@arms, rem(i, 8))
    hub = elem(@hubs, (1 - u) * 8 + (1 - d) * 4 + (1 - r) * 2 + (1 - l))

    plot(
      5,
      3,
      [{2, 1, hub}] ++
        if(u == 1, do: [{2, 0, "│"}], else: []) ++
        if(d == 1, do: [{2, 2, "│"}], else: []) ++
        if(l == 1, do: [{0, 1, "─"}, {1, 1, "─"}], else: []) ++
        if(r == 1, do: [{3, 1, "─"}, {4, 1, "─"}], else: [])
    )
  end

  defp draw("arc", i) do
    # An arc chasing round a rounded box, stretching and shrinking as it goes.
    n = 3 + JSMath.round(ping(8, i) * 4 / 7)
    plot(5, 3, for(k <- 0..(n - 1), do: Enum.at(@ring, rem(i + 12 - k, 12))))
  end

  defp draw("bounce", i) do
    p = ping(6, i)
    ["[" <> String.duplicate(" ", p) <> "o" <> String.duplicate(" ", 5 - p) <> "]"]
  end

  defp draw("clock", i) do
    # One hand from the middle to the rim, a quarter turn a step.
    face = [{0, 0, "╭"}, {6, 0, "╮"}, {0, 1, "│"}, {6, 1, "│"}, {0, 2, "╰"}, {6, 2, "╯"}]
    rims = for x <- 1..5, y <- [0, 2], do: {x, y, "─"}
    plot(7, 3, face ++ rims ++ elem(@hands, rem(i, 4)))
  end

  defp draw("bar", i) do
    # A bar three rows tall filling and draining in eighths.
    level = JSMath.round(ping(12, i + 2) * 24 / 11)
    for k <- [2, 1, 0], do: String.duplicate(elem(@bars, max(0, min(8, level - 8 * k))), 3)
  end

  defp draw("loop", i) do
    # A snake of four quadrants running round a three-cell strip.
    on = MapSet.new(0..3, &elem(@loop, rem(i + &1, 12)))
    at = fn x, y -> if MapSet.member?(on, {x, y}), do: 1, else: 0 end
    [Enum.map_join([0, 2, 4], &quad(at.(&1, 0), at.(&1 + 1, 0), at.(&1, 1), at.(&1 + 1, 1)))]
  end

  defp draw("scan", i) do
    head = ping(7, i)
    dir = if rem(i, 12) < 6, do: -1, else: 1

    [
      Enum.map_join(0..6, fn x ->
        cond do
          x == head -> "█"
          x == head + dir -> "▓"
          x == head + 2 * dir -> "░"
          true -> "·"
        end
      end)
    ]
  end

  defp draw("wave", i) do
    [
      Enum.map_join(
        0..6,
        &elem(@bars, 1 + JSMath.round(3.5 + 3.5 * :math.sin((&1 - i) * :math.pi() / 4)))
      )
    ]
  end

  defp draw("slide", i) do
    from = rem(i, 10) - 2
    ["[" <> Enum.map_join(0..7, &if(&1 - from >= 0 and &1 - from < 3, do: "=", else: " ")) <> "]"]
  end

  defp draw("orbit", i) do
    cells =
      for {{x, y}, k} <- Enum.with_index(@orbit) do
        {x, y,
         cond do
           k == rem(i, 8) -> "o"
           k == rem(i + 7, 8) -> "°"
           true -> "·"
         end}
      end

    plot(5, 3, cells)
  end
end
