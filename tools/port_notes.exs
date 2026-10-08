# Notes for PORT_STATUS.md, by slug: a string, or {:blocked, why} for a piece
# that cannot be matched (and is then left unregistered).
%{
  "ocean-sunset" =>
    "static cells precomputed to their dot, and terms skipped where they are exactly zero",
  "varanasi-ghats" =>
    "lamp light and streaks added into Float32 cells in upstream's order; static cells precomputed to their dot, as ocean-sunset; a negative base to the 1.8 (NaN) that upstream always overwrites is skipped",
  "storm-plains" => "Float32 floor, jitter and ear stores kept; static cells use a precomputed dot",
  "taj-dawn" => "pow(peak, 1.1) tabulated over upstream's 1025-step tone table; floors stored as Float32",
  "night-coast" =>
    "the reference scene: time-invariant terms per cell, float-typed hot helpers, a bounded pow in the dot with exact fallback, a per-cell memo across frames, and a per-frame lattice for the sea's noise",
  "alpine-dawn" =>
    "a certified fast pow in the halftone dot, redone with :math.pow wherever a decision sits near its threshold; static cells precomputed to their dot",
  "aurora-fjord" => "a certified fast pow for the dot and the rays; terms with a zero envelope skipped; over the 10 ms budget, under 3x",
  "deep-reef" => "a certified fast pow, with Float32 store checks; writes past the buffer's end dropped as a typed array drops them; over the 10 ms budget, under 3x",
  "desert-night" => "its own octave-shifted fBm; a certified fast pow; b *= A * B grouped as upstream; ~1.3 s init",
  "glxgears" =>
    "~67,000 points a frame: face points rotated from precomputed rests; depths quantised with exact tie-breaking by upstream's rule wherever candidates could differ",
  "gyroscope" => "the stand's depth buffer computed once; only each cell's final winner is shaded; pow(x, 24) bracketed, exact when the bracket straddles a ramp step",
  "heart" => "the sign of a - z*cbrt(q) from signs or a cubed comparison with a margin; cbrt only when that is ambiguous",
  "mobius-strip" => "deferred shading on a Float32 depth buffer; upstream's widest-view search runs in init",
  "torus-knot" => "deferred shading on a Float32 depth buffer; upstream's extent search runs in init",
  "twisted-ring" => "face strips wholly in front or behind are decided at their ends",
  "icosahedron" => "per-edge line style kept in state, as upstream's closure keeps it",
  "tesseract" => "edge styles kept in state; solid or dotted decided once a frame",
  "earthrise" => "only the box round the Earth and the twinkling stars are redrawn; the colour cache evolves in mono frames too, as upstream's; ~1.3 s init (heightfield)",
  "kyoto-dusk" => "pow(peak, 1.1) tabulated by upstream's 1025-step tone table; a per-cell memo of last frame's steps",
  "marine-drive" => "the water's noises from a per-frame lattice; a glint below half an ulp of the water colour is skipped",
  "misty-forest" => "d = (dist[k] = x) keeps the unrounded double while later reads get the Float32",
  "fern" =>
    "36,000 points a frame: placed with :math approximations, and wherever a point lies within 1e-5 of a cell edge or a cell's character could flip under a rigorous error bound, worked again on the plain path in upstream's order; a property test holds the fast frame to the exact one",
  "campfire" => "a negative lift to the power 1.4 (NaN upstream) skips the tongue; the flood fill's += 2 marker changes the stored Float32 value, reproduced",
  "landscape" => "reads env.now every frame; night and the moon are not reached at the fixtures' instant and were checked against Node",
  "fractal-tree" => "children start from their parent's Float32-stored tip; the parent's stroke uses the unrounded one",
  "fireflies" => "count truncated and bounded 0..500; the seed goes to mulberry32 as given",
  "snowfall" => "steps in 0.05 s pieces by repeated subtraction from a clamped dt, as upstream; 400 warm-up steps",
  "wind" => "noise corners hashed once a frame into a table",
  "bonsai" => "its own hash; a leaf off the grid reads JS's undefined and is skipped",
  "rain" => "its own hash, in unsigned arithmetic",
  "contour-map" => "the || 1e-9 fallbacks for a zero hypot and gradient are kept",
  "reaction-diffusion" =>
    "50 steps over 2,880 cells a frame; rows as lists with is_float guards so the arithmetic stays unboxed, and an exact fast Float32 rounding (Veltkamp split); over upstream's 4 ms budget, under 3x",
  "mandelbrot" => "frames deep in the zoom (15-30 s of each 48 s loop) cost 12-18 ms, over budget for that stretch; a zero derivative (upstream's Infinity) draws nothing",
  "epicycles" => "sqrt of a tiny negative from rounding (upstream's NaN) skips the dot",
  "flow-field" => "ink at or below the visible floor is dropped from the state, exactly",
  "voronoi" => "upstream's Infinity starting distance is a finite sentinel; coincident seeds (NaN) leave the cell blank",
  "langtons-ant" => "the first frame runs 10,350 steps",
  "maze" => "mazes cached by number; the wall-closing phase is between golden times and was checked against Node",
  "bar-chart" =>
    "writes clip at the frame's edge where unusual options would make upstream's lines grow past cols; a dataset with no values draws zeros where upstream throws",
  "candlesticks" => "seeds go raw into mulberry32, as upstream's; an open of 0 prints NaN% or Infinity% as upstream does",
  "cpu-meters" => "restarts from a cached post-warm-up snapshot when t goes back, as upstream rebuilds to the same state",
  "equalizer" => "tests (held -= dt) < 0 on the unrounded double, stores the Float32",
  "gauge" => "upstream's NaN band sentinel is nil",
  "radar" => "the corner text is cut at the frame's edge when range or unit overflow it (upstream's line grows)",
  "sparkline" => "the format option is not supported; digits held to 0..100 (toFixed throws outside); missing keys follow upstream's ?? defaults",
  "dissolve" => "the word index wraps with rem where unusual options would make upstream throw",
  "marquee" => "JS whitespace rules for trim",
  "split-flap" => "an unparseable time (upstream's NaN) is nil; JS whitespace rules for trim",
  "wave-text" => "Number(x) || fallback reproduced: 0 takes the default",
  "candle" => "halo neighbours by flat index wrap across rows, as upstream's do; the candlestick is traced once in init",
  "coffee" => "upstream's NaN from a negative base to the power 1.5 just above the surface draws the wisp as '|' or '.', reproduced; the still picture is traced in init (~0.14 s)",
  "ferris-wheel" => "slanted rim cells picked in a JS Map's insertion order",
  "hourglass" => "the outline marks cells by flat index, wrapping across rows as upstream's does",
  "sundial" =>
    "reads env.now; the day of the year counts from local midnight on 1 January; redrawn once a minute, the key ignoring the date as upstream's does",
  "train" => "a puff a hair past its life (NaN power upstream) draws nothing",
  "lighthouse" => "beam terms that would underflow to exactly 0 are skipped",
  "hawa-mahal" => "stateful lamps on a clamped play clock",
  "skyline" => "stateful windows on a clamped play clock",
  "calendar" => "reads env.now; keeps upstream's play-time offset from the wall clock, re-synced the same way",
  "digital-clock" => "reads env.now; keeps upstream's play-time offset from the wall clock, re-synced the same way",
  "form-controls" => "the clear-email event reads upstream's final script time, as its closure does",
  "file-tree" => "lines trimmed with JS whitespace rules (U+0085 and U+FEFF differ from String.trim/1)",
  "sparks" => "its own hash in unsigned arithmetic; Float32 heat with a store at every add",
  "synthwave" => "every floor row prebuilt in init",
  "tunnel" => "ray directions and start depths precomputed",
  "bouncing-balls" =>
    "balls bounded 1..5 as upstream clamps them; a highlight power below half an ulp of the sum is skipped",
  "chladni" =>
    "upstream's NaN crossing sentinel is a missing key; grain trips precomputed in init (~0.1 s)",
  "double-pendulum" =>
    "restores its post-warm-up state when t goes back, as upstream re-integrates to the same bits",
  "flag" =>
    "strip crossings worked out once per row level; ~17,000 sin/cos a frame keep it near its budget",
  "fountain" => "its own three-round hash, in unsigned arithmetic",
  "lorenz" => "the depth sum runs in the trail ring's raw index order, as upstream sums it",
  "smoke" =>
    "replays upstream's dt loop exactly, sub-step remainders included; 270 warm-up steps in init",
  "harmonograph" => "pen positions kept as a 16-bit binary; ~71,000 pow calls in init",
  "black-hole" =>
    "only the ray-path entries some ray uses are integrated, each once, in upstream's push order",
  "eclipse" =>
    "conservative fast paths (squared-distance pre-tests, skipped corona steps that cannot change a cell), checked byte for byte against a build without them",
  "galaxy" =>
    "closest of the space pieces to its budget: two pow and two cos per lit sample",
  "planet" =>
    "upstream's module-level albedo variable is returned alongside the ring opacity instead",
  "rocket" =>
    "puff splats folded per cell in upstream's puff order, with a Float32 store at each add",
  "solar-system" => "the centre is held as an integer so it can index cells",
  "three-body" =>
    "the 7200 leapfrog steps of one lap run once in init, in upstream's order; frames index the lap",
  "starlings" =>
    "flocking: velocities update bird by bird mid-step and neighbours are visited in upstream's linked-list order; the NaN falcon sentinel is nil; 200 warm-up steps in init",
  "spider" =>
    "upstream's 0/0 silk slope at the sprite's top row draws nothing; the port returns early there",
  "snake" => "a pure function of t; tail slots keep JS Map insertion order",
  "butterfly" =>
    "shading skipped exactly where only a hit/miss is needed; per-column perspective hoisted",
  "jellyfish" => "per-frame trail table by lag; edge sums kept in upstream's order",
  "whale" => "its own hash, in unsigned 32-bit arithmetic",
  "analog-clock" =>
    "reads env.now; notes the wall clock at the first frame rather than at init (the same instant when played at once)",
  "doom-fire" =>
    "200 warm-up steps in init (~0.3 s); noise rows reused across steps, as the spread shifts a row a step",
  "spinners" =>
    "with names chosen, the frame shrinks to fit them, as upstream (and leaves meta's size)"
}
