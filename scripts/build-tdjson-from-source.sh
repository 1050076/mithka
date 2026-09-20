#!/usr/bin/env bash
# Build tdjson from verified upstream TDLib source + the vendored patch set
# in third_party/tdlib-patches — no prebuilt binary is ever downloaded.
#
# usage: build-tdjson-from-source.sh <windows|linux|macos> OUTPUT [x64|arm64|universal]
#
# Pins (must stay in sync with third_party/tdlib-patches/UPSTREAM.pin):
#   - upstream TDLib commit from tdlib/td (verified by full sha1)
#   - patch series in third_party/tdlib-patches (guarded by PATCHES.SHA256SUMS)
set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "usage: $0 <windows|linux|macos> OUTPUT_LIBRARY [ARCHITECTURE]" >&2
  exit 2
fi

PLATFORM="$1"
OUTPUT_LIBRARY="$2"
ARCHITECTURE="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_ROOT/third_party/tdlib-patches"
UPSTREAM_REPO="https://github.com/tdlib/td.git"
UPSTREAM_SHA="$(awk '$1 == "commit:" { print $2 }' "$PATCH_DIR/UPSTREAM.pin")"
BUILD_ROOT="${TDJSON_BUILD_ROOT:-$REPO_ROOT/build/tdjson-src-$PLATFORM-${ARCHITECTURE:-default}}"
TD_SOURCE="$BUILD_ROOT/td"
TD_BUILD="$BUILD_ROOT/td-build"

test -n "$UPSTREAM_SHA"

case "$PLATFORM" in
  windows|linux)
    ARCHITECTURE="${ARCHITECTURE:-x64}"
    ;;
  macos)
    ARCHITECTURE="${ARCHITECTURE:-universal}"
    ;;
  *) echo "error: unsupported platform: $PLATFORM" >&2; exit 2 ;;
esac

# The vendored patches are part of the trusted build definition; refuse to
# build if anyone modified them without updating the checksum manifest.
# Strip CR first: a checkout with autocrlf=true rewrites the manifest and the
# patch files, which would otherwise break both the checksum and `git apply`.
(
  cd "$PATCH_DIR"
  find . -name '*.patch' -o -name series -o -name PATCHES.SHA256SUMS |
    while IFS= read -r f; do
      tmp="$(mktemp)"
      tr -d '\r' < "$f" > "$tmp" && mv "$tmp" "$f"
    done
  sha256sum --quiet --check PATCHES.SHA256SUMS
  echo "==> patch set checksums verified"
)

mkdir -p "$(dirname "$OUTPUT_LIBRARY")" "$BUILD_ROOT"

# --- 1. Fetch upstream TDLib at the pinned commit and VERIFY it. -------------
if [[ ! -d "$TD_SOURCE/.git" ]] ||
   [[ "$(git -C "$TD_SOURCE" rev-parse HEAD 2>/dev/null || true)" != "$UPSTREAM_SHA" ]]; then
  rm -rf "$TD_SOURCE"
  git init -q "$TD_SOURCE"
  git -C "$TD_SOURCE" remote add origin "$UPSTREAM_REPO"
fi
if [[ "$(git -C "$TD_SOURCE" rev-parse HEAD 2>/dev/null || true)" != "$UPSTREAM_SHA" ]]; then
  git -C "$TD_SOURCE" fetch origin "$UPSTREAM_SHA"
  git -C "$TD_SOURCE" checkout -q --detach "$UPSTREAM_SHA"
fi
git -C "$TD_SOURCE" reset --hard "$UPSTREAM_SHA"
git -C "$TD_SOURCE" clean -fdx
echo "==> TDLib source at verified commit $UPSTREAM_SHA"

# --- 2. Apply the vendored patch series. -------------------------------------
while IFS= read -r patch_name; do
  patch_name="${patch_name%$'\r'}"
  [[ -n "$patch_name" ]] || continue
  [[ "$patch_name" != \#* ]] || continue
  patch_file="$PATCH_DIR/$patch_name"
  test -f "$patch_file"
  git -C "$TD_SOURCE" apply --unidiff-zero "$patch_file"
  echo "==> applied $patch_name"
done < "$PATCH_DIR/series"

# --- 3. Build with the same recipes as the official mithka-tdjson scripts. ---
rm -rf "$TD_BUILD"

case "$PLATFORM" in
  linux)
    cmake -S "$TD_SOURCE" -B "$TD_BUILD" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DTD_ENABLE_LTO=OFF
    cmake --build "$TD_BUILD" --target tdjson --parallel "${TD_BUILD_JOBS:-2}"
    built_library="$(find "$TD_BUILD" -type f -name 'libtdjson.so*' -print -quit)"
    ;;
  macos)
    cmake -S "$TD_SOURCE" -B "$TD_BUILD" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES='arm64;x86_64' \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 \
      -DTD_ENABLE_LTO=OFF \
      -DOPENSSL_ROOT_DIR="$(brew --prefix openssl)" \
      -DOPENSSL_USE_STATIC_LIBS=TRUE
    cmake --build "$TD_BUILD" --target tdjson --parallel "${TD_BUILD_JOBS:-2}"
    built_library="$(find "$TD_BUILD" -type f -name 'libtdjson*.dylib' -print -quit)"
    ;;
  windows)
    if [[ -n "${VCPKG_INSTALLATION_ROOT:-}" ]]; then
      vcpkg_toolchain="$(cygpath -m "$VCPKG_INSTALLATION_ROOT/scripts/buildsystems/vcpkg.cmake")"
      cmake -S "$TD_SOURCE" -B "$TD_BUILD" \
        -G 'Visual Studio 17 2022' -A x64 \
        -DCMAKE_TOOLCHAIN_FILE="$vcpkg_toolchain" \
        -DVCPKG_TARGET_TRIPLET=x64-windows-static \
        -DTD_ENABLE_LTO=OFF
    else
      cmake -S "$TD_SOURCE" -B "$TD_BUILD" \
        -G 'Visual Studio 17 2022' -A x64 \
        -DTD_ENABLE_LTO=OFF
    fi
    cmake --build "$TD_BUILD" --target tdjson --config Release --parallel "${TD_BUILD_JOBS:-2}"
    built_library="$(find "$TD_BUILD" -type f -iname 'tdjson.dll' -print -quit)"
    ;;
esac

if [[ -z "${built_library:-}" || ! -s "$built_library" ]]; then
  echo "error: tdjson library was not produced for $PLATFORM" >&2
  exit 1
fi

cp "$built_library" "$OUTPUT_LIBRARY"
echo "Built $PLATFORM $ARCHITECTURE tdjson from verified source: $OUTPUT_LIBRARY"
echo "upstream:   $UPSTREAM_SHA"
echo "patches:    $(sha256sum "$PATCH_DIR"/*.patch | sha256sum | cut -d' ' -f1)"
