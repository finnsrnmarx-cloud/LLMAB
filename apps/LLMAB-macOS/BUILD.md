# Building ω (LLMAB-macOS)

## V1 path: generate the xcodeproj, open in Xcode

```sh
brew install xcodegen     # one-time
make xcodeproj            # regenerates LLMAB.xcodeproj from project.yml
open LLMAB.xcodeproj
```

In Xcode: pick the `LLMABApp` scheme → **⌘R**. You get a real `.app`
bundle with proper SwiftUI App lifecycle (the bare SwiftPM binary
doesn't — it exits immediately on macOS).

Or, if you don't want to open Xcode:

```sh
make run-app              # xcodebuild + open the resulting .app
```

## CI / headless

```sh
make build                # libraries + CLI only (no app)
make test                 # swift test
make app                  # xcodebuild the .app bundle
```

`LLMAB.xcodeproj` is deliberately **not checked in** — it's regenerated
from `project.yml` on demand. Edit `project.yml`, not the generated
project, to avoid merge pain.

## CLI usage

```sh
make cli                  # swift build -c release --product llmab
swift run llmab models
swift run llmab chat "hello"
```

## Release (signed DMG)

See [`docs/RELEASE.md`](../../docs/RELEASE.md) for Developer ID +
notarization. TL;DR:

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="llmab-notary" \
make package
```

## Runtime expectations

ω auto-detects whichever local runtimes are installed — you only need
one:

- **Ollama** — `brew install ollama && brew services start ollama && ollama pull gemma3:4b`
- **llama.cpp** — `brew install llama.cpp`; run `llama-server -m <gguf> --port 8080 ...`
- **MLX** — `pip install mlx-lm` + HuggingFace MLX-community models under `~/.cache/huggingface/hub`

The ones you don't install simply appear greyed-out in Settings.

## Privacy posture

`Info.plist` and `PrivacyInfo.xcprivacy` are calibrated for the App
Review 5.1.2(i) exemption (on-device only, no third-party AI). See
`docs/APP-STORE.md` for the full copy.
