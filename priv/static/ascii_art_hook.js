// ascii_art's LiveView hook for AsciiArt.Phoenix.PlayerLive: the browser
// draws the piece, a text piece in its <pre>, a coloured one on a <canvas>
// a character a cell in its palette colour over its ground.
//
// A piece that closes a loop arrives once, as one cycle, and plays here with
// no more from the server. Any other piece arrives a frame at a time, each as
// the runs of cells that changed. Play stops while the picture is off screen or its
// tab hidden, and a reader who prefers reduced motion keeps frame 0.
// Register it with your LiveSocket:
//
// Its events go to whatever owns its element: AsciiArt.Phoenix.PlayerLive, or
// AsciiArt.Phoenix.PlayerComponent inside your LiveView.
//
//   import {AsciiArt} from "../../deps/ascii_art/priv/static/ascii_art_hook.js"
//   let liveSocket = new LiveSocket("/live", Socket, {hooks: {AsciiArt}, ...})
const FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";
const MAX_STEP = 100; // ms of play time a frame at most, as upstream's mount

const bytes = (base64) => Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
const canInflate = typeof DecompressionStream !== "undefined";

async function inflate(base64) {
  const stream = new Blob([bytes(base64)]).stream().pipeThrough(new DecompressionStream("deflate"));
  return JSON.parse(await new Response(stream).text());
}

