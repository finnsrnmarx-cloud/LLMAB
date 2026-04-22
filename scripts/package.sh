#!/usr/bin/env bash
#
# scripts/package.sh — generate xcodeproj → archive → export → notarize →
# staple → DMG. Produces a Developer-ID-signed, notarized .app and a
# distributable .dmg under `build/`.
#
# Prerequisites:
#   - Xcode 15.x or 16.x installed and selected (`sudo xcode-select -s ...`)
#   - `brew install xcodegen create-dmg` (create-dmg optional; hdiutil fallback)
#   - Developer ID Application certificate in the login keychain
#   - Notarytool credential stored as a keychain profile:
#       xcrun notarytool store-credentials llmab-notary \
#           --apple-id "you@example.com" \
#           --team-id TEAMID \
#           --password "xxxx-xxxx-xxxx-xxxx"
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" \
#   TEAM_ID=TEAMID \
#   NOTARY_PROFILE=llmab-notary \
#   scripts/package.sh
#
# Outputs (under build/):
#   LLMAB.xcarchive        the xcodebuild archive
#   export/LLMAB.app       signed, notarized, stapled
#   LLMAB-<version>.dmg    distributable disk image

set -euo pipefail

: "${DEV_ID:?set DEV_ID, e.g. \"Developer ID Application: Your Name (TEAMID)\"}"
: "${TEAM_ID:?set TEAM_ID to your 10-char Apple team id}"
: "${NOTARY_PROFILE:=llmab-notary}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(awk -F'"' '/LLMCore.version/ {print $2; exit}' \
           packages/LLMCore/Sources/LLMCore/LLMCore.swift || echo "0.0.0")"

build_dir="$root/build"
archive_path="$build_dir/LLMAB.xcarchive"
export_path="$build_dir/export"
app_path="$export_path/LLMAB.app"

rm -rf "$build_dir"
mkdir -p "$build_dir"

# 1. Regenerate xcodeproj from project.yml (idempotent).
command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
echo "→ xcodegen generate"
xcodegen generate

# 2. Render ExportOptions.plist with the caller's TEAM_ID.
export_opts_src="$root/scripts/ExportOptions.plist"
export_opts="$build_dir/ExportOptions.plist"
sed "s/__TEAM_ID__/$TEAM_ID/" "$export_opts_src" > "$export_opts"

# 3. Archive.
echo "→ xcodebuild archive"
xcodebuild \
    -project LLMAB.xcodeproj \
    -scheme LLMABApp \
    -configuration Release \
    -archivePath "$archive_path" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$DEV_ID" \
    CODE_SIGN_STYLE=Manual \
    archive

# 4. Export (Developer ID, outside-App-Store).
echo "→ xcodebuild -exportArchive"
xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$export_opts" \
    -exportPath "$export_path"

if [[ ! -d "$app_path" ]]; then
    echo "✗ expected $app_path after export" ; exit 1
fi

# 5. Verify signature.
echo "→ codesign --verify"
codesign --verify --deep --strict --verbose=2 "$app_path"

# 6. Zip + notarize.
zip_path="$build_dir/LLMAB.zip"
echo "→ ditto zip for notarization"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

echo "→ notarytool submit (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$zip_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# 7. Staple.
echo "→ staple"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"

# 8. DMG.
dmg_path="$build_dir/LLMAB-$version.dmg"
if command -v create-dmg >/dev/null 2>&1; then
    echo "→ create-dmg"
    create-dmg \
        --volname "ω $version" \
        --app-drop-link 480 180 \
        "$dmg_path" "$app_path"
else
    echo "→ hdiutil create (fallback — install create-dmg for a prettier layout)"
    hdiutil create -volname "ω $version" \
        -srcfolder "$app_path" \
        -ov -format UDZO \
        "$dmg_path"
fi

echo
echo "✓ done"
echo "  $app_path"
echo "  $dmg_path"
