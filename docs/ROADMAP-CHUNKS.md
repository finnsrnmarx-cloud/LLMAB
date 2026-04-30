# ω Roadmap Chunks (Execution Plan)

This roadmap converts high-priority work into one-PR chunks with acceptance criteria.

## Chunk 36: QA harness + release confidence baseline

Status: implemented in the app-hardening pass.

### Scope

- Add `scripts/qa.sh` with fast/full modes.
- Add `make qa-fast` and `make qa-full` targets.
- Add `docs/QA-PLAN.md`.

### Acceptance criteria

- `make qa-fast` passes locally on a configured machine.
- `make qa-full` creates artifact folder and manual checklist guidance.
- Failures stop immediately and point to log file paths.
- Debug app builds normalize macOS extended attributes before codesign.

### Rollback

- Remove Make targets and script if build environments cannot support xcodegen/xcodebuild calls.

## Chunk 37: Live mode loop wiring (MVP)

### Scope

- Implement tight listen → transcribe → model reply → speak → re-arm loop.
- Add explicit stop control and visible loop state.

### Acceptance criteria

- End-to-end loop works for at least three consecutive turns without reopening controls.
- Loop exits cleanly on stop/cancel.
- Failures surface inline and do not wedge UI.

### Rollback

- Keep Dictate mode behavior and gate Live mode behind placeholder card again.

## Chunk 38: Capability contract tests (registry + UI gating)

### Scope

- Add tests for capability edge cases (unknown family/variant, partial modalities).
- Validate UI gating against capability flags for attachments/features.

### Acceptance criteria

- Capability regressions are caught by tests before merge.
- Attachment and mode eligibility follows capability flags in all tabs.

### Rollback

- Disable only new test fixtures if mapping churn blocks development.

## Chunk 39: Agent safety hardening

### Scope

- Expand tests for repeated consent denial, malformed tool args, and timeout paths.
- Improve transcript clarity for stop reason and tool failure reason.

### Acceptance criteria

- No tool runs after explicit denial.
- Session ends with deterministic reason for budget exhaustion and timeout.
- Transcript ordering remains stable.

### Rollback

- Keep existing six baseline tests and defer advanced paths.

## Chunk 40: llama-server lifecycle stress tests

### Scope

- Add start/stop/restart race tests with mocked process lifecycle.
- Verify command argument construction and readiness behavior.

### Acceptance criteria

- Tests cover fast start-stop churn with no invalid state transitions.
- `--flash-attn on` remains enforced.

### Rollback

- Keep existing controller behavior and isolate flaky stress fixtures.

## Chunk 41: CLI named sessions + parallel runs

### Scope

- Introduce `llmab session` commands (`create/list/run/resume/stop`).
- Add session persistence + locking for concurrent operations.

### Acceptance criteria

- Multiple sessions can run concurrently without state corruption.
- Interrupt/restart preserves session state.
- Deterministic exit codes for CI usage.

### Rollback

- Keep single-session flow and hide session subcommands behind feature flag.

## Chunk 42: Runtime parity hardening

### Scope

- Expand llama.cpp adapter support beyond plain text.
- Keep MLX non-streaming behavior documented until native streaming lands.
- Add targeted tests for wire-format and streamed tool-call parsing.

### Acceptance criteria

- llama-server accepts image-bearing messages through OpenAI-compatible content blocks.
- llama-server receives tool schemas and emits `ChatChunk.toolCall` events from streamed tool-call deltas.
- Agent tab can use a tool-capable llama-server model without falling back to Ollama.

### Rollback

- Preserve text-only llama-server chat behavior and hide tool/image support behind capability gates.
