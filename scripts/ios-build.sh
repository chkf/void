#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$PWD/.build/ios"
mkdir -p "$out"
args=(-project ios/Void.xcodeproj -scheme Void -derivedDataPath "$out/DerivedData")
case "${1:-device}" in
  device)
    xcodebuild "${args[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
    app="$out/DerivedData/Build/Products/Release-iphoneos/VoidHost.app"
    xcrun lipo -verify_arch arm64 "$app/VoidHost"
    test -s "$app/Toolchain/esbuild.wasm"
    test -s "$app/StarterProject/app/src/main.tsx"
    test "$(plutil -extract MinimumOSVersion raw "$app/Info.plist")" = 17.0
    staging=$(mktemp -d "$out/package.XXXXXX")
    mkdir -p "$staging/Payload"
    ditto "$app" "$staging/Payload/VoidHost.app"
    ditto -c -k --norsrc --keepParent "$staging/Payload" "$out/void-unsigned.ipa"
    unzip -tq "$out/void-unsigned.ipa"
    ;;
  test)
    sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
    device=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
sdk = tuple(map(int, sys.argv[1].split(".")))[:2]
choices = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(map(int, runtime.split(".iOS-")[-1].split("-")))
    if (17, 0) <= version[:2] <= sdk:
        choices.extend((version, d["name"] == "iPhone 16", d["name"], d["udid"]) for d in devices if d["name"].startswith("iPhone") and d["isAvailable"])
if not choices:
    sys.exit("缺少与 Xcode 匹配的 iPhone 模拟器")
version, _, name, udid = max(choices)
print(name, "iOS " + ".".join(map(str, version)), file=sys.stderr)
print(udid)' "$sdk")
    xcrun simctl bootstatus "$device" -b
    result="$out/tests-$(date +%s).xcresult"
    xcodebuild "${args[@]}" -configuration Debug -destination "platform=iOS Simulator,id=$device" \
      -parallel-testing-enabled NO -resultBundlePath "$result" test
    ditto -c -k --keepParent "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app" "$out/void-simulator.zip"
    ;;
  *) echo "用法：bash scripts/ios-build.sh device|test" >&2; exit 2 ;;
esac
