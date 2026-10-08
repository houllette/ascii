# ExRatatui

[ExRatatui](https://hexdocs.pm/ex_ratatui) brings the Rust
[ratatui](https://ratatui.rs) terminal UI library to Elixir: widgets, layout,
key and mouse events, and supervised TUI apps that run in a local terminal,
over SSH or across distributed Erlang. `AsciiArt.ExRatatui` makes frames into
ratatui widgets, and `AsciiArt.ExRatatui.Viewer` is a ready-made app that
plays pieces full screen. ExRatatui is an optional dependency of this
library: add it to your project to have both. Written against ExRatatui 0.17.

```elixir
# needs: mix.exs
{:ascii_art, github: "houllette/ascii_art"},
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
