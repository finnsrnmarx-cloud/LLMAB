# Typography in ω

Every font size, weight, and design in the app goes through one namespace:
[`UIKitOmega.Typography`](../packages/UIKitOmega/Sources/UIKitOmega/Typography.swift).
Views call semantic names (`Typography.title`, `Typography.body`,
`Typography.meta`, `Typography.mono`, `Typography.micro`) rather than
scattering `.system(.caption, design: .monospaced).weight(.semibold)` across
fifty files.

## Current stack (defaults)

| Style         | Size | Weight    | Design     | Where it's used                          |
|---------------|------|-----------|------------|------------------------------------------|
| `.title`      | 20   | semibold  | rounded    | Dialog titles, onboarding slates         |
| `.subtitle`   | 13   | semibold  | rounded    | Section labels in Settings               |
| `.body`       | 14   | regular   | default    | Chat bubbles, tab body copy              |
| `.bodySmall`  | 12   | regular   | default    | Placeholder / subtitle strings           |
| `.meta`       | 11   | medium    | monospaced | Tab subtitles, capability badges         |
| `.micro`      | 9    | semibold  | monospaced | Step chips, tiny labels                  |
| `.mono`       | 12   | regular   | monospaced | Tool call JSON, code blocks, logs        |
| `.monoLarge`  | 14   | regular   | monospaced | CLIPrompt input, analysis pane body      |

Resolves to **SF Pro** / **SF Mono** (the system stack) on macOS —
cleanest possible default, zero bundle cost.

## Swap in a bundled font (e.g. Inter)

If you want Inter / Geist / JetBrains Mono instead:

1. **Download** the fonts. For Inter:
   <https://github.com/rsms/inter/releases> — pick the latest `Inter.zip`,
   extract the `Inter Variable.ttf` (or the specific weight TTFs you want).
2. **Drop them in** under `apps/LLMAB-macOS/Resources/Fonts/`. Create the
   directory if missing.
3. **Register them** in `apps/LLMAB-macOS/Info.plist`:
   ```xml
   <key>ATSApplicationFontsPath</key>
   <string>Fonts</string>
   ```
4. **Point Typography at the family** — early in `LLMABApp.init()`:
   ```swift
   Typography.bundledFamilyName = "Inter"
   Typography.bundledMonoFamilyName = "JetBrains Mono"   // optional
   ```
5. **Rebuild.** Typography's resolver checks
   `NSFontManager.shared.availableFontFamilies` at call time and falls
   back to SF automatically if the family isn't registered, so the app
   never "blanks out" because a file is missing.

## Why semantic names?

- **One place to retune** — change `.body` size from 14 → 15 and every
  chat bubble / tab body updates.
- **Font swap is two lines** — `bundledFamilyName = "Inter"` and the
  whole UI switches.
- **Easier to audit** — grepping for `Typography.micro` shows every use
  of the 9 pt mono chip style; grepping `.system(size: 9, ...)` finds
  only the stragglers that haven't been migrated yet.

## Migration status

As of chunk 27, Typography is used in:
- `TabHeader` (title + subtitle)
- `PlaceholderCard`
- `CLIPrompt` (composer input)

Remaining ad-hoc `.system(...)` calls live in `MessageBubble`,
`SettingsView`, `ChatConversationView`, and a few tab subviews — these
get migrated as they're touched for other reasons. No rush; the
typography palette itself is already consistent.
