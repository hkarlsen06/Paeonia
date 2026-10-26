#!/usr/bin/env bash
# Regenerates ios/Scripts/launch.order, the linker order file that
# places the functions a cold launch runs next to each other in the Release app.
#
#   ios/Scripts/generate-launch-order-file.sh [seconds]
#
# It builds an instrumented Release copy of the app into a scratch DerivedData
# folder, with launch-order-collector.c linked in and sanitizer coverage on, so
# the app and its Swift packages record each function the first time it runs. It
# then installs that build on the Shared iPhone simulator, launches it, waits
# [seconds] (default 15, enough to reach Home for an account that is already
# signed in), and reads the recorded symbols from the app's tmp folder. Last, it
# puts the app that was installed before back on the simulator.
#
# The simulator must already hold a signed-in, paired account, because the order
# should cover the path to Home. The build is not held under the simulator lock,
# only the install, launch and pull. The instrumented build talks to
# api.paeonia.no and only reads.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

simulator="Shared iPhone"
bundle_id=no.paeonia.app
wait_seconds=${1:-15}
order_file=ios/Scripts/launch.order

# LAUNCH_ORDER_WORK=<dir> reuses that folder, so the build is incremental, and
# keeps it afterwards. It also holds launch.png, a screenshot taken just before
# the symbols are written, to check that the app had reached Home.
if [[ -n ${LAUNCH_ORDER_WORK:-} ]]; then
  work=$LAUNCH_ORDER_WORK
  mkdir -p "$work"
  keep_work=1
else
  work=$(mktemp -d /tmp/paeonia-launch-order.XXXXXX)
  keep_work=0
fi
lock_held=0
original_app=""

restore() {
  if [[ -n $original_app && -d $original_app ]]; then
    xcrun simctl terminate "$simulator" "$bundle_id" 2>/dev/null || true
    xcrun simctl install "$simulator" "$original_app" || echo "could not reinstall the original app from $original_app" >&2
  fi
  if [[ $lock_held == 1 ]]; then
    scripts/lock release "$simulator" || true
  fi
}
cleanup() {
  restore
  if [[ $keep_work == 0 ]]; then rm -rf "$work"; fi
}
trap cleanup EXIT

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -target arm64-apple-ios27.0-simulator -isysroot "$sdk" -O1 \
  -c ios/Scripts/launch-order-collector.c -o "$work/collector.o"

./scripts/generate-ios-build-number.sh >/dev/null

# ORDER_FILE is cleared so the old order does not shape the build that measures
# the new one. DEBUG_INFORMATION_FORMAT=dwarf makes the "Upload dSYMs to PostHog"
# build phase skip, so this build never sends symbols to PostHog.
# -sanitize=undefined is the sanitizer the Swift driver requires
# before it accepts -sanitize-coverage.
xcodebuild \
  -quiet \
  -project ios/Paeonia.xcodeproj \
  -scheme App \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$work/derived" \
  build \
  ORDER_FILE= \
  DEBUG_INFORMATION_FORMAT=dwarf \
  'OTHER_SWIFT_FLAGS=$(inherited) -sanitize-coverage=func -sanitize=undefined' \
  'OTHER_CFLAGS=$(inherited) -fsanitize-coverage=func,trace-pc-guard' \
  'OTHER_CPLUSPLUSFLAGS=$(inherited) -fsanitize-coverage=func,trace-pc-guard' \
  "OTHER_LDFLAGS=\$(inherited) $work/collector.o"

instrumented_app="$work/derived/Build/Products/Release-iphonesimulator/PaeoniaApp.app"
[[ -d $instrumented_app ]] || { echo "no instrumented app at $instrumented_app" >&2; exit 1; }

scripts/lock acquire "$simulator" >/dev/null
lock_held=1

if installed=$(xcrun simctl get_app_container "$simulator" "$bundle_id" app 2>/dev/null); then
  rm -rf "$work/original"
  mkdir "$work/original"
  cp -R "$installed" "$work/original/"
  original_app="$work/original/$(basename "$installed")"
fi

xcrun simctl terminate "$simulator" "$bundle_id" 2>/dev/null || true
xcrun simctl install "$simulator" "$instrumented_app"
data_container=$(xcrun simctl get_app_container "$simulator" "$bundle_id" data)
rm -f "$data_container/tmp/launch-order-symbols.txt"
SIMCTL_CHILD_LAUNCH_ORDER_SECONDS=$wait_seconds xcrun simctl launch "$simulator" "$bundle_id"
sleep $((wait_seconds - 1))
xcrun simctl io "$simulator" screenshot "$work/launch.png" >/dev/null 2>&1 || true
# Looking up every symbol takes the app a minute or two after the delay.
for _ in $(seq 300); do
  [[ -f $data_container/tmp/launch-order-symbols.txt ]] && break
  sleep 1
done
[[ -f $data_container/tmp/launch-order-symbols.txt ]] || { echo "the app wrote no symbol list" >&2; exit 1; }
cp "$data_container/tmp/launch-order-symbols.txt" "$work/symbols.txt"
xcrun simctl terminate "$simulator" "$bundle_id" 2>/dev/null || true
restore
original_app=""
lock_held=0

{
  echo "# Functions a cold launch runs, in order of first call."
  echo "# Regenerate with ios/Scripts/generate-launch-order-file.sh."
  # Objective-C methods appear in an order file without the leading underscore.
  sed -E 's/^_([-+]\[)/\1/' "$work/symbols.txt" | awk '!seen[$0]++'
} > "$order_file"

total=$(grep -vc '^#' "$order_file")
app_module=$(grep -c '^_\$s10PaeoniaApp' "$order_file" || true)
echo "Wrote $total symbols to $order_file ($app_module in the PaeoniaApp module, $((total - app_module)) elsewhere)."
