# Releasing ω (LLMAB-macOS)

## V1 distribution — Developer ID + DMG

Outside-App-Store distribution: Developer-ID-signed, notarised, stapled,
DMG-wrapped. This keeps the Code and Agents tabs unsandboxed so they can
read arbitrary folders and run shell commands under user consent.

### Prerequisites (one-time)

1. Apple Developer Program membership + 10-char `TEAM_ID`.
2. **Developer ID Application** certificate in the signing Mac's login
   keychain (Xcode → Settings → Accounts → Manage Certificates → + →
   Developer ID Application).
3. App-specific password from <https://appleid.apple.com>.
4. Register the notarytool credential in the keychain:
   ```sh
   xcrun notarytool store-credentials llmab-notary \
       --apple-id "you@example.com" \
       --team-id TEAMID \
       --password "xxxx-xxxx-xxxx-xxxx"
   ```
5. `brew install xcodegen create-dmg` — `xcodegen` is required;
   `create-dmg` optional (script falls back to `hdiutil`).

### Release

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID)" \
TEAM_ID=TEAMID \
NOTARY_PROFILE=llmab-notary \
make package
```

What happens under the hood:

1. `xcodegen generate` regenerates `LLMAB.xcodeproj` from `project.yml`
2. `xcodebuild … archive` produces `build/LLMAB.xcarchive` (signed with
   `$DEV_ID`, hardened runtime on by default)
3. `xcodebuild -exportArchive` with method=developer-id extracts the
   `.app` into `build/export/`
4. `codesign --verify` sanity-checks the signature chain
5. `ditto -c -k` zips the app for submission
6. `xcrun notarytool submit … --wait` sends to Apple, waits for the
   accept/reject verdict
7. `xcrun stapler staple` embeds the notarization ticket so offline
   Macs can verify the app without calling home
8. `create-dmg` (or `hdiutil`) wraps the stapled app into
   `build/LLMAB-<version>.dmg`

End users drag ω into /Applications, open it, macOS's first-launch
Gatekeeper dialog respects the notarization.

## Apple App Review posture

All AI inference is on-device, so guideline **5.1.2(i)** (third-party AI
disclosure) does not apply. App Review notes for any Mac App Store
submission (post-v1 sandboxed variant):

> All AI inference is performed on-device via user-installed runtimes
> (Ollama, MLX, llama.cpp). No third-party AI services are contacted.
> No data is collected. Network access is limited to loopback ports
> (127.0.0.1:11434, 127.0.0.1:8080) for local-runtime communication.

See [`docs/APP-STORE.md`](APP-STORE.md) for entitlements and `Info.plist`
usage strings.

## Version bumping

The canonical version string lives at
`packages/LLMCore/Sources/LLMCore/LLMCore.swift` (`LLMCore.version`).
`scripts/package.sh` reads it to name the DMG.
`MARKETING_VERSION` in `project.yml` should be updated in the same commit.

## Post-v1 roadmap

- GitHub Action that runs `package.sh` on a release tag and attaches the
  DMG automatically (chunk 21).
- Mac App Store variant as a second target in `project.yml`
  (sandboxed, reduced-capability Code and Agents tabs).
- Sparkle integration for in-app updates.
