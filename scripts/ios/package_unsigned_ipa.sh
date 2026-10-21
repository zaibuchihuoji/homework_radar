#!/usr/bin/env bash
set -euo pipefail

ROOT=$(pwd)
APP="$ROOT/build/ios/iphoneos/Runner.app"
OUT="$ROOT/build/ios/ipa"
test -d "$APP"
test ! -f "$APP/embedded.mobileprovision"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")" = 'iPhoneOS'

# Check the actual binaries, so a simulator .app can never be mislabeled as IPA.
for binary in "$APP/Runner" "$APP/Frameworks/App.framework/App" "$APP/Frameworks/Flutter.framework/Flutter"; do
  xcrun lipo -verify_arch arm64 "$binary"
  xcrun vtool -show-build "$binary" | grep -Eq 'platform +IOS$'
done

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
mkdir -p "$OUT"
STAGE=$(mktemp -d)
mkdir "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/Runner.app"
IPA="$OUT/homework-radar-$VERSION-ios-unsigned.ipa"
(cd "$STAGE" && ditto -c -k --keepParent Payload "$IPA")
python3 scripts/ios/verify_ipa.py "$IPA"
(cd "$OUT" && shasum -a 256 "$(basename "$IPA")" > SHA256SUMS)
