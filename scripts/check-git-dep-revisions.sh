#!/usr/bin/env bash
#
# Fails when a git dependency resolved to a revision nobody reviewed.
#
# pubspec.lock pins git dependencies by `resolved-ref`, so a tag repointed
# upstream cannot change what a build pulls — the lock wins. The gap is that
# regenerating the lock (`flutter pub upgrade`, adding a dependency) re-resolves
# the tag silently, and the next build compiles whatever the author points the
# tag at now. This check turns that silent swap into a failed build.
#
# Why not put the commit SHA in pubspec.yaml instead? pub requires the
# description of a package to be identical everywhere it appears, and
# f-videoplayer's own sub-packages (packages/f_videoplayer_fvp) require
# f_videoplayer with `ref: v0.5.7`. Pointing the root at a raw SHA therefore
# makes version solving fail outright ("... is forbidden").
set -euo pipefail

LOCK="${1:-pubspec.lock}"
EXPECTED_URL="https://github.com/iebb/f-videoplayer.git"
EXPECTED_REV="1e81ed16d036070bea6d08c82eb0797fa1e5d089"
EXPECTED_COUNT=4 # f_videoplayer, f_videoplayer_fvp, f_videoplayer_pip, fvp (override)

test -f "$LOCK" || { echo "error: $LOCK not found" >&2; exit 1; }

urls="$(grep -c "url: \"$EXPECTED_URL\"" "$LOCK" || true)"
revs="$(grep -c "resolved-ref: \"$EXPECTED_REV\"" "$LOCK" || true)"

echo "git dependency $EXPECTED_URL"
echo "  lock entries: $urls (expected $EXPECTED_COUNT)"
echo "  entries pinned to $EXPECTED_REV: $revs"

if [ "$urls" -ne "$EXPECTED_COUNT" ] || [ "$revs" -ne "$EXPECTED_COUNT" ]; then
  echo "::error::$LOCK no longer pins all $EXPECTED_COUNT git dependencies of" \
       "$EXPECTED_URL to $EXPECTED_REV."
  echo "::error::A lock regeneration re-resolved the mutable v0.5.7 tag." \
       "Review the new revision before accepting it."
  grep -B2 -A2 'resolved-ref' "$LOCK" | head -40 >&2 || true
  exit 1
fi

echo "✓ all $EXPECTED_COUNT git dependencies pinned to the reviewed revision"
