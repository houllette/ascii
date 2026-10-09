# Phoenix and LiveView

The components are LiveView components: a gauge, a sparkline or an
htop-style panel in your dashboard takes its readings from your assigns,
and draws in your colours. With `phoenix_live_view` in your deps, AsciiArt
adds:

  * `AsciiArt.Phoenix.Components.ascii/1` draws one frame as a `<pre>`, with
    no JavaScript: for dead views, controllers, emails and stills;
    `AsciiArt.Phoenix.Components.frame/1` draws a frame you already have;
  * `AsciiArt.Phoenix.player/1` plays a piece live, through a small LiveView
    of its own (`AsciiArt.Phoenix.PlayerLive`), so your LiveView needs no
    timers or `handle_info`;
  * `AsciiArt.Phoenix.live_player/1` plays a piece inside your LiveView
    (`AsciiArt.Phoenix.PlayerComponent`), taking new options as your
    assigns change: for live data;
  * `priv/static/ascii_art_hook.js`, a LiveView hook that lets the browser
    do the drawing, so the server sends a looping piece once and anything
    else only as it changes.

## A still

```heex
<AsciiArt.Phoenix.Components.ascii piece="donut" />
<AsciiArt.Phoenix.Components.ascii piece="donut" t={2.5} paper class="hero" />
<AsciiArt.Phoenix.Components.ascii piece="elixir" label="the Elixir logo" />
<AsciiArt.Phoenix.Components.ascii piece="elixir" mono />
<AsciiArt.Phoenix.Components.ascii piece="big-text" ink={["#ff5f6d", "#ffc371"]} />
<AsciiArt.Phoenix.Components.ascii piece="boot-log" parts={%{"status.warn" => "#d29922"}} />
```

It works in any HEEx template, LiveView or not. A text piece is plain text in
the page's own colour and font, or runs of `<span style="color:…">` in an
`ink` (one colour, or several for a `gradient`; see `AsciiArt.Ink`) and of
colours for its `parts` (`true` for the ones it suggests; see
`AsciiArt.Parts`); a
coloured piece is runs of its palette over its ground (`mono` draws it in one
ink instead).
The `<pre>` is `role="img"` with an `aria-label` (the `label`, or the piece's
name), and carries a few styles that ASCII art needs (no margin, line height
1.2, no ligatures); add your own with `class` or `style`. Attributes it does
not know are passed to the `<pre>`.

Frame 0 is the default `t`, and upstream draws frame 0 to be a good still.
It is drawn once and kept (`AsciiArt.still/2`), so a scene in a template
costs its setup, up to a second, the first time it is shown, and microseconds
after.

## Playing a piece

```heex
<AsciiArt.Phoenix.player socket={@socket} id="spinner" piece="spinners" />
<AsciiArt.Phoenix.player socket={@socket} id="logo" piece="elixir" fps={20} label="Elixir" />
<AsciiArt.Phoenix.player socket={@socket} id="coast" piece="night-coast" render={:server} />
```

`player/1` calls `live_render/3`, so the piece plays in its own process with
its own timer: your LiveView does nothing per frame. Pass the parent's socket
(or the `conn` in a dead view). Before the page connects it shows frame 0,
whole, so a page without JavaScript still shows the picture; once connected it
plays, with play time moving as upstream's does (real time, at most 100 ms a
frame).

Its attributes: `piece`, `id` (unique on the page), `options`, `fps`, `mono`,
`ink`, `gradient`, `parts`, `paper`, `label`, and `render`. A piece in an
`ink`, or with colours for its `parts`, plays as text in spans of its
colours, the size it would be in one ink. `piece` is a slug or a module of your own
(see [Writing a piece](writing-pieces.md)).

## What goes over the wire

With the hook registered (`render={:client}`, the default), the browser
draws: a text piece in its `<pre>`, a coloured one on a `<canvas>` in its
palette over its ground. What the server sends depends on the piece:

  * **A closed loop** (60 pieces, among them every logo; see
    `AsciiArt.loop/1`) is drawn for one cycle and sent once, compressed:
    a logo is 5 to 12 KB, the longest loop under half a megabyte. The browser
    plays it from then on, and the server does nothing more for it.
  * **Anything else** is drawn on the server at its frame rate, and each
    frame sends only the runs of cells that changed, or nothing at all when
    the picture did not. A 200×100 scene changes a few cells in a hundred a
    frame, so it sends a few kilobytes a frame rather than forty.

Either way, play stops while the picture is off screen or its tab hidden
(the server stops drawing too), and readers who prefer reduced motion keep
frame 0. Each player's events are its own, so any number can share a page.

