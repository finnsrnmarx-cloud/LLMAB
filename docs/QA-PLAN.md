# ω QA Plan

This document defines repeatable QA flows for LLMAB.

## Goals

- Provide a single command entrypoint for fast verification on every PR.
- Define a full manual + artifact-backed release candidate pass.
- Keep failures actionable with deterministic logs and clear ownership.

## Modes

### 1) Fast mode (PR gate)

Run on every branch before opening a PR:

```bash
make qa-fast
```

`qa-fast` runs:

1. `swift build -c debug`
2. `swift test --parallel`
3. macOS metadata normalization (`xattr -cr` on app resources/assets)
4. `xcodegen generate`
5. `xcodebuild` Debug app build
6. final app bundle metadata normalization
7. `codesign --verify --deep --strict` on the Debug app bundle

For local desktop smoke tests, use:

```bash
make run-app
```

`run-app` builds the Debug app, launches it, strips launch-time Finder metadata
that macOS may attach to the bundle, then re-runs strict codesign verification.

### 2) Full mode (release candidate)

Run before cut/release and for major feature chunks:

```bash
make qa-full
```

`qa-full` runs:

- All fast checks.
- Manual checklist handoff (`docs/TEST-CHECKLIST.md`).
- Artifact capture shell that stores logs under `artifacts/qa/<timestamp>/`.

## Artifact conventions

`qa.sh` writes under:

- `artifacts/qa/<timestamp>/summary.txt`
- `artifacts/qa/<timestamp>/commands.log`
- `artifacts/qa/<timestamp>/build.log`
- `artifacts/qa/<timestamp>/test.log`
- `artifacts/qa/<timestamp>/xattr.log`
- `artifacts/qa/<timestamp>/xcodegen.log`
- `artifacts/qa/<timestamp>/xcodebuild.log`
- `artifacts/qa/<timestamp>/app-xattr.log`
- `artifacts/qa/<timestamp>/codesign-verify.log`

When a command fails, the run stops and the failing command is recorded in `summary.txt`.

## Runtime matrix to cover in manual QA

For each release candidate run the checklist with these runtime states:

1. Ollama installed + running.
2. llama-server installed + running.
3. MLX available.
4. One runtime missing/unreachable.
5. No runtime reachable (empty fallback UX).

## Permission matrix to cover in manual QA

At minimum validate:

- Microphone denied then granted.
- Camera denied then granted.
- Speech recognition unavailable then available.
- Accessibility permission flow (when computer-use tools land).

## Exit criteria

A feature chunk is QA-complete when:

1. `make qa-fast` passes.
2. Checklist rows for changed features are marked pass.
3. Any failures are filed with reproduction steps + logs from `artifacts/qa/<timestamp>/`.
