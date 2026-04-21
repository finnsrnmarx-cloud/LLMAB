# Gemma 4 — compatibility with LLMAB

Gemma 4 was released by Google DeepMind on April 2, 2026 under Apache 2.0. It ships in four variants. **Not every feature in LLMAB is supported by every variant**; the app feature-gates the UI at runtime using the table below.

## Variant × modality matrix

| Modality                     | E2B (~2.3 B) | E4B (~4.5 B) | 26B A4B MoE (4 B active) | 31B dense |
|------------------------------|:------------:|:------------:|:------------------------:|:---------:|
| Text → text                  | ✅ | ✅ | ✅ | ✅ |
| Image + text → text          | ✅ | ✅ | ✅ | ✅ |
| Audio input (ASR/translate)  | ✅ | ✅ | ❌ | ❌ |
| Video ≤60 s @ 1 fps → text   | ❌ | ❌ | ✅ | ✅ |
| Text → image                 | ❌ | ❌ | ❌ | ❌ |
| Audio output (TTS)           | ❌ | ❌ | ❌ | ❌ |
| Native tool-use / thinking   | ✅ | ✅ | ✅ | ✅ |
| 256 K context                | ✅ | ✅ | ✅ | ✅ |
| 140 + languages              | ✅ | ✅ | ✅ | ✅ |

## LLMAB tab × variant matrix

| LLMAB sub-mode          | Requires                  | E2B / E4B | 26B / 31B |
|-------------------------|---------------------------|:---------:|:---------:|
| Chat → typing           | text                      | ✅ | ✅ |
| Chat → upload image     | image-in                  | ✅ | ✅ |
| Chat → dictate          | ASR *or* Apple Speech     | ✅ | ✅* |
| Chat → live conversation| ASR + text + TTS          | ✅ | ✅* |
| Chat → create image     | external diffusion model  | gated | gated |
| Code tab                | text                      | ✅ | ✅ |
| Agents tab              | text + tool-use           | ✅ | ✅ |
| Video tab               | video-in                  | ❌ | ✅ |

`*` On 26B / 31B, audio input is delivered via **Apple Speech framework** (on-device, offline) rather than Gemma 4 native audio — the app falls back automatically.

`TTS` is always served by `AVSpeechSynthesizer` (native macOS, offline, free). A future opt-in upgrade path is Kokoro-TTS / Parakeet via MLX.

## Recommended default

`gemma-4:e4b` via Ollama — covers every tab except Video, fits on 8 GB Apple Silicon, ~70 tok/s on M3.

## External companions (optional)

| Need | Model | Runtime |
|------|-------|---------|
| Image generation | FLUX.1-schnell or SDXL Turbo | Ollama or ml-stable-diffusion |
| Higher-quality TTS | Kokoro-82M, Parakeet | mlx-audio |
| Faster ASR on 26B/31B | Whisper-large-v3-turbo | whisper.cpp |

## Sources

- Google DeepMind, *Gemma 4 model card*, April 2026.
- Hugging Face, *Welcome Gemma 4: Frontier multimodal intelligence on device*, April 2026.
- InfoQ, *Google Opens Gemma 4 Under Apache 2.0 with Multimodal and Agentic Capabilities*, April 2026.
