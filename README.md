# AsciiArt

An Elixir port of [bas3line/ascii](https://github.com/bas3line/ascii)
(ascii.rest) — animated ASCII art. Upstream is a TypeScript library of ~170–190
animated pieces for web pages; this port generates the frames in Elixir.

## Development

```sh
mix deps.get
mix test
mix precommit   # same checks CI runs
```

Tool versions are pinned in `.tool-versions`.

## Agent tooling

[Tidewave](https://tidewave.ai) is configured via `.mcp.json`. Start the server
with `mix tidewave` (port 4000); the MCP endpoint is only live while it runs.
Check the connection with `/mcp` in Claude Code.
