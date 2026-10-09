# Ascii

ASCII components and diagrams for Elixir: file trees, boot logs, htop-style
meters, gauges, sparklines, progress bars, forms, terminals, calendars and
departure boards that draw your own live data, natively, in Phoenix
LiveView, terminal UIs, Livebook and Nerves devices, in your app's colours.
191 animated pieces in all: alongside the components, scenes, logos,
distros, 3D shapes, simulations and type.

```text
   0[|||||||||||||||||||||98.0%]    4[|||||||||||||||####  73.5%]
   1[|||||#               23.7%]    5[|||||||||||||||##### 75.9%]
   2[|||||||||||||||||##  74.9%]    6[||||||||||||||||||###86.2%]
   3[|||||||||||||||||### 75.1%]    7[||||||||||||||||||###91.8%]
 Mem[|||||||||||****6.51G/15.5G]  Tasks: 142, 421 thr; 7 running
 Swp[||              141M/2.00G]  Load average: 3.29 1.70 1.08
                                  Uptime: 4 days, 03:12:45

   PID USER      VIRT   RES S  CPU% MEM%     TIME+  Command
 20379 app      1.19G  350M R 497.8  2.2  25:38.59  indexer
 19941 root     2.85G  191M S  29.0  1.2   9:54.68  server
 21514 app      2.29G  551M S  29.0  3.5  15:08.45  backup
```

