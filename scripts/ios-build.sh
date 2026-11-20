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
profile = sys.argv[3]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)", runtime)
    if not match:
        continue
    version = tuple(map(int, match.group(1).split("-")))
    if (17, 0) <= version[:2] <= sdk and (not requested or version[:2] == requested):
        for d in devices:
            name = d["name"]
            if not d["isAvailable"] or not name.startswith("iPad" if profile == "ipad" else "iPhone"):
                continue
            if profile == "compact":
                # Prefer the smallest available phone for the installed runtime.
                rank = next((8-i for i, part in enumerate(["SE", "mini", "16e", "17e", "iPhone 16", "iPhone 17"]) if part in name and "Pro" not in name and "Plus" not in name), 0)
            else:
                rank = int(name in ("iPhone 17", "iPhone 16") or "mini" in name)
            choices.append((version, rank, name, d["udid"]))
if not choices:
    sys.exit("缺少与所选 SDK 匹配的 iPhone 模拟器 " + sys.argv[2])
version, _, name, udid = max(choices)
print(name, "iOS " + ".".join(map(str, version)), file=sys.stderr)
print(udid)' "$(xcrun --sdk iphonesimulator --show-sdk-version)" "${VOID_IOS_SDK:-}" "${VOID_LAYOUT_PROFILE:-}"
}

