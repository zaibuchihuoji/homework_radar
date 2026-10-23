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
# Simulator entitlements live in __TEXT,__entitlements, rather than the
# ordinary codesign entitlement blob. The Keychain test verifies real access.
codesign -d -vv "$APP" 2> "$QA/simulator-signing.log"

# The simulator is only needed for execution, not the native compilation above.
cleanup() {
  DATA=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.worknote.homeworkRadar data 2>/dev/null) || true
  if [ -n "${DATA:-}" ] && [ -d "$DATA/Documents/widget-snapshots" ]; then cp -R "$DATA/Documents/widget-snapshots" "$QA/"; fi
  xcrun simctl io "$SIMULATOR_ID" screenshot "$QA/last-simulator-state.png" || true
  xcrun simctl shutdown "$SIMULATOR_ID" || true
}
trap cleanup EXIT
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -resultBundlePath "$QA/RunnerTests.xcresult" test-without-building BUILD_DIR="$ROOT/build/ios" \
  > "$QA/native-tests.log" 2>&1 || { tail -n 100 "$QA/native-tests.log"; exit 1; }
xcrun simctl io "$SIMULATOR_ID" screenshot "$QA/widget-desktop.png"
xcrun simctl install "$SIMULATOR_ID" "$APP"
xcrun simctl launch "$SIMULATOR_ID" com.worknote.homeworkRadar
sleep 3
xcrun simctl openurl "$SIMULATOR_ID" 'homework-radar://widget/timetable?homeWidget=1'
sleep 3
xcrun simctl io "$SIMULATOR_ID" screenshot "$QA/launch.png"
