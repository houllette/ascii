# Terminal apps

## Trying a piece

```sh
mix ascii.play night-coast
mix ascii.play elixir --mode ansi256
mix ascii.play typewriter --option "prefix=we make " --paper --fps 10
mix ascii.play big-text --ink ff5f6d,ffc371 --gradient diagonal
mix ascii.play boot-log --parts --part status.warn=ff8800
```

It plays until you press `q` or Ctrl-C, then shows the cursor again and resets
the colours. See `Mix.Tasks.Ascii.Play` for every flag.

A piece that can be used takes your keys with `--interactive` (then only
Ctrl-C stops it, as `q` may be a key for the piece):

```sh
mix ascii.play file-tree --option walk=false --interactive
mix ascii.play calendar --option date=2026-10-08 --option time=false --interactive
```

## Watching the BEAM

`mix ascii.top` is htop for the VM it runs in: its schedulers as cores,
memory, the run queue as the load, the busiest processes by reductions, and
two minutes of history. In your project it starts your application first,
so it watches your app at work. It is the pieces themselves (`cpu-meters`
and `sparkline`, fed by `Ascii.BEAM`, in panels by `Ascii.Compose`),
side by side on a wide terminal, one above the other on a narrow one.

```sh
mix ascii.top
mix ascii.top --interval 2 --mode ansi256 --no-parts
```

## Pictures to keep

`mix ascii.svg` writes a frame as an SVG (`Ascii.Render.SVG`), for a
README or a slide, taking the same flags as `ascii.play`:

```sh
mix ascii.svg big-text --option text=hello --ink ff5f6d,ffc371
mix ascii.svg gauge --option value=72 --parts --background 0d1117 --foreground c9d1d9
```

## ANSI colour

`Ascii.Render.ANSI` turns a frame into text with colour escapes:
24-bit colour (`:truecolor`, the default), the nearest of xterm's 256
(`:ansi256`) where 24-bit is not supported, or none (`:mono`). It writes one
escape a run of colour, paints a scene's ground behind it (unless
`ground: false`), and resets at the end of every line so nothing bleeds.

```elixir
alias Ascii.Render.ANSI

{frame, _} = Ascii.new!("ubuntu") |> Ascii.frame(0.0)
IO.puts(ANSI.render(frame))
IO.puts(ANSI.render(frame, mode: :ansi256))

# Text pieces, and coloured ones drawn with color: false, are plain text.
{text, _} = Ascii.new!("donut") |> Ascii.frame(0.0)
IO.iodata_to_binary(ANSI.render(text)) == text.text
#=> true

# Unless given an ink, which they are written in.
{inked, _} = Ascii.new!("donut", ink: "#7fdbca") |> Ascii.frame(0.0)
IO.iodata_to_binary(ANSI.render(inked)) =~ "\e[38;2;127;219;202m"
#=> true

# Or colours for their parts; the rest in the terminal's own foreground.
{boot, _} = Ascii.new!("boot-log", parts: %{"status.warn" => "#d29922"}) |> Ascii.frame(0.0)
IO.iodata_to_binary(ANSI.render(boot)) =~ "\e[38;2;210;153;34m[ WARN ]"
#=> true
```

To animate in place, move the cursor home before each frame; hide it while
playing:

```elixir
alias Ascii.Render.ANSI

IO.write([ANSI.hide_cursor(), ANSI.clear()])

Ascii.stream!("spinners")
|> Enum.take(12)
|> Enum.each(fn frame ->
  IO.write([ANSI.home(), ANSI.render(frame)])
end)

IO.write([ANSI.reset(), ANSI.show_cursor(), "\n"])
```

## Writing only what changed

A terminal that already shows a frame needs only what changed in the next:
`ANSI.changes/3` moves the cursor to each run of cells that changed and
writes it, and writes nothing at all when nothing did. Most pieces change a
few cells in a hundred a frame, so over SSH or a serial console this is
far less to send than the whole frame. `:at` places the frame elsewhere on
the screen.

```elixir
alias Ascii.Render.ANSI

anim = Ascii.new!("night-coast")
{a, anim} = Ascii.frame(anim, 1.0)
{b, _anim} = Ascii.frame(anim, 1.1)

IO.write([ANSI.clear(), ANSI.changes(nil, a)])
IO.write(ANSI.changes(a, b))

whole = b |> ANSI.render() |> IO.iodata_to_binary() |> byte_size()
changed = a |> ANSI.changes(b) |> IO.iodata_to_binary() |> byte_size()
changed * 4 < whole
#=> true
```

`mix ascii.play` writes this way. `Ascii.Frame.changes/3` gives the
same runs as data, for drawing them some other way.

## Playing in real time

`Ascii.Player` is a process that draws a frame every `1/fps` seconds and
hands it on, keeping its pace against the monotonic clock. Give it a
`:callback` to draw straight away:

