// node tools/port_marks.mjs [upstream dir] [slug ...]
//
// Writes lib/ascii_art/pieces/<slug>.ex and test/pieces/<slug>_test.exs for
// upstream's logo and distro pieces. All 27 logos share one body of code and
// all 22 distros another, differing only in meta, header and drawings, so
// each port is that data around AsciiArt.Kit.Logo or AsciiArt.Kit.Distro.
// The meta comes from importing the piece; the header and the three drawings
// (MONO, ART, INK) from its source. A dev tool, run once per upstream bump.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [upstreamArg, ...picked] = process.argv.slice(2);
const PIECES = resolve(upstreamArg || "tmp/upstream", "src/pieces");

const camel = (slug) => slug.split("-").map((w) => w[0].toUpperCase() + w.slice(1)).join("");
const snake = (slug) => slug.replaceAll("-", "_");
const sentence = (s) => s[0].toUpperCase() + s.slice(1);
const str = (s) => JSON.stringify(s);

// The header comment as paragraphs, "slug: what it is" turned into a sentence.
function header(src, slug) {
  const m = src.match(/^\/\*([\s\S]*?)\*\//);
  const text = m[1].split("\n").map((l) => l.replace(/^\s*\* ?/, "")).join("\n").trim();
  return text
    .split(/\n\s*\n/)
    .map((p) => p.replace(/\s*\n\s*/g, " ").trim())
    .map((p, i) => (i === 0 ? sentence(p.replace(new RegExp(`^${slug.replaceAll("-", "[- ]")}: `, "i"), "")) : p));
}

// A drawing as an Elixir heredoc holding upstream's raw string less its first
// character (the newline after the backtick); the heredoc's own closing
// newline stands for the newline before the closing backtick.
function drawing(raw) {
  const body = raw.slice(1);
  const lines = body.slice(0, -1).split("\n");
  for (const [open, close] of [['~S"""', '"""'], ["~S'''", "'''"]]) {
    if (!body.includes(close)) return `${open}\n${lines.map((l) => (l ? "  " + l : "")).join("\n")}\n  ${close}`;
  }
  // Both heredoc delimiters appear: a list of lines, joined back up.
  return `Enum.join([\n${lines.map((l) => "    " + str(l)).join(",\n")}\n  ], "\\n") <> "\\n"`;
}

function wrap(text, width = 76) {
  const out = [];
  let line = "";
  for (const word of text.split(" ")) {
    if (line && line.length + 1 + word.length > width) {
      out.push(line);
      line = word;
    } else line = line ? line + " " + word : word;
  }
  if (line) out.push(line);
  return out.map((l) => "  " + l).join("\n");
}

const slugs = picked.length
  ? picked
  : readdirSync(PIECES)
      .filter((f) => f.endsWith(".ts") && f !== "index.ts")
      .map((f) => f.slice(0, -3))
      .filter((s) => /category: "(logos|distros)"/.test(readFileSync(`${PIECES}/${s}.ts`, "utf8")));

for (const slug of slugs) {
  const src = readFileSync(`${PIECES}/${slug}.ts`, "utf8");
  const { meta } = await import(pathToFileURL(`${PIECES}/${slug}.ts`).href);
  const logo = meta.category === "logos";
  const [kit, option] = logo ? ["Logo", "shine"] : ["Distro", "scan"];
  const raw = {};
  for (const name of ["MONO", "ART", "INK"]) {
    const m = src.match(new RegExp(`const ${name} = String\\.raw\`([\\s\\S]*?)\`;`));
    if (!m) throw new Error(`${slug}: no ${name}`);
    raw[name] = m[1];
  }
  const doc = [sentence(meta.note) + ".", ...header(src, slug), `Ported from \`src/pieces/${slug}.ts\` in bas3line/ascii (MIT).`];
  const palette = meta.palette.map(str);
  const paletteRows = [];
  for (let i = 0; i < palette.length; i += 6) paletteRows.push("      " + palette.slice(i, i + 6).join(", "));
  const mod = camel(slug);

  writeFileSync(
    `lib/ascii_art/pieces/${snake(slug)}.ex`,
    `defmodule AsciiArt.Pieces.${mod} do
  @moduledoc """
${doc.map((p) => wrap(p)).join("\n\n")}
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.${kit}

  @meta %AsciiArt.Meta{
    name: ${str(meta.name)},
    category: :${meta.category},
    note: ${str(meta.note)},
    cols: ${meta.cols},
    rows: ${meta.rows},
    fps: ${meta.fps},
    options: %{${option}: ${meta.options[option]}},
    bounds: %{${option}: {0, 3600}},
    # The logo's colours for a light page, then for a dark one; each as
    # drawn, then twice lighter for the ${logo ? "glint" : "scan"}.
    palette: [
${paletteRows.join(",\n")}
    ]
  }

  # In one ink.
  @mono ${drawing(raw.MONO)}

  # Drawn for colour, and the colour of each cell: an index into a variant.
  @art ${drawing(raw.ART)}

  @ink ${drawing(raw.INK)}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{${option}: ${option}}), do: ${kit}.init(@meta, ${option}, @mono, @art, @ink)

  @impl true
  def frame(state, t, env), do: ${kit}.frame(state, t, env)
end
`,
  );

  writeFileSync(
    `test/pieces/${snake(slug)}_test.exs`,
    `defmodule AsciiArt.Pieces.${mod}Test do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.${mod}
  use AsciiArt.GoldenCase, slug: ${str(slug)}, piece: AsciiArt.Pieces.${mod}
end
`,
  );
}
console.log(`${slugs.length} marks written`);
