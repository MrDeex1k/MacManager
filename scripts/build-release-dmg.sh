#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf '%s\n' "Usage: DEVELOPER_ID_APPLICATION='Developer ID Application: ...' APPLE_TEAM_ID=... NOTARY_PROFILE=... $0 VERSION" >&2
    exit 64
fi

version=$1
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s\n' "Invalid release version: $version" >&2
    exit 64
fi

: "${DEVELOPER_ID_APPLICATION:?Set the full Developer ID Application identity}"
: "${APPLE_TEAM_ID:?Set the Apple Developer Team ID}"
: "${NOTARY_PROFILE:?Set the notarytool Keychain profile name}"

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output="$root/.build/releases/v$version"
archive="$output/MacManager.xcarchive"
stage="$output/dmg-root"
dmg="$output/MacManager-v$version-arm64.dmg"
build_number=${BUILD_NUMBER:-8}

if ! security find-identity -v -p codesigning | grep -Fq "\"$DEVELOPER_ID_APPLICATION\""; then
    printf '%s\n' "Developer ID Application identity is not available in the keychain" >&2
    exit 1
fi

rm -rf "$output"
mkdir -p "$output"

xcodebuild -quiet \
    -project "$root/MacManager.xcodeproj" \
    -scheme MacManager \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    archive \
    PRODUCT_BUNDLE_IDENTIFIER=dev.macmanager.MacManager \
    INFOPLIST_KEY_CFBundleDisplayName="Mac Manager" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS=--timestamp

app="$archive/Products/Applications/MacManager.app"
if [ ! -d "$app" ]; then
    printf '%s\n' "Archive does not contain MacManager.app" >&2
    exit 1
fi

actual_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
if [ "$actual_identifier" != "dev.macmanager.MacManager" ]; then
    printf '%s\n' "Release app has an unexpected bundle identifier: $actual_identifier" >&2
    exit 1
fi

actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [ "$actual_version" != "$version" ]; then
    printf '%s\n' "Expected version $version, built $actual_version" >&2
    exit 1
fi

if [ "$(lipo -archs "$app/Contents/MacOS/MacManager")" != "arm64" ]; then
    printf '%s\n' "Release executable is not arm64-only" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app"
if ! codesign -dv --verbose=4 "$app" 2>&1 | grep -q 'flags=.*runtime'; then
    printf '%s\n' "Release app is missing Hardened Runtime" >&2
    exit 1
fi

mkdir -p "$stage"
ditto "$app" "$stage/MacManager.app"
cp "$root/LICENSE" "$stage/LICENSE.txt"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Mac Manager $version" -srcfolder "$stage" -format UDZO "$dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$dmg"
codesign --verify --verbose=2 "$dmg"

xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

(cd "$output" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
printf '%s\n' "Release artifact: $dmg"
printf '%s\n' "Checksum: $dmg.sha256"
