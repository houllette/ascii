#!/bin/sh
# tools/merge_batch.sh <workspace>: copies the piece modules and tests a
# porting workspace added (tmp/agents/<name>) into the project, then
# regenerates the registry. Existing files are never overwritten.
set -e
W="$1"
for f in "$W"/lib/ascii/pieces/*.ex; do
  b=$(basename "$f")
  [ -e "lib/ascii/pieces/$b" ] || { cp "$f" "lib/ascii/pieces/$b"; echo "added $b"; }
done
for f in "$W"/test/pieces/*_test.exs; do
  b=$(basename "$f")
  [ -e "test/pieces/$b" ] || cp "$f" "test/pieces/$b"
done
mix run tools/gen_registry.exs
