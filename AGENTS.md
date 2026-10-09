# Agent Guidelines

## Project overview

`ascii` is an Elixir port of the [bas3line/ascii](https://github.com/bas3line/ascii)
library (ascii.rest) — "animated ascii art for web pages". Upstream is a
TypeScript package of roughly 170–190 animated pieces (scenes, UI elements,
charts, text effects, logos, 3D shapes, physics, generative patterns) that mount
into a `<pre>` or `<canvas>` via `mount/3`, React/Astro components, or an
`<ascii-art>` custom element.

This is a plain library (`mix new`, no supervision tree, no web layer). The
browser/DOM half of upstream has no Elixir equivalent, so the port is aimed at
producing frames as pure data that a consumer (e.g. a future LiveView
component) can render. Upstream's `load`/`names`/`isPiece` helpers are the model
for the piece registry API.

## Commands

Everything below is bundled into one alias. **Run `mix precommit` when you
think you're done** — it runs the same checks CI runs, so a green `precommit`
means a green PR.

| Task | Command |
| --- | --- |
| Everything (run this before you're done) | `mix precommit` |
| Install deps | `mix deps.get` |
| Compile (warnings are errors in CI) | `mix compile --warnings-as-errors` |
| Run all tests | `mix test` |
| Run one test file | `mix test test/path/to/file_test.exs` |
| Run one test | `mix test test/path/to/file_test.exs:LINE` |
| Format | `mix format` |
| Lint | `mix credo --strict` |
| Compile-time dependency check | `mix xref graph --label compile-connected --fail-above 0` |
| Type check (slow; runs in CI, not in `precommit`) | `mix dialyzer` |
| Dependency vulnerabilities | `mix deps.audit` |
| Retired packages | `mix hex.audit` |
| Start Tidewave MCP server (dev) | `mix tidewave` |
| Refresh AGENTS.md usage rules | `mix usage_rules.sync --yes` |
| Check those rules are current | `mix usage_rules.sync --check` |
| Search dependency docs | `mix usage_rules.search_docs "term" -p package` |

Some of these only exist once the matching dep is installed; the `precommit`
alias in `mix.exs` is the authoritative list for this project.

## Conventions

- **Run `mix precommit` before declaring work finished.** Fix what it reports
  rather than narrowing the check or adding a suppression. If a check is
  genuinely wrong for this project, change the config in a separate commit and
  say why.
- **Format before committing.** CI enforces `mix format --check-formatted`.
- **No compiler warnings.** CI compiles with `--warnings-as-errors`, and tests
  run with `--warnings-as-errors` too — test files are held to the same bar.
- **Test-first when practical.** Add or update an ExUnit test that captures the
  behavior change, watch it fail, then implement. Use `async: true` in test
  modules unless they share global state (named processes, the database outside
  the SQL sandbox, Application env).
- **A test must be able to fail.** No test without an assertion, and no
  assertion that holds regardless of the code under test (`assert x == x`,
  or `assert is_map(result)` where every return value passes). If you can't
  write an assertion that would have failed before the change, the test isn't
  earning its keep.
- **Don't add dependencies to solve small problems.** The standard library
  covers date and time (`Date`, `Time`, `DateTime`, `Calendar`), and every new
  dep is one more thing CI has to audit. Ask before adding one.
- **Pattern match at function heads** rather than with nested `case`/`cond`
  where it reads naturally; use `with` for chains of fallible calls. Never
  write a `case` whose only clauses are `true` and `false` — that's an `if`.
- **Let it crash where appropriate.** Don't defensively rescue exceptions in
  supervised processes; reserve `try/rescue` for genuine boundary concerns.
  Never `rescue` an exception only to log it and continue.
- **Typespecs on public functions** of library-style modules; Dialyzer runs in
  CI when `dialyxir` is installed. Name the arguments in the spec —
  `@spec fetch(user_id :: integer()) :: {:ok, t()} | {:error, term()}`.
- **Keep runtime deps out of compile time.** `mix xref graph --label
  compile-connected --fail-above 0` fails the build when a module edit starts
  triggering wide recompiles. The fix is usually to stop invoking a macro or
  referencing a struct at compile time across a context boundary.
- **Don't edit generated or vendored files** (`deps/`, `_build/`,
  `priv/static/assets/`, migration files that have already shipped).
- **If this repo has both `.github/workflows/` and `.forgejo/workflows/`,
  they are not copies.** The Forgejo one installs the BEAM by hand, references
  actions by full URL, and reaches services by container name — every
  difference is deliberate and documented in README.md. When you change one
  pipeline, decide consciously whether the other needs the same change; don't
  mirror it mechanically. Note that `actionlint` cannot check the Forgejo file,
  so verify edits there by hand.

## Porting rules for this project

- **Every piece is exact.** A piece's frames must equal upstream's, byte for
  byte, text and colours; `test/pieces/<slug>_test.exs` (GoldenCase and
  ContractCase) checks it. Read `PORTING.md` before touching a piece: it has
  the hazards and the speed techniques that keep results exact.
- **JS numbers go through `Ascii.JSMath` and `Ascii.Int32`** where
  they differ from Elixir's (`Math.round`, `%`, `Math.fround`, typed-array
  stores, `Math.hypot`, `Math.cbrt`, `Math.log1p`, number formatting,
  32-bit operators), never raw `Bitwise` on JS values or Elixir's `round/1`.
  Transcendental functions (`sin`, `exp`, `pow`, `atan2`, ...) are
  `:math`. Certified fast paths, cheaper guesses checked against the plain
  path, need a test holding them to it (`exact?` switches, reference ports
  in test files).
