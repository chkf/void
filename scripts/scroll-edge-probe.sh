#!/usr/bin/env bash
set -euo pipefail
out="$PWD/.build/ios"
bash scripts/ios-build.sh start-simulator
device=$(xcrun simctl list devices booted -j | python3 -c 'import sys,json; print(next(d["udid"] for rt,ds in json.load(sys.stdin)["devices"].items() for d in ds if d["state"]=="Booted" and d["name"].startswith("iPhone")))')
xcrun simctl bootstatus "$device" -b
bash scripts/ios-build.sh build-tests
xcrun simctl install "$device" "$out/DerivedData/Build/Products/Debug-iphonesimulator/VoidHost.app"
xcrun simctl ui "$device" appearance dark
xcrun simctl status_bar "$device" override --time 9:41
mkdir -p "$out/scroll-displays"
(
  last=""
  while true; do
    container=$(xcrun simctl get_app_container "$device" app.chkf.void data) || { sleep 0.3; continue; }
    request="$container/tmp/void-scroll-request"
    if [[ -s "$request" ]]; then
      name=$(cat "$request")
      if [[ "$name" != "$last" && "$name" =~ ^(Tabs|Plain|Titled)-(Rest|Scrolled|Returned)$ ]]; then
        xcrun simctl io "$device" screenshot "$out/scroll-displays/$name.png"
        printf '%s' "$name" > "$container/tmp/void-scroll-done.tmp"
        mv "$container/tmp/void-scroll-done.tmp" "$container/tmp/void-scroll-done"
        last="$name"
      fi
    fi
    sleep 0.25
  done
) & watcher=$!
trap 'kill "$watcher" 2>/dev/null || true' EXIT
for scenario in testHeaderInTabScrollsBehindStatusBar testDeclaredTitleUsesSystemNavigation; do
  TEST_RUNNER_VOID_SCROLL_SCREENSHOTS=1 xcodebuild -project ios/Void.xcodeproj -scheme Void -configuration Debug \
    -derivedDataPath "$out/DerivedData" -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
    -only-testing:VoidTests/NativeScrollViewportTests/"$scenario" -resultBundlePath "$out/$scenario.xcresult" test-without-building
done
