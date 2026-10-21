#!/bin/sh
# Reproducible local/CI checks. Signing and publishing are separate release actions.
set -eu

profile=${1:-all}
case "$profile" in
    quick|ui|system|all) ;;
    *) printf '%s\n' "Usage: $0 [quick|ui|system|all]" >&2; exit 64 ;;
esac
[ "$#" -le 1 ] || { printf '%s\n' "Expected at most one profile" >&2; exit 64; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
[ "$(uname -m)" = arm64 ] || { printf '%s\n' "An Apple Silicon Mac is required" >&2; exit 1; }
sdk=$(xcrun --sdk macosx --show-sdk-version)
[ "${sdk%%.*}" -ge 26 ] || { printf '%s\n' "Select Xcode with macOS SDK 26 or later" >&2; exit 1; }

output=${MM_VERIFY_OUTPUT:-"$root/.build/verification"}
mkdir -p "$output"
run_dir=$(mktemp -d "$output/run.XXXXXX")
printf 'Verification profile: %s\nResults: %s\n' "$profile" "$run_dir"
{
    git rev-parse HEAD
    sw_vers -productVersion
    uname -m
    printf 'macOS SDK: %s\n' "$sdk"
    xcodebuild -version
    swift --version
} > "$run_dir/environment.log" 2>&1

# Ambient opt-ins must not silently change quick or UI checks.
unset MM_SYSTEM_TESTS MM_BENCHMARKS MM_LAUNCHER_TEST_ROOT MM_UI_BENCHMARKS
unset TEST_RUNNER_MM_UI_BENCHMARKS
run() {
    name=$1
    shift
    printf 'Running %s\n' "$name"
    if "$@" > "$run_dir/$name.log" 2>&1; then
        printf 'PASS %s\n' "$name"
    else
        status=$?
        printf 'FAIL %s (exit %s); see %s\n' "$name" "$status" "$run_dir/$name.log" >&2
        tail -n 60 "$run_dir/$name.log" >&2
        exit "$status"
    fi
}
quick() {
    run hooks ./scripts/test-git-hooks.sh
    run core swift test --package-path Packages/MacManagerCore --scratch-path "$run_dir/core"
    run session ./scripts/test-session-monitor.sh
    run debug xcodebuild build-for-testing -scheme MacManager -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath "$run_dir/debug" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES
    run release xcodebuild build -scheme MacManager -configuration Release \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath "$run_dir/release" CODE_SIGNING_ALLOWED=NO
    binary="$run_dir/release/Build/Products/Release/MacManager.app/Contents/MacOS/MacManager"
    nm "$binary" > "$run_dir/release-symbols.raw"
    xcrun swift-demangle < "$run_dir/release-symbols.raw" > "$run_dir/release-symbols.log"
    if grep -Eq 'FixtureAppleMusicAdapter|FixturePodcastsAdapter|EphemeralClipboardKey' "$run_dir/release-symbols.log"; then
        printf '%s\n' 'FAIL: test fixture implementation present in Release' >&2
        exit 1
    fi
}
ui() {
    # A fresh directory prevents stale runner signatures and concurrent build mutation.
    # Hardware, live shortcuts and end-to-end timings belong to the system profile.
    run ui xcodebuild test -scheme MacManager -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
        -derivedDataPath "$run_dir/ui" -resultBundlePath "$run_dir/ui.xcresult" \
        -skip-testing:MacManagerUITests/LauncherTests/testLauncherGlobalShortcutHiddenWindowAndApplicationLaunch \
        -skip-testing:MacManagerUITests/LauncherTests/testLauncherAliasFavoriteAndShortcutConflict \
        -skip-testing:MacManagerUITests/LauncherTests/testQueryToVisibleResultBenchmark \
        -skip-testing:MacManagerUITests/AppShellTests/testLiveMetricsAndSamplingPreference \
        -skip-testing:MacManagerUITests/AppShellTests/testSensorsUnitsAndLiveReadings \
        -skip-testing:MacManagerUITests/SystemTests/testLoginLaunchStaysInBackgroundAndProvidesMenuBar \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES
}
system() {
    run core-system env MM_SYSTEM_TESTS=1 swift test --package-path Packages/MacManagerCore --scratch-path "$run_dir/core"
    run live-ui env TEST_RUNNER_MM_UI_BENCHMARKS=1 xcodebuild test -scheme MacManager \
        -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
        -derivedDataPath "$run_dir/system-ui" -resultBundlePath "$run_dir/system-ui.xcresult" \
        -only-testing:MacManagerUITests/LauncherTests/testLauncherGlobalShortcutHiddenWindowAndApplicationLaunch \
        -only-testing:MacManagerUITests/LauncherTests/testLauncherAliasFavoriteAndShortcutConflict \
        -only-testing:MacManagerUITests/LauncherTests/testQueryToVisibleResultBenchmark \
        -only-testing:MacManagerUITests/AppShellTests/testLiveMetricsAndSamplingPreference \
        -only-testing:MacManagerUITests/AppShellTests/testSensorsUnitsAndLiveReadings \
        -only-testing:MacManagerUITests/SystemTests/testLoginLaunchStaysInBackgroundAndProvidesMenuBar \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES
}
case "$profile" in
    quick) quick ;;
    ui) ui ;;
    system) system ;;
    all) quick; ui ;;
esac
printf 'PASS profile %s; review skips in %s\n' "$profile" "$run_dir"
