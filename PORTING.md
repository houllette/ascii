# Porting notes

How `ascii_art` maps [bas3line/ascii](https://github.com/bas3line/ascii) onto
Elixir, and every place JavaScript and Elixir disagree. Upstream is the source
of truth: where this port differs from upstream, the difference is listed
here. The pinned commit is in `UPSTREAM.md`.

## The upstream contract

A piece is one TypeScript module, `src/pieces/<slug>.ts`, with no runtime
imports. It exports:

- `meta`: `name` (lowercase), `category` (one of 14), `note` (one lowercase
  line, at most 72 characters), `cols` and `rows` (the frame size in cells),
  `fps` (0 to 60; 0 is a still), and optionally `options` (defaults for every
  option), `clock: true` (the picture reads the real time), `palette` (2 to 64
  `#rrggbb` colours), `ground` (the colour behind it) and `cell` (1 for square
  cells, else 2).
- a default function: takes the options, precomputes, and returns
  `frame(t, env)`, which returns the picture at `t` seconds as one string of
  exactly `rows` lines of exactly `cols` characters, joined by `\n`.

`env` has two fields. `paper` is true when ink is dark on a light ground, and
shaded pieces flip their ramp for it. `color`, present only when a coloured
piece is drawn in colour, is a `Uint8Array(cols * rows)` that the frame
fills with palette indices, row by row. `mount` allocates one such buffer per
mounted piece and never clears it, so a cell a frame does not write keeps its
last index.

The frame function is a closure, and many pieces keep state in it: a
simulation stepped by how far `t` moved since the last call, or a cache keyed
on the minute. `mount` only ever calls it with `t` increasing from 0, by
`min(dt, 100 ms)` a frame while the piece is on screen.

Frames may use printable ASCII, `·`, `°` and U+2500–U+259F. Scenes may also
use `•` and `●`. Text pieces are at most 80×32; scenes (`category: "scenes"`,
which must have a palette and a ground) are at most 320×120. `scripts/check.ts`
enforces all of this, plus determinism (same `t`, same frame, unless `clock`),
"frame 0 is a good still", at least three distinct frames in six seconds for
an animated piece, and a time budget: 4 ms a frame on average and 30 ms at
worst, or 10 ms on average for a scene.

Logos (`logos`) and distros (`distros`) have a palette and no ground, and draw
from a second picture in colour (`env.color` present) than in one ink.

## The Elixir mapping

| upstream | here |
| --- | --- |
| `src/pieces/<slug>.ts` | `AsciiArt.Pieces.<CamelName>` in `lib/ascii_art/pieces/<slug>.ex` |
| `meta` | `c:AsciiArt.Piece.meta/0` returning `%AsciiArt.Meta{}`; options keyed by atoms |
| the default function | `c:AsciiArt.Piece.init/1`: takes every option, merged with the defaults, and precomputes |
| `frame(t, env)` | `c:AsciiArt.Piece.frame/3`: `(state, t, env)` to `{iodata, colours, state}` |
| the closure's mutable state | the `state` term, threaded through by the caller |
| `env.paper` | `env.paper` |
| `env.color` (the buffer) | `env.color?` says whether colours are wanted; the frame returns them as a binary of `cols * rows` palette indices, row-major, or `nil` |
| `Date.now()` | `env.now`, a `DateTime` (the golden tests pin it) or `nil` for the system clock; see `AsciiArt.Kit.Clock` |
| `load`, `names`, `isPiece` | `AsciiArt.Registry` and `AsciiArt.pieces/0,1`, `AsciiArt.meta/1` |
| `mount` | `AsciiArt.new/2` + `AsciiArt.frame/2`, `AsciiArt.Player`, the Phoenix components |

A piece that leaves some colour cells unwritten (upstream relies on the
buffer keeping old values) keeps its last colours in its state and starts
from zeros, which is what a fresh `Uint8Array` holds.

Categories are atoms written in code (`:scenes`, `:logos`, ...), never made
from input. Slugs are the upstream file names, as strings; looking one up
never creates an atom.

### Options

Options passed to `AsciiArt.new/2` (or a LiveView session, or the CLI) are
checked against the piece's defaults before `init/1` sees them:

- keys must name a default option; string keys are matched against the
  defaults' names, so no atom is ever created from input;
- each value must have the shape of its default (a number for a number, a
  list of strings for a list of strings, a map with known keys for a map),
  and strings from params are cast to numbers or booleans where the default
  is one;
- numbers are clamped to the piece's `meta.bounds` for that option, or to
  ±1,000,000; strings to 256 characters and lists to 256 entries.

Anything else is `{:error, {:invalid_option, key}}`. Upstream accepts
anything and lets the piece cope.

## Numbers: `:math`, and what JS needs besides

Pieces shade with `Math.sin`, `Math.exp`, `Math.pow` and so on, and a cell's
character often sits on a threshold of one. Two facts shape how this port
computes them.

1. **`:math` is not V8.** Erlang's `:math` calls the platform libm. V8 calls
   its own port of fdlibm (`src/base/ieee754.cc`). Over random inputs they
   disagree in the last bit for 4% (`sin`) to 17% (`acos`) of calls, and
   macOS and glibc disagree with each other too.

2. **V8 itself differs between CPUs.** Clang compiles `ieee754.cc` with
   `-ffp-contract=on`, and on arm64, where fused multiply-add is always
   available, it fuses `a * b + c` inside the polynomials. The darwin-arm64
   Node disagrees with the darwin-x64 Node in the last bit of `sin`, `cos`,
   `tan`, `exp`, `log`, `log10`, `log1p`, `asin` and (more rarely) `pow` for
   up to about 0.5% of inputs. **The fixtures are generated with x64 Node**,
   which runs fdlibm as written; the generators refuse to run on non-x64
   Node. Regenerating every fixture with the arm64 Node gives identical
   frames and colours for all 191 pieces all the same.

The port first answered (1) by transcribing fdlibm into pure Elixir, so
that every function agreed with x64 V8 bit for bit. Measured afterwards,
that bought nothing a picture shows: with `:math` in its place, every golden
frame of all 191 pieces still matches, on macOS (arm64) and on Linux (glibc,
arm64 and, in CI, x86-64), because a character rarely sits within a last bit
of its threshold. And `:math` is a BIF, several times faster than fdlibm in
Elixir: frames are 1.3 times faster overall, scenes 1.25 times, setup 1.35
times, and a few pieces that are little but math far more (`galaxy` 8.8
times). So the pieces call `:math` for the transcendental functions, and the
1,200 lines of fdlibm are gone.

What that costs: a frame can now, in principle, differ from upstream's in a
cell that sits within a last bit of a threshold, and from one platform to
another. The golden tests run on macOS and Linux and would show it. And the
chaotic simulations (double-pendulum, three-body, lorenz) drift apart from
upstream's, and between platforms, over a long run; the goldens cover the
times upstream's own checks play.

`AsciiArt.JSMath` keeps what JS does differently and Elixir has no answer
for, each agreeing with V8 bit for bit (`test/fixtures/js_math.json` holds
V8's answers and `AsciiArt.JSMathTest` requires them):

  * `Math.round` (halves up, toward +infinity), `%` (the dividend's sign),
    `Math.fround`, typed-array stores, `toFixed` and `String(number)`;
  * `Math.hypot`, which in V8 is not libm but Torque code that scales by the
    largest argument and sums with Kahan compensation. It differs from
    `sqrt(a*a + b*b)` in about a third of cases;
  * `Math.cbrt` and `Math.log1p`, which `:math` does not have, as fdlibm
    computes them (`log(1 + x)` loses what matters near 0).

`sqrt` is exactly rounded everywhere and is `:math.sqrt/1`.

## JS → Elixir hazards

Every piece is checked against this list.

- **32-bit integers.** `Math.imul`, `>>>`, `>>`, `<<`, `| 0`, `^`, `&` wrap at
  32 bits; Elixir integers do not. Hashes and PRNGs go through
  `AsciiArt.Int32`, never raw `Bitwise` on unbounded values. `(x * 9) | 0` on
  a float truncates toward zero, then wraps.
- **`Math.round`** rounds halves toward +∞: `JSMath.round(-2.5) == -2`.
  Elixir's `round/1` rounds halves away from zero. V8 computes it as
  `ceil(x)`, less one if that is more than half above `x`, which is also right
  for `0.49999999999999994`. All rounding helpers return integers.
- **`%`** is a truncated remainder with the dividend's sign, for floats too:
  `JSMath.mod/2` (C `fmod`). Pieces that want a true modulo write
  `((a % n) + n) % n` upstream, and the port does the same.
- **Division by zero, `Infinity`, `NaN`.** Erlang floats cannot hold
  infinities or NaN: `1 / 0.0` raises, and so does `:math.exp(1000)`. Decided
  once for the whole port: **no sentinels**. `:math` and `JSMath` raise
  `ArithmeticError` wherever JS would produce `Infinity` or `NaN`. Each piece
  guards the sites where upstream relies on one (for example
  `at = -Infinity` meaning "no glint": the port uses `nil` and the branch it
  implies). The golden tests at fixed times and the property tests at random
  times both run every piece, so a missed guard fails loudly rather than
  drawing something wrong.
- **Typed arrays.** A `Float32Array` stores `Math.fround(x)`: the port rounds
  through `JSMath.fround/1` (`<<x::float-32>>`) at every store into one, which
  matters for depth buffers compared against fresh doubles (`donut`).
  `Uint8Array`, `Int8Array`, `Int16Array` and `Uint16Array` wrap (`JSMath.u8/1`
  and friends); `Uint8ClampedArray` clamps and rounds halves to even
  (`JSMath.clamp_u8/1`). No piece uses the clamped one.
- **Reads past the end.** `a[i]` out of range is `undefined`, which becomes
  `NaN` in arithmetic and is falsy in a test. The port returns the value JS
  would have ended up with at each such site (usually a branch not taken).
- **Truthiness.** `0`, `""` and `NaN` are falsy in JS; in Elixir only `nil`
  and `false` are. Every `if (x)` on a number becomes `x != 0`.
- **Strings.** JS indexes UTF-16 code units. Every character a frame may
  contain is in the BMP, so a code unit is a code point; the port works on
  code points (or single-character binaries) and never on bytes, since `·`,
  `°` and the box drawing are two and three bytes in UTF-8. Option text with
  characters outside the BMP would count differently (JS counts surrogate
  pairs as two); that case is not reproduced.
- **Closure state and time going backwards.** Each piece's state is explicit
  and threaded through; where upstream clamps `t - last` (`doom-fire`,
  `falling-sand`) the port clamps the same way. When `t` decreases, the port
  does what upstream does: usually it steps by zero and holds.
- **The clock.** The five `clock: true` pieces (`analog-clock`, `calendar`,
  `digital-clock`, `landscape`, `sundial`) read `env.now` instead of
  `Date.now()`. Local time comes from the `DateTime`'s own offset. With
  `now: nil` it is the system's local time.
- **Sorting.** `Array.prototype.sort` is stable in V8, as is `Enum.sort/2`.
  Comparators of the form `(a, b) => a.k - b.k` become `Enum.sort_by/3` on the
  key, which keeps ties in order the same way.
- **Iteration order.** `Map` and `Set` iterate in insertion order in JS;
  Elixir maps do not past 32 keys. The pieces that iterate one keep a list.
- **Number formatting.** `toFixed` rounds the exact binary value, halves away
  from zero, and `String(x)` prints the shortest round-trip digits with JS's
  own exponent rules. These are `JSMath.to_fixed/2` and `JSMath.to_string/1`,
  checked against V8.
- **Negative zero.** JS keeps `-0` in doubles. Elixir integer arithmetic has
  no `-0`. It only matters where a sign of zero is observed (`atan2`, `1/x`),
  and those sites stay in float arithmetic.

The bulk port found more, each now handled where it occurs:

- **Assignments are expressions.** `d = (a[k] = x)` gives `d` the unrounded
  double while later reads of the Float32Array get the rounded one;
  `(f32[i] -= d) < 0` tests the unrounded value. A `+=` into a
  Float32Array rounds at every add, and a Float32Array used as a visit
  marker (`fire[k] += 2`) changes the stored value. `typedArray.map` returns
  a typed array, so its results are rounded too.
- **Compound assignment groups the whole right side**: `x += a + b` is
  `x + (a + b)` and `b *= A * B` is `b * (A * B)`; and `+ W + 40` is two
  additions, not `+ (W + 40)`. `mix(c, r, 1)` is not exactly `r`.
- **Loops.** `for (i = 0; i < x; i++)` with a float `x` runs `ceil(x)`
  times. `for (; dt > eps; dt -= step)` leaves sub-step remainders that must
  be replayed. A JS loop with `<=` can run zero times, but Elixir's `lo..hi`
  counts down when `hi < lo`: such ranges are written `lo..hi//1`.
  `continue` skips the draws of `rand()` later in the same iteration.
- **Order of visits.** A JS `Map` iterates in insertion order, and updating
  a key keeps its place (snake, ferris-wheel). Neighbours walked through a
  linked list come out newest first (starlings). Velocities written during a
  step are seen by later birds in the same step. A ring buffer may be summed
  in raw index order, not oldest first (lorenz): float sums depend on order.
- **Indexing.** Neighbour lookups by flat index wrap across rows (candle,
  hourglass); writes past a typed array's end are dropped; reads past it are
  `undefined`, which may be "not a space" (bonsai).
- **NaN that draws nothing.** A negative base to a fractional power, a
  `sqrt` of a rounding-negative, 0/0 from a zero-length segment: JS gets NaN,
  every comparison with it is false, and the piece draws nothing there (or
  draws its fallback character). The port takes that branch explicitly.
  `Infinity` as a starting distance becomes a finite sentinel or `nil`.
- **Elixir's own traps.** `/` always gives a float, so `(cols - 1) / 2` used
  as an index or map key misses the integer key; `Bitwise` raises on a float
  like `2 * 24.5`. `Math.max(0, x)` in Elixir can return the integer 0. In a
  `for` comprehension a binding whose value is `false` or `nil` filters the
  element out. JS `trim()` trims U+FEFF but not U+0085, the opposite of
  `String.trim/1`, and PCRE's `$` matches before a final newline (anchor with
  `\z`). A call to `JSMath` in a module attribute makes a compile-time
  dependency; such constants are computed in `init`.
- **Closures read final values.** A closure that reads a variable the setup
  code goes on changing sees its last value (form-controls), and a
  module-level `let` is shared by every instance (planet).
- **Seeds.** Upstream sometimes passes an arbitrary number straight into
  mulberry32, which adds, then truncates; `Kit.Rand.seed/1` truncates first,
  which differs for negative fractions, so those pieces call
  `Int32.mulberry32/1` with the raw value.
- **Golden times are samples.** They can miss whole phases of a cyclic
  piece (maze's closing walls, landscape's night). Every batch also compared
  long plays, random jumps backwards and forwards, and non-default options
  against upstream in Node.

## Speed without changing a bit

BEAM is several times slower than V8 at float arithmetic, and upstream's
scenes do tens of thousands of `pow` and `exp` calls a frame. Every piece
keeps upstream's results exactly; the ones that needed it are fast by these
means, in order of preference:

1. **Precompute what does not move**, in `init`, as the very subexpressions
   upstream computes (multiplication is not associative), down to whole
   static cells.
2. **Skip work whose result is known**: a term multiplied by an exact zero,
   a term below half an ulp of the sum it joins, a cell provably outside a
   shape, a frame where a term is static (night-coast's glow without a
   flash), a memo of last frame's inputs per cell.
3. **Guard floats.** `is_float` guards on hot functions and on values read
   from tuples or lists let the compiler keep arithmetic unboxed: 2-4x in
   the hottest loops.
4. **Certified fast paths.** Where a value only feeds a rounding, a
   threshold or a colour step, a cheaper value is computed first (a table
   and series for `pow`, a quantised depth), with a proven error bound;
   wherever the decision lies within the bound of its boundary, the plain
   value is computed instead. fern places its points by angle sums, short
   series and fixed-point sums this way, 2.5 times faster than placing them
   plainly. (ocean-sunset and varanasi-ghats once guessed with `:math` and
   checked against fdlibm; with `:math` as the plain path that went.)

Each certified fast path is held to its exact path by tests: fern and the
scenes have an internal `exact?` switch, and glxgears, gyroscope, heart,
mobius-strip, torus-knot and twisted-ring have a plain reference port in
their test files; a property compares them at random times, and fixed times
cover the rarest Float32 cases. One gap is known: a property that plays random
times rarely catches a per-cell memo whose key leaves out one colour channel,
since the channels move together.

Frame times are in [PORT_STATUS.md](PORT_STATUS.md). Six pieces are over
upstream's own budget (4 ms a frame, 10 ms for scenes) and all are within
three times it: alpine-dawn, aurora-fjord, deep-reef, ocean-sunset and
varanasi-ghats (10.6-14.1 ms against 10), and reaction-diffusion (~9.1 ms
against 4). mandelbrot is within budget over check.ts's six seconds but
takes 16-22 ms deep in its zoom; it closes a loop, so a LiveView player
draws that once.

## Golden fixtures

`tools/gen_golden.mjs` (run with `mix ascii_art.golden`) imports every
upstream piece and writes `test/fixtures/golden/<slug>.json`:

- `meta`, `upstream_commit`, `node`, `arch` and `call_order`
  (`[0, 0.5, 1, 2.5, 5, 10, 30]`);
- `frames`: for each run, a fresh instance played at each time in
  `call_order`, recording `t`, `paper`, `mono` (no colour buffer), `now` (the
  stubbed clock, for clock pieces) and `text`. A run in colour also records
  the colour buffer after each frame, base64-encoded (about a quarter of the
  size of a JSON list of indices, which matters for the 20,000-cell scenes).
  Text pieces get two runs (ink and paper); coloured pieces get four (ink and
  paper, each in colour and in one ink).
- `play`: `scripts/check.ts`'s own playback. A fresh instance stepped every
  `1/fps` seconds from 0 to 6 (`t = round(i * step * 1e6) / 1e6`), keeping
  the frames nearest 0, 1, 2, 3, 4 and 6 s. Stateful pieces step differently
  under small, even steps than under the jumps of `call_order`, so both are
  checked.

Clock pieces see `Date` stubbed to 2026-03-14T15:09:26.535Z at `t = 0`,
advancing with `t`, in `TZ=UTC`.

`AsciiArt.GoldenCase` replays both, threading state, and requires every frame
and every colour to match exactly. A per-piece tolerance
(`test/fixtures/tolerances.exs`) exists for a libm difference proven to sit on
a threshold. Since `JSMath` matches V8 bit for bit there should be none, and
the list below is the complete set.

### Tolerances

None.

## Deviations from upstream

At the default options, none: every piece draws upstream's frames. The
differences:

- **Options are validated** (above). Upstream takes any value.
- **`sparkline`'s per-series `format` function** is not accepted as an option:
  options are data, and functions cannot come from params. Its `digits` is
  held to 0..100, where upstream's `toFixed` would throw.
- **Options of this port's own**, for live data in dashboards and terminal
  UIs. Their defaults leave upstream's picture as it is (the golden tests
  hold it), and `meta.options` lists them with upstream's:
  progress-bar `values`, `style`, `cols`; sparkline `cols`, `rows` (and
  upstream's own per-series `values`, which the options could not reach
  before `meta.shapes`); gauge `value`; cpu-meters `cores`, `memory`, `swap`,
  `load`, `tasks`, `uptime`, `processes`; uptime-bar `history`, `days`;
  heatmap `counts`, `date`, `weeks`; candlesticks `candles`, `times`,
  `digits`; bar-chart `cols`; equalizer `levels`. Each piece's documentation
  says what they do. Pieces whose size follows their options say so with
  `c:AsciiArt.Piece.size/1`, and those that carry state over new options
  (the gauge's needle, the bars of bar-chart and equalizer, cpu-meters'
  simulation) with `c:AsciiArt.Piece.update/2`.
- **spinners** with `names` shrinks to fit them, as upstream means it to; a
  frame here must say its size, so this is `size/1`. Names it does not know
  are left out, and if none is left it shows all twelve, where upstream draws
  nothing. A negative `speed` runs them backwards, where upstream would index
  past its frames.
- **Unusual options that make upstream misbehave.** bar-chart and radar clip
  at the frame's edge where upstream's lines would grow past `cols`;
  bar-chart draws zeros for a dataset without values, and no bars for none,
  where upstream throws; dissolve wraps its word index where upstream would
  throw. Counts that size arrays (starfield's `stars`, fireflies' `count`)
  are truncated to integers within their bounds.
- **The clock is read at the first frame.** analog-clock notes the wall
  clock when it is made upstream and at its first frame here: the same
  instant when a piece is played as soon as it is made. With `env.now: nil`
  local time comes from the system's time zone (sundial's start of the year
  uses its offset at that instant, as JS's `Date` does).
- **Fixtures come from x64 V8** (above), so a threshold cell may differ from
  what an Apple-silicon browser draws.
- **`paper` follows the ground in colour.** As in `mount`, a coloured piece
  drawn in colour over its `ground` gets `paper` from the ground's lightness,
  whatever was asked for.
