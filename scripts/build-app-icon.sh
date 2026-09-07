#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$root/Design/AppIcon/master.png"
output="$root/MacManager/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$output"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$source_icon" --out "$output/icon_${size}x${size}.png" >/dev/null
    pixels=$((size * 2))
    /usr/bin/sips -z "$pixels" "$pixels" "$source_icon" --out "$output/icon_${size}x${size}@2x.png" >/dev/null
done
printf '%s\n' 'AppIcon PNG assets regenerated from Design/AppIcon/master.png.'
