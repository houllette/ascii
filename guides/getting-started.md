# Getting started

AsciiArt is ASCII-art UI components for Elixir, and animated art: the 191
pieces of [ascii.rest](https://ascii.rest), from file trees, gauges and
htop-style meters that draw your own data to scenes and logos. A piece is a
function of time: ask for its picture at `t` seconds and you get a frame,
`rows` lines of `cols` characters, and for coloured pieces a palette colour
for every cell. Everything else in the library, and every integration in
these guides, is built on that: a component is a piece that takes your data
as options (see [Live data](#live-data)) and your colours (see
[Colouring parts](#colouring-parts)).

## Installation

AsciiArt has no required dependencies. Add Phoenix LiveView only if you want
the Phoenix components.

```elixir
# needs: a mix.exs to put it in
def deps do
  [
    {:ascii_art, "~> 0.2"},
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
| `sparkline` | `series`, each with its `values` (to ±10^15; too wide, `17.5M`) | `cols`, `rows` |
| `gauge` | `value`, with `min`, `max`, `unit` | `cols`, `rows` |
| `bar-chart` | `datasets`, `labels`, `title` | `cols` |
| `cpu-meters` | `cores`, `memory`, `swap`, `load`, `tasks`, `uptime`, `processes` | grows with cores |
| `uptime-bar` | `history`, daily uptime per service | `days` |
| `heatmap` | `counts`, daily, up to a `date`; `months`, `weekdays` | `weeks` |
| `candlesticks` | `candles`, `[open, high, low, close]`; `times` | |
| `equalizer` | `levels`, 0 to 1 a band | |
| `radar` | `contacts`, each a `bearing` and `range`; `land` | |
| `boot-log` | `steps`, each `text` and `status` (`ok`, `warn`, `fail`, `busy`); `title` | `cols`, `rows` |
| `terminal` | `history`, commands and their output; `typing` | `cols`, `rows` |
| `file-tree` | `paths` (or `entries`); with `walk: false`, `open` and `cursor` | `cols`, `rows` |
| `form-controls` | `fields` (text, select, radio, checkbox, switch, slider), `buttons`, `focus`, `status` | `cols`; two rows a field |
| `calendar` | `date` to show and select, `marks`; `months`, `weekdays` | `cols`, `rows` |
| `digital-clock` | `timer` (`down` or `up`), `from` seconds, `label` | |

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

## Keys and clicks

A component that can be used takes keys, by ExRatatui's names for them
(`"up"`, `"enter"`, `" "`, a character), and clicks on its cells: a file
tree with `walk: false`, a form of your `fields`, a calendar with a `date`.
`AsciiArt.handle_event/2` gives the piece the event, and it takes up what
changes as new options, so what was chosen is there to read; an event it
has no use for is `:ignore`.

```elixir
calendar = AsciiArt.new!("calendar", options: %{date: "2026-10-08", time: false})
{:ok, calendar} = AsciiArt.handle_event(calendar, {:key, "right"})
{:ok, calendar} = AsciiArt.handle_event(calendar, {:key, "down"})
calendar.options.date
#=> "2026-10-16"

form = %{fields: [%{type: "text", label: "name"}, %{type: "switch", label: "notify"}]}
anim = AsciiArt.new!("form-controls", options: form)
anim = Enum.reduce(~w(a d a), anim, fn key, anim -> elem(AsciiArt.handle_event(anim, {:key, key}), 1) end)
hd(anim.options.fields).text
#=> "ada"

AsciiArt.handle_event(anim, {:key, "f1"})
#=> :ignore
```

`AsciiArt.part_at/4` says what is under a cell: for a click, which file,
which bar, which day. In Phoenix, a player with `interactive` takes the
browser's keys and clicks (see [Phoenix](phoenix.md#keys-and-clicks)); in
ExRatatui, `AsciiArt.ExRatatui.handle_event/3` takes its events; in a
terminal, `mix ascii_art.play --interactive`.

## Words for screen readers

Each component tells what it shows from its data, for a screen reader or a
caption; a piece that plays its own script says what it is. The Phoenix
players and components label their picture with it, and
`AsciiArt.Render.SVG` takes it as a title.

```elixir
AsciiArt.new!("gauge", options: %{label: "load", value: 72}) |> AsciiArt.describe()
#=> "load: 72%"

steps = [%{text: "built", status: "ok"}, %{text: "migrating", status: "busy"}]
AsciiArt.new!("boot-log", options: %{title: "deploy", steps: steps}) |> AsciiArt.describe()
#=> "deploy: 2 steps, 1 ok, 1 running (migrating)"

AsciiArt.new!("donut") |> AsciiArt.describe()
#=> "donut: a lit torus turning on two axes, after donut.c"
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

## Colouring the ink

A piece in one ink, which is most of them, can be given its colour with
`:ink`: one colour for every character, or several for a gradient across the
picture, left to right unless `:gradient` says `:vertical` or `:diagonal`.
Its frames then carry colours like a coloured piece's, so every renderer
shows them in colour where it can (and as plain text in `mode: :mono`). The
characters are exactly the piece's own; a coloured piece keeps its palette
unless drawn with `color: false`. See `AsciiArt.Ink`.

```elixir
{frame, _} = AsciiArt.new!("big-text", ink: ["#ff5f6d", "#ffc371"]) |> AsciiArt.frame(1.0)
{hd(frame.palette), List.last(frame.palette)}
#=> {"#ff5f6d", "#ffc371"}

{frame, _} = AsciiArt.new!("donut", ink: "#7fdbca") |> AsciiArt.frame(0.0)
frame.palette
#=> ["#7fdbca"]
```

On a page, one ink can be a CSS variable, so a piece takes your theme's
colour and follows it into dark mode; a terminal draws the fallback, if it
has one:

```elixir
{frame, _} = AsciiArt.new!("donut", ink: "var(--accent, #7fdbca)") |> AsciiArt.frame(0.0)
frame.palette
#=> ["var(--accent, #7fdbca)"]
```

## Colouring parts

Some pieces know what each of their cells is: a file tree's folders, files
and branches, a boot log's `OK` and `WARN`, a meter's bars and readings.
Their meta lists these `parts`, each with a colour it suggests, and `:parts`
gives them colours: a map of names to colours, or `true` for the suggested
ones. A name covers the names under it, so `file` colours every file and
`file.md` only Markdown. Parts not given a colour take the `:ink`, or the
renderer's own. See `AsciiArt.Parts`.

```elixir
AsciiArt.meta!("boot-log").parts |> Enum.take(5)
#=> [{"title", nil}, {"rule", "#8b949e"}, {"label", nil}, {"detail", nil}, {"status.ok", "#3fb950"}]

{frame, _} =
  AsciiArt.new!("file-tree", parts: %{"folder" => "#58a6ff", "file.md" => "#d29922"})
  |> AsciiArt.frame(3.0)

frame.palette
#=> [nil, "#58a6ff", "#d29922"]
```

The `nil` is the renderer's own ink: a terminal's foreground, a page's
colour. Parts' colours can be CSS variables too, and with `paper: true`
the suggested colours are those for a light page:

```elixir
{frame, _} = AsciiArt.new!("boot-log", parts: true, paper: true) |> AsciiArt.frame(0.0)
"#1a7f37" in frame.palette
#=> true
```

The type pieces (`big-text`, `glitch`, `wave-text`) know their letters, so
a heading can be in your palette a letter at a time: `parts: %{"letter.1" =>
"#ff5f6d", "letter.2" => "#ffc371"}`, or `"letter"` for all of them.

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

  * [Components at a glance](components.md): every component, the data it
    takes, its size, its parts and its keys.
  * [Phoenix and LiveView](phoenix.md): stills, live players, what goes over
    the wire.
  * [Terminal apps](terminal.md): `mix ascii_art.play`, `mix ascii_art.top`,
    `AsciiArt.Player`, ANSI colour, writing only what changed, and panels
    with `AsciiArt.Compose`.
  * [ExRatatui](ex_ratatui.md): a full-screen viewer, and pieces as widgets in
    a ratatui terminal UI.
  * [Livebook](livebook.md): pieces in a notebook.
  * [Nerves](nerves.md): pieces on a device's console, over SSH, or on a display.
  * [Drawing frames yourself](custom-rendering.md): pixels, SVG, anything.
  * [Writing a piece](writing-pieces.md): your own pieces, on the same contract.