- **Fixtures come from upstream**, regenerated with
  `NODE=<x64 node> mix ascii.golden` (see `UPSTREAM.md`); never edit them.
- **Generated files**: the registry map (`mix run tools/gen_registry.exs`),
  the README pieces table (`mix run tools/readme_pieces.exs`) and
  `PORT_STATUS.md` (`mix run tools/port_status.exs`). Tests fail when the
  first two are stale.
- `mix ascii.perf [slug]` times pieces against upstream's budgets;
  `mix test --only perf` fails any piece over three times its budget.

## Library guidelines

The generated usage-rules block at the very end of this file is **generated
from the installed dependencies** by `mix usage_rules.sync`. Never hand-edit
inside it: the next sync overwrites it, and CI fails when the block is out of
date. Put your own guidance above it instead. After changing dependencies, run
`mix usage_rules.sync --yes` and commit the result.

That task prompts for confirmation, so it hangs if you run it bare in a
non-interactive shell. Always pass `--yes` (write the changes) or `--check`
(exit non-zero if stale, without writing).

## Versions

Erlang/Elixir versions are pinned in `.tool-versions` (used by asdf/mise
locally and by `erlef/setup-beam` in CI). Bump versions there, nowhere else.

<!-- usage-rules-start -->
<!-- ex_ratatui-start -->
## ex_ratatui usage
_Elixir bindings for the Rust ratatui terminal UI library_

# ExRatatui Usage Rules