Without the hook, or with `render={:server}`, the server draws and LiveView
patches the `<pre>` a row at a time: only rows that changed are sent, and
nothing for a frame that did not change, and a loop is drawn once and
replayed. That needs no JavaScript of ours, but it sends HTML: fine for text
pieces and logos, heavy for scenes, and it plays on out of sight, since the
server cannot tell. A player whose hook does not answer within two seconds
falls back to this.

## The hook

Register it with your LiveSocket in `assets/js/app.js`:

```js
import {AsciiArt} from "../../deps/ascii_art/priv/static/ascii_art_hook.js"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {AsciiArt},
  params: {_csrf_token: csrfToken},
})
```

If you already have hooks, add it to them: `hooks: {...Hooks, AsciiArt}`.

## Options from params

`options` are checked against the piece's defaults before it sees them (see
`AsciiArt.Options`): unknown keys and values of the wrong kind are refused,
numbers are clamped, strings are cast where the default is a number or a
boolean. No atom is ever created. So a query string can go straight to the
player:

```elixir
# needs: a Phoenix app
def mount(params, _session, socket) do
  {:ok, assign(socket, piece: Map.get(params, "piece", "donut"), options: Map.get(params, "o", %{}))}
end
```

```heex
<AsciiArt.Phoenix.player socket={@socket} id="art" piece={@piece} options={@options} />
```

An unknown piece or a refused option shows a short `role="alert"` message in
place of the picture rather than crashing your page.

`player/1` takes its options when it mounts; to change them, give it a new
`id`, and LiveView starts a fresh player. For options that change while it
plays, use `live_player/1` (below).

## Live data

