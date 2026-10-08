# Terminal apps

## Trying a piece

```sh
mix ascii_art.play night-coast
mix ascii_art.play elixir --mode ansi256
mix ascii_art.play typewriter --option "prefix=we make " --paper --fps 10
```

It plays until you press `q` or Ctrl-C, then shows the cursor again and resets
the colours. See `Mix.Tasks.AsciiArt.Play` for every flag.

## ANSI colour

`AsciiArt.Render.ANSI` turns a frame into text with colour escapes:
24-bit colour (`:truecolor`, the default), the nearest of xterm's 256
(`:ansi256`) where 24-bit is not supported, or none (`:mono`). It writes one
escape a run of colour, paints a scene's ground behind it (unless
`ground: false`), and resets at the end of every line so nothing bleeds.

```elixir
alias AsciiArt.Render.ANSI

{frame, _} = AsciiArt.new!("ubuntu") |> AsciiArt.frame(0.0)
IO.puts(ANSI.render(frame))
IO.puts(ANSI.render(frame, mode: :ansi256))

# Text pieces, and coloured ones drawn with color: false, are plain text.
{text, _} = AsciiArt.new!("donut") |> AsciiArt.frame(0.0)
IO.iodata_to_binary(ANSI.render(text)) == text.text
#=> true
```

To animate in place, move the cursor home before each frame; hide it while
playing:

```elixir
alias AsciiArt.Render.ANSI

IO.write([ANSI.hide_cursor(), ANSI.clear()])

AsciiArt.stream!("spinners")
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
alias AsciiArt.Render.ANSI

anim = AsciiArt.new!("night-coast")
{a, anim} = AsciiArt.frame(anim, 1.0)
{b, _anim} = AsciiArt.frame(anim, 1.1)

IO.write([ANSI.clear(), ANSI.changes(nil, a)])
IO.write(ANSI.changes(a, b))

whole = b |> ANSI.render() |> IO.iodata_to_binary() |> byte_size()
changed = a |> ANSI.changes(b) |> IO.iodata_to_binary() |> byte_size()
changed * 4 < whole
#=> true
```

`mix ascii_art.play` writes this way. `AsciiArt.Frame.changes/3` gives the
same runs as data, for drawing them some other way.

## Playing in real time

`AsciiArt.Player` is a process that draws a frame every `1/fps` seconds and
hands it on, keeping its pace against the monotonic clock. Give it a
`:callback` to draw straight away:

```elixir
alias AsciiArt.{Player, Render.ANSI}

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
{:ok, player} = AsciiArt.Player.start_link(piece: "donut", fps: 30)
ref = AsciiArt.Player.ref(player)

receive do
  {:ascii_art_frame, ^ref, frame} -> frame.rows
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
{:ok, gauge} = AsciiArt.Player.start_link(piece: "gauge", options: %{label: "load", value: 20})
:ok = AsciiArt.Player.set_options(gauge, value: 85)
AsciiArt.Player.frame(gauge).text =~ "85%"
#=> true
```

See [Live data](getting-started.md#live-data) for the pieces that take
data, and the [ExRatatui guide](ex_ratatui.md#a-live-dashboard) for a
dashboard.

## Sharing a player

Any number of processes can `subscribe/1` to one player, and `frame/1`
returns its latest frame. A player with no owner (`to: nil`, or started by a
supervisor) sends only to its subscribers, and while it has none it holds
its frame and does no work:

```elixir
{:ok, shared} = AsciiArt.Player.start_link(piece: "spinners", to: nil)
AsciiArt.Player.frame(shared).t
#=> 0.0

:ok = AsciiArt.Player.subscribe(shared)
ref = AsciiArt.Player.ref(shared)

receive do
  {:ascii_art_frame, ^ref, frame} -> frame.t > 0
end
#=> true
```

Under a supervisor, `{AsciiArt.Player, piece: "donut", name: MyApp.Donut}`
starts one with no owner: it never sends frames to the supervisor. Its name
is its child id, so one supervisor can hold several players.

## In a script or an escript

A one-off script needs nothing else:

```elixir
# needs: a file, run with `elixir clock.exs`
Mix.install([{:ascii_art, github: "houllette/ascii_art"}])

alias AsciiArt.Render.ANSI
IO.write([ANSI.hide_cursor(), ANSI.clear()])
{:ok, _} = AsciiArt.Player.start_link(piece: "analog-clock", callback: &IO.write([ANSI.home(), ANSI.render(&1)]))
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