ExRatatui is Elixir bindings for the Rust [ratatui](https://ratatui.rs) terminal UI library, via Rustler NIFs. It builds rich terminal UIs that run on the BEAM's DirtyIo scheduler, so rendering never blocks application processes.

It is **not** the Rust ratatui API and **not** bubbletea. Widgets are plain Elixir structs (pure view descriptors), assembled each frame and handed to a draw/render function. There are no stateful widget objects that update in place.

## Choosing a runtime

Pick the runtime before writing any code — this is the single most important decision and the easiest to get wrong.

| Use | When | Shape |
|-----|------|-------|
| `ExRatatui.run/2` | Scripts, one-shots, examples, throwaway demos | A closure that draws and polls events itself |
| `use ExRatatui.App` | Supervised interactive apps (the default) | LiveView-style `mount/1`, `render/2`, `handle_event/2`, `handle_info/2` |
| `use ExRatatui.App, runtime: :reducer` | Apps wanting pure transitions, declarative timers, and managed side effects | `init/1`, `update/2`, `render/2`, `subscriptions/1` + `Command`/`Subscription` |

- The callback runtime is the default and fits most apps. Reach for the reducer runtime when modeling the app as `(msg, state) -> state` with `Command`-driven effects and `Subscription`-driven timers is worth the structure.
- Both `App` runtimes are supervised: add `{MyApp.TUI, opts}` to a supervision tree. Never hand-roll the loop with `run/2` for a long-lived interactive app.

## Core API shape

Canonical entry points for a raw `run/2` loop — match these signatures exactly, do not invent Rust- or bubbletea-shaped calls:

```elixir
# fun receives a terminal reference; terminal is restored on exit, even on raise
ExRatatui.run(fn terminal ->
  {width, height} = ExRatatui.terminal_size()

  # draw/2 takes a LIST of {widget_struct, %Rect{}} tuples — a bare widget draws nothing
  ExRatatui.draw(terminal, [
    {%ExRatatui.Widgets.Paragraph{text: "hi"},
     %ExRatatui.Layout.Rect{x: 0, y: 0, width: width, height: height}}
  ])

  ExRatatui.poll_event(60_000)
end, mouse_capture: false, focus_events: false)
```

- `run/2` — `run(fun, opts \\ [])`. `fun` is arity-1, receiving a terminal reference. Opts: `:mouse_capture` and `:focus_events`, both **default `false`** on the local transport — opt in explicitly when needed.
- `draw/2` — `draw(terminal, [{widget, %Rect{}}, ...])`. The rect, in absolute 0-based cell coordinates, says where to paint.
- `poll_event/1` — `poll_event(timeout_ms \\ 250)`. Returns an `ExRatatui.Event.*` struct, `nil` on timeout, or `{:error, reason}`.
- `terminal_size/0` — returns `{width, height}` (a tuple, not a `Rect`).
- `Layout.split/4` — `split(area, direction, constraints, opts \\ [])`. Returns a list of `%Rect{}` (one per constraint). Direction is `:horizontal | :vertical`; constraints are `{:percentage, n}`, `{:length, n}`, `{:min, n}`, `{:max, n}`, `{:ratio, num, den}`, `{:fill, weight}`.
- `%ExRatatui.Layout.Rect{x: 0, y: 0, width: 0, height: 0}` — placement is explicit; widgets do not auto-resize to the terminal.

In an `App`, `render/2` receives `(state, %ExRatatui.Frame{width:, height:})` and returns the **full** `[{widget, %Rect{}}]` list for the whole screen — describe the entire frame every time, never a partial delta. The runtime diffs cells.

## Widget index

All widgets are structs under `ExRatatui.Widgets.*` (a few have a companion data module under `ExRatatui.*`). Knowing what exists prevents reinventing it.

**Text and containers**
- `Paragraph` — wrapped/aligned text with an optional block frame
- `Block` — borders, titles (top/bottom, per-title alignment via `Block.Title`)
- `Clear` — clears a region (use under popups/overlays)

**Lists and tables**
- `List` — selectable item list
- `Table` — rows, columns, header, selection
- `WidgetList` — vertically stacked, scrollable list of primitive widgets

**Progress and activity**
- `Gauge` — ratio bar with label
- `LineGauge` — single-line ratio bar
- `Sparkline` — compact inline trend line
- `Throbber` — animated spinner

**Charts and drawing**
- `BarChart` — bars (`Bar`, `BarGroup` data modules)
- `Chart` — line/scatter datasets (`Chart.Axis`, `Chart.Dataset`)
- `Canvas` — freeform drawing (`Circle`, `Label`, `Line`, `Map`, `Points`, `Rectangle`)

**Navigation and selection**
- `Tabs` — horizontal tab bar
- `Scrollbar` — scroll position indicator
- `Calendar` — month grid
- `Checkbox` — toggle
- `Popup` — modal/overlay container
- `SlashCommands` — command palette (`SlashCommands.Command`)

**Input (stateful — NIF-backed)**
- `TextInput` — single-line editor; drive via `ExRatatui.text_input_*` helpers
- `Textarea` — multi-line editor; drive via `ExRatatui.textarea_*` helpers and set `wrap_mode: :word_or_glyph` when long logical lines should soft-wrap to the widget width (`:none` is the default)

**Rich / special**
- `Markdown` — rendered Markdown
- `Image` — image rendering (`ExRatatui.Image` decodes; Kitty/Sixel/iTerm2/halfblocks)
- `BigText` — oversized 8x8 pixel text (`ExRatatui.BigText`)
- `CodeBlock` — syntax-highlighted code (`ExRatatui.CodeBlock`)

**App-level helpers (not widgets)**
- `ExRatatui.Focus` — focus ring for multi-panel apps. `handle_key/2` consumes Tab/Shift+Tab and returns `{focus, key_or_nil}` (`nil` = consumed); register rects to get click-to-focus via `handle_mouse/2`; style with `focused?/2`. Pure data, no process — do not hand-roll focus tracking.
- `ExRatatui.Theme` — semantic color palette (eleven slots) with `default/0` / `light/0` constructors and `border_style/2` / `text_style/2` / `selection_style/1` helpers. Pure data threaded through render code — no globals, no automatic widget injection.
- `ExRatatui.CellSession` — render to a cell buffer instead of ANSI bytes (Phoenix LiveView, framebuffers, screenshots). Reach for it before parsing ANSI out of a `Session`. When the consumer owns real pixels, create it with `font_size: {w, h}`: `Viewport3D` and `Image` in pixel modes then ship RGB bitmaps in `Diff.regions` / `Snapshot.regions` (`ExRatatui.CellSession.Region`, the complete list per frame, covered cells blank) instead of half blocks. A consumer painting a panel that is mounted on its side turns a region's bitmap with `ExRatatui.CellSession.Region.rotate/2` (or `ExRatatui.Pixels.rotate_rgb8/4` on the raw bytes) instead of gathering each row from a source column — it rotates the pixels only, never the cell rect. To put an app on a pixel display, such as an e-ink panel or a Linux framebuffer, use [raster_ex_ratatui](https://hexdocs.pm/raster_ex_ratatui) rather than rasterising cells by hand.

Compose custom composite widgets in pure Elixir via the `ExRatatui.Widget` protocol — no Rust required. See the Custom Widgets guide.

## Anti-patterns and gotchas

Highest-value rules. The guides hold the full set; these are the ones agents get wrong most.

- **Key event fields are lowercase strings, never atoms — wrong values compile and silently never match.** The shape is `%Event.Key{code: "up", kind: "press", modifiers: ["ctrl"]}`. Character keys are their string value (`"a"`, `"1"`, `" "`); special keys include `"enter"`, `"esc"`, `"tab"`, `"back_tab"`, `"backspace"`, `"up"` / `"down"` / `"left"` / `"right"`, `"page_up"` / `"page_down"`, `"f1"`..`"f12"` — full table in `ExRatatui.Event.Key`. Mouse events use string `kind` / `button` the same way (`%Event.Mouse{kind: "down", button: "left", x: 0, y: 0}`).
- **Never call `draw/2` with a bare widget — pass `[{widget, %Rect{}}, ...]`.** A widget without a rect paints nothing.
- **Never treat a widget as stateful — rebuild the struct each frame.** Widgets are immutable view descriptors, not objects that mutate in place.
- **Never return a partial scene from `render/2` — return the whole screen.** The runtime diffs cells; the job is to describe the full frame.
- **Never create `TextInput`/`Textarea` state in `render/2` — create it once in `mount/1`/`init/1` and keep the ref in state.** Recreating it each render drops cursor position and typed text.
- **Never do I/O, HTTP, sorting, or large allocations in `render/2`.** It runs up to ~60fps; derive once in the transition callback and store the result in state.
- **Never make a blocking call in `handle_event/2`/`update/2`.** Use `ExRatatui.Command.async/2` (reducer) or `Task.Supervisor.async_nolink/2` (callback). A blocking call freezes the whole UI.
- **Never hand-roll a render throttle to survive message bursts — the runtime already merges them.** A transition that finds more messages queued defers its render, so a burst renders once with the final state; an idle message renders immediately. Don't count renders per message in tests either: drive input with `Runtime.inject_event/2`, which renders synchronously.
- **A `[:ex_ratatui, :runtime, :mailbox]` event or "messages queued" warning means the callbacks can't keep up — fix the source, don't raise the threshold.** Make the slow callback cheap, sample or batch the noisy subscription, and return `render?: false` where nothing visible changed. `:mailbox_warn_threshold` (default `10_000`, `false` disables) is a start option; over `:ssh`/`:distributed` it goes inside `:app_opts`.
- **Always include a catch-all `handle_event(_event, state)` / `update(_msg, state)` returning `{:noreply, state}`.** Unmatched events otherwise crash the app.
- **Never `IO.inspect`/`IO.puts`/`dbg` to stdout while in raw mode** — it garbles the display. Log to a file via `Logger`, or use `Runtime.snapshot/1`.
- **Reducer `update/2` receives `{:event, event}` and `{:info, msg}`, never bare structs.** All input is routed through one `update/2`.
- **`commands:` and `render?:` runtime opts are designed for the reducer runtime.** They execute under the callback runtime too (command results land in `handle_info/2`), but idiomatic callback apps use `Process.send_after/3` or a supervised Task.
- **Never serve a TUI to remote users over the `:local` transport — use `transport: :ssh` or `:distributed`.** `:local` grabs the host tty and fails with `terminal_init_failed` where there is no TTY.
- **Never background or pipe stdin into a `mix run`/`iex` TUI example.** With no TTY it exits immediately or raises `terminal_init_failed`; run it in a real terminal emulator.
- **In tests, always pass `test_mode: {w, h}` and `name: nil`, and drive input with `ExRatatui.Runtime.inject_event/2`.** `test_mode` disables live TTY polling so `async: true` tests do not race; named apps collide across parallel tests.

## Going deeper

Full walkthroughs and the complete gotcha set live in the guides (hexdocs):

- Getting started — https://hexdocs.pm/ex_ratatui/getting_started.html
- Building UIs — https://hexdocs.pm/ex_ratatui/building_uis.html
- Callback runtime — https://hexdocs.pm/ex_ratatui/callback_runtime.html
- Reducer runtime — https://hexdocs.pm/ex_ratatui/reducer_runtime.html
- Custom widgets — https://hexdocs.pm/ex_ratatui/custom_widgets.html
- State machine patterns — https://hexdocs.pm/ex_ratatui/state_machines.html
- Testing — https://hexdocs.pm/ex_ratatui/testing.html
- Debugging — https://hexdocs.pm/ex_ratatui/debugging.html
- Performance — https://hexdocs.pm/ex_ratatui/performance.html
- Telemetry — https://hexdocs.pm/ex_ratatui/telemetry.html
- Transports — https://hexdocs.pm/ex_ratatui/transports.html
- Running over SSH — https://hexdocs.pm/ex_ratatui/ssh_transport.html
- Running over Erlang distribution — https://hexdocs.pm/ex_ratatui/distributed_transport.html
- Custom transports — https://hexdocs.pm/ex_ratatui/custom_transports.html
- Rendering to non-terminal surfaces (CellSession) — https://hexdocs.pm/ex_ratatui/cell_session.html
- Rendering to a framebuffer — https://hexdocs.pm/ex_ratatui/framebuffer_surfaces.html
- Images — https://hexdocs.pm/ex_ratatui/images.html
- Paste and clipboard — https://hexdocs.pm/ex_ratatui/paste_and_clipboard.html
- Widgets cheatsheet — https://hexdocs.pm/ex_ratatui/widgets.html

<!-- ex_ratatui-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