```elixir
alias Ascii.{Player, Render.ANSI}

draw = fn frame -> IO.write([ANSI.home(), ANSI.render(frame)]) end

IO.write([ANSI.hide_cursor(), ANSI.clear()])
{:ok, player} = Player.start_link(piece: "matrix-rain", callback: draw)
Process.sleep(300)
Player.stop(player)
IO.write([ANSI.reset(), ANSI.show_cursor(), "\n"])
```

Or receive frames as messages, which suits a GenServer that does other work
too. Each message carries the player's ref, so one process can listen to
several players:

```elixir
{:ok, player} = Ascii.Player.start_link(piece: "donut", fps: 30)
ref = Ascii.Player.ref(player)

receive do
  {:ascii_frame, ^ref, frame} -> frame.rows
end
#=> 22
```

`pause/1`, `resume/1` and `set_fps/2` control it; play time does not advance
while paused, so a piece resumes where it was. The player stops when its
owner, the process it sends to, exits.

A piece that closes a loop (sixty do, every logo among them) is drawn once
a frame of its cycle and then repeated, so after one cycle it costs the
player nothing.

## Live data

`set_options/2` gives a playing piece new options, such as a reading for a
gauge or the latest samples for a sparkline, and sends the new picture at
once:

```elixir
{:ok, gauge} = Ascii.Player.start_link(piece: "gauge", options: %{label: "load", value: 20})
:ok = Ascii.Player.set_options(gauge, value: 85)
Ascii.Player.frame(gauge).text =~ "85%"
#=> true
```

See [Live data](getting-started.md#live-data) for the pieces that take
data, and the [ExRatatui guide](ex_ratatui.md#a-live-dashboard) for a
dashboard. `Ascii.BEAM` and `Ascii.Telemetry` give readings to feed
them; `Ascii.Player.handle_event/2` gives a playing piece a key.

## Panels and layouts

Without a terminal UI library, `Ascii.Compose` puts frames together into
one: each in a bordered panel with a title, side by side or one above
another, rules between sections, and `fit/4` to cut or pad the whole to the
terminal. The result is a frame, so `ANSI.changes/3` writes only what
changed of all of it:

```elixir
alias Ascii.Compose

{gauge, _} = Ascii.new!("gauge", options: %{label: "load", value: 40}) |> Ascii.frame(1.0)
{log, _} = Ascii.new!("boot-log", options: %{steps: [%{text: "ready", status: "ok"}]}) |> Ascii.frame(1.0)

board =
  Compose.above([
    Compose.beside([Compose.panel(gauge, title: "load"), Compose.panel(log, title: "boot", style: :double)]),
    Compose.divider(128, label: "q to quit", style: :dotted)
  ])

{board.cols, board.rows}
#=> {128, 21}

screen = Compose.fit(board, 80, 24, align: :left, valign: :top)
{screen.cols, screen.rows}
#=> {80, 24}
```

Each tick, draw each piece's frame at the play time, put them together, and
write the changes; `Mix.Tasks.Ascii.Top` is a whole example. A coloured
scene's ground is dropped where the frames do not share one, so give the
whole a `ground:` or play scenes on a dark terminal.

## Sharing a player

Any number of processes can `subscribe/1` to one player, and `frame/1`
returns its latest frame. A player with no owner (`to: nil`, or started by a
supervisor) sends only to its subscribers, and while it has none it holds
its frame and does no work:

```elixir
{:ok, shared} = Ascii.Player.start_link(piece: "spinners", to: nil)
Ascii.Player.frame(shared).t
#=> 0.0

:ok = Ascii.Player.subscribe(shared)
ref = Ascii.Player.ref(shared)

receive do
  {:ascii_frame, ^ref, frame} -> frame.t > 0
end
#=> true
```

Under a supervisor, `{Ascii.Player, piece: "donut", name: MyApp.Donut}`
starts one with no owner: it never sends frames to the supervisor. Its name
is its child id, so one supervisor can hold several players.

## In a script or an escript

A one-off script needs nothing else:

```elixir
# needs: a file, run with `elixir clock.exs`
Mix.install([{:ascii, "~> 0.3.0"}])

alias Ascii.Render.ANSI
IO.write([ANSI.hide_cursor(), ANSI.clear()])
{:ok, _} = Ascii.Player.start_link(piece: "analog-clock", callback: &IO.write([ANSI.home(), ANSI.render(&1)]))
Process.sleep(:infinity)
```

In an escript or a release, the same code runs; restore the cursor
(`ANSI.show_cursor/0`) on your way out. For a full-screen app with layout,
widgets and key handling, see the [ExRatatui guide](ex_ratatui.md), and its
ready-made viewer.

## Size

Pieces are drawn at their own size (`frame.cols` × `frame.rows`); a terminal
narrower than that wraps lines and garbles the picture. Most text pieces are
at most 80×32. Scenes are 200×100 with square cells (`frame.cell == 1`), so
they need a very large terminal or a small font; `color: false` and a
logo or text piece suit ordinary terminals better.
