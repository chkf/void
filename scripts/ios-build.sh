#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$PWD/.build/ios"
mkdir -p "$out"
args=(-project ios/Void.xcodeproj -scheme Void -derivedDataPath "$out/DerivedData")
choose_simulator() {
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys
sdk = tuple(map(int, sys.argv[1].split(".")))[:2]
requested = tuple(map(int, sys.argv[2].split("."))) if sys.argv[2] else None
choices = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)", runtime)
    if not match:
        continue
    version = tuple(map(int, match.group(1).split("-")))
    if (17, 0) <= version[:2] <= sdk and (not requested or version[:2] == requested):
        choices.extend((version, d["name"] in ("iPhone 17", "iPhone 16"), d["name"], d["udid"]) for d in devices if d["name"].startswith("iPhone") and d["isAvailable"])
if not choices:
    sys.exit("缺少与所选 SDK 匹配的 iPhone 模拟器 " + sys.argv[2])
version, _, name, udid = max(choices)
print(name, "iOS " + ".".join(map(str, version)), file=sys.stderr)
print(udid)' "$(xcrun --sdk iphonesimulator --show-sdk-version)" "${VOID_IOS_SDK:-}"
}

case "${1:-device}" in
  device)
    xcodebuild "${args[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
    app="$out/DerivedData/Build/Products/Release-iphoneos/VoidHost.app"
    xcrun lipo "$app/VoidHost" -verify_arch arm64
    test -s "$app/Toolchain/esbuild.wasm"
    test -s "$app/Toolchain/sdk-api.json"
    test -s "$app/Toolchain/sdk-reference.md"
    test -s "$app/Toolchain/sdk.d.ts"
    test -s "$app/StarterProject/app/SwiftUI/ProjectContentView.swift"
    test -s "$app/TSXProject/app/src/main.tsx"
    if [[ -n "${VOID_IOS_SDK:-}" ]]; then
      test "$(plutil -extract DTSDKName raw "$app/Info.plist")" = "iphoneos$VOID_IOS_SDK"
    fi
    test "$(plutil -extract MinimumOSVersion raw "$app/Info.plist")" = 17.0
    staging=$(mktemp -d "$out/package.XXXXXX")
    mkdir -p "$staging/Payload"
    ditto "$app" "$staging/Payload/VoidHost.app"
    ditto -c -k --norsrc --keepParent "$staging/Payload" "$out/void-unsigned.ipa"
    unzip -tq "$out/void-unsigned.ipa"
    ;;
  start-simulator)
    device=$(choose_simulator)
    if ! xcrun simctl list devices booted | grep -Fq "$device"; then xcrun simctl boot "$device"; fi
    ;;
  build-tests)
    if [[ "$(xcrun --sdk iphonesimulator --show-sdk-version)" == 18.5 ]]; then
      # Apple 在 iOS 18.5 模拟器镜像中将旧版 WebKit Swift 库放到了 Cryptex 路径。
      args+=(IPHONEOS_DEPLOYMENT_TARGET=18.4)
    fi
    xcodebuild "${args[@]}" -configuration Debug -destination 'generic/platform=iOS Simulator' build-for-testing
    ;;
  test)
    bash scripts/ios-build.sh start-simulator
    bash scripts/ios-build.sh build-tests
    bash scripts/ios-build.sh run-tests
    ;;
  run-tests)
    device=$(choose_simulator)
    xcrun simctl bootstatus "$device" -b
    if [[ "${VOID_SIMULATOR_FIXTURES:-}" == 1 ]]; then
      xcrun simctl install "$device" "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app"
      for service in contacts calendar reminders photos photos-add location; do
        xcrun simctl privacy "$device" grant "$service" app.chkf.void
      done
      xcrun simctl location "$device" set 37.3349,-122.0090
      container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
      touch "$container/tmp/void-sdk-fixtures"
    fi
    result="$out/tests-$(date +%s).xcresult"
    xcodebuild "${args[@]}" -configuration Debug -destination "platform=iOS Simulator,id=$device" \
      -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 240 \
      -resultBundlePath "$result" test-without-building
    ditto -c -k --keepParent "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app" "$out/void-simulator.zip"
    ;;
  *) echo "用法：bash scripts/ios-build.sh device|test|start-simulator|build-tests|run-tests" >&2; exit 2 ;;
esac
