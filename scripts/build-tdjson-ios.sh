#!/usr/bin/env bash
#
# Ensures the TDLib XCFramework consumed by the iOS Runner exists.
#
# Preferred path: build it from verified upstream source + the vendored patch
# set (scripts/build-tdjson-ios-from-source.sh) — no prebuilt binary involved.
# Fallback: download the checksum-pinned release asset, for machines without
# the iOS build toolchain.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESTINATION="$REPO_ROOT/ios/tdjson/tdjson.xcframework"

# An already-built framework from source is used as-is.
if [[ "${TDJSON_FROM_SOURCE:-0}" != "1" &&
      -f "$DESTINATION/ios-arm64/tdjson.framework/tdjson" ]]; then
  "$SCRIPT_DIR/check-tdjson-session-symbols.sh" "$DESTINATION"
  echo "Reusing existing source-built iOS tdjson XCFramework."
  exit 0
fi

if [[ "${TDJSON_FROM_SOURCE:-0}" == "1" ]]; then
  "$SCRIPT_DIR/build-tdjson-ios-from-source.sh"
  "$SCRIPT_DIR/check-tdjson-session-symbols.sh" "$DESTINATION"
  echo "Installed source-built iOS tdjson XCFramework."
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "error: Python 3 is required to install tdjson artifacts" >&2
  exit 1
fi

"$PYTHON" "$SCRIPT_DIR/install-tdjson-artifact.py" \
  tdjson-ios.xcframework.zip \
  "$DESTINATION"
"$SCRIPT_DIR/check-tdjson-session-symbols.sh" "$DESTINATION"

echo "Installed pinned iOS tdjson XCFramework."
echo "Now run: cd ios && pod install   (then: flutter run)"
