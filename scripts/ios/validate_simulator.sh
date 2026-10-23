#!/usr/bin/env bash
set -euo pipefail

ROOT=$(pwd)
QA="$ROOT/build/ios/qa"
mkdir -p "$QA"
SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v if x["name"].startswith("iPhone")))')
# Compile once before booting the simulator, keeping CI memory use bounded.
flutter build ios --simulator --debug --config-only > "$QA/simulator-config.log" 2>&1 || { tail -n 100 "$QA/simulator-config.log"; exit 1; }
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -jobs 2 build-for-testing \
  BUILD_DIR="$ROOT/build/ios" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- VERBOSE_SCRIPT_LOGGING=YES \
  > "$QA/simulator-build.log" 2>&1 || { tail -n 100 "$QA/simulator-build.log"; exit 1; }
APP="$ROOT/build/ios/Debug-iphonesimulator/Runner.app"
codesign -d --entitlements :- "$APP" > "$QA/simulator-entitlements.plist" 2> "$QA/simulator-signing.log"
python3 - "$QA/simulator-entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    identity = plistlib.load(source)['application-identifier']
assert identity.endswith('com.worknote.homeworkRadar') and '$(' not in identity
PY

# The simulator is only needed for execution, not the native compilation above.
trap 'xcrun simctl shutdown "$SIMULATOR_ID" || true' EXIT
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -resultBundlePath "$QA/RunnerTests.xcresult" test-without-building BUILD_DIR="$ROOT/build/ios" \
  > "$QA/native-tests.log" 2>&1 || { tail -n 100 "$QA/native-tests.log"; exit 1; }
xcrun simctl install "$SIMULATOR_ID" "$APP"
xcrun simctl launch "$SIMULATOR_ID" com.worknote.homeworkRadar
sleep 8
xcrun simctl io "$SIMULATOR_ID" screenshot "$QA/launch.png"
