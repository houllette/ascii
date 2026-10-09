# Migrating to ascii

Version 0.3.0 moves the library from the Hex package and OTP application
`ascii_art` to `ascii`. All public modules move from `AsciiArt` to `Ascii`,
including structs, behaviours, Phoenix components and Mix tasks. This is a
breaking release with no compatibility aliases or bridge package.

## Updating a consumer

Replace the `ascii_art` dependency with:

```elixir
# needs: a mix.exs to put it in
{:ascii, "~> 0.4.0"}
```

Replace `AsciiArt` with `Ascii` in aliases, imports, function calls, struct
patterns, behaviours and module names passed to configuration or supervisors.
Custom pieces implement `Ascii.Piece` and return `Ascii.Meta` data.

Update application references such as `Application.app_dir/2`, `otp_app`,
explicit application lists and `Plug.Static`'s `from` option to `:ascii`.
The library remains a plain library with no application supervision tree.

The following names also change:

| Before | After |
| --- | --- |
| `mix ascii_art.play`, `.svg`, `.top`, `.perf`, `.golden` | `mix ascii.play`, `.svg`, `.top`, `.perf`, `.golden` |
| `{:ascii_art_frame, ref, frame}` | `{:ascii_frame, ref, frame}` |
| `{:ascii_art_telemetry, feed, readings}` | `{:ascii_telemetry, feed, readings}` |
| `{:ascii_art, id, info}` from interactive Phoenix players | `{:ascii, id, info}` |
| JavaScript export and LiveView hook `AsciiArt` | `Ascii` |
| `deps/ascii_art/priv/static/ascii_art_hook.js` | `deps/ascii/priv/static/ascii_hook.js` |
| Browser events prefixed with `ascii_art:` | Events prefixed with `ascii:` |

For Phoenix, update the hook import and registration together with the Elixir
dependency:

```javascript
import {Ascii} from "../../deps/ascii/priv/static/ascii_hook.js"

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...Hooks, Ascii},
  // Your existing params and other options.
})
```

Rebuild the consumer's JavaScript assets and reload its browser sessions so
the new hook and server use the same event names. Generated live-component
DOM IDs now start with `ascii-`; update selectors that relied on the previous
`ascii-art-` prefix.

Remove the old lock entry and fetch the new dependency, then compile and run
the consumer's tests:

```sh
mix deps.unlock ascii_art
mix deps.get
mix compile --warnings-as-errors
mix test
```

The upstream piece slugs and golden fixtures are unchanged. Native diagrams
and their optional element colours are available through `Ascii.Diagram` and
`Ascii.Mermaid`; see the [diagram guide](diagrams.md).

## Publishing the renamed library

The first `ascii` release was 0.3.0. Subsequent releases continue under `ascii`;
the existing `ascii_art` releases retain their original package name. The
repository is now [houllette/ascii](https://github.com/houllette/ascii).

Before publishing, run `mix precommit`, inspect `mix hex.build --unpack`, and
run `mix hex.publish --dry-run --yes`. Verify the built package in a fresh consumer,
including its optional integrations and static assets. After publishing with
`mix hex.publish`, repeat the consumer check with the dependency fetched from
Hex.

Once the new package is verified on Hex, retire each existing `ascii_art`
release with reason `renamed` and a message pointing to `ascii`. For example:

```sh
mix hex.retire ascii_art 0.2.2 renamed --message "Renamed to ascii; see ascii's migration guide for the 0.3.0 API changes."
```

Retirement keeps old releases resolvable and displays a migration warning.
It does not redirect existing dependencies. See Hex's
[publishing](https://hexdocs.pm/hex/Mix.Tasks.Hex.Publish.html) and
[retirement](https://hexdocs.pm/hex/Mix.Tasks.Hex.Retire.html) documentation.