prepare_native_ui_test() {
  local device="$1" container
  xcrun simctl install "$device" "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app"
  container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
  TEST_RUNNER_VOID_NATIVE_UI_PROJECT=$(python3 - "$container" <<'PY'
import json, pathlib, shutil, sys, uuid
token = str(uuid.uuid4())
name = "Void Native UI " + token[:8]
root = pathlib.Path(sys.argv[1]) / "Documents" / name
shutil.copytree("examples/native-ui", root)
(root / "runtime.json").write_text(json.dumps({"formatVersion": 1, "id": token}))
manifest = root / "app/manifest.json"
value = json.loads(manifest.read_bytes())
value["name"] = name
manifest.write_text(json.dumps(value))
profile = root.with_name(name + " Profile")
shutil.copytree(root, profile)
(profile / "runtime.json").write_text(json.dumps({"formatVersion": 1, "id": str(uuid.uuid4())}))
(profile / "app/manifest.json").write_text(json.dumps({**value, "name": profile.name}))
shutil.copyfile("tests/fixtures/profile-settings.tsx", profile / "app/src/main.tsx")
sample = root.with_name("Void Safe Area " + token[:8])
shutil.copytree("tests/fixtures/safe-area", sample)
(sample / "runtime.json").write_text(json.dumps({"formatVersion": 1, "id": str(uuid.uuid4())}))
manifest = sample / "app/manifest.json"
manifest.write_text(json.dumps({**json.loads(manifest.read_bytes()), "name": sample.name}))
print(name)
PY
  )
  export TEST_RUNNER_VOID_NATIVE_UI_PROJECT
  export TEST_RUNNER_VOID_SAFE_AREA_PROJECT="Void Safe Area ${TEST_RUNNER_VOID_NATIVE_UI_PROJECT##* }"
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

# Prepare an unregistered TSX folder in this simulator's Documents. Consent and
# SQLite are created by the app itself, through the normal preview and SDK APIs.
prepare_consent_test() {
  local device="$1" configuration="$2" container
  xcrun simctl install "$device" "$out/DerivedData/Build/Products/${configuration}-iphonesimulator/VoidHost.app"
  container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
  TEST_RUNNER_VOID_CONSENT_PROJECT=$(python3 - "$container" <<'PY'
import json, pathlib, shutil, sys, uuid

project_id = uuid.uuid4()
name = f"Void Consent {str(project_id)[:8]}"
root = pathlib.Path(sys.argv[1]) / "Documents" / name
root.parent.mkdir(exist_ok=True)
root.mkdir()
(root / "app/src").mkdir(parents=True)
(root / "runtime.json").write_text(json.dumps({"formatVersion": 1, "id": str(project_id)}))
manifest = {"name": name, "entry": "src/main.tsx", "uiMode": "native", "version": "1.1.0",
            "permissions": ["database", "files.read"]}
(root / "app/manifest.json").write_text(json.dumps(manifest))
shutil.copyfile("ios/TSXProject/app/package.json", root / "app/package.json")
shutil.copyfile("tests/fixtures/consent-preview.tsx", root / "app/src/main.tsx")
print(name)
PY
  )
  export TEST_RUNNER_VOID_CONSENT_PROJECT
}

# Capture only call stacks from the hosted simulator test, outside its main thread.
sample_slow_rebuild() {
  local device="$1" container marker pid executable report
  local end=$((SECONDS + 1200))
  while (( SECONDS < end )); do
    container=$(xcrun simctl get_app_container "$device" app.chkf.void data 2>/dev/null) || container=""
    marker="$container/tmp/void-rebuild-test-pid"
    if [[ -n "$container" && -f "$marker" ]]; then
      pid=$(cat "$marker") || return 0
      [[ "$pid" =~ ^[0-9]+$ ]] || return 0
      sleep 12
      [[ -f "$marker" ]] || return 0
      executable=$(ps -p "$pid" -o comm=) || return 0
      [[ "$executable" == *"/VoidHost.app/VoidHost" ]] || return 0
      report="$out/simulator-rebuild.sample"
      if sample "$pid" 3 5 -file "$report" >/dev/null 2>&1; then
        echo '重建等待期间的模拟器主线程采样'
        awk '/Call graph:/{p=1; next} /Binary Images:/{exit} p && /Thread_/ && seen++ {exit} p && n++ < 160 {print}' "$report"
      fi
      return 0
    fi
    sleep 2
  done
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
    test -s "$app/Toolchain/ui.d.ts"
    test -s "$app/Toolchain/native-ui.md"
    test -s "$app/Toolchain/NativeUIDemo/app/src/main.tsx"
    test -s "$app/StarterProject/app/SwiftUI/ProjectContentView.swift"
    test -s "$app/TSXProject/app/src/main.tsx"
    test -s "$app/Settings.bundle/Root.plist"
    if [[ -n "${VOID_IOS_SDK:-}" ]]; then
      test "$(plutil -extract DTSDKName raw "$app/Info.plist")" = "iphoneos$VOID_IOS_SDK"
    fi
    test "$(plutil -extract MinimumOSVersion raw "$app/Info.plist")" = 17.0
    [[ "$(plutil -extract CFBundleVersion raw "$app/Info.plist")" =~ ^[1-9][0-9]*$ ]]
    staging=$(mktemp -d "$out/package.XXXXXX")
    mkdir -p "$staging/Payload"
    ditto "$app" "$staging/Payload/VoidHost.app"
    ditto -c -k --norsrc --keepParent "$staging/Payload" "$out/void-unsigned.ipa"
    unzip -tq "$out/void-unsigned.ipa"
    ditto -c -k --norsrc --keepParent examples/native-ui "$out/native-ui-example.zip"
    unzip -tq "$out/native-ui-example.zip"
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
  release-preview)
    bash scripts/ios-build.sh start-simulator
    device=$(choose_simulator)
    xcrun simctl bootstatus "$device" -b
    preview_args=("${args[@]}" -configuration Release ENABLE_TESTABILITY=YES -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO)
    xcodebuild "${preview_args[@]}" build-for-testing
    prepare_consent_test "$device" Release
    sample_slow_rebuild "$device" & sample_pid=$!
    trap 'kill "$sample_pid" 2>/dev/null || true' EXIT
    xcodebuild "${preview_args[@]}" \
      -only-testing:VoidUITests/HostTests/testFirstPreviewPermissionChoicesAndSQLiteSurviveRelaunch \
      -only-testing:VoidTests/NativeSDKTests/testClosingFirstConsentCancelsWithoutSavingADecision \
      -only-testing:VoidTests/DirectoryTests/testLocalScanAndRecentSelectionDoNotReadOrStartAProject \
      -only-testing:VoidTests/DirectoryTests/testFingerprintMatchesFullContentsWithoutRetainingAssetsAndBoundsGrowingSources \
      -only-testing:VoidTests/DirectoryTests/testRecentTSXPreviewsExistingSQLiteThroughNativeFirstFrame \
      -only-testing:VoidTests/DirectoryTests/testRealImportPreviewRebuildFailureRecoveryAndColdReopen \
      -only-testing:VoidTests/DirectoryTests/testStartupFileWatchCanBeCancelledWhileProviderHoldsDirectory \
      -only-testing:VoidTests/WorkspaceTests/testBuildStoreWritesRawResourcesAndCanRestoreLegacyVersion \
      -only-testing:VoidTests/WorkspaceTests/testRejectsInvalidNativeTree \
      -only-testing:VoidTests/NativeContractTests \
      -only-testing:VoidTests/NativeTabEventTests \
      -only-testing:VoidTests/PreviewRecoveryTests/testRecoveryUsesTheInterruptedRequestEvenAfterNewerFolderScan \
      -only-testing:VoidTests/PreviewRecoveryTests/testNewWorkspaceRemainsSelectedAfterADifferentInterruptedPreview \
      -resultBundlePath "$out/release-preview.xcresult" test-without-building
    ;;
  test)
    bash scripts/ios-build.sh build-tests
    bash scripts/ios-build.sh start-simulator
    bash scripts/ios-build.sh run-tests
    ;;
  local-picker)
    device=$(choose_simulator)
    xcrun simctl bootstatus "$device" -b
    xcrun simctl install "$device" "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app"
    container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
    existing_project=$(uuidgen)
    SIMCTL_CHILD_VOID_PICKER_TEST_PROJECT="$existing_project" xcrun simctl launch "$device" app.chkf.void
    # Exercise Files with a previously created project, as on an in-place update.
    # The preparing process ends before Files starts; the project has no catalog entry.
    python3 - "$container/Documents" "$existing_project" <<'PY'
