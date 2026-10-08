// node tools/gen_golden.mjs [upstream dir] [out dir] [slug ...]
//
// Writes test/fixtures/golden/<slug>.json for every piece in the upstream
// checkout (tmp/upstream by default): frames at fixed play times, ink and
// paper, in colour and in one ink, from fresh instances of each piece. A dev
// tool only; `mix test` never runs Node.
//
// Needs Node 22.18+ (or 23.6+), which runs TypeScript files directly, built
// for x64: arm64 builds of V8 fuse multiply-adds inside Math.sin, Math.log and
// the like, which moves their last bit (see PORTING.md).
process.env.TZ = "UTC";
if (process.arch !== "x64" && !process.env.ALLOW_ANY_ARCH) {
  console.error(`run this with an x64 node (this one is ${process.arch}); see PORTING.md`);
  process.exit(2);
}

import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [upstreamArg, outArg, ...picked] = process.argv.slice(2);
const UPSTREAM = resolve(upstreamArg || "tmp/upstream");
const OUT = resolve(outArg || "test/fixtures/golden");
const PIECES = `${UPSTREAM}/src/pieces`;

// Play times for the replayed runs, in this order, each run a fresh instance.
const CALL_ORDER = [0, 0.5, 1, 2.5, 5, 10, 30];
// check.ts plays a fresh instance from 0 in 1/fps steps and samples these.
const PLAY_SAMPLES = [0, 1, 2, 3, 4, 6];
// The instant clock pieces read at t = 0: 2026-03-14T15:09:26.535Z.
const CLOCK_START = 1773500966535;

const commit = execFileSync("git", ["-C", UPSTREAM, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();

// Date, stubbed so a clock piece reads CLOCK_START + t seconds.
const RealDate = Date;
let now = CLOCK_START;
class StubDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) super(now);
    else super(...args);
  }
  static now() {
    return now;
  }
}
globalThis.Date = StubDate;

const slugs = picked.length
  ? picked
  : readdirSync(PIECES)
      .filter((f) => f.endsWith(".ts") && f !== "index.ts")
      .map((f) => f.slice(0, -3))
      .sort();

const b64 = (bytes) => Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString("base64");
const atClock = (meta, t) => (meta.clock ? CLOCK_START + Math.round(t * 1000) : null);

// One fresh instance played at each of `times` in turn, as mount would: one
// colour buffer for the run, never cleared between frames.
function run(mod, times, paper, mono) {
  const { meta } = mod;
  now = CLOCK_START;
  const frame = mod.default({ ...(meta.options || {}) });
  const color = meta.palette && !mono ? new Uint8Array(meta.cols * meta.rows) : undefined;
  return times.map((t) => {
    const at = atClock(meta, t);
    if (at !== null) now = at;
    const text = frame(t, { paper, color });
    return { t, paper, mono: !color, now: at, text, color: color ? b64(color) : null };
  });
}

// check.ts's playback: every 1/fps step from 0, keeping the sampled frames.
function play(mod) {
  const { meta } = mod;
  now = CLOCK_START;
  const frame = mod.default({ ...(meta.options || {}) });
  const color = meta.palette ? new Uint8Array(meta.cols * meta.rows) : undefined;
  const step = meta.fps ? 1 / meta.fps : 0.5;
  const end = Math.max(...PLAY_SAMPLES);
  const kept = new Map();
  for (let i = 0; ; i++) {
    const t = Math.round(i * step * 1e6) / 1e6;
    if (t > end + 1e-9) break;
    const at = atClock(meta, t);
    if (at !== null) now = at;
    const text = frame(t, { paper: false, color });
    for (const want of PLAY_SAMPLES)
      if (Math.abs(want - t) < step / 2 + 1e-9 && !kept.has(want))
        kept.set(want, { t, sample: want, paper: false, mono: !color, now: at, text, color: color ? b64(color) : null });
  }
  return { step, until: end, samples: PLAY_SAMPLES, frames: PLAY_SAMPLES.map((s) => kept.get(s)) };
}

mkdirSync(OUT, { recursive: true });
let failed = 0;
for (const slug of slugs) {
  try {
    const mod = await import(pathToFileURL(`${PIECES}/${slug}.ts`).href);
    const { meta } = mod;
    const runs = meta.palette
      ? [[false, false], [true, false], [false, true], [true, true]]
      : [[false, true], [true, true]];
    const frames = runs.flatMap(([paper, mono]) => run(mod, CALL_ORDER, paper, mono));
    const fixture = {
      slug,
      upstream_commit: commit,
      node: process.version,
      arch: process.arch,
      meta,
      call_order: CALL_ORDER,
      clock: meta.clock ? { start: CLOCK_START, tz: "UTC" } : null,
      frames,
      play: play(mod),
    };
    writeFileSync(`${OUT}/${slug}.json`, JSON.stringify(fixture) + "\n");
  } catch (e) {
    console.error(`FAIL ${slug}: ${e.stack}`);
    failed++;
  }
}
console.log(`${slugs.length - failed}/${slugs.length} fixtures written to ${OUT}`);
process.exit(failed ? 1 : 0);
