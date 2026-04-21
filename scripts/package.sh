#!/usr/bin/env bash
#
# scripts/package.sh — build → sign → notarise → DMG for ω (LLMAB-macOS).
#
# Prerequisites (all on the Mac doing the signing):
#   - Xcode 15.x or 16.x installed
#   - A Developer ID Application certificate in the login keychain
#   - `xcrun notarytool` credentials stored via keychain profile
#   - `create-dmg` (optional, for a nicer DMG background): `brew install create-dmg`
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="llmab-notary" \
#   scripts/package.sh
#
# Outputs:
#   build/LLMAB.app            — signed & notarised
#   build/LLMAB-<version>.dmg  — distributable disk image

set -euo pipefail

: "${DEV_ID:?set DEV_ID, e.g. \"Developer ID Application: Your Name (TEAMID)\"}"
: "${NOTARY_PROFILE:=llmab-notary}"

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

version="$(awk -F'"' '/LLMCore.version/ {print $2; exit}' \
           packages/LLMCore/Sources/LLMCore/LLMCore.swift || echo "0.0.0")"

build_dir="$here/build"
app_dir="$build_dir/LLMAB.app"
rm -rf "$build_dir"
mkdir -p "$build_dir"

echo "→ swift build -c release --product LLMABApp"
swift build -c release --product LLMABApp

# Assemble the .app bundle by hand. Chunk 16 lands XcodeGen later; this
# script is the pre-XcodeGen shortcut.
bin_src="$(swift build -c release --show-bin-path)/LLMABApp"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$bin_src" "$app_dir/Contents/MacOS/LLMABApp"
cp apps/LLMAB-macOS/Info.plist "$app_dir/Contents/Info.plist"
cp apps/LLMAB-macOS/Resources/PrivacyInfo.xcprivacy \
   "$app_dir/Contents/Resources/PrivacyInfo.xcprivacy" || true
# Icon: ship the concept SVG converted to icns in a later iteration.
cp assets/brand/omega-mark.svg "$app_dir/Contents/Resources/" 2>/dev/null || true

echo "→ codesign (Developer ID, hardened runtime, entitlements)"
codesign --force --deep --timestamp --options runtime \
    --entitlements apps/LLMAB-macOS/LLMAB.entitlements \
    --sign "$DEV_ID" \
    "$app_dir"

echo "→ codesign --verify"
codesign --verify --deep --strict --verbose=2 "$app_dir"

echo "→ zip for notarization"
zip_path="$build_dir/LLMAB.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"

echo "→ notarytool submit (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$zip_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ staple"
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"

echo "→ build DMG"
dmg_path="$build_dir/LLMAB-$version.dmg"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "ω $version" \
        --app-drop-link 480 180 \
        "$dmg_path" "$app_dir"
else
    hdiutil create -volname "ω $version" \
        -srcfolder "$app_dir" \
        -ov -format UDZO \
        "$dmg_path"
fi

echo
echo "✓ done"
echo "  $app_dir"
echo "  $dmg_path"
