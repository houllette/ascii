# ExRatatui

[ExRatatui](https://hexdocs.pm/ex_ratatui) brings the Rust
[ratatui](https://ratatui.rs) terminal UI library to Elixir: widgets, layout,
key and mouse events, and supervised TUI apps that run in a local terminal,
over SSH or across distributed Erlang. `AsciiArt.ExRatatui` makes frames into
ratatui widgets, so the components (a file tree, meters, gauges, a boot log)
sit in your terminal UI beside ratatui's own, and `AsciiArt.ExRatatui.Viewer`
is a ready-made app that plays pieces full screen. ExRatatui is an optional dependency of this
library: add it to your project to have both. Written against ExRatatui 0.17.

```elixir
# needs: mix.exs
{:ascii_art, "~> 0.2"},
{:ex_ratatui, "~> 0.17"}
```

## The viewer

In a terminal:

```sh
mix run -e 'AsciiArt.ExRatatui.Viewer.run(piece: "donut")'
```

Space pauses, ← and → step through the pieces, q quits. It takes the pieces
to step through, options for the first, and how to draw colour:

```elixir
# needs: a real terminal
AsciiArt.ExRatatui.Viewer.run(pieces: ~w(donut elixir matrix-rain), mode: :ansi256)
```

With `interactive: true`, keys go to a piece that can be used first (a file
tree's arrows, a form's typing), and those it has no use for to the viewer:

```elixir
# needs: a real terminal
AsciiArt.ExRatatui.Viewer.run(piece: "file-tree", options: %{walk: false}, interactive: true)
```

Coloured pieces want a terminal with 24-bit colour, which most modern ones
have; `mode: :ansi256` takes the nearest of xterm's 256 colours instead.
Scenes are 200 columns wide: in a smaller window the viewer shows their
middle.

## Frames as widgets

A frame is a widget, so `[{frame, rect}]` in `render/2` draws it from the
top left of `rect`. `AsciiArt.ExRatatui.place/3` gives it a rect of its own
size, centred in an area, in a titled box if you like:

```elixir
alias ExRatatui.Layout.Rect

{:ok, frame} = AsciiArt.still("elixir")
area = %Rect{x: 0, y: 0, width: 80, height: 40}
{paragraph, rect} = AsciiArt.ExRatatui.place(frame, area, title: "elixir")
rect
#=> %ExRatatui.Layout.Rect{x: 20, y: 5, width: 40, height: 30}
```

Too big for its area, a frame fills it and shows its middle. For text of
your own composing, `AsciiArt.ExRatatui.lines/2` gives the frame as ratatui
lines, a span to each run of one colour. All three take `mode: :ansi256`.

## An app of your own

`ExRatatui.App` gives a LiveView-like app: `mount/1`, `render/2`,
`handle_event/2` and `handle_info/2`. An `AsciiArt.Player` keeps the time and
sends the app each frame, so `render/2` only places the latest:

```elixir
defmodule MyApp.ArtTUI do
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect

  @impl true
  def mount(opts) do
    {:ok, _player} = AsciiArt.Player.start_link(piece: Keyword.get(opts, :piece, "donut"))
    {:ok, %{frame: nil}}
  end

  @impl true
  def render(%{frame: nil}, _size), do: []

  def render(%{frame: frame}, size) do
    area = %Rect{x: 0, y: 0, width: size.width, height: size.height}
    [AsciiArt.ExRatatui.place(frame, area, title: "art")]
  end

  @impl true
  def handle_info({:ascii_art_frame, _ref, frame}, state), do: {:noreply, %{state | frame: frame}}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_event(%Key{code: "q", kind: "press"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state}
end
```

Start it under a supervisor, `{MyApp.ArtTUI, piece: "night-coast"}`, or from a
script with `MyApp.ArtTUI.start_link(piece: "donut")`. In a standalone script,
add a `terminate/2` that calls `System.stop(0)` so quitting ends the program.

## Keys and clicks

A piece that can be used (see
[Keys and clicks](getting-started.md#keys-and-clicks)) takes ExRatatui's
events through `AsciiArt.ExRatatui.handle_event/3`: a key by its code, and
a left click as the frame's cell under it, wherever `place/3` put the
picture (its box, centring and scroll allowed for). Keep the animation in
your state rather than a player, and what was chosen is in its options:

```elixir
alias ExRatatui.Event.{Key, Mouse}
alias ExRatatui.Layout.Rect

tree = AsciiArt.new!("file-tree", options: %{walk: false, paths: ["lib/app.ex", "mix.exs"], root: "app"})
{picture, tree} = AsciiArt.frame(tree, 0.0)
placed = AsciiArt.ExRatatui.place(picture, %Rect{x: 0, y: 0, width: 80, height: 30}, title: "files")

{:ok, tree} = AsciiArt.ExRatatui.handle_event(tree, %Key{code: "down", kind: "press"}, placed)
tree.options.cursor
#=> "lib/"

# A click on the row of mix.exs, where it is on the screen.
{_paragraph, rect} = placed
{:ok, tree} = AsciiArt.ExRatatui.handle_event(tree, %Mouse{kind: "down", button: "left", x: rect.x + 15, y: rect.y + 3}, placed)
tree.options.cursor
#=> "mix.exs"
```

In an `ExRatatui.App`, call it from `handle_event/2` with the `placed` your
`render/2` used (keep the screen's size in state from `%ExRatatui.Event.Resize{}`
events, or lay the screen out the same way in both), and start the app with
`mouse_capture: true` for clicks. `AsciiArt.ExRatatui.event/2` gives the
piece's event alone, for a key you want to look at first.

## A live dashboard

The UI and data pieces take your own data (see
[Live data](getting-started.md#live-data)), so they make dashboard widgets:
a sparkline of samples, a gauge of a reading, a progress bar, an htop-style
`cpu-meters`. Keep each as an animation, take new data up with
`AsciiArt.put_options!/2` as it comes, and draw on a timer. Here, the VM's
memory and process count, sampled every second, one under the other:

```elixir
defmodule MyApp.Dashboard do
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect

  @series %{label: "memory", unit: " mb", values: []}

  @impl true
  def mount(_opts) do
    memory =
      AsciiArt.new!("sparkline", options: %{series: [@series], range: false, cols: 60, rows: 3})

    procs =
      AsciiArt.new!("gauge",
        options: %{label: "processes", unit: "", max: 1000, value: :erlang.system_info(:process_count)}
      )

    send(self(), :sample)
    send(self(), :tick)
    {:ok, %{memory: memory, procs: procs, samples: [], frames: [], t: 0.0}}
  end

  @impl true
  def render(state, size) do
    area = %Rect{x: 0, y: 0, width: size.width, height: size.height}
    heights = for {_title, art} <- state.frames, do: {:length, art.rows + 2}
    rects = Layout.split(area, :vertical, heights ++ [{:min, 0}])

    for {{title, art}, rect} <- Enum.zip(state.frames, rects),
        do: AsciiArt.ExRatatui.place(art, rect, title: title)
  end

  # New data: taken up by each piece, drawn on the next tick.
  @impl true
  def handle_info(:sample, state) do
    mb = div(:erlang.memory(:total), 1_048_576)
    samples = Enum.take(state.samples ++ [mb], -60)
    memory = AsciiArt.put_options!(state.memory, series: [%{@series | values: samples}])
    procs = AsciiArt.put_options!(state.procs, value: :erlang.system_info(:process_count))
    Process.send_after(self(), :sample, 1000)
    {:noreply, %{state | memory: memory, procs: procs, samples: samples}, render?: false}
  end

  def handle_info(:tick, state) do
    t = state.t + 0.1
    {memory_frame, memory} = AsciiArt.frame(state.memory, t)
    {procs_frame, procs} = AsciiArt.frame(state.procs, t)
    Process.send_after(self(), :tick, 100)
    frames = [{"memory", memory_frame}, {"processes", procs_frame}]
    {:noreply, %{state | memory: memory, procs: procs, frames: frames, t: t}}
  end

  @impl true
  def handle_event(%Key{code: "q", kind: "press"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state}
end
```

The gauge's needle swings from its last reading to each new one; the
sparkline scrolls as samples come. Pieces with a size of their own (the
sparkline's `cols` and `rows` here) give frames of that size, so the layout
follows `art.rows`. ratatui already writes only the cells that change
between draws.

A piece is just a `{widget, rect}` in the list `render/2` returns, so it can
sit beside lists, tables and ratatui's own gauges in any `ExRatatui.Layout`.

## Colouring parts

Pieces that know their parts (a file tree's folders and files, a boot log's
statuses, a meter's bars; see `AsciiArt.Parts`) take a colour for each with
`:parts`, so a widget can match the rest of your UI: files by type, warnings
in your warning colour. Pass it to `AsciiArt.new/2` or the player, or
`parts: true` for the colours each piece suggests. Parts given no colour are
drawn in the terminal's own.

```elixir
parts = %{"folder" => "#58a6ff", "file.md" => "#d29922", "branch" => "#8b949e"}
{tree, _} = AsciiArt.new!("file-tree", parts: parts) |> AsciiArt.frame(3.0)

[_root, _docs, guide | _] = AsciiArt.ExRatatui.lines(tree)
Enum.map(guide.spans, &{String.trim(&1.content), &1.style.fg})
#=> [{"│   ├──", {:rgb, 139, 148, 158}}, {"guide.md", {:rgb, 210, 153, 34}}]
```

## Over SSH and across nodes

An app can be served over SSH, each client getting its own session (and so
its own animation), or attached to from another node. The viewer serves as
it is; give each transport its own child id:

```elixir
# needs: an SSH host key in /data/ssh
children = [
  Supervisor.child_spec(
    {AsciiArt.ExRatatui.Viewer,
     transport: :ssh, port: 2222, system_dir: "/data/ssh", app_opts: [piece: "matrix-rain"]},
    id: :art_over_ssh
  ),
  Supervisor.child_spec({AsciiArt.ExRatatui.Viewer, transport: :distributed}, id: :art_over_dist)
]
```

Then `ssh -p 2222 host`. `system_dir` holds the daemon's host key (make one
with `ssh-keygen -t ed25519 -N "" -f /data/ssh/ssh_host_ed25519_key`), and
the other options of OTP's `:ssh.daemon/2`, such as `:user_dir` and
`:pwdfun`, say who may log in. This is a good fit for a [Nerves](nerves.md)
device.

## Testing

ExRatatui's `test_mode: {width, height}` runs an app headlessly, and
`ExRatatui.Runtime.inject_event/2` drives keys, so an art app is tested like
any other:

```elixir
alias ExRatatui.Event.Key
alias ExRatatui.Runtime

{:ok, pid} = MyApp.ArtTUI.start_link(piece: "spinners", test_mode: {60, 30}, name: nil)
Process.sleep(300)
Runtime.snapshot(pid).render_count > 1
#=> true
Runtime.inject_event(pid, %Key{code: "q", kind: "press"})
#=> :ok
```

To see what was drawn, draw it into an `ExRatatui.CellSession` and read the
cells back:

```elixir
alias ExRatatui.CellSession

session = CellSession.new(38, 28)
:ok = CellSession.draw(session, [{frame, %Rect{x: 0, y: 0, width: 38, height: 28}}])
cells = CellSession.take_cells(session).cells
Enum.at(cells, 1 * 38 + 17).symbol
#=> "_"
```
