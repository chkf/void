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

# Seed a user folder in the dedicated simulator's local Files provider. The host
# app still needs a real pick and security scope to read any of these files.
install_picker_fixture() {
  local device="$1" files_data
  xcrun simctl launch "$device" com.apple.DocumentsApp
  files_data=$(xcrun simctl get_app_container "$device" com.apple.DocumentsApp data)
  python3 - "$files_data" "$device" <<'PY'
import pathlib, plistlib, shutil, sys, time, uuid

app_data = pathlib.Path(sys.argv[1]).resolve()
device_id = uuid.UUID(sys.argv[2])
containers = next(p for p in app_data.parents if p.name == "Containers")
if containers.parent.name != "data" or uuid.UUID(containers.parent.parent.name) != device_id:
    raise SystemExit("无法核实测试模拟器的文稿容器")
root = None
for attempt in range(30):
    for group in (containers / "Shared" / "AppGroup").iterdir():
        try:
            with (group / ".com.apple.mobile_container_manager.metadata.plist").open("rb") as stream:
                identifier = plistlib.load(stream)["MCMMetadataIdentifier"]
        except (OSError, ValueError, KeyError):
            continue
        if identifier.lower() != "group.com.apple.fileprovider.localstorage":
            continue
        candidate = group / "File Provider Storage"
        if not candidate.is_symlink() and candidate.is_dir():
            root = candidate
            break
    if root:
        break
    time.sleep(1)
if not root:
    raise SystemExit("独立测试模拟器未提供本地 Files 文稿位置")
target = root / "Void Files QA"
template = pathlib.Path("ios/TSXProject")
if not target.exists():
    shutil.copytree(template, target)
if target.is_symlink() or (target / "runtime.json").read_bytes() != (template / "runtime.json").read_bytes():
    raise SystemExit("独立 Files 测试目录的身份不符")
print("已在模拟器本地 File Provider 准备外部 TSX 测试目录")
PY
  xcrun simctl terminate "$device" com.apple.DocumentsApp
}

case "${1:-device}" in
  device)
    xcodebuild "${args[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
    app="$out/DerivedData/Build/Products/Release-iphoneos/VoidHost.app"
    xcrun lipo "$app/VoidHost" -verify_arch arm64
    test -s "$app/Toolchain/esbuild.wasm"
    test -s "$app/Toolchain/compiler-client.js"
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
    bash scripts/ios-build.sh build-tests
    bash scripts/ios-build.sh start-simulator
    bash scripts/ios-build.sh run-tests
    ;;
  run-tests)
    device=$(choose_simulator)
    xcrun simctl bootstatus "$device" -b
    install_picker_fixture "$device"
    if [[ "${VOID_SIMULATOR_FIXTURES:-}" == 1 ]]; then
      xcrun simctl install "$device" "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app"
      container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
      for service in contacts calendar reminders photos photos-add location; do
        xcrun simctl privacy "$device" grant "$service" app.chkf.void
      done
      xcrun simctl location "$device" set 37.3349,-122.0090
      touch "$container/tmp/void-sdk-fixtures"
    fi
    result="$out/tests-$(date +%s).xcresult"
    test_status=0
    xcodebuild "${args[@]}" -configuration Debug -destination "platform=iOS Simulator,id=$device" \
      -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 240 \
      -resultBundlePath "$result" test-without-building || test_status=$?
    if [[ "${CI:-}" == true ]] && container=$(xcrun simctl get_app_container "$device" app.chkf.void data); then
      python3 - "$container/Library/Preferences/app.chkf.void.plist" <<'PY'
import json, plistlib, sys

try:
    with open(sys.argv[1], "rb") as preferences:
        events = json.loads(plistlib.load(preferences).get("void.directoryDiagnostics.v1", b"[]"))
except (OSError, ValueError, plistlib.InvalidFileException):
    events = []
actual = {e["request"] for e in events if e["stage"] in ("picker.willPresent", "picker.didPick", "local.request")}
for e in events:
    if e["request"] in actual or e["stage"] == "fixture.ready":
        print(e["request"], e["purpose"], e["stage"], f'+{e["milliseconds"]}ms',
              e["detail"], e.get("domain", ""), e.get("code", ""))
PY
    fi
    if ((test_status != 0)); then exit "$test_status"; fi
    ditto -c -k --keepParent "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app" "$out/void-simulator.zip"
    ;;
  *) echo "用法：bash scripts/ios-build.sh device|test|start-simulator|build-tests|run-tests" >&2; exit 2 ;;
esac
