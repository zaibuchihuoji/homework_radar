#!/usr/bin/env bash
set -euo pipefail
ROOT=$(pwd)
QA="$ROOT/build/ios/major-flows"
mkdir -p "$QA"
# A smaller screen reduces simulator memory use. Every run gets a fresh
# container: no developer/user app database or Keychain is reused or cleared.
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]))')
SIMULATOR_ID=$(xcrun simctl create "Homework Radar QA" com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$RUNTIME")
cleanup() {
  DATA=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.worknote.homeworkRadar data 2>/dev/null) || true
  if [ -n "${DATA:-}" ]; then
    cp "$DATA/Library/Preferences/com.worknote.homeworkRadar.plist" "$QA/test-app-preferences.plist" || true
  fi
  UI_DATA=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.worknote.homeworkRadar.RunnerUITests.xctrunner data 2>/dev/null) || true
  if [ -n "${UI_DATA:-}" ] && [ -d "$UI_DATA/Documents/major-flows" ]; then cp -R "$UI_DATA/Documents/major-flows" "$QA/screenshots"; fi
  xcrun simctl io "$SIMULATOR_ID" screenshot "$QA/last-simulator-state.png" || true
  xcrun simctl shutdown "$SIMULATOR_ID" || true
}
trap cleanup EXIT
flutter build ios --simulator --debug --config-only > "$QA/config.log" 2>&1 || { tail -n 60 "$QA/config.log"; exit 1; }
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -jobs 2 build-for-testing \
  BUILD_DIR="$ROOT/build/ios" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  > "$QA/build.log" 2>&1 || { tail -n 80 "$QA/build.log"; exit 1; }
xcrun simctl boot "$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b > "$QA/boot.log" 2>&1
xcrun simctl addmedia "$SIMULATOR_ID" "$ROOT/test/fixtures/ios_homework_screenshot.png"
# Do not run the WidgetKit/SpringBoard gallery suite or rebuild a device IPA.
case "${IOS_MAJOR_FLOW:-all}" in
  all) UI_FILTERS=(-only-testing:RunnerUITests/MajorFlowsTests) ;;
  notification) UI_FILTERS=(-only-testing:RunnerUITests/MajorFlowsTests/test04ScheduledReminderDeliveredAndOpensDetail) ;;
  native_edges) UI_FILTERS=(-only-testing:RunnerUITests/MajorFlowsTests/test02PhotosScreenshotOcrReviewAndConfirm -only-testing:RunnerUITests/MajorFlowsTests/test04ScheduledReminderDeliveredAndOpensDetail) ;;
  *) echo 'Unknown flow'; exit 1 ;;
esac
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  "${UI_FILTERS[@]}" -resultBundlePath "$QA/MainFlows.xcresult" \
  test-without-building BUILD_DIR="$ROOT/build/ios" > "$QA/ui-tests.log" 2>&1 \
  || { tail -n 100 "$QA/ui-tests.log"; exit 1; }
if [ "${IOS_MAJOR_FLOW:-all}" != all ]; then exit 0; fi
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -only-testing:RunnerTests/MajorFlowsPersistenceTests -resultBundlePath "$QA/Persistence.xcresult" \
  test-without-building BUILD_DIR="$ROOT/build/ios" > "$QA/persistence-tests.log" 2>&1 \
  || { tail -n 80 "$QA/persistence-tests.log"; exit 1; }
