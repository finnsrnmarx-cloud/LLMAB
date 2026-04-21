# LLMAB — ω

**A local-LLM macOS app for Gemma 4 and friends.**

LLMAB (wordmark: lowercase **ω**) is a SwiftUI-first, fully on-device multimodal chat, coding, and agent app. It runs against local LLM runtimes (Ollama first, then MLX and llama.cpp) and auto-detects which models are installed on the machine, gating features by what the selected model can actually do.

## Why

- **On-device first.** No third-party cloud AI. Apple App Review guideline 5.1.2(i) explicitly exempts on-device inference from the new third-party-AI disclosure regime; the app posture is favorable.
- **Gemma 4 native.** Capability matrix (text, image, audio, video) is wired into the UI so each variant (E2B, E4B, 26B A4B, 31B dense) surfaces only the tabs it can serve.
- **Aurora on midnight.** Full-spectrum gradient on near-black, lowercase ω as the mark, every active feature animates.

## Status

This repo is under active construction on branch `claude/gemini-llm-cli-macos-U6vmP`, shipping in 16 numbered chunks. Chunk 1 = scaffold; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full plan.

## Repository layout

```
apps/LLMAB-macOS/           SwiftUI macOS app (Xcode project, arrives in chunk 7)
cli/llmab/                  Companion CLI binary (llmab)
packages/
  LLMCore/                  LLMRuntime protocol + shared types
  RuntimeOllama/            Ollama HTTP adapter (default)
  RuntimeMLX/               mlx_lm adapter (chunk 14)
  RuntimeLlamaCpp/          llama.cpp adapter (chunk 14)
  ModelRegistry/            Detection + Gemma 4 capability map
  AgentKit/                 Tool-use loop (file, shell, web)
  MediaKit/                 AVFoundation capture, Speech, TTS
  UIKitOmega/               Shared SwiftUI: OmegaMark, OmegaSpinner, AuroraRing, AuroraGradient
docs/                       Architecture, Gemma 4 compatibility, App Store notes
assets/brand/               ω glyph, aurora gradient tokens, app icon
```

## Tabs (target design)

1. **Chat** (default) — live conversation, typed chat, dictate, image+text, optional image-gen.
2. **Code** — CLI-styled file tree + streaming bug-fix/refactor analysis.
3. **Agents** — tool-use loop (read/write file, run shell, web search, list dir).
4. **Video** — 1 fps camera + mic → Gemma 4 26B/31B → TTS response.

All tabs feature-gate on the selected model's capability badges.

## Building (once chunk 1 lands)

```sh
swift build
swift test
```

The macOS app (chunk 7+) builds via the `LLMAB` Xcode scheme.

## License

Apache-2.0, matching Gemma 4.
