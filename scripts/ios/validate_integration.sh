#!/usr/bin/env bash
set -euo pipefail
ROOT=$(pwd)
QA="$ROOT/build/ios/major-flows"
mkdir -p "$QA"
# Test SDK/plugin is added only to this disposable CI checkout. Production
# pubspec/lock and Android plugin registration in the repository stay unchanged.
python3 - <<'PY'
from pathlib import Path
p = Path('pubspec.yaml')
p.write_text(p.read_text().replace('dev_dependencies:\n', 'dev_dependencies:\n  integration_test:\n    sdk: flutter\n', 1))
Path('integration_test').mkdir(exist_ok=True)
Path('integration_test/ios_major_flows_test.dart').write_text(Path('scripts/ios/major_flows.dart.in').read_text())
Path('ios/RunnerTests/RunnerTests.swift').write_text(Path('scripts/ios/IntegrationDriver.swift').read_text())
PY
flutter pub get > "$QA/integration-dependencies.log" 2>&1
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]))')
SIMULATOR_ID=$(xcrun simctl create "Homework Radar Integration QA" com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$RUNTIME")
cleanup() {
  DATA=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.worknote.homeworkRadar data 2>/dev/null) || true
  if [ -n "${DATA:-}" ]; then
    if [ -d "$DATA/Documents/major-integration" ]; then cp -R "$DATA/Documents/major-integration" "$QA/"; fi
    cp "$DATA/Library/Preferences/com.worknote.homeworkRadar.plist" "$QA/test-app-preferences.plist" || true
  fi
  xcrun simctl io "$SIMULATOR_ID" screenshot "$QA/last-simulator-state.png" || true
  xcrun simctl shutdown "$SIMULATOR_ID" || true
}
trap cleanup EXIT
flutter build ios --simulator --debug --config-only --target integration_test/ios_major_flows_test.dart > "$QA/config.log" 2>&1 || { tail -n 70 "$QA/config.log"; exit 1; }
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -jobs 2 build-for-testing \
  BUILD_DIR="$ROOT/build/ios" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  > "$QA/build.log" 2>&1 || { tail -n 80 "$QA/build.log"; exit 1; }
xcrun simctl boot "$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b > "$QA/boot.log" 2>&1
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -only-testing:RunnerTests/IOSMajorFlowIntegrationDriver -resultBundlePath "$QA/Integration.xcresult" \
  test-without-building BUILD_DIR="$ROOT/build/ios" > "$QA/integration-tests.log" 2>&1 \
  || { tail -n 120 "$QA/integration-tests.log"; exit 1; }