The UI and data pieces take readings as options (see
[Live data](getting-started.md#live-data)): a gauge's `value`, a sparkline's
samples, an htop panel's cores. `live_player/1` plays a piece inside your
LiveView, and each time your LiveView renders it with other options, the
piece takes them up as it plays: the gauge's needle swings from the last
reading to the new one, bars ease to new values, a sparkline scrolls on.

```elixir
# needs: a Phoenix app
def mount(_params, _session, socket) do
  if connected?(socket), do: :timer.send_interval(1000, :sample)
  {:ok, assign(socket, load: 0, samples: [])}
end

def handle_info(:sample, socket) do
  load = :erlang.statistics(:total_run_queue_lengths)
  {:noreply, assign(socket, load: load, samples: Enum.take(socket.assigns.samples ++ [load], -60))}
end
```

```heex
<AsciiArt.Phoenix.live_player id="load" piece="gauge" options={%{label: "run queue", max: 20, value: @load}} />
<AsciiArt.Phoenix.live_player
  id="history"
  piece="sparkline"
  options={%{series: [%{label: "run queue", values: @samples}], range: false, rows: 3}}
/>
```

It plays as `player/1` does, with the same hook and the same economy: what
goes over the wire is the cells that change, nothing while out of sight.
Options of the same size are sent as changes at the next frame; a piece
whose size follows its options (more bars, a longer sparkline) is sent
whole at its new size; another `piece`, `fps`, `paper`, `mono` or `render`
starts it afresh. Its attributes are `player/1`'s, less `socket`.

The difference is where it runs: in your LiveView's process, beside the
state its options come from. That suits widgets, which draw in well under a
millisecond a frame. A 200×100 scene costs milliseconds a frame, which your
LiveView would spend between its own events: play scenes with `player/1`.

`examples/demo.exs` has a dashboard of this BEAM's schedulers, memory, run
queue and busiest processes, every widget a `live_player/1` fed by
`AsciiArt.BEAM` (`elixir examples/demo.exs`, then open
http://localhost:4000/dashboard).

### From telemetry

`AsciiArt.Telemetry` keeps your app's `:telemetry` events as readings, a
sample a second, from the same `Telemetry.Metrics` definitions a reporter
takes, and sends them to whoever subscribes:

```elixir
# needs: a Phoenix app; in application.ex
children = [
  {AsciiArt.Telemetry,
   name: MyApp.Readings,
   metrics: [
     Telemetry.Metrics.last_value("vm.memory.total", unit: {:byte, :megabyte}),
     Telemetry.Metrics.summary("my_app.repo.query.total_time", unit: {:native, :millisecond})
   ]}
]
```

```elixir
# needs: a Phoenix app
def mount(_params, _session, socket) do
  if connected?(socket), do: AsciiArt.Telemetry.subscribe(MyApp.Readings)
  {:ok, assign(socket, history: %{})}
end

def handle_info({:ascii_art_telemetry, _feed, readings}, socket),
  do: {:noreply, assign(socket, history: AsciiArt.Telemetry.sparkline(readings))}
```

```heex
<AsciiArt.Phoenix.live_player id="history" piece="sparkline" options={@history} parts />
```

## Keys and clicks

A component that can be used (a file tree with `walk: false`, a form of
your `fields`, a calendar with a `date`; see
[Keys and clicks](getting-started.md#keys-and-clicks)) takes the browser's
keys and clicks in a player given `interactive`. Its picture takes focus;
arrows, space, enter and typing go to the piece, which moves its cursor,
ticks its box or picks its day, and what changed is sent at once. Tab is
left to the page, so focus moves on as ever; ctrl, alt and meta keys are the
browser's. Clicks need the hook, which works out the cell clicked; without
it (`render={:server}`) keys still come, by `phx-keydown`.

With `notify` as well, your LiveView is told of each key and click as
`{:ascii_art, id, info}`: the event, the part clicked and its text (see
`AsciiArt.part_at/4`), and the options the piece now has, from which to read
what was chosen.

```heex
<AsciiArt.Phoenix.live_player
  id="files"
  piece="file-tree"
  options={%{walk: false, paths: @paths, root: "my_app"}}
  interactive
  notify
/>
```

```elixir
# needs: a Phoenix app
def handle_info({:ascii_art, "files", %{event: {:key, "enter"}, options: %{cursor: path}}}, socket),
  do: {:noreply, assign(socket, open: path)}

def handle_info({:ascii_art, "files", %{event: {:click, _x, _y}, part: "file" <> _, options: options}}, socket),
  do: {:noreply, assign(socket, open: options.cursor)}

def handle_info({:ascii_art, _id, _info}, socket), do: {:noreply, socket}
```

The options you give `live_player/1` are merged over what the piece's
events changed, so leave out those it keeps (a tree's `cursor` and `open`, a
form's `focus`) unless you mean to set them. `player/1` takes `interactive`
and `notify` too, telling the LiveView that embeds it.

Every player and still is labelled for screen readers with what the piece
tells of its data (`AsciiArt.describe/1`): "load: 72%", "deploy: 6 steps, 1
failed", and anew as the data changes. `label` gives your own words
instead.

## In a controller or a dead view

`ascii/1` works in any template. To build markup yourself, say for an email
or a static page, `AsciiArt.Render.HTML` gives the inside of the `<pre>`,
already escaped:

```elixir
{frame, _} = AsciiArt.new!("elixir") |> AsciiArt.frame(0.0)
inner = AsciiArt.Render.HTML.render(frame)
style = AsciiArt.Render.HTML.style(frame)

html = ["<pre style=\"", style || "", "\">", inner, "</pre>"] |> IO.iodata_to_binary()
html =~ "<span style=\"color:#"
#=> true
```

## Performance

Each `player/1` is a process. For a loop it draws one cycle, in a task, and
is then idle. For anything else it draws a frame each tick while the picture
is in view: text pieces in well under a millisecond, scenes in 2 to 14 ms,
after up to 1.2 s to set up when the player connects. The HTML sent before
it connects is frame 0, kept from the first time, so that costs nothing. A page of many scenes in
view at once is a lot of server work: show stills (`ascii/1`) and play on
demand, or, when many people watch the same piece, play it once for all of
them (below).

## One player, many viewers

`player/1` gives every viewer a process and an animation of their own. For a
piece everyone sees alike, say a logo in the site's header, play it once
under your application's supervisor:

```elixir
# needs: a Phoenix app; in application.ex
children = [
  # ...
  {AsciiArt.Player, piece: "elixir", name: MyApp.Logo}
]
```

Each LiveView takes the latest frame for its first render, and subscribes
once connected:

```elixir
# needs: a Phoenix app
def mount(_params, _session, socket) do
  if connected?(socket), do: AsciiArt.Player.subscribe(MyApp.Logo)
  {:ok, assign(socket, frame: AsciiArt.Player.frame(MyApp.Logo))}
end

def handle_info({:ascii_art_frame, _ref, frame}, socket), do: {:noreply, assign(socket, frame: frame)}
```

```heex
<AsciiArt.Phoenix.Components.frame frame={@frame} label="the Elixir logo" />
```

`frame/1` draws it as `ascii/1` draws a piece, a row an element, so as the
frame changes LiveView sends only the rows that did.

A supervised player sends frames only to its subscribers, never to the
supervisor, and drops each LiveView as it exits. While no one is watching it
holds its frame and does no work. Give it readings with
`AsciiArt.Player.set_options/2` and every viewer sees the needle swing. To
share one player across a cluster, give it a `:callback` that broadcasts
each frame with `Phoenix.PubSub`.

## A whole app

`examples/demo.exs` in this repository is a gallery of every piece as a
one-file Phoenix app: an index of stills, a page per piece that plays it
with switches for paper and one ink and a form for its options, and a live
dashboard of the BEAM it runs on.

```sh
elixir examples/demo.exs   # then open http://localhost:4000
```
