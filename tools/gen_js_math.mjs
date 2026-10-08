// node tools/gen_js_math.mjs [out file]
//
// Writes test/fixtures/js_math.json: V8's answers for the Math functions,
// 32-bit integer operators and number formatting that AsciiArt.JSMath and
// AsciiArt.Int32 reimplement (the pieces call :math for the rest). Doubles
// are stored as 16 hex digits of their bits, so the comparison in the tests
// is exact.
//
// Run it with an x64 Node: arm64 builds of V8 fuse multiply-adds inside
// fdlibm, which can move the last bit of log1p and cbrt (PORTING.md).
import { writeFileSync } from "node:fs";

if (process.arch !== "x64" && !process.env.ALLOW_ANY_ARCH) {
  console.error(`run this with an x64 node (this one is ${process.arch}); see PORTING.md`);
  process.exit(2);
}

const OUT = process.argv[2] || "test/fixtures/js_math.json";

let seed = 20260314;
const rand = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const view = new DataView(new ArrayBuffer(8));
const hex = (x) => {
  view.setFloat64(0, x);
  return view.getBigUint64(0).toString(16).padStart(16, "0");
};
const N = 600;
const range = (lo, hi) => () => lo + (hi - lo) * rand();
// A spread of magnitudes, both signs: 10^-8 to 10^5.
const wide = () => (rand() < 0.5 ? -1 : 1) * 10 ** (rand() * 13 - 8);

const unary = {
  log1p: [range(-0.9, 10), wide],
  cbrt: [range(0, 100), wide, () => [0, 1, 8, 27, -8, 1e-300]],
  sqrt: [range(0, 100), () => 10 ** (rand() * 40 - 20)],
  round: [range(-100, 100), () => Math.floor(rand() * 200 - 100) + 0.5, () => [0.49999999999999994, -0.5, 0.5, 2.5, -2.5, 4503599627370497, -0.49999999999999994]],
  fround: [range(-100, 100), wide],
};

const binary = {
  hypot: [() => [rand() * 2 - 1, rand() * 2 - 1], () => [wide(), wide()], () => [0, 0], () => [3, 4]],
  hypot3: [() => [rand() * 2 - 1, rand() * 2 - 1, rand() * 2 - 1], () => [wide(), wide(), wide()]],
  fmod: [() => [rand() * 200 - 100, rand() * 10 + 0.1], () => [wide(), wide()], () => [-7.5, 2], () => [7.5, -2]],
};

const math = {};
const apply = { hypot3: (a, b, c) => Math.hypot(a, b, c), fmod: (a, b) => a % b };
for (const [name, gens] of Object.entries(unary)) {
  const f = Math[name];
  const inputs = gens.flatMap((g) => {
    const first = g();
    return Array.isArray(first) ? first : [first, ...Array.from({ length: N - 1 }, g)];
  });
  // JS answers some inputs with Infinity or NaN, which Erlang floats cannot hold.
  math[name] = inputs.filter((x) => Number.isFinite(f(x))).map((x) => [hex(x), hex(f(x))]);
}
for (const [name, gens] of Object.entries(binary)) {
  const f = apply[name] || Math[name];
  const inputs = gens.flatMap((g) => Array.from({ length: N }, g));
  math[name] = inputs.filter((args) => Number.isFinite(f(...args))).map((args) => [...args.map(hex), hex(f(...args))]);
}

// 32-bit integers, as JS sees them.
const ints = () => {
  const r = rand();
  if (r < 0.25) return Math.floor(rand() * 2 ** 32) - 2 ** 31;
  if (r < 0.5) return Math.floor(rand() * 2 ** 32);
  if (r < 0.75) return Math.floor(rand() * 2000) - 1000;
  return Math.floor((rand() - 0.5) * 2 ** 40);
};
const int32 = {
  imul: Array.from({ length: N }, () => { const a = ints(), b = ints(); return [a, b, Math.imul(a, b)]; }),
  ushr: Array.from({ length: N }, () => { const a = ints(), b = Math.floor(rand() * 40); return [a, b, a >>> b]; }),
  sar: Array.from({ length: N }, () => { const a = ints(), b = Math.floor(rand() * 40); return [a, b, a >> b]; }),
  shl: Array.from({ length: N }, () => { const a = ints(), b = Math.floor(rand() * 40); return [a, b, a << b]; }),
  bor: Array.from({ length: N }, () => { const a = ints(), b = ints(); return [a, b, a | b]; }),
  bxor: Array.from({ length: N }, () => { const a = ints(), b = ints(); return [a, b, a ^ b]; }),
  band: Array.from({ length: N }, () => { const a = ints(), b = ints(); return [a, b, a & b]; }),
  to_int32: Array.from({ length: N }, () => { const a = rand() < 0.5 ? ints() : (rand() - 0.5) * 2 ** 34; return [hex(a), a | 0]; }),
  to_uint32: Array.from({ length: N }, () => { const a = rand() < 0.5 ? ints() : (rand() - 0.5) * 2 ** 34; return [hex(a), a >>> 0]; }),
  mulberry32: [0, 1, 7, 9, 31, -5, 2 ** 31 - 1, 123456789].map((s) => {
    let a = s | 0;
    const out = [];
    for (let i = 0; i < 64; i++) {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      out.push(hex(((t ^ (t >>> 14)) >>> 0) / 4294967296));
    }
    return [s, out];
  }),
};

// Number to text.
const fixedInputs = [
  ...Array.from({ length: N }, () => (rand() - 0.5) * 2000),
  ...Array.from({ length: 500 }, () => Math.floor(rand() * 2000 - 1000) / 8),
  0.5, 1.5, 2.5, -0.5, -1.5, 1.005, 1.045, 0, -0.0001, 1e-7, 123.456, 99.995, 0.125, 0.375,
];
const toFixed = fixedInputs.flatMap((x) => [0, 1, 2, 3, 6].map((d) => [hex(x), d, x.toFixed(d)]));
const stringInputs = [
  ...Array.from({ length: N }, () => (rand() - 0.5) * 2000),
  ...Array.from({ length: 300 }, wide),
  ...Array.from({ length: 300 }, () => Math.floor(rand() * 1e6)),
  0, 1, -1, 0.1, 1e21, 1.5e21, 1e-6, 1e-7, 1.234e-7, 123456789012345680000, 5e-324, 1.7976931348623157e308,
];
const toString = stringInputs.map((x) => [hex(x), String(x)]);

writeFileSync(OUT, JSON.stringify({ node: process.version, arch: process.arch, math, int32, to_fixed: toFixed, to_string: toString }) + "\n");
console.log(`wrote ${OUT}`);
