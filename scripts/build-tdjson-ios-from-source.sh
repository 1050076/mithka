#!/usr/bin/env bash
# Build ios/tdjson/tdjson.xcframework from verified upstream TDLib source plus
# the vendored patch set in third_party/tdlib-patches — no prebuilt binary is
# ever downloaded.
#
# usage: build-tdjson-ios-from-source.sh
#
# Pins:
#   - upstream TDLib commit from third_party/tdlib-patches/UPSTREAM.pin
#   - vendored patch series guarded by PATCHES.SHA256SUMS
#   - OpenSSL 3.3.2 (pinned by SHA-256) built as a static library per slice
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_ROOT/third_party/tdlib-patches"
DESTINATION="$REPO_ROOT/ios/tdjson/tdjson.xcframework"
UPSTREAM_REPO="https://github.com/tdlib/td.git"
UPSTREAM_SHA="$(awk '$1 == "commit:" { print $2 }' "$PATCH_DIR/UPSTREAM.pin" | tr -d '\r')"
MIN_IOS="${MIN_IOS:-15.0}"
OPENSSL_VERSION="3.3.2"
OPENSSL_SHA256="2e8a40b01979afe8be0bbfb3de5dc1c6709fedb46d6c89c10da114ab5fc3d281"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
BUILD_ROOT="${TDJSON_BUILD_ROOT:-$REPO_ROOT/build/tdjson-ios-src}"
TD_SOURCE="$BUILD_ROOT/td"
GENERATED_TD_SOURCE="$BUILD_ROOT/td-generated"

test -n "$UPSTREAM_SHA"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: the iOS tdjson build requires macOS" >&2
  exit 2
fi
for tool in cmake ninja xcodebuild gperf; do
  command -v "$tool" >/dev/null 2>&1 ||
    { echo "error: missing required tool: $tool" >&2; exit 1; }
done

