# AsciiArt

An Elixir port of [ascii.rest](https://ascii.rest) by
[@bas3line](https://github.com/bas3line): 191 pieces of animated ASCII art
(scenes, logos, distros, 3D shapes, simulations, charts and type) as pure
Elixir. The original is [bas3line/ascii](https://github.com/bas3line/ascii),
a TypeScript library for web pages; this port draws the same frames as data,
for Phoenix and LiveView, terminal apps, and Nerves devices.

```text
                  @@@@@@$$
               $$$$@@@@@@@$$#*
             #***##$$$$$$$$$$#*!
            !!!!!!*##$$$$$$$$##*!
           !;=;;;!***###$$$####**!
           =::~~~;=!!**########**!=
           ;:-...~;=!**#######***!=;
          ;;:-....~;=!*****#****!!=;
          ;;:~-....:;=!!*******!!==;~
           ==;::~-.-;=!!!******!!==;~
           !!*###*!;;==!!!!!!!!!==;:~
           !*#$$@$$#;==!!!!!!!!===;:-
           ;!#$@@@$*;====!!!!===;;:~-
            !*#$$#!;;=========;;;:~-.
            ~=***!==========;;;::~-,
             :=!!====;;;;;;;;::~~-,
              -====;;;;;:::::~~-,.
                ~:;::::::~~~~-,..
                  ,-------,,..
```

Every piece draws **exactly** what upstream draws, character for character
and colour for colour: each is tested frame by frame against golden output
generated from upstream's own source, on macOS and Linux.
[PORTING.md](PORTING.md) has the story. No NIFs, no Node at runtime, and no
required dependencies; the optional [ExRatatui](guides/ex_ratatui.md)
integration brings ratatui's NIF only if you add it.

## Installation

Not on Hex. Add it from git or a path:

```elixir
# in mix.exs
def deps do
  [
    {:ascii_art, github: "houllette/ascii_art"},
    # optional, for the Phoenix components and the LiveView player:
    {:phoenix_live_view, "~> 1.1"},
    # optional, for ratatui widgets and the full-screen terminal viewer:
    {:ex_ratatui, "~> 0.17"}
  ]
end
```

## Quick start

### One frame

```elixir
# The picture at 1.5 seconds, as text.
IO.puts(AsciiArt.render!("donut", 1.5))

{:ok, text} = AsciiArt.render("typewriter", 0.0, options: %{prefix: "we make "})
true = text =~ "we make "

# What a piece is.
meta = AsciiArt.meta!("night-coast")
{200, 100, :scenes} = {meta.cols, meta.rows, meta.category}
"night-coast" in AsciiArt.pieces(category: :scenes)
```

### Playing frames

Pieces are functions of time with state (simulations step by how far `t`
moved), so play time forward through `AsciiArt.frame/3`:

```elixir
{:ok, anim} = AsciiArt.new("doom-fire")
{frame, anim} = AsciiArt.frame(anim, 0.0)
{frame, _anim} = AsciiArt.frame(anim, 1 / 24)

# An AsciiArt.Frame: text, lines, and for coloured pieces a palette index a cell.
18 = length(frame.lines)
nil = frame.colors

# A coloured piece gives cols * rows palette indices, row by row.
{logo, _} = AsciiArt.new!("elixir") |> AsciiArt.frame(0.0)
true = byte_size(logo.colors) == logo.cols * logo.rows
"#" <> _ = AsciiArt.Frame.color_at(logo, 20, 10)

# Or a lazy stream, one frame every 1/fps seconds.
AsciiArt.stream!("spinners", fps: 12) |> Enum.take(3) |> Enum.map(& &1.t)
```

Options are checked against the piece's defaults: unknown keys and values of
the wrong kind are `{:error, {:invalid_option, key}}`, string keys and
values (from params) are cast, and numbers are clamped. Nothing from outside
ever becomes an atom.

### In a terminal

```sh
mix ascii_art.play night-coast            # q or Ctrl-C to stop
mix ascii_art.play elixir --mode ansi256
mix ascii_art.play typewriter --option "prefix=we make " --paper
```

With [ExRatatui](guides/ex_ratatui.md) as a dependency, a full-screen viewer
steps through every piece (space pauses, ← and → for the next, q quits), in
your terminal or served over SSH, and frames are ratatui widgets for your own
terminal UIs:

```sh
mix run -e 'AsciiArt.ExRatatui.Viewer.run(piece: "donut")'
```

From code, `AsciiArt.Player` plays a piece in real time and hands each frame
to a process, a callback, or any number of subscribers; under a supervisor
it sends only to its callback and subscribers. `AsciiArt.Render.ANSI` turns
a frame into truecolor (or 256-colour, or plain) escapes:

```elixir
alias AsciiArt.{Player, Render.ANSI}

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

The UI and data pieces draw your own data: progress bars, sparklines, a
gauge, an htop-style panel, uptime bars, a contribution heatmap,
candlesticks, a bar chart, an equalizer. Give it as options, and new data
while it plays with `AsciiArt.put_options/2` (or `AsciiArt.Player.set_options/2`):

```elixir
cpu = %{label: "cpu", unit: "%", lo: 0, hi: 100, values: [12, 30, 25, 60]}
anim = AsciiArt.new!("sparkline", options: %{series: [cpu], range: false, rows: 3})

anim = AsciiArt.put_options!(anim, series: [%{cpu | values: cpu.values ++ [45]}])
{frame, _anim} = AsciiArt.frame(anim, 1.0)
IO.puts(frame.text)
```

[Getting started](guides/getting-started.md#live-data) lists what each
takes.

### Phoenix: a still

`AsciiArt.Phoenix.Components.ascii/1` draws one frame (frame 0 by default,
which upstream designs to be a good still) as a `<pre>`: plain text for text
pieces, runs of coloured spans over the ground for coloured ones. No
JavaScript. It is `role="img"` with an `aria-label`.

```heex
<AsciiArt.Phoenix.Components.ascii piece="donut" />
<AsciiArt.Phoenix.Components.ascii piece="night-coast" label="a lighthouse at night" />
<AsciiArt.Phoenix.Components.ascii piece="elixir" mono class="logo" />
```

### Phoenix: playing

`AsciiArt.Phoenix.player/1` embeds `AsciiArt.Phoenix.PlayerLive` with
`live_render/3`: a LiveView of its own, with its own timer, so the page
needs no `handle_info`. The dead render is frame 0; once connected it plays.

```heex
<AsciiArt.Phoenix.player socket={@socket} id="spinners" piece="spinners" />
<AsciiArt.Phoenix.player socket={@socket} id="logo" piece="elixir" fps={20} />
<AsciiArt.Phoenix.player socket={@socket} id="coast" piece="night-coast" />
```

For live data, `AsciiArt.Phoenix.live_player/1` plays a piece inside your
LiveView and takes new options each time it renders with them: the gauge's
needle swings to each new reading.

```heex
<AsciiArt.Phoenix.live_player id="load" piece="gauge" options={%{label: "load", value: @load}} />
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

The only JavaScript in the project, `priv/static/ascii_art_hook.js`. Register
it in your `app.js`:

```js
import {AsciiArt} from "../../deps/ascii_art/priv/static/ascii_art_hook.js"

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: {AsciiArt},
  params: {_csrf_token: csrfToken},
})
```

`examples/demo.exs` is a gallery of every piece, a whole Phoenix app in one
file: `elixir examples/demo.exs`, then open http://localhost:4000. The index
shows frame 0 of each piece by category (text pieces through
`Components.ascii/1`, coloured ones on a canvas); each opens a page that
plays it with `player/1`, where you can try its options, paper and one ink.

### Nerves and other devices

`AsciiArt.Player` needs nothing from Phoenix. On a device with a serial
console, play into the terminal as above. With a display, draw the frame's
cells yourself: `frame.lines` holds the characters and `frame.colors` a
palette index for each, row by row.

```elixir
defmodule MyDevice.Art do
  use GenServer

  def start_link(piece), do: GenServer.start_link(__MODULE__, piece)

  @impl true
  def init(piece) do
    {:ok, player} = AsciiArt.Player.start_link(piece: piece, fps: 10)
    {:ok, %{player: player, palette: nil}}
  end

  @impl true
  def handle_info({:ascii_art_frame, _ref, frame}, state) do
    for {line, y} <- Enum.with_index(frame.lines),
        {char, x} <- Enum.with_index(String.codepoints(line)),
        char != " " do
      color = AsciiArt.Frame.color_at(frame, x, y) || "#ffffff"
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
    live data for the UI and data pieces, paper and one ink, clocks, and
    what things cost.
  * [Phoenix and LiveView](guides/phoenix.md): stills, live players, live
    data with `live_player/1`, what goes over the wire, one player for many
    viewers.
  * [Terminal apps](guides/terminal.md): `mix ascii_art.play`, ANSI colour,
    writing only what changed, `AsciiArt.Player`, scripts.
  * [ExRatatui](guides/ex_ratatui.md): the full-screen viewer, pieces as
    widgets in your own terminal UI, locally or over SSH, and a live
    dashboard.
  * [Livebook](guides/livebook.md): stills and animations in a notebook with
    Kino.
  * [Nerves](guides/nerves.md): the console, SSH, supervised players, and
    pixels for a framebuffer or an SPI panel.
  * [Drawing frames yourself](guides/custom-rendering.md): cells, runs of
    colour, SVG, asciinema recordings, frames over the wire.
  * [Writing a piece](guides/writing-pieces.md): your own pieces, on the same
    contract.

## Pieces

Each slug is upstream's file name; `AsciiArt.meta!/1` says what a piece
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

- `AsciiArt.JSMath` reproduces JavaScript's numbers where they differ from
  Elixir's, bit for bit: `Math.round`, `%`, `Math.fround`, typed-array
  stores, `Math.hypot`, `Math.cbrt`, `Math.log1p`, `toFixed` and
  `String(number)`. `AsciiArt.Int32` does JS's 32-bit operators. `sin`,
  `exp`, `pow` and the rest are Erlang's `:math`, which can differ from V8
  in the last bit but has never changed a golden frame.
- `test/fixtures/golden/` holds frames from upstream, generated with Node at
  fixed times and played at the frame rate, ink and paper, in colour and one
  ink. Every piece is tested against them (`AsciiArt.GoldenCase`), and
  against upstream's contract (`AsciiArt.ContractCase`).
- [PORTING.md](PORTING.md) lists every place JavaScript and Elixir differ and
  how the port handles it, and every deviation from upstream (there are few,
  all for unusual options).

## Contributing a piece

A piece is a module implementing `AsciiArt.Piece`: `meta/0`, `init/1` (the
options, merged with the defaults; precompute here) and `frame/3` (the
picture at `t` for an `AsciiArt.Env`, its colours, and the next state). The
contract is upstream's: every frame exactly `rows` lines of `cols`
characters from printable ASCII, `·`, `°` and U+2500–U+259F (scenes also `•`
and `●`); deterministic for the same `t`; colours, when asked for, a palette
index for every cell. See `AsciiArt.Piece` for an example.

To port an upstream piece:

1. Have upstream at the commit in [UPSTREAM.md](UPSTREAM.md) in
   `tmp/upstream`, and its golden fixture in `test/fixtures/golden/`
   (`NODE=/path/to/x64/node mix ascii_art.golden <slug>`).
2. Write `test/pieces/<slug>_test.exs` with `use AsciiArt.ContractCase` and
   `use AsciiArt.GoldenCase`, and watch it fail.
3. Port the piece until it passes, using `AsciiArt.JSMath`, `AsciiArt.Int32`
   and the helpers in `AsciiArt.Kit`; [PORTING.md](PORTING.md) has the
   hazards to check.
4. `mix run tools/gen_registry.exs` registers it; `mix ascii_art.perf <slug>`
   times it against upstream's budget; `mix precommit` checks everything.

## Development

```sh
mix deps.get
mix test                 # everything but the frame-time budgets
mix test --only perf     # the budgets
mix precommit            # what CI runs
mix ascii_art.perf       # frame times of every piece
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