import json, pathlib, sys, time

name = 'Void Picker ' + sys.argv[2][:8].upper()
folder = pathlib.Path(sys.argv[1]) / name
for _ in range(90):
    if (folder / 'app/src/main.tsx').is_file() and (folder / 'app/manifest.json').is_file():
        assert json.loads((folder / 'app/manifest.json').read_bytes())['name'] == name
        break
    time.sleep(0.5)
else:
    raise SystemExit("模拟器中缺少预先创建的本机目录")
PY
    xcrun simctl terminate "$device" app.chkf.void
    xcrun simctl launch "$device" com.apple.DocumentsApp
    xcrun simctl terminate "$device" com.apple.DocumentsApp
    local_test_status=0
    TEST_RUNNER_VOID_EXISTING_PICKER_PROJECT="$existing_project" xcodebuild "${args[@]}" -configuration Debug -destination "platform=iOS Simulator,id=$device" \
      -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 240 \
      -only-testing:VoidUITests/FolderPickerTests/testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory \
      -resultBundlePath "$out/local-picker.xcresult" test-without-building || local_test_status=$?
    container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
    python3 - "$container/Library/Preferences/app.chkf.void.plist" "$local_test_status" "$existing_project" <<'PY'
import json, plistlib, sys, time

events = []
for _ in range(30):
    try:
        with open(sys.argv[1], "rb") as stream:
            events = json.loads(plistlib.load(stream).get("void.directoryDiagnostics.v1", b"[]"))
    except (OSError, ValueError):
        pass
    if any(e["stage"] == "page.firstFrame" for e in events):
        break
    time.sleep(0.25)
for event in events:
    if event['purpose'] == 'import':
        print(event['request'], event['stage'], event['milliseconds'], event['detail'],
              event.get('domain', ''), event.get('code', ''), flush=True)
if int(sys.argv[2]):
    raise SystemExit(int(sys.argv[2]))
picks = [e for e in events if e["stage"] == "picker.didPick"]
assert len(picks) == 1, "本机 Files 必须只返回一次真实选中回调"
picked = picks[0]
timeline = [e for e in events if e["request"] == picked["request"]]
expected = "count=1 Void Picker " + sys.argv[3][:8].upper()
assert picked["detail"] == expected, "系统未返回预先创建的原目录"
assert all(any(e["stage"] == step for e in timeline)
           for step in ["picker.present", "picker.dismiss", "import.result", "page.firstFrame"])
PY
    ;;
  native-layout)
    bash scripts/ios-build.sh start-simulator
    device=$(choose_simulator)
    xcrun simctl bootstatus "$device" -b
    bash scripts/ios-build.sh build-tests
    prepare_native_ui_test "$device"
    xcodebuild "${args[@]}" -configuration Debug -destination "platform=iOS Simulator,id=$device" \
      -parallel-testing-enabled NO -only-testing:VoidTests/NativeContractTests -only-testing:VoidTests/NativeTabEventTests \
      -only-testing:VoidTests/NativeSafeAreaTests -only-testing:VoidUITests/SafeAreaTests \
      -only-testing:VoidUITests/NativeNavigationTests \
      -resultBundlePath "$out/layout.xcresult" test-without-building
    ;;
  run-tests)
    device=$(choose_simulator)
    xcrun simctl bootstatus "$device" -b
    install_picker_fixture "$device"
    prepare_consent_test "$device" Debug
    prepare_native_ui_test "$device"
    if [[ "${VOID_SIMULATOR_FIXTURES:-}" == 1 ]]; then
      container=$(xcrun simctl get_app_container "$device" app.chkf.void data)
      for service in contacts calendar reminders photos photos-add location; do
        xcrun simctl privacy "$device" grant "$service" app.chkf.void
      done
      xcrun simctl location "$device" set 37.3349,-122.0090
      touch "$container/tmp/void-sdk-fixtures"
    fi
    result="$out/tests-$(date +%s).xcresult"
    sample_slow_rebuild "$device" & sample_pid=$!
    trap 'kill "$sample_pid" 2>/dev/null || true' EXIT
    test_status=0
    if [[ "${VOID_SEPARATE_LOCAL_PICKER:-}" == 1 ]]; then
      args+=(-skip-testing:VoidUITests/FolderPickerTests/testSystemOpenPreviewsProjectFromSelectedDocumentsDirectory)
    fi
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
  *) echo "用法：bash scripts/ios-build.sh device|test|start-simulator|build-tests|run-tests|release-preview|local-picker|native-layout" >&2; exit 2 ;;
esac
