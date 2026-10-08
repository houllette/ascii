# Getting started

AsciiArt plays the 191 animated pieces of [ascii.rest](https://ascii.rest)
in Elixir. A piece is a function of time: ask for its picture at `t` seconds
and you get a frame, `rows` lines of `cols` characters, and for coloured
pieces a palette colour for every cell. Everything else in the library, and
every integration in these guides, is built on that.

## Installation

AsciiArt has no required dependencies. Add Phoenix LiveView only if you want
the Phoenix components.

```elixir
# needs: a mix.exs to put it in
def deps do
  [
    {:ascii_art, github: "houllette/ascii_art"},
    # optional:
    {:phoenix_live_view, "~> 1.1"}
  ]
end
```

## Finding a piece

Pieces are named by their upstream slug. `AsciiArt.meta!/1` says what a piece
is, how big it is, how fast it plays and which options it takes.

```elixir
AsciiArt.pieces() |> length()
#=> 191

AsciiArt.pieces(category: :logos) |> Enum.take(3)
#=> ["c", "clojure", "cpp"]

meta = AsciiArt.meta!("spinners")
{meta.cols, meta.rows, meta.fps}
#=> {66, 13, 12}

meta.options
#=> %{labels: true, names: [], speed: 1}
```

The fourteen categories are in `AsciiArt.Meta.categories/0`. Scenes are
large coloured pictures (200×100 cells); logos and distros are coloured
marks; everything else is text in one ink.

## One frame

`AsciiArt.render!/3` draws a single frame from a fresh start: the quickest way
to put a picture somewhere.

```elixir
IO.puts(AsciiArt.render!("donut", 1.5))

{:ok, text} = AsciiArt.render("big-text", 0.0, options: %{text: "elixir"})
String.split(text, "\n") |> length()
#=> 8
```

Frame 0 is designed upstream to be a good still: it is what a reader who
prefers reduced motion sees. `AsciiArt.still/2` draws it once and keeps it,
for pieces at their default options: a scene takes up to a second to set
up, and after the first time its still is there at once.

```elixir
{:ok, frame} = AsciiArt.still("night-coast")
{frame.cols, frame.rows}
#=> {200, 100}
```

## Playing a piece

Many pieces keep state between frames (a simulation steps by how far `t`
moved since the last frame), so to play one, make an animation and move
forward through time with `AsciiArt.frame/3`, keeping the animation each
call returns:

```elixir
{:ok, anim} = AsciiArt.new("matrix-rain")

{frames, _anim} =
  Enum.map_reduce(0..9, anim, fn i, anim ->
    AsciiArt.frame(anim, i / anim.fps)
  end)

Enum.map(frames, & &1.t) |> Enum.take(3)
#=> [0.0, 0.05, 0.1]
```

Or take frames from a lazy stream, one every `1/fps` seconds:

```elixir
AsciiArt.stream!("spinners", fps: 12)
|> Stream.map(& &1.text)
|> Enum.take(24)
|> length()
#=> 24
```

For real-time playback (a frame on screen every `1/fps` of a second) use
`AsciiArt.Player`; see the [terminal guide](terminal.md).

## Loops

Sixty pieces, every logo among them, close a loop: after `meta.loop` seconds
their frames come round again exactly. `AsciiArt.loop/1` draws one cycle,
which you can then repeat for nothing rather than draw every frame anew:

```elixir
AsciiArt.meta!("elixir").loop
#=> 5

{:ok, frames, fps} = AsciiArt.new!("elixir") |> AsciiArt.loop()
{length(frames), fps}
#=> {150, 30}

AsciiArt.new!("donut") |> AsciiArt.loop()
#=> :error
```

Options can change a period (a logo shines every `shine` seconds), so with
anything but the defaults `loop/1` draws a second cycle to check, and gives
`:error` when it does not match. The LiveView player sends a loop to the
browser once and is then idle; see the [Phoenix guide](phoenix.md).

## What a frame holds

An `AsciiArt.Frame` is plain data, for any renderer:

  * `text`: the picture, lines joined by `\n`; `lines`: the same, as a list;
  * `cols`, `rows`: its size in cells; `cell`: a cell's height in cell widths
    (2, the shape of a character, or 1 for square-celled scenes);
  * `colors`: for a coloured piece drawn in colour, a binary of
    `cols * rows` bytes, one palette index a cell, row by row; otherwise `nil`;
  * `palette`: the `#rrggbb` colours those indices point into;
  * `ground`: the colour behind a scene, or `nil`;
  * `t`: the time it was drawn at.

```elixir
{frame, _anim} = AsciiArt.new!("elixir") |> AsciiArt.frame(0.0)
byte_size(frame.colors) == frame.cols * frame.rows
#=> true

AsciiArt.Frame.color_at(frame, 20, 14)
#=> "#816a92"
```

## Options

Each piece takes the options in its meta. Whatever you pass is checked against
those defaults before the piece sees it: keys must be the piece's own, values
must be of the same kind, numbers are clamped to sane bounds, and strings from
params are cast. Nothing from outside ever becomes an atom, so it is safe to
pass params straight through.

```elixir
{:ok, _} = AsciiArt.new("typewriter", options: %{"prefix" => "we make ", "phrases" => ["tools."]})
{:ok, _} = AsciiArt.new("spinners", options: %{"speed" => "2"})

AsciiArt.new("typewriter", options: %{"evil" => 1})
#=> {:error, {:invalid_option, "evil"}}

AsciiArt.new("no-such-piece")
#=> {:error, :unknown_piece}
```

## Live data

Most pieces are art, but the UI and data ones are also widgets: give them
your own data and they draw it, for a dashboard, a status page or a terminal
UI. `AsciiArt.put_options/2` takes new options while a piece plays, checked
and merged over its own, and pieces that can carry on from where they were
(a gauge's needle swings to a new reading, bars ease to new values):

```elixir
anim = AsciiArt.new!("gauge", options: %{label: "cpu", value: 35})
{frame, anim} = AsciiArt.frame(anim, 0.0)
frame.text =~ "35%"
#=> true

anim = AsciiArt.put_options!(anim, value: 80)
{frame, _anim} = AsciiArt.frame(anim, 0.5)
frame.text =~ "80%"
#=> true
```

| piece | your data | its size |
| --- | --- | --- |
| `progress-bar` | `values`, percentages; `labels`, `style` | `cols`; two rows a bar |
| `spinners` | `names`, the ones to show | shrinks to fit them |
| `sparkline` | `series`, each with its `values` | `cols`, `rows` |
| `gauge` | `value`, with `min`, `max`, `unit` | |
| `bar-chart` | `datasets`, `labels`, `title` | `cols` |
| `cpu-meters` | `cores`, `memory`, `swap`, `load`, `tasks`, `uptime`, `processes` | grows with cores |
| `uptime-bar` | `history`, daily uptime per service | `days` |
| `heatmap` | `counts`, daily, up to a `date` | `weeks` |
| `candlesticks` | `candles`, `[open, high, low, close]`; `times` | |
| `equalizer` | `levels`, 0 to 1 a band | |

Each piece's documentation (`AsciiArt.Pieces.Gauge` and so on) has the
details. In Phoenix, `AsciiArt.Phoenix.live_player/1` takes new options
from your assigns as they change; in a terminal, `AsciiArt.Player.set_options/2`. Lists of numbers are checked as numbers, so these can come from
params as JSON, like any option. A piece whose size follows its options
gives frames of that size: always read `frame.cols` and `frame.rows`.

```elixir
{frame, _} =
  "progress-bar"
  |> AsciiArt.new!(options: %{values: [42], labels: ["copying"], cols: 40})
  |> AsciiArt.frame(0.0)

{frame.cols, frame.rows}
#=> {40, 3}
```

## Light pages and one ink

Shaded pieces read their character ramp from the other end on a light page,
so dense characters still mean dark: pass `paper: true`. A coloured piece can
be drawn as text in one ink with `color: false`, for places that cannot show
colour.

```elixir
{:ok, anim} = AsciiArt.new("donut", paper: true)
{:ok, mono} = AsciiArt.new("night-coast", color: false)
{frame, _} = AsciiArt.frame(mono, 0.0)
frame.colors
#=> nil
```

## Pieces that read the clock

`analog-clock`, `digital-clock`, `calendar`, `sundial` and `landscape` show
the real time. They read the system clock in the system's time zone, or a
`DateTime` you pass as `:now`, whose offset sets the local time:

```elixir
now = DateTime.new!(~D[2026-03-14], ~T[15:09:26], "Etc/UTC")
text = AsciiArt.render!("digital-clock", 0.0, now: now)
text =~ "█"
#=> true
```

## Cost

Most pieces draw a frame in well under a millisecond. Scenes are the heavy
ones: up to about 1.2 seconds to set up (`AsciiArt.new/2`) and 2 to 14 ms a
frame. Set a piece up once and keep the animation, rather than calling
`render/3` in a loop. `mix ascii_art.perf` times every piece on your machine.

## Where next

  * [Phoenix and LiveView](phoenix.md): stills, live players, what goes over
    the wire.
  * [Terminal apps](terminal.md): `mix ascii_art.play`, `AsciiArt.Player`,
    ANSI colour, and writing only what changed.
  * [ExRatatui](ex_ratatui.md): a full-screen viewer, and pieces as widgets in
    a ratatui terminal UI.
  * [Livebook](livebook.md): pieces in a notebook.
  * [Nerves](nerves.md): pieces on a device's console, over SSH, or on a display.
  * [Drawing frames yourself](custom-rendering.md): pixels, SVG, anything.
  * [Writing a piece](writing-pieces.md): your own pieces, on the same contract.
