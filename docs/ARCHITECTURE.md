# LLMAB — Architecture

## Goals

1. Ship a local-first multimodal macOS app (`ω`) that runs local LLMs — Gemma 4 first — with explicit opt-in cloud providers.
2. Detect installed runtimes and models on the user's machine and feature-gate the UI to each model's real capabilities.
3. Ship a companion `llmab` CLI sharing the same core.
4. Stay exempt from Apple's guideline 5.1.2(i) (third-party AI disclosure) by doing all inference on-device.
5. Port cleanly to iPadOS / iOS after v1.

## High-level layout

```
apps/LLMAB-macOS/     SwiftUI app (Xcode project, chunk 7+)
cli/llmab/            Executable: swift run llmab
packages/
  LLMCore             Runtime-agnostic types + LLMRuntime protocol
  RuntimeOllama       HTTP adapter for the Ollama daemon (default)
  RuntimeMLX          mlx_lm shell-out adapter
  RuntimeLlamaCpp     llama.cpp / llama-server adapter
  RuntimeOpenAICompatible DeepSeek / OpenAI-compatible opt-in cloud adapters
  ModelRegistry       Runtime scan + Gemma 4 capability map
  AgentKit            Tool-use loop (read_file, write_file, run_shell, web_search, list_dir)
  MediaKit            AVFoundation capture, Speech framework, AVSpeechSynthesizer
  UIKitOmega          SwiftUI atoms: OmegaMark, OmegaSpinner, AuroraRing, AuroraGradient, CLIPrompt
docs/                 This doc + Gemma 4 compatibility + App Store notes
assets/brand/         ω glyph, aurora gradient tokens, app icon
```

## Runtime protocol (LLMCore)

```swift
public protocol LLMRuntime: Sendable {
    var id: String { get }                             // "ollama" | "mlx" | "llamacpp" | "deepseek"
    func discoverModels() async -> [ModelInfo]
    func capabilities(of: ModelInfo) -> ModelCapabilities
    func chat(_ req: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
}
```

`ChatRequest` carries the full message history, tool schema, image/audio/video parts, and sampling config. `ChatChunk` is either a token delta, a tool-call, or a terminal reason. The adapter layer turns this into Ollama's `/api/chat`, MLX's `mlx_lm.generate`, llama-server's OpenAI-compatible endpoint, or an explicitly configured cloud provider.

## Capability gating

`ModelRegistry` holds the canonical capability table and heuristic pattern matcher (`gemma-4:e2b` / `gemma-4:e4b` / `gemma-4:26b` / `gemma-4:31b`, DeepSeek, Qwen VL, Llama, MiniCPM-V, Mistral/Pixtral, Phi, Llava, diffusion families). The UI asks the selected model's `ModelCapabilities` before enabling any tab sub-mode, including privacy badges and video frame-ingest profiles.

## UI principles

- **Midnight base** (`#050712` / `#0A0B14`) with aurora-gradient accents.
- **Lowercase ω** as the only product mark — the titlebar, CLI prompt prefix, app icon.
- **Every active state spins** — `OmegaSpinner` (rotating ω) for foreground ops, `AuroraRing` (rotating halo) for peripheral ops. No system spinners.
- **Code tab** uses a cooler sub-palette (cyan → teal → indigo → violet) and monospaces everything.

## Chunked delivery

Build proceeds in 16 numbered chunks, each = one commit + one PR on `claude/gemini-llm-cli-macos-U6vmP`. The chunk list lives in the plan file at `/root/.claude/plans/i-want-to-create-shimmying-plum.md` and in the root `README.md`.

## Non-goals (v1)

- No implicit cloud fallback; cloud providers are explicit opt-in only.
- No image generation bundled — gated behind user-installed diffusion models.
- No Windows/Linux native builds (CLI may work, GUI will not).
