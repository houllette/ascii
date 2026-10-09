# Components at a glance

The UI, data and type pieces are components: they draw your data, in your
colours, and the ones that can be used take keys and clicks. Each one's
documentation has the same sections: its **Options**, its **Colours** part
by part, the **Keys and clicks** it takes (or that it takes none), what it
tells **Screen readers**, and an **Example**. This page is the map.

## What every component shares

  * **Your data as options**, checked against the piece's defaults, given to
    `Ascii.new/2` and taken up while it plays with `Ascii.put_options/2`
    (or a Phoenix player's `options`). Pieces that can carry on from where
    they were do: a gauge's needle swings, bars ease, a terminal keeps
    typing. See [Live data](getting-started.md#live-data).
  * **Your colours**: one ink or a gradient (`:ink`, `:gradient`, see
    `Ascii.Ink`), and part by part (`:parts`, see `Ascii.Parts`),
    `parts: true` for the colours each suggests, or for a light page with
    `paper: true`. On a page, colours can be CSS variables.
  * **Keys and clicks** for those that can be used
    (`Ascii.handle_event/2`), with what was chosen in their options; in
    Phoenix a player's `interactive` (and `notify` to be told), in
    ExRatatui `Ascii.ExRatatui.handle_event/3`, in a terminal
    `mix ascii.play --interactive`. `Ascii.part_at/4` says which part
    is under a click, on any piece that knows its parts.
  * **Words for screen readers** from their data (`Ascii.describe/1`),
    which the Phoenix players and components use as their label.
  * **Frames like any piece's**: into panels and layouts with
    `Ascii.Compose`, out as ANSI, HTML or SVG.

## The components

"size" says which options set the frame's size; "parts" how many parts it
colours one by one; "keys" whether it takes keys and clicks.

| component | your data | size | parts | keys |
| --- | --- | --- | --- | --- |
| `Ascii.Pieces.BootLog` | `steps` (ok, warn, fail, busy), `title` | `cols`, `rows` | 18 | |
| `Ascii.Pieces.BoxFrames` | (a sheet of frame styles; see `Ascii.Compose.panel/2` for yours) | | | |
| `Ascii.Pieces.Calendar` | `date`, `marks`, `months`, `weekdays`, `monday`, `time` | `cols`, `rows` | 11 | with a `date` |
| `Ascii.Pieces.DigitalClock` | `timer`, `from`, `label`, `hour12`, `seconds`, `date` | | 7 | |
| `Ascii.Pieces.Dividers` | `width` (see `Ascii.Compose.divider/2` for one of yours) | | | |
| `Ascii.Pieces.FileTree` | `paths` or `entries`, `root`; `walk`, `open`, `cursor` | `cols`, `rows` | 14 | with `walk: false` |
| `Ascii.Pieces.FormControls` | `fields`, `buttons`, `focus`, `status`, `title` | `cols`; two rows a field | 23 | with `fields` |
| `Ascii.Pieces.NotFound` | `code`, `title`, `message` | | | |
| `Ascii.Pieces.ProgressBar` | `values`, `labels`, `style` | `cols`; two rows a bar | 7 | |
| `Ascii.Pieces.Skeleton` | `lines`, `image`, `avatar` | | | |
| `Ascii.Pieces.Spinners` | `names`, `labels`, `speed` | fits the spinners shown | | |
| `Ascii.Pieces.Terminal` | `history`, `typing`, `prompt`, `title` | `cols`, `rows` | 8 | |
| `Ascii.Pieces.BarChart` | `datasets`, `labels`, `title` | `cols` | 9 | |
| `Ascii.Pieces.Candlesticks` | `candles`, `times`, `start`, `digits`, `seed` | | 9 | |
| `Ascii.Pieces.CpuMeters` | `cores`, `memory`, `swap`, `load`, `tasks`, `uptime`, `processes`, `commands` | grows with cores | 15 | |
| `Ascii.Pieces.Equalizer` | `levels`, `bpm` | | 7 | |
| `Ascii.Pieces.Gauge` | `value`, `label`, `unit`, `min`, `max` | `cols`, `rows` | 11 | |
| `Ascii.Pieces.Heartbeat` | `bpm` | | | |
| `Ascii.Pieces.Heatmap` | `counts`, `date`, `unit`, `months`, `weekdays`, `seed` | `weeks` | 9 | |
| `Ascii.Pieces.Radar` | `contacts`, `range`, `unit`, `land` | | 9 | |
| `Ascii.Pieces.Sparkline` | `series`, `range`, `rate` | `cols`, `rows` | 14 | |
| `Ascii.Pieces.UptimeBar` | `history`, `services` | `days` | 13 | |
| `Ascii.Pieces.BigText` | `text` | | per letter | |
| `Ascii.Pieces.Dissolve` | `words` | | | |
| `Ascii.Pieces.Glitch` | `text` | | per letter | |
| `Ascii.Pieces.Marquee` | `text`, `speed` | | 4 | |
| `Ascii.Pieces.Morse` | `text` | | | |
| `Ascii.Pieces.Scramble` | `phrases` | | | |
| `Ascii.Pieces.SplitFlap` | `flights`, `title`, `start` | | 16 | |
| `Ascii.Pieces.Typewriter` | `phrases`, `prefix` | | 3 | |
| `Ascii.Pieces.WaveText` | `text`, `amp`, `wavelength`, `speed`, `spacing`, `settle` | | per letter | |

Fed from your app: `Ascii.BEAM` gives options for `cpu-meters`,
`sparkline`, `gauge` and `progress-bar` from this VM, and
`Ascii.Telemetry` for `sparkline` and `gauge` from your `:telemetry`
events.

## One of each

```elixir
board = [
  {"gauge", %{label: "load", value: 72}},
  {"boot-log", %{title: "deploy", steps: [%{text: "built", status: "ok"}]}},
  {"file-tree", %{walk: false, paths: ["lib/app.ex", "mix.exs"], root: "app"}}
]

for {piece, options} <- board do
  piece |> Ascii.new!(options: options, parts: true) |> Ascii.describe()
end
#=> ["load: 72%", "deploy: 1 step, 1 ok", "file tree of app: 1 folder, 2 files"]
```
