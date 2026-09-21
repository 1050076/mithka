#!/usr/bin/env bash
#
# Fails when a build carries real Telegram credentials.
#
# This fork and its releases are public, so anything compiled in can be pulled
# straight back out — `strings` on the AOT snapshot shows a string constant.
# Zero-credential builds therefore ship apiId 0 plus the placeholder hash, and
# this asserts that against the actual binary instead of trusting the workflow
# environment: an env var could be injected, a secret added, or a build run from
# a different branch, and nothing else in the pipeline would notice.
#
# Usage: check-no-embedded-credentials.sh <path>
#   <path> may be an .app bundle, an unpacked Windows build directory, or the
#   AOT snapshot file itself.
set -euo pipefail

TARGET="${1:?usage: $0 <Runner.app | build dir | app.so>}"
PLACEHOLDER="${EXPECTED_API_HASH_PLACEHOLDER:-not-configured}"
# A real Telegram api hash looks like "<8-10 digit api id>:<32+ char secret>".
CREDENTIAL_PATTERN='^[0-9]{6,10}:[A-Za-z0-9_-]{28,}$'

snapshots=()
if [ -f "$TARGET" ]; then
  snapshots=("$TARGET")
else
  while IFS= read -r found; do
    snapshots+=("$found")
  done < <(
    find "$TARGET" -type f \
      \( -name 'App' -path '*App.framework*' -o -name 'app.so' -o -name 'kernel_blob.bin' \) \
      2>/dev/null | head -5
  )
fi

[ "${#snapshots[@]}" -gt 0 ] || {
  echo "::error::no AOT snapshot found under $TARGET"
  exit 1
}

status=0
placeholder_seen=0
for snapshot in "${snapshots[@]}"; do
  echo "▸ scanning $snapshot"
  # grep -a reads the binary as text; no dependency on binutils `strings`.
  matches="$(grep -a -o -E "$CREDENTIAL_PATTERN" "$snapshot" 2>/dev/null || true)"
  if [ -n "$matches" ]; then
    count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
    # Never print the match itself: CI logs of a public repository are readable
    # by anyone, and the whole point of this check is that the value is secret.
    first_two="$(printf '%s\n' "$matches" | head -1 | cut -c1-2)"
    echo "::error::a Telegram api hash is compiled into $snapshot ($count match(es), first starts with ${first_two}…)"
    status=1
  fi
  if grep -a -q -F "$PLACEHOLDER" "$snapshot" 2>/dev/null; then
    placeholder_seen=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "::error::build carries embedded credentials — build with the placeholder values instead"
  exit 1
fi

# The placeholder is the real guarantee: the credential constant that would hold
# a real api hash holds this string instead, so its presence is what proves no
# secret was injected. Its absence means either a credential build or a build
# whose constant was replaced wholesale.
if [ "$placeholder_seen" -ne 1 ]; then
  echo "::error::$PLACEHOLDER not found in the AOT snapshot of $TARGET — this build was not made with placeholder credentials"
  exit 1
fi

echo "✓ no embedded credentials; $PLACEHOLDER placeholder present as expected"
