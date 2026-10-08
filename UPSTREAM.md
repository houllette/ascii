# Upstream

This library ports [bas3line/ascii](https://github.com/bas3line/ascii)
([ascii.rest](https://ascii.rest)), MIT licensed, © bas3line.

| | |
| --- | --- |
| Repository | https://github.com/bas3line/ascii |
| Commit | `fcb644403bfc25af0002e415d1006dd10b99ca34` |
| Commit date | 2026-10-07T23:40:31+05:30 |
| Subject | fixes: rows on android, a play button under reduced motion, faster scenes on phones (#11) |
| Pieces | 191 |

The same commit is `AsciiArt.upstream_commit/0`, and every golden fixture
records the commit it was generated from.

## Regenerating the fixtures

The goldens in `test/fixtures/golden/` and `test/fixtures/js_math.json` are
generated from upstream with Node. `mix test` never needs Node.

```sh
git clone https://github.com/bas3line/ascii tmp/upstream
git -C tmp/upstream checkout fcb644403bfc25af0002e415d1006dd10b99ca34
NODE=/path/to/x64/node mix ascii_art.golden
```

Use an **x64** build of Node 22.18 or later (on Apple silicon, the darwin-x64
build runs under Rosetta). arm64 builds of V8 fuse multiply-adds inside
`Math.sin`, `Math.log` and friends, which changes their last bit; see
`PORTING.md`. The fixtures in this repository were made with Node v22.21.1
darwin-x64.

To move to a newer upstream: check out the new commit in `tmp/upstream`,
update the commit here and in `lib/ascii_art.ex`, regenerate, and run
`mix test`. Every piece whose frames changed fails its golden test.
