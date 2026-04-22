#!/usr/bin/env bash
#
# scripts/make-icon.sh — turn assets/brand/app-icon.svg into
# apps/LLMAB-macOS/Resources/AppIcon.icns via rsvg-convert + iconutil.
#
# Prerequisites (install once):
#   brew install librsvg              # rsvg-convert
#   # iconutil ships with Xcode command-line tools
#
# Run it from the repo root:
#   ./scripts/make-icon.sh
#
# Regenerate any time the source SVG changes.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

svg="$root/assets/brand/app-icon.svg"
iconset_dir="$root/build/AppIcon.iconset"
out_dir="$root/apps/LLMAB-macOS/Resources"
out_icns="$out_dir/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found — brew install librsvg"; exit 1; }
command -v iconutil     >/dev/null || { echo "iconutil not found — install Xcode command-line tools"; exit 1; }

rm -rf "$iconset_dir"
mkdir -p "$iconset_dir" "$out_dir"

# Apple's required icon sizes.
declare -a sizes=(
    "16     icon_16x16.png"
    "32     icon_16x16@2x.png"
    "32     icon_32x32.png"
    "64     icon_32x32@2x.png"
    "128    icon_128x128.png"
    "256    icon_128x128@2x.png"
    "256    icon_256x256.png"
    "512    icon_256x256@2x.png"
    "512    icon_512x512.png"
    "1024   icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
    size="${entry%% *}"
    name="${entry##* }"
    echo "→ ${size}×${size}  $name"
    rsvg-convert -w "$size" -h "$size" "$svg" -o "$iconset_dir/$name"
done

echo "→ iconutil --convert icns → $out_icns"
iconutil --convert icns --output "$out_icns" "$iconset_dir"

echo
echo "✓ wrote $out_icns"
echo "   size: $(du -h "$out_icns" | cut -f1)"
