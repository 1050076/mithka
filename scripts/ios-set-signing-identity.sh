#!/usr/bin/env bash
#
# Rewrites the checked-in Apple identity (team id, bundle identifiers, app
# group) to a real account's values.
#
# The repository ships the upstream author's identifiers — team 7P8CLHDH5G,
# bundle ad.neko.mithka, app group group.ad.neko.mithka.notifications. None of
# them is a secret, but they are not ours: the App IDs, the app group and the
# provisioning profiles belong to another team, and App Store Connect has no
# app record we could upload to. Building against them therefore cannot produce
# something we can sign or ship.
#
# Every replacement asserts its occurrence count *before* writing anything, so
# an upstream reshuffle fails the build loudly instead of shipping a
# half-renamed app.
#
# Inputs (environment):
#   IOS_TEAM_ID              required, 10-character Apple team id
#   IOS_BUNDLE_ID            required, base bundle id, e.g. com.example.mithka
#   IOS_APP_GROUP            optional, defaults to group.<IOS_BUNDLE_ID>.notifications
#   IOS_STRIP_ENTITLEMENTS   optional, space-separated entitlement keys to drop
#                            from both entitlements files. Defaults to
#                            com.apple.developer.private-cloud-compute, which
#                            Apple grants only on request, so leaving it in
#                            fails archiving on most accounts.
set -euo pipefail

UPSTREAM_TEAM_ID="7P8CLHDH5G"
UPSTREAM_BUNDLE_ID="ad.neko.mithka"
UPSTREAM_APP_GROUP="group.ad.neko.mithka.notifications"
UPSTREAM_IAP_PREFIX="ad.neko.mithka.pro"

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
PRO_BRIDGE="ios/Runner/MithkaProBridge.swift"
PRO_SERVICE="lib/pro/mithka_pro_service.dart"
INFO_PLIST="ios/Runner/Info.plist"
HANDOFF="apple/HandoffBridge.swift"
EXPORT_OPTIONS="ios/ExportOptions.app-store-connect.plist"
RUNNER_ENTITLEMENTS="ios/Runner/Runner.entitlements"
EXTENSION_ENTITLEMENTS="ios/NotificationService/NotificationService.entitlements"
APP_GROUP_CONSTANT="ios/Runner/NotificationCommunicationContent.swift"

TEAM_ID="${IOS_TEAM_ID:-}"
BUNDLE_ID="${IOS_BUNDLE_ID:-}"
APP_GROUP="${IOS_APP_GROUP:-group.${BUNDLE_ID}.notifications}"

fail() { echo "::error::$*" >&2; exit 1; }

[ -n "$TEAM_ID" ] || fail "IOS_TEAM_ID is not set (10-character Apple team id)"
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "IOS_TEAM_ID '$TEAM_ID' is not 10 uppercase alphanumerics"
[ -n "$BUNDLE_ID" ] || fail "IOS_BUNDLE_ID is not set (e.g. com.example.mithka)"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || fail "IOS_BUNDLE_ID '$BUNDLE_ID' is not a reverse-DNS identifier"
[ "$BUNDLE_ID" != "$UPSTREAM_BUNDLE_ID" ] || fail "IOS_BUNDLE_ID is the upstream author's bundle id"
case "$APP_GROUP" in
  group.*) ;;
  *) fail "IOS_APP_GROUP '$APP_GROUP' must start with 'group.'" ;;
esac

# replace <from> with <to> across <file>... — count first, rewrite only when the
# count matches the reviewed expectation.
replace_across() { # expected_count from to file...
  local want="$1" from="$2" to="$3"
  shift 3
  local files=("$@") total=0 got
  for f in "${files[@]}"; do
    [ -f "$f" ] || fail "expected file $f is missing"
    got="$(grep -o -F -- "$from" "$f" | wc -l | tr -d ' ')"
    total=$((total + got))
  done
  if [ "$total" -ne "$want" ]; then
    fail "expected $want occurrences of '$from' in ${files[*]}, found $total — upstream layout changed, re-derive the counts in $0"
  fi
  FROM="$from" TO="$to" perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "${files[@]}"
  echo "✓ $from → $to ($total occurrences)"
}

echo "▸ applying Apple identity: team=$TEAM_ID bundle=$BUNDLE_ID group=$APP_GROUP"

# Team id: 6 occurrences in the Xcode project + 1 in the export options.
replace_across 7 "$UPSTREAM_TEAM_ID" "$TEAM_ID" "$PBXPROJ" "$EXPORT_OPTIONS"

# Bundle identifiers: 12 in the Xcode project (Runner, NotificationService,
# RunnerTests, RunnerUITests), the Pro in-app-purchase product ids on both the
# Swift and the Dart side (the Dart constants are compared against what StoreKit
# returns, so a mismatch breaks purchases), and the NSUserActivity type shared by
# Info.plist and HandoffBridge (they must move together).
replace_across 12 "$UPSTREAM_BUNDLE_ID" "$BUNDLE_ID" "$PBXPROJ"
replace_across 4 "$UPSTREAM_IAP_PREFIX" "$BUNDLE_ID.pro" "$PRO_BRIDGE" "$PRO_SERVICE"
replace_across 1 "$UPSTREAM_BUNDLE_ID" "$BUNDLE_ID" "$INFO_PLIST"
replace_across 1 "$UPSTREAM_BUNDLE_ID" "$BUNDLE_ID" "$HANDOFF"