# --- 0. Verify the vendored patch set before trusting it. --------------------
(
  cd "$PATCH_DIR"
  for f in ./*.patch ./series ./PATCHES.SHA256SUMS; do
    tmp="$(mktemp)"
    tr -d '\r' < "$f" > "$tmp" && mv "$tmp" "$f"
  done
  shasum -a 256 -c PATCHES.SHA256SUMS
  echo "==> patch set checksums verified"
)

mkdir -p "$BUILD_ROOT"

# --- 1. Fetch upstream TDLib at the pinned commit and verify it. -------------
if [[ ! -d "$TD_SOURCE/.git" ]]; then
  git clone --filter=blob:none "$UPSTREAM_REPO" "$TD_SOURCE"
fi
if [[ "$(git -C "$TD_SOURCE" rev-parse HEAD 2>/dev/null || true)" != "$UPSTREAM_SHA" ]]; then
  git -C "$TD_SOURCE" fetch --quiet origin "$UPSTREAM_SHA"
  git -C "$TD_SOURCE" checkout --quiet --detach "$UPSTREAM_SHA"
fi
git -C "$TD_SOURCE" reset --hard --quiet "$UPSTREAM_SHA"
git -C "$TD_SOURCE" clean -fdxq
echo "==> TDLib source at verified commit $UPSTREAM_SHA"

# --- 2. Copy + patch, then run TDLib's own source generator. -----------------
rm -rf "$GENERATED_TD_SOURCE" "$BUILD_ROOT/native-generate"
mkdir -p "$GENERATED_TD_SOURCE"
rsync -a --delete "$TD_SOURCE/" "$GENERATED_TD_SOURCE/"

while IFS= read -r patch_name; do
  patch_name="${patch_name%$'\r'}"
  [[ -n "$patch_name" ]] || continue
  [[ "$patch_name" != \#* ]] || continue
  patch_file="$PATCH_DIR/$patch_name"
  test -f "$patch_file"
  git -C "$GENERATED_TD_SOURCE" apply --unidiff-zero "$patch_file"
  echo "==> applied $patch_name"
done < "$PATCH_DIR/series"

TD_VERSION="$(sed -n 's/project(TDLib VERSION \([^ ]*\).*/\1/p' \
  "$GENERATED_TD_SOURCE/CMakeLists.txt" | head -n 1)"
test -n "$TD_VERSION"

cmake -S "$GENERATED_TD_SOURCE" -B "$BUILD_ROOT/native-generate" -G Ninja \
  -DTD_GENERATE_SOURCE_FILES=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_ROOT/native-generate"

# --- 3. OpenSSL, static, one build per slice. -------------------------------
build_openssl() {
  local name="$1" target="$2" min_flag="$3"
  local out="$BUILD_ROOT/$name/openssl"
  local src="$BUILD_ROOT/$name/openssl-src"

  if [[ -f "$out/lib/libcrypto.a" && -f "$out/lib/libssl.a" ]]; then
    echo "==> reusing OpenSSL $OPENSSL_VERSION for $name"
    return
  fi

  rm -rf "$src" "$out"
  mkdir -p "$src" "$out"

  local tarball="$BUILD_ROOT/openssl-$OPENSSL_VERSION.tar.gz"
  if [[ ! -f "$tarball" ]]; then
    curl -fL --retry 5 --retry-all-errors "$OPENSSL_URL" -o "$tarball"
  fi
  printf '%s  %s\n' "$OPENSSL_SHA256" "$tarball" | shasum -a 256 -c -
  tar xzf "$tarball" -C "$src" --strip-components=1

  echo "==> building OpenSSL $OPENSSL_VERSION for $name"
  (
    cd "$src"
    ./Configure "$target" no-shared no-tests no-apps no-docs no-hw no-engine \
      "$min_flag=$MIN_IOS" "--prefix=$out" --libdir=lib
    make -j"$(sysctl -n hw.ncpu)" build_libs
    make install_dev
  )
}

# --- 4. Build one tdjson.framework per slice. -------------------------------
build_slice() {
  local name="$1" sdk="$2" platform="$3" min_flag="$4"
  local openssl="$BUILD_ROOT/$name/openssl"
  local td_build="$BUILD_ROOT/$name/td"
  local framework="$BUILD_ROOT/$name/tdjson.framework"

  echo "==> building tdjson for $name"
  rm -rf "$td_build"
  cmake -S "$GENERATED_TD_SOURCE" -B "$td_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS="$platform" \
    -DOPENSSL_FOUND=1 \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$openssl/lib/libssl.a" \
    -DOPENSSL_INCLUDE_DIR="$openssl/include" \
    -DZLIB_LIBRARY="$(xcrun --sdk "$sdk" --show-sdk-path)/usr/lib/libz.tbd" \
    -DZLIB_INCLUDE_DIR="$(xcrun --sdk "$sdk" --show-sdk-path)/usr/include"
  cmake --build "$td_build" --target tdjson

  local dylib
  dylib="$(find "$td_build" -maxdepth 2 -type f -name 'libtdjson*.dylib' | head -n 1)"
  test -n "$dylib"

  rm -rf "$framework"
  mkdir -p "$framework/Headers" "$framework/Modules"
  cp "$dylib" "$framework/tdjson"
  install_name_tool -id "@rpath/tdjson.framework/tdjson" "$framework/tdjson"
  cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>tdjson</string>
  <key>CFBundleIdentifier</key>
  <string>ad.neko.tdjson</string>
  <key>CFBundleName</key>
  <string>tdjson</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>$TD_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$TD_VERSION</string>
  <key>MinimumOSVersion</key>
  <string>$MIN_IOS</string>
</dict>
</plist>
PLIST
  cat > "$framework/Modules/module.modulemap" <<'MODULEMAP'
framework module tdjson {
  umbrella header "tdjson.h"
  export *
  module * { export * }
}
MODULEMAP
  cp "$GENERATED_TD_SOURCE/td/telegram/td_json_client.h" \
    "$framework/Headers/tdjson.h"
}

build_openssl ios-arm64 ios64-xcrun "-mios-version-min"
build_openssl ios-arm64-simulator iossimulator-arm64-xcrun "-mios-simulator-version-min"
build_slice ios-arm64 iphoneos iphoneos "-mios-version-min"
build_slice ios-arm64-simulator iphonesimulator iphonesimulator "-mios-simulator-version-min"

# --- 5. Assemble and verify the XCFramework. --------------------------------
rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
xcodebuild -create-xcframework \
  -framework "$BUILD_ROOT/ios-arm64/tdjson.framework" \
  -framework "$BUILD_ROOT/ios-arm64-simulator/tdjson.framework" \
  -output "$DESTINATION"

for binary in \
  "$DESTINATION/ios-arm64/tdjson.framework/tdjson" \
  "$DESTINATION/ios-arm64-simulator/tdjson.framework/tdjson"; do
  test -s "$binary"
  symbols="$(nm -gU "$binary")"
  for symbol in \
    _td_create_client_id \
    _td_mithka_export_session_string \
    _td_mithka_import_session_string \
    _td_mithka_last_error \
    _td_mithka_set_transfer_boost; do
    grep " $symbol$" <<<"$symbols" >/dev/null
  done
done

echo "==> built $DESTINATION from verified source"
echo "upstream: $UPSTREAM_SHA"
echo "tdlib:    $TD_VERSION"