- **Components that take live data.** The UI, data and type pieces take
  your data as options (readings, listings, text), and new data as it comes
  (`Ascii.put_options/2`): a gauge's needle swings to the new value, a
  sparkline scrolls on, a file tree lists your files. See
  [Live data](guides/getting-started.md#live-data).
- **Native to the Elixir ecosystem.** Function components and LiveView
  players for Phoenix (`live_player/1` takes your assigns), widgets for
  [ExRatatui](guides/ex_ratatui.md) terminal UIs, locally or over SSH, ANSI
  for any terminal, a supervised `Ascii.Player` for a process of your
  own, and plain frame data for Livebook, a framebuffer or anything else.
  No NIFs, no Node at runtime, and no required dependencies; the
  optional ExRatatui integration brings ratatui's NIF only if you add it.
- **Usable.** A file tree's cursor walks and its folders open, a form's
  fields take typing, a calendar picks a date: keys and clicks go to the
  piece (`Ascii.handle_event/2`), in LiveView, in ExRatatui and in a
  plain terminal, and what was chosen is in its options. A click tells you
  the part under it, the file or the bar (`Ascii.part_at/4`).
- **In your colours.** Give a piece an ink, one colour or a gradient
  (`Ascii.Ink`), and colour its parts one by one: a file tree's folders
  and file types, a boot log's `OK` and `WARN`, a meter's bars, a heading's
  letters (`Ascii.Parts`). On a page the colours can be CSS variables,
  so they follow your theme into dark mode; on paper, the suggested colours
  are those for a light page.
- **Put together.** Frames go into bordered panels, beside and above one
  another, with rules between (`Ascii.Compose`), for a dashboard on a
  plain terminal or a device's screen; out as SVG for a README or an email
  (`Ascii.Render.SVG`, `mix ascii.svg`); and `mix ascii.top`
  watches your BEAM, htop-style, made of the pieces themselves.
- **Native diagrams.** Build flowcharts with nested groups, sequence diagrams, C4 views,
  state diagrams and entity relationship diagrams from Elixir data or supported Mermaid source (`Ascii.Diagram`,
  `Ascii.Mermaid`). The result is a frame for the same renderers, with
  nested boundaries and sequence fragments, optional colours per element,
  and retained geometry for hit testing, selection styling and panned viewports.
  See the [diagram guide](guides/diagrams.md) for the syntax support matrix and runnable examples.
- **Accessible.** Each component says what it shows, from its data, for
  screen readers ("load: 72%", "deploy: 6 steps, 1 failed"), and the
  Phoenix players label the picture with it (`Ascii.describe/1`).
- **Exact.** It began as a port of [ascii.rest](https://ascii.rest) by
  [@bas3line](https://github.com/bas3line)
  ([bas3line/ascii](https://github.com/bas3line/ascii), a TypeScript
  library for web pages), and every piece draws exactly what upstream draws,
  character for character and colour for colour: each is tested frame by
  frame against golden output generated from upstream's own source, on
  macOS and Linux. [PORTING.md](PORTING.md) has the story.

## Installation

Requires Elixir 1.18 or later.

From [Hex](https://hex.pm/packages/ascii), with the docs on
[HexDocs](https://ascii.hexdocs.pm/):

```elixir
# in mix.exs
def deps do
  [
    {:ascii, "~> 0.4.1"},
    # optional, for the Phoenix components and the LiveView player:
    {:phoenix_live_view, "~> 1.1"},
    # optional, for ratatui widgets and the full-screen terminal viewer:
    {:ex_ratatui, "~> 0.17"},
    # optional (Phoenix brings it), to feed the pieces your :telemetry events:
    {:telemetry, "~> 1.0"}
  ]
end
```

Version 0.4.1 wraps diagram labels at word boundaries, splitting words only
when they exceed the full label width.

Version 0.4.0 adds nested flowchart groups, state and ER diagrams, compact
layouts, selection styling and panned viewports.

Version 0.3.0 renames `ascii_art` to `ascii` and `AsciiArt.*` to `Ascii.*`.
Existing consumers should follow the [migration guide](guides/migrating-to-ascii.md).

## Quick start

### One frame

```elixir
# A component, from your data: a gauge reading 72%, two seconds in.
IO.puts(Ascii.render!("gauge", 2.0, options: %{label: "cpu", value: 72}))

# Or art: the picture at 1.5 seconds, as text.
IO.puts(Ascii.render!("donut", 1.5))

{:ok, text} = Ascii.render("typewriter", 0.0, options: %{prefix: "we make "})
true = text =~ "we make "

# What a piece is.
meta = Ascii.meta!("night-coast")
{200, 100, :scenes} = {meta.cols, meta.rows, meta.category}
"night-coast" in Ascii.pieces(category: :scenes)
```

### Playing frames

Pieces are functions of time with state (simulations step by how far `t`
moved), so play time forward through `Ascii.frame/3`:

```elixir
{:ok, anim} = Ascii.new("doom-fire")
{frame, anim} = Ascii.frame(anim, 0.0)
{frame, _anim} = Ascii.frame(anim, 1 / 24)

# An Ascii.Frame: text, lines, and for coloured pieces a palette index a cell.
18 = length(frame.lines)
nil = frame.colors

# A coloured piece gives cols * rows palette indices, row by row.
{logo, _} = Ascii.new!("elixir") |> Ascii.frame(0.0)
true = byte_size(logo.colors) == logo.cols * logo.rows
"#" <> _ = Ascii.Frame.color_at(logo, 20, 10)

# Or a lazy stream, one frame every 1/fps seconds.
Ascii.stream!("spinners", fps: 12) |> Enum.take(3) |> Enum.map(& &1.t)
```

Options are checked against the piece's defaults: unknown keys and values of
the wrong kind are `{:error, {:invalid_option, key}}`, string keys and
values (from params) are cast, and numbers are clamped. Nothing from outside
ever becomes an atom.

### In a terminal

```sh
mix ascii.play night-coast            # q or Ctrl-C to stop
mix ascii.play elixir --mode ansi256
mix ascii.play typewriter --option "prefix=we make " --paper
mix ascii.play big-text --ink ff5f6d,ffc371   # one ink, or a gradient
mix ascii.play boot-log --parts               # its parts in colour
mix ascii.play file-tree --option walk=false --interactive   # arrows, enter, space
mix ascii.top                                 # this BEAM, htop-style
mix ascii.svg gauge --option value=72 --parts # one frame as an SVG
```

With [ExRatatui](guides/ex_ratatui.md) as a dependency, a full-screen viewer
steps through every piece (space pauses, ← and → for the next, q quits), in
your terminal or served over SSH, and frames are ratatui widgets for your own
terminal UIs:

```sh
mix run -e 'Ascii.ExRatatui.Viewer.run(piece: "donut")'
```

From code, `Ascii.Player` plays a piece in real time and hands each frame
to a process, a callback, or any number of subscribers; under a supervisor
it sends only to its callback and subscribers. `Ascii.Render.ANSI` turns
a frame into truecolor (or 256-colour, or plain) escapes:

```elixir
alias Ascii.{Player, Render.ANSI}

draw = fn frame -> IO.write([ANSI.home(), ANSI.render(frame, mode: :truecolor)]) end

IO.write([ANSI.hide_cursor(), ANSI.clear()])
{:ok, player} = Player.start_link(piece: "matrix-rain", callback: draw)
Process.sleep(500)
:ok = Player.pause(player)
:ok = Player.set_fps(player, 10)
:ok = Player.resume(player)
Player.stop(player)
IO.write([ANSI.reset(), ANSI.show_cursor(), "\n"])
```

### Live data

The components draw your own data: progress bars, sparklines, a gauge, an
htop-style panel, uptime bars, a contribution heatmap, candlesticks, a bar
chart, an equalizer, a file tree, a terminal session, a departures board.
Give it as options, and new data while it plays with
`Ascii.put_options/2` (or `Ascii.Player.set_options/2`):

```elixir
cpu = %{label: "cpu", unit: "%", lo: 0, hi: 100, values: [12, 30, 25, 60]}
anim = Ascii.new!("sparkline", options: %{series: [cpu], range: false, rows: 3})

anim = Ascii.put_options!(anim, series: [%{cpu | values: cpu.values ++ [45]}])
{frame, _anim} = Ascii.frame(anim, 1.0)
IO.puts(frame.text)
```

[Getting started](guides/getting-started.md#live-data) lists what each
takes. `Ascii.Telemetry` turns your app's `:telemetry` events into
readings for them, and `Ascii.BEAM` your VM's schedulers, memory and
busiest processes.

### Usable components

A component that can be used takes keys and clicks: a file tree's cursor
moves and its folders open, a form's fields take typing, a calendar picks a
date. Everything it changes is in its options, so what was chosen is
there to read:

```elixir
paths = ["lib/my_app.ex", "lib/my_app/repo.ex", "mix.exs", "README.md"]
tree = Ascii.new!("file-tree", options: %{walk: false, paths: paths, root: "my_app"})

{:ok, tree} = Ascii.handle_event(tree, {:key, "down"})
{:ok, tree} = Ascii.handle_event(tree, {:key, "right"})
{:ok, tree} = Ascii.handle_event(tree, {:key, "down"})
"lib/my_app.ex" = tree.options.cursor
"file tree of my_app: 2 folders, 4 files; at lib/my_app.ex" = Ascii.describe(tree)

# Which part is under a click: here, the file the cursor is on.
{frame, tree} = Ascii.frame(tree, 0.0)
{"file.ex", "my_app.ex"} = Ascii.part_at(tree, frame, 18, 2)
```

In LiveView, give the player `interactive` (and `notify` to be told of each
key and click); in ExRatatui, `Ascii.ExRatatui.handle_event/3` takes
its events; in a terminal, `mix ascii.play --interactive`.

### Putting frames together

```elixir
alias Ascii.Compose

{:ok, gauge} = Ascii.still("gauge", options: %{label: "load", value: 72}, parts: true)
{:ok, log} = Ascii.still("boot-log", options: %{title: "deploy", steps: [%{text: "built", status: "ok"}]})

board =
  Compose.above([
    Compose.beside([Compose.panel(gauge, title: "load"), Compose.panel(log, title: "deploy")]),
    Compose.divider(128, label: "end of report", style: :dashed)
  ])

IO.puts(Ascii.Render.ANSI.render(board))
svg = IO.iodata_to_binary(Ascii.Render.SVG.render(board, background: "#0d1117"))
true = String.starts_with?(svg, "<svg")
```

### Phoenix: a still

`Ascii.Phoenix.Components.ascii/1` draws one frame (frame 0 by default,
which upstream designs to be a good still) as a `<pre>`: plain text for text
pieces, runs of coloured spans over the ground for coloured ones. No
JavaScript. It is `role="img"` with an `aria-label`.

```heex
<Ascii.Phoenix.Components.ascii piece="donut" />
<Ascii.Phoenix.Components.ascii piece="night-coast" label="a lighthouse at night" />
<Ascii.Phoenix.Components.ascii piece="elixir" mono class="logo" />
<Ascii.Phoenix.Components.ascii piece="big-text" ink={["#ff5f6d", "#ffc371"]} />
<Ascii.Phoenix.Components.ascii piece="file-tree" parts={%{"folder" => "#58a6ff"}} />
```

### Phoenix: playing

`Ascii.Phoenix.player/1` embeds `Ascii.Phoenix.PlayerLive` with
`live_render/3`: a LiveView of its own, with its own timer, so the page
needs no `handle_info`. The dead render is frame 0; once connected it plays.

```heex
<Ascii.Phoenix.player socket={@socket} id="spinners" piece="spinners" />
<Ascii.Phoenix.player socket={@socket} id="logo" piece="elixir" fps={20} />
<Ascii.Phoenix.player socket={@socket} id="coast" piece="night-coast" />
```

For live data, `Ascii.Phoenix.live_player/1` plays a piece inside your
LiveView and takes new options each time it renders with them: the gauge's
needle swings to each new reading.

```heex
<Ascii.Phoenix.live_player id="load" piece="gauge" options={%{label: "load", value: @load}} />
<Ascii.Phoenix.live_player id="top" piece="cpu-meters" options={@readings} parts />
```

`parts` colours each part of a component as it suggests (htop's green and
red bars here), or in your colours: `parts={%{"bar.user" => "#22c55e"}}`,
or your theme's: `parts={%{"bar.user" => "var(--color-success)"}}`.

`interactive` gives a player keys and clicks; `notify` sends your LiveView
each one, with the part clicked and the options the piece now has:

```heex
<Ascii.Phoenix.live_player id="files" piece="file-tree" options={%{walk: false, paths: @paths}} interactive notify />
```

With the hook below registered, the browser draws, and the server sends as
little as it can. A piece that closes a loop (60 of them, every logo among
them) is drawn for one cycle and sent once, compressed, a few kilobytes for
a logo; the browser plays it from then on and the server does nothing more.
Any other piece sends each frame as the runs of cells that changed, nothing
when none did, and nothing while the picture is off screen or its tab
hidden. Without the hook (or with `render={:server}`) the server patches the
HTML a row at a time instead. See the
[Phoenix guide](guides/phoenix.md#what-goes-over-the-wire).

### The hook

The only JavaScript in the project, `priv/static/ascii_hook.js`. Register
it in your `app.js`:

```js
import {Ascii} from "../../deps/ascii/priv/static/ascii_hook.js"

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: {Ascii},
  params: {_csrf_token: csrfToken},
})
```

`examples/demo.exs` is a gallery of every piece, a whole Phoenix app in one
file: `elixir examples/demo.exs`, then open http://localhost:4000. The index
shows frame 0 of each piece by category (text pieces through
`Components.ascii/1`, coloured ones on a canvas); each opens a page that
plays it with `player/1`, where you can try its options, paper, one ink, the
ink's colour, and colours for its parts.

### Nerves and other devices

`Ascii.Player` needs nothing from Phoenix. On a device with a serial
console, play into the terminal as above. With a display, draw the frame's
cells yourself: `frame.lines` holds the characters and `frame.colors` a
palette index for each, row by row.

```elixir
defmodule MyDevice.Art do
  use GenServer

  def start_link(piece), do: GenServer.start_link(__MODULE__, piece)

  @impl true
  def init(piece) do
    {:ok, player} = Ascii.Player.start_link(piece: piece, fps: 10)
    {:ok, %{player: player, palette: nil}}
  end

  @impl true
  def handle_info({:ascii_frame, _ref, frame}, state) do
    for {line, y} <- Enum.with_index(frame.lines),
        {char, x} <- Enum.with_index(String.codepoints(line)),
        char != " " do
      color = Ascii.Frame.color_at(frame, x, y) || "#ffffff"
      # draw `char` at cell (x, y) in `color` on your display
      {x, y, char, color}
    end

    {:noreply, state}
  end
end

{:ok, _} = MyDevice.Art.start_link("ubuntu")
```

## Guides

  * [Getting started](guides/getting-started.md): pieces, frames, options,
    live data for the components, keys and clicks, words for screen
    readers, your colours (ink, parts, CSS variables), paper and one ink,
    clocks, and what things cost.
  * [Components at a glance](guides/components.md): every component, the
    data it takes, its size, parts and keys, and what they all share.
  * [Phoenix and LiveView](guides/phoenix.md): stills, live players, live
    data with `live_player/1`, interactive players, telemetry, what goes
    over the wire, one player for many viewers.
  * [Terminal apps](guides/terminal.md): `mix ascii.play`,
    `mix ascii.top`, ANSI colour, writing only what changed, panels and
    layouts with `Ascii.Compose`, `Ascii.Player`, scripts.
  * [ExRatatui](guides/ex_ratatui.md): the full-screen viewer, pieces as
    widgets in your own terminal UI, locally or over SSH, keys and clicks,
    and a live dashboard.
  * [Livebook](guides/livebook.md): stills and animations in a notebook with
    Kino.
  * [Nerves](guides/nerves.md): the console, SSH, supervised players, and
    pixels for a framebuffer or an SPI panel.
  * [Drawing frames yourself](guides/custom-rendering.md): cells, runs of
    colour, SVG (`Ascii.Render.SVG`), asciinema recordings, frames over
    the wire.
  * [Writing a piece](guides/writing-pieces.md): your own pieces, on the same
    contract.

## Pieces

Each slug is upstream's file name; `Ascii.meta!/1` says what a piece
shows and which options it takes.

<!-- pieces -->
| category | pieces | slugs |
| --- | --- | --- |
| scenes | 13 | `alpine-dawn`, `aurora-fjord`, `deep-reef`, `desert-night`, `earthrise`, `kyoto-dusk`, `marine-drive`, `misty-forest`, `night-coast`, `ocean-sunset`, `storm-plains`, `taj-dawn`, `varanasi-ghats` |
| shapes | 12 | `cube`, `dna-helix`, `donut`, `glxgears`, `gyroscope`, `heart`, `icosahedron`, `mobius-strip`, `spring`, `tesseract`, `torus-knot`, `twisted-ring` |
| space | 11 | `black-hole`, `earth`, `eclipse`, `galaxy`, `moon-phases`, `planet`, `rocket`, `saptarishi`, `solar-system`, `starfield`, `three-body` |
| physics | 14 | `bouncing-balls`, `chladni`, `double-pendulum`, `falling-sand`, `flag`, `fountain`, `harmonograph`, `lorenz`, `newtons-cradle`, `pendulum-wave`, `plucked-string`, `pond-ripples`, `smoke`, `wave-interference` |
| nature | 16 | `aurora`, `bonsai`, `campfire`, `cherry-blossom`, `contour-map`, `fern`, `fireflies`, `fractal-tree`, `landscape`, `lightning`, `rain`, `ruled-mountains`, `sea-swell`, `snowfall`, `sunrise`, `wind` |
| creatures | 10 | `aquarium`, `butterfly`, `cat`, `fox`, `jellyfish`, `owl`, `snake`, `spider`, `starlings`, `whale` |
| objects | 14 | `analog-clock`, `candle`, `coffee`, `ferris-wheel`, `hawa-mahal`, `hourglass`, `kite`, `lava-lamp`, `lighthouse`, `skyline`, `sundial`, `train`, `vinyl`, `windmill` |
| generative | 13 | `epicycles`, `flow-field`, `glider-gun`, `hilbert-curve`, `julia-set`, `langtons-ant`, `mandelbrot`, `maze`, `plasma`, `reaction-diffusion`, `rule-30`, `sierpinski`, `voronoi` |
| effects | 8 | `doom-fire`, `fireworks`, `matrix-rain`, `rotozoomer`, `sparks`, `synthwave`, `tunnel`, `tv-static` |
| ui | 12 | `boot-log`, `box-frames`, `calendar`, `digital-clock`, `dividers`, `file-tree`, `form-controls`, `not-found`, `progress-bar`, `skeleton`, `spinners`, `terminal` |
| data | 10 | `bar-chart`, `candlesticks`, `cpu-meters`, `equalizer`, `gauge`, `heartbeat`, `heatmap`, `radar`, `sparkline`, `uptime-bar` |
| type | 9 | `big-text`, `dissolve`, `glitch`, `marquee`, `morse`, `scramble`, `split-flap`, `typewriter`, `wave-text` |
| logos | 27 | `c`, `clojure`, `cpp`, `csharp`, `css`, `dart`, `elixir`, `erlang`, `go`, `haskell`, `html`, `java`, `javascript`, `julia`, `kotlin`, `lua`, `ocaml`, `perl`, `php`, `python`, `r`, `ruby`, `rust`, `scala`, `swift`, `typescript`, `zig` |
| distros | 22 | `almalinux`, `alpine-linux`, `arch-linux`, `centos`, `debian`, `deepin`, `elementary-os`, `endeavouros`, `fedora`, `gentoo`, `kali-linux`, `linux-mint`, `manjaro`, `nixos`, `opensuse`, `pop-os`, `red-hat`, `rocky-linux`, `tux`, `ubuntu`, `void-linux`, `zorin-os` |
<!-- /pieces -->

[PORT_STATUS.md](PORT_STATUS.md) lists every piece with its frame time and
porting notes.

## How it matches upstream

- `Ascii.JSMath` reproduces JavaScript's numbers where they differ from
  Elixir's, bit for bit: `Math.round`, `%`, `Math.fround`, typed-array
  stores, `Math.hypot`, `Math.cbrt`, `Math.log1p`, `toFixed` and
  `String(number)`. `Ascii.Int32` does JS's 32-bit operators. `sin`,
  `exp`, `pow` and the rest are Erlang's `:math`, which can differ from V8
  in the last bit but has never changed a golden frame.
- `test/fixtures/golden/` holds frames from upstream, generated with Node at
  fixed times and played at the frame rate, ink and paper, in colour and one
  ink. Every piece is tested against them (`Ascii.GoldenCase`), and
  against upstream's contract (`Ascii.ContractCase`).
- [PORTING.md](PORTING.md) lists every place JavaScript and Elixir differ and
  how the port handles it, and every deviation from upstream (there are few,
  all for unusual options).

## Contributing a piece

A piece is a module implementing `Ascii.Piece`: `meta/0`, `init/1` (the
options, merged with the defaults; precompute here) and `frame/3` (the
picture at `t` for an `Ascii.Env`, its colours, and the next state). The
contract is upstream's: every frame exactly `rows` lines of `cols`
characters from printable ASCII, `·`, `°` and U+2500–U+259F (scenes also `•`
and `●`); deterministic for the same `t`; colours, when asked for, a palette
index for every cell. See `Ascii.Piece` for an example.

To port an upstream piece:

1. Have upstream at the commit in [UPSTREAM.md](UPSTREAM.md) in
   `tmp/upstream`, and its golden fixture in `test/fixtures/golden/`
   (`NODE=/path/to/x64/node mix ascii.golden <slug>`).
2. Write `test/pieces/<slug>_test.exs` with `use Ascii.ContractCase` and
   `use Ascii.GoldenCase`, and watch it fail.
3. Port the piece until it passes, using `Ascii.JSMath`, `Ascii.Int32`
   and the helpers in `Ascii.Kit`; [PORTING.md](PORTING.md) has the
   hazards to check.
4. `mix run tools/gen_registry.exs` registers it; `mix ascii.perf <slug>`
   times it against upstream's budget; `mix precommit` checks everything.

## Development

```sh
mix deps.get
mix test                 # everything but the frame-time budgets
mix test --only perf     # the budgets
mix precommit            # what CI runs
mix ascii.perf       # frame times of every piece
```

Tool versions are pinned in `.tool-versions`. Regenerating fixtures needs
Node; see [UPSTREAM.md](UPSTREAM.md).

## Licence

MIT, © [@bas3line](https://github.com/bas3line) for ascii.rest, and the
authors of this port. The logos and distros are drawn from
[devicon](https://github.com/devicons/devicon) (MIT) and
[Simple Icons](https://github.com/simple-icons/simple-icons) (CC0); each is
a trademark of its owner, shown to name the language or the distribution.
See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
