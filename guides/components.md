# Components at a glance

The UI, data and type pieces are components: they draw your data, in your
colours, and the ones that can be used take keys and clicks. Each one's
documentation has the same sections: its **Options**, its **Colours** part
by part, the **Keys and clicks** it takes (or that it takes none), what it
tells **Screen readers**, and an **Example**. This page is the map.

## What every component shares

  * **Your data as options**, checked against the piece's defaults, given to
    `AsciiArt.new/2` and taken up while it plays with `AsciiArt.put_options/2`
    (or a Phoenix player's `options`). Pieces that can carry on from where
    they were do: a gauge's needle swings, bars ease, a terminal keeps
    typing. See [Live data](getting-started.md#live-data).
  * **Your colours**: one ink or a gradient (`:ink`, `:gradient`, see
    `AsciiArt.Ink`), and part by part (`:parts`, see `AsciiArt.Parts`),
    `parts: true` for the colours each suggests, or for a light page with
    `paper: true`. On a page, colours can be CSS variables.
  * **Keys and clicks** for those that can be used
    (`AsciiArt.handle_event/2`), with what was chosen in their options; in
    Phoenix a player's `interactive` (and `notify` to be told), in
    ExRatatui `AsciiArt.ExRatatui.handle_event/3`, in a terminal
    `mix ascii_art.play --interactive`. `AsciiArt.part_at/4` says which part
    is under a click, on any piece that knows its parts.
  * **Words for screen readers** from their data (`AsciiArt.describe/1`),
    which the Phoenix players and components use as their label.
  * **Frames like any piece's**: into panels and layouts with
    `AsciiArt.Compose`, out as ANSI, HTML or SVG.

## The components

"size" says which options set the frame's size; "parts" how many parts it
colours one by one; "keys" whether it takes keys and clicks.

| component | your data | size | parts | keys |
| --- | --- | --- | --- | --- |
| `AsciiArt.Pieces.BootLog` | `steps` (ok, warn, fail, busy), `title` | `cols`, `rows` | 18 | |
| `AsciiArt.Pieces.BoxFrames` | (a sheet of frame styles; see `AsciiArt.Compose.panel/2` for yours) | | | |
| `AsciiArt.Pieces.Calendar` | `date`, `marks`, `months`, `weekdays`, `monday`, `time` | `cols`, `rows` | 11 | with a `date` |
| `AsciiArt.Pieces.DigitalClock` | `timer`, `from`, `label`, `hour12`, `seconds`, `date` | | 7 | |
| `AsciiArt.Pieces.Dividers` | `width` (see `AsciiArt.Compose.divider/2` for one of yours) | | | |
| `AsciiArt.Pieces.FileTree` | `paths` or `entries`, `root`; `walk`, `open`, `cursor` | `cols`, `rows` | 14 | with `walk: false` |
| `AsciiArt.Pieces.FormControls` | `fields`, `buttons`, `focus`, `status`, `title` | `cols`; two rows a field | 23 | with `fields` |
| `AsciiArt.Pieces.NotFound` | `code`, `title`, `message` | | | |
| `AsciiArt.Pieces.ProgressBar` | `values`, `labels`, `style` | `cols`; two rows a bar | 7 | |
| `AsciiArt.Pieces.Skeleton` | `lines`, `image`, `avatar` | | | |
| `AsciiArt.Pieces.Spinners` | `names`, `labels`, `speed` | fits the spinners shown | | |
| `AsciiArt.Pieces.Terminal` | `history`, `typing`, `prompt`, `title` | `cols`, `rows` | 8 | |
| `AsciiArt.Pieces.BarChart` | `datasets`, `labels`, `title` | `cols` | 9 | |
| `AsciiArt.Pieces.Candlesticks` | `candles`, `times`, `start`, `digits`, `seed` | | 9 | |
| `AsciiArt.Pieces.CpuMeters` | `cores`, `memory`, `swap`, `load`, `tasks`, `uptime`, `processes`, `commands` | grows with cores | 15 | |
| `AsciiArt.Pieces.Equalizer` | `levels`, `bpm` | | 7 | |
| `AsciiArt.Pieces.Gauge` | `value`, `label`, `unit`, `min`, `max` | `cols`, `rows` | 11 | |
| `AsciiArt.Pieces.Heartbeat` | `bpm` | | | |
| `AsciiArt.Pieces.Heatmap` | `counts`, `date`, `unit`, `months`, `weekdays`, `seed` | `weeks` | 9 | |
| `AsciiArt.Pieces.Radar` | `contacts`, `range`, `unit`, `land` | | 9 | |
| `AsciiArt.Pieces.Sparkline` | `series`, `range`, `rate` | `cols`, `rows` | 14 | |
| `AsciiArt.Pieces.UptimeBar` | `history`, `services` | `days` | 13 | |
| `AsciiArt.Pieces.BigText` | `text` | | per letter | |
| `AsciiArt.Pieces.Dissolve` | `words` | | | |
| `AsciiArt.Pieces.Glitch` | `text` | | per letter | |
| `AsciiArt.Pieces.Marquee` | `text`, `speed` | | 4 | |
| `AsciiArt.Pieces.Morse` | `text` | | | |
| `AsciiArt.Pieces.Scramble` | `phrases` | | | |
| `AsciiArt.Pieces.SplitFlap` | `flights`, `title`, `start` | | 16 | |
| `AsciiArt.Pieces.Typewriter` | `phrases`, `prefix` | | 3 | |
| `AsciiArt.Pieces.WaveText` | `text`, `amp`, `wavelength`, `speed`, `spacing`, `settle` | | per letter | |

Fed from your app: `AsciiArt.BEAM` gives options for `cpu-meters`,
`sparkline`, `gauge` and `progress-bar` from this VM, and
`AsciiArt.Telemetry` for `sparkline` and `gauge` from your `:telemetry`
events.

## One of each

```elixir
board = [
  {"gauge", %{label: "load", value: 72}},
  {"boot-log", %{title: "deploy", steps: [%{text: "built", status: "ok"}]}},
  {"file-tree", %{walk: false, paths: ["lib/app.ex", "mix.exs"], root: "app"}}
]

for {piece, options} <- board do
  piece |> AsciiArt.new!(options: options, parts: true) |> AsciiArt.describe()
end
#=> ["load: 72%", "deploy: 1 step, 1 ok", "file tree of app: 1 folder, 2 files"]
```
