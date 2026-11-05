#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ $(uname -m) != arm64 ]]; then
    echo 'Run verification on an Apple Silicon Mac with Xcode 27 or newer.' >&2
    exit 1
fi

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

./tools/test-hooks.sh
env -u MM_SYSTEM_TESTS -u MM_LAUNCHER_TEST_ROOT -u MM_BENCHMARKS \
    swift test --package-path Packages/MacManagerCore --no-parallel

xcode=(xcodebuild -project MacManager.xcodeproj -scheme MacManager
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_dir")
"${xcode[@]}" -configuration Debug -parallel-testing-enabled NO \
    -only-testing:MacManagerTests test
"${xcode[@]}" -configuration Release CODE_SIGNING_ALLOWED=NO build

contents="$build_dir/Build/Products/Release/MacManager.app/Contents"
binary="$contents/MacOS/MacManager"
if [[ $(xcrun lipo -archs "$binary") != arm64 ]]; then
    echo 'Expected a native arm64 Release executable.' >&2
    exit 1
fi
for language in en pl; do
    plutil -lint "$contents/Resources/$language.lproj/Localizable.strings"
    plutil -lint "$contents/Resources/$language.lproj/InfoPlist.strings"
done

xcrun nm "$binary" | xcrun swift-demangle > "$build_dir/release-symbols"
xcrun strings -a "$binary" > "$build_dir/release-strings"
if grep -E 'Fixture(AppleMusic|Podcasts|Clipboard|Launcher)|Test(LoginItemService|ScrollDriver|UpdateFixture)|setSessionSuspendedForTesting|simulateDisplayChangeForTesting' "$build_dir/release-symbols" \
    || grep -Ex -- '--ui-testing|--island-reserved-region-probe|MM_UI_TEST_ID' "$build_dir/release-strings"; then
    echo 'UI test fixtures found in Release.' >&2
    exit 1
fi
echo 'Release architecture, localizations and fixture checks passed.'