# App group: both entitlements plus the Swift constant the notification service
# reads its shared defaults through. Miss the constant and the app and the
# extension stop seeing each other's data.
replace_across 1 "$UPSTREAM_APP_GROUP" "$APP_GROUP" "$RUNNER_ENTITLEMENTS"
replace_across 1 "$UPSTREAM_APP_GROUP" "$APP_GROUP" "$EXTENSION_ENTITLEMENTS"
replace_across 1 "$UPSTREAM_APP_GROUP" "$APP_GROUP" "$APP_GROUP_CONSTANT"

# Entitlements Apple grants only on request would fail archiving on a normal
# account, so drop them unless the caller opts out.
STRIP_ENTITLEMENTS="${IOS_STRIP_ENTITLEMENTS:-com.apple.developer.private-cloud-compute}"
# Explicit opt-out for accounts Apple has granted the gated capabilities.
[ "$STRIP_ENTITLEMENTS" = "none" ] && STRIP_ENTITLEMENTS=""
strip_entitlement() { # key file
  local key="$1" f="$2"
  if ! grep -q -F -- "<key>$key</key>" "$f"; then
    echo "  ($key absent from $f)"
    return 0
  fi
  KEY="$key" perl -0777 -pi -e \
    's{\s*<key>\Q$ENV{KEY}\E</key>\s*<(true|false)/>}{}g; s{\s*<key>\Q$ENV{KEY}\E</key>\s*<string>[^<]*</string>}{}g' \
    "$f"
  grep -q -F -- "<key>$key</key>" "$f" && fail "could not strip $key from $f"
  echo "✓ stripped $key from $f"
}
for key in $STRIP_ENTITLEMENTS; do
  strip_entitlement "$key" "$RUNNER_ENTITLEMENTS"
  strip_entitlement "$key" "$EXTENSION_ENTITLEMENTS"
done

# Optional: rename the app on the device (the icon label). Off unless
# IOS_APP_DISPLAY_NAME is set, so the repository keeps its own name.
if [ -n "${IOS_APP_DISPLAY_NAME:-}" ]; then
  DISPLAY_NAME="$IOS_APP_DISPLAY_NAME"
  pairs="$(grep -c -E '<key>(CFBundleDisplayName|CFBundleName)</key>' "$INFO_PLIST" || true)"
  [ "$pairs" -eq 2 ] || fail "expected CFBundleDisplayName + CFBundleName in $INFO_PLIST, found $pairs"
  NAME="$DISPLAY_NAME" perl -0777 -pi -e \
    's{(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)}{$1 . $ENV{NAME} . $2}ge' "$INFO_PLIST"
  NAME="$DISPLAY_NAME" perl -0777 -pi -e \
    's{(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)}{$1 . $ENV{NAME} . $2}ge' "$INFO_PLIST"
  grep -q -F "<string>$DISPLAY_NAME</string>" "$INFO_PLIST" || fail "could not apply display name $DISPLAY_NAME"
  echo "✓ device display name → $DISPLAY_NAME"
fi

# Optional: manual signing. When profile names are supplied, write a
# PROVISIONING_PROFILE_SPECIFIER next to each target's bundle identifier so
# xcodebuild has no reason to talk to App Store Connect at archive time
# (automatic signing needs API-key auth that can fail; a profile built by
# scripts in this repository removes that dependency).
if [ -n "${IOS_PROFILE_APP:-}" ]; then
  APP_PROFILE="$IOS_PROFILE_APP" \
  EXT_PROFILE="${IOS_PROFILE_EXTENSION:-$IOS_PROFILE_APP}" \
  APP_BUNDLE="$BUNDLE_ID" \
  perl -0777 -pi -e '
    my ($app, $ext, $base) = ($ENV{APP_PROFILE}, $ENV{EXT_PROFILE}, $ENV{APP_BUNDLE});
    s{(PRODUCT_BUNDLE_IDENTIFIER = )([^;]+)(;)}{
      my ($head, $id, $tail) = ($1, $2, $3);
      my $profile = $id eq $base ? $app
                  : $id eq $base . ".NotificationService" ? $ext
                  : "";
      # Quote the value: a profile name usually contains spaces, and an
      # unquoted value with spaces makes the whole project file unparseable
      # ("The project 'Runner' is damaged").
      $profile ? $head . $id . $tail . "\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = \"" . $profile . "\";"
               : $head . $id . $tail;
    }ge;
  ' "$PBXPROJ"
  injected="$(grep -c 'PROVISIONING_PROFILE_SPECIFIER = "[^"]\+";' "$PBXPROJ" || true)"
  [ "$injected" -eq 6 ] || fail "expected 6 quoted PROVISIONING_PROFILE_SPECIFIER entries (3 app + 3 extension), found $injected"
  echo "✓ manual signing profiles assigned ($injected targets)"
fi

# The rewritten files must no longer mention the upstream identity.
leftovers="$(grep -l -F -e "$UPSTREAM_TEAM_ID" -e "$UPSTREAM_BUNDLE_ID" -e "$UPSTREAM_APP_GROUP" \
  "$PBXPROJ" "$PRO_BRIDGE" "$PRO_SERVICE" "$INFO_PLIST" "$HANDOFF" "$EXPORT_OPTIONS" \
  "$RUNNER_ENTITLEMENTS" "$EXTENSION_ENTITLEMENTS" "$APP_GROUP_CONSTANT" 2>/dev/null || true)"
[ -z "$leftovers" ] || fail "upstream identity still present in: $leftovers"

# Informational: strings that keep the upstream bundle id on purpose (keychain
# service label, HTTP user agent, NSUserActivity type, Android package).
echo "▸ left as-is on purpose (not team-scoped):"
grep -rl -F "$UPSTREAM_BUNDLE_ID" lib/ android/ 2>/dev/null | sed 's/^/    /' || true

echo "✓ Apple identity applied"
