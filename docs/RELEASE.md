# Releasing ω (LLMAB-macOS)

## V1 distribution — Developer ID + DMG

Outside-App-Store distribution: Developer-ID-signed, notarised, stapled,
DMG-wrapped. This keeps the Code and Agents tabs unsandboxed so they can
read arbitrary folders and run shell commands under user consent.

## Automated path (GitHub Actions, recommended)

`.github/workflows/release.yml` fires on any `v*` tag push (or via
Actions → Release (DMG) → Run workflow). It builds, signs, notarises,
staples, wraps the DMG, and attaches it to a draft GitHub Release for
the tag.

### One-time: add secrets

Settings → Secrets and variables → Actions → New repository secret.

| Secret | What it is |
|---|---|
| `APPLE_DEV_ID_CERT_BASE64`   | `base64 -i DeveloperID.p12 \| pbcopy` — full .p12 export from Keychain Access |
| `APPLE_DEV_ID_CERT_PASSWORD` | password you set when exporting the .p12 |
| `APPLE_DEV_ID`               | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_TEAM_ID`              | 10-char Apple team id |
| `APPLE_ID_EMAIL`             | Apple ID email for notarytool |
| `APPLE_ID_APP_PASSWORD`      | app-specific password from <https://appleid.apple.com> |

### Cut a release

```sh
# Bump LLMCore.version in packages/LLMCore/Sources/LLMCore/LLMCore.swift
# and MARKETING_VERSION in project.yml to match.
git commit -am "release 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

The workflow takes 10–15 min (notarization dominates). When it's done,
open the draft release, review the auto-generated notes, and click
Publish.

## Manual path (local machine)

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

- Mac App Store variant as a second target in `project.yml`
  (sandboxed, reduced-capability Code and Agents tabs).
- Sparkle integration for in-app updates.