export const AsciiArt = {
  mounted() {
    const d = this.el.dataset;
    this.pre = this.el.querySelector("pre");
    this.load();

    if (this.palette) {
      this.canvas = document.createElement("canvas");
      this.pre.replaceWith(this.canvas);
      this.ctx = this.canvas.getContext("2d");
      this.resizer = new ResizeObserver(() => this.size());
      this.resizer.observe(this.canvas);
      this.fit();
    }

    this.handleEvent(d.event, (msg) => {
      if (msg.loop) this.take(msg.loop);
      else if (msg.frame) this.replace(msg.frame);
      else this.patch(msg.runs);
    });

    this.still = matchMedia("(prefers-reduced-motion: reduce)");
    this.onChange = () => this.report();
    this.still.addEventListener("change", this.onChange);
    document.addEventListener("visibilitychange", this.onChange);
    this.seen = false;
    this.watcher = new IntersectionObserver((entries) => {
      this.seen = entries[entries.length - 1].isIntersecting;
      this.report();
    });
    this.watcher.observe(this.el);
    this.ready();
  },

  // Frame 0 and its size, from the element: the picture, row by row, and
  // for a coloured piece its colours.
  load() {
    const d = this.el.dataset;
    this.cols = +d.cols;
    this.rows = +d.rows;
    this.cell = +d.cell || 2;
    this.palette = d.palette ? JSON.parse(d.palette) : null;
    this.ground = d.ground || null;
    const lines = d.text.split("\n");
    const colors = d.colors ? bytes(d.colors) : null;
    this.first = {
      lines,
      colors: lines.map((_, y) => colors && colors.subarray(y * this.cols, (y + 1) * this.cols)),
    };
    this.frame = this.first;
  },

  // The server starts afresh after a reconnect, from frame 0 as the element
  // now gives it (new options may have changed it).
  reconnected() {
    this.stop();
    this.loop = null;
    this.load();
    if (this.canvas) this.fit();
    this.show(this.first);
    this.ready();
  },

  // The canvas keeps the picture's shape, a cell `cell` widths tall.
  fit() {
    this.canvas.style.cssText = `display:block;width:100%;aspect-ratio:${this.cols} / ${this.rows * this.cell}`;
    this.size();
  },

  destroyed() {
    this.stop();
    this.watcher.disconnect();
    this.resizer?.disconnect();
    this.still.removeEventListener("change", this.onChange);
    document.removeEventListener("visibilitychange", this.onChange);
  },

  ready() {
    this.told = this.visible();
    this.pushEventTo(this.el, "ascii_art:ready", {visible: this.told, deflate: canInflate});
  },

  visible() {
    return this.seen && document.visibilityState === "visible" && !this.still.matches;
  },

  // The server ticks only while the picture can be seen and may move; a loop
  // plays only then.
  report() {
    const visible = this.visible();
    if (visible !== this.told) {
      this.told = visible;
      this.pushEventTo(this.el, "ascii_art:visible", {visible});
    }
    if (this.loop) visible ? this.play() : this.stop();
  },

  // A frame as the runs of cells that changed: [y, x, text, colours as
  // base64 or null]. Rows are shared between frames, so a changed row is a
  // new one.
  apply(frame, runs) {
    const next = {lines: frame.lines.slice(), colors: frame.colors.slice()};
    for (const [y, x, text, colors] of runs) {
      const line = next.lines[y];
      next.lines[y] = line.slice(0, x) + text + line.slice(x + text.length);
      if (colors) {
        const row = new Uint8Array(next.colors[y] || this.cols);
        row.set(bytes(colors), x);
        next.colors[y] = row;
      }
    }
    return next;
  },

  patch(runs) {
    if (!this.still.matches) this.show(this.apply(this.frame, runs));
  },

  // The whole picture, perhaps at a new size, after new options: whatever
  // was playing stops, and changes follow from this.
  replace({cols, rows, runs}) {
    this.stop();
    this.loop = null;
    const resized = cols !== this.cols || rows !== this.rows;
    this.cols = cols;
    this.rows = rows;
    const blank = {
      lines: Array.from({length: rows}, () => " ".repeat(cols)),
      colors: Array.from({length: rows}, () => (this.palette ? new Uint8Array(cols) : null)),
    };
    this.frame = this.apply(blank, runs);
    if (this.canvas && resized) this.fit();
    else this.show(this.frame);
  },

  // One cycle: each frame what changed from the one before, or the index of
  // an earlier frame it repeats. It starts at the server's play time.
  async take(loop) {
    const {fps, frames: list} = loop.deflate ? await inflate(loop.deflate) : loop;
    const frames = [];
    let prev = this.first;
    for (const item of list) {
      prev = typeof item === "number" ? frames[item] : this.apply(prev, item);
      frames.push(prev);
    }
    this.loop = {fps, frames, t: loop.t};
    this.report();
  },

  play() {
    if (this.raf) return;
    let last = performance.now();
    const step = (now) => {
      const loop = this.loop;
      const n = loop.frames.length;
      // A frame's timestamp can be a little before the time play started.
      loop.t += Math.max(0, Math.min(now - last, MAX_STEP)) / 1000;
      last = now;
      const frame = loop.frames[((Math.floor(loop.t * loop.fps) % n) + n) % n];
      if (frame !== this.frame) this.show(frame);
      this.raf = requestAnimationFrame(step);
    };
    this.raf = requestAnimationFrame(step);
  },

  stop() {
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = null;
  },

  show(frame) {
    this.frame = frame;
    if (this.ctx) this.draw();
    else this.pre.textContent = frame.lines.join("\n");
  },

  // As wide as it is shown, in device pixels; cells `cell` widths tall.
  size() {
    const w = this.canvas.clientWidth * (window.devicePixelRatio || 1);
    this.canvas.width = Math.round(w);
    this.canvas.height = Math.round((w / this.cols) * this.cell * this.rows);
    this.draw();
  },

  draw() {
    const {ctx, cols, rows, canvas} = this;
    const {lines, colors} = this.frame;
    const cw = canvas.width / cols, ch = canvas.height / rows;
    if (this.ground) {
      ctx.fillStyle = this.ground;
      ctx.fillRect(0, 0, canvas.width, canvas.height);
    } else ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.font = `${cw / 0.6}px ${FONT}`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (let y = 0; y < rows; y++) {
      const row = colors[y];
      let x = 0;
      for (const c of lines[y]) {
        if (c !== " ") {
          ctx.fillStyle = this.palette[row[x]] || this.palette[0];
          ctx.fillText(c, (x + 0.5) * cw, (y + 0.5) * ch);
        }
        x++;
      }
    }
  },
};
