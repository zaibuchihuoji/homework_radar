#!/usr/bin/env bash
set -euo pipefail

ROOT=$(pwd)
APP="$ROOT/build/ios/iphoneos/Runner.app"
OUT="$ROOT/build/ios/ipa"
mkdir -p "$OUT"
test -d "$APP"
test ! -f "$APP/embedded.mobileprovision"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")" = 'iPhoneOS'

# Check the actual binaries, so a simulator .app can never be mislabeled as IPA.
for binary in "$APP/Runner" "$APP/Frameworks/App.framework/App" "$APP/Frameworks/Flutter.framework/Flutter" "$APP/PlugIns/HomeworkWidgets.appex/HomeworkWidgets"; do
  xcrun lipo "$binary" -verify_arch arm64
  xcrun vtool -show-build "$binary" | grep -Eq 'platform +IOS$'
done

# Preserve requested group entitlements for Windows signing tools to inspect.
# This ad-hoc signature has NO device provisioning and cannot install on iPhone.
for nested in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.dylib; do
  [ -e "$nested" ] || continue
  codesign --force --sign - --timestamp=none "$nested"
done
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements ios/HomeworkWidgets/Widgets.entitlements "$APP/PlugIns/HomeworkWidgets.appex"
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements ios/Runner/Runner.entitlements "$APP"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" > "$OUT/main-entitlements.plist"
codesign -d --entitlements :- "$APP/PlugIns/HomeworkWidgets.appex" > "$OUT/widget-entitlements.plist"
python3 - "$OUT" <<'PYENT'
import plistlib, sys
from pathlib import Path
for name in ['main-entitlements.plist', 'widget-entitlements.plist']:
    with (Path(sys.argv[1]) / name).open('rb') as source:
        assert plistlib.load(source)['com.apple.security.application-groups'] == ['group.com.worknote.homeworkRadar']
PYENT

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
mkdir -p "$OUT"
STAGE=$(mktemp -d)
mkdir "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/Runner.app"
IPA="$OUT/homework-radar-$VERSION-ios-self-sign.ipa"
(cd "$STAGE" && ditto -c -k --norsrc --keepParent Payload "$IPA")
python3 scripts/ios/verify_ipa.py "$IPA"
(cd "$OUT" && shasum -a 256 "$(basename "$IPA")" > SHA256SUMS)
