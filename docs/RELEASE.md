# Releasing ω (LLMAB-macOS)

## V1 distribution — Developer ID + DMG

The v1 flow is Developer-ID-signed + notarised + stapled + DMG-wrapped —
no Mac App Store submission. This keeps the Code and Agents tabs
unsandboxed, which lets them read arbitrary folders and run shell
commands under user consent.

### Prerequisites (one-time)

1. Apple Developer Program membership.
2. Developer ID Application certificate in the signing Mac's login
   keychain. (Xcode → Settings → Accounts → Manage Certificates → +
   Developer ID Application.)
3. An app-specific password from <https://appleid.apple.com>.
4. Register the notarytool credential in the keychain:
   ```sh
   xcrun notarytool store-credentials llmab-notary \
       --apple-id "you@example.com" \
       --team-id TEAMID \
       --password "xxxx-xxxx-xxxx-xxxx"
   ```
5. Optional: `brew install create-dmg` for a nicer DMG layout.

### Release

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="llmab-notary" \
make package
```

Output:

- `build/LLMAB.app` — signed, notarised, stapled
- `build/LLMAB-<version>.dmg` — distributable

Upload the DMG to GitHub Releases. End users drag ω into /Applications
and open — macOS's first-launch Gatekeeper dialog respects the notarisation.

## Apple App Review posture

All AI inference is on-device, so guideline **5.1.2(i)** (third-party
AI disclosure) does not apply. The review notes we attach to any App
Store submission (post-v1 sandboxed build) should say:

> All AI inference is performed on-device via user-installed runtimes
> (Ollama, MLX, llama.cpp). No third-party AI services are contacted.
> No data is collected. Network access is limited to loopback ports
> (127.0.0.1:11434, 127.0.0.1:8080) for local-runtime communication.

See [`docs/APP-STORE.md`](APP-STORE.md) for entitlements and the
`Info.plist` usage strings.

## Version bumping

The canonical version string lives at
`packages/LLMCore/Sources/LLMCore/LLMCore.swift` (`LLMCore.version`).
`scripts/package.sh` reads it to name the DMG. `CFBundleShortVersionString`
in `apps/LLMAB-macOS/Info.plist` should be updated in the same commit.

## Post-v1 roadmap

- XcodeGen-generated `.xcodeproj` so `xcodebuild archive` drives the
  release (replacing the hand-assembled bundle in `package.sh`).
- Mac App Store variant (sandboxed, reduced-capability Code and Agents
  tabs).
- Sparkle integration for in-app updates.
- GitHub Actions workflow that runs `package.sh` on a release tag and
  attaches the DMG automatically.
