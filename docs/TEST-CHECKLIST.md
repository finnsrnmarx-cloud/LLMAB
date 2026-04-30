# ω manual test checklist

Tick through this on a real Mac after every meaningful PR lands on `main`.
No CI can verify what actually happens when you click a button; this is the
eyes-and-hands backstop.

Every row has:
- **Action** — the thing you do
- **Expected** — what should happen
- **Pass/Fail** — check the box if it matches; if not, open an issue
  linking this document

If any row fails that used to pass, it's a regression — file it.

---

## 0. Pre-flight

- [ ] Ollama or llama-server is running and reachable on loopback
- [ ] At least one model is discoverable (`swift run llmab models` lists one)
- [ ] App builds cleanly: `make xcodeproj && make run-app` (or Xcode ⌘R)

---

## 1. App shell

| Action | Expected |
|---|---|
| [ ] Launch the app | Window opens, midnight background, ω mark drifts in the title bar |
| [ ] Resize window down to minimum | Nothing clips; min size is 960 × 640 |
| [ ] ⌘Q to quit | Window dismisses; relaunch preserves last-viewed tab + conversation (persistence chunk 23) |

---

## 2. Tab rail (left side)

For each tab: **Code / Chat / Agents / Video / Settings**

| Action | Expected |
|---|---|
| [ ] Click each rail icon | The centre pane switches to that tab; the selected icon gets aurora gradient + glow outline |
| [ ] Settings sits pinned at the bottom of the rail | Visually separated from the top group (Code/Chat/Agents/Video) |
| [ ] ⌘, from any tab | A separate Settings window opens in addition to (not instead of) the tab |

---

## 3. Chat tab

### Mode picker (segmented control)

| Action | Expected |
|---|---|
| [ ] Click `Chat` | Shows conversation + composer |
| [ ] Click `Dictate` | Shows dictation view with big ω button |
| [ ] Click `Image` | Shows conversation with "tap the paperclip" hint banner |
| [ ] Click `Live` / `Create` | Shows feature-gated placeholder card without stale chunk references |

### Chat mode — composer

| Action | Expected |
|---|---|
| [ ] Focus the text field, type | Text appears in field |
| [ ] Press ⌘↵ with text | Message appears in conversation; streaming reply follows |
| [ ] Click the ω send button with empty input | Button is dimmed; click does nothing |
| [ ] Click the ω send button while streaming | Button shows spinner; click cancels the stream |
| [ ] Click the paperclip (📎) | File picker opens |
| [ ] Pick an image | Chip with filename + size appears above the composer |
| [ ] Click ✕ on the chip | Chip disappears |
| [ ] Send with image + text, using an imageIn model (Gemma 4) | Image and text arrive in the conversation; reply streams |
| [ ] Send with image + text, using a text-only model | Assistant bubble shows "X does not accept images — remove the attachment or switch model" |
| [ ] Switch to another tab, come back | Conversation + draft text are still there (persistence) |

### Dictate mode

| Action | Expected |
|---|---|
| [ ] Click the big ω button | First time: microphone + speech-recognition permission dialogs appear; grant both |
| [ ] Speak after granting | Live transcription appears in the panel; ω button halo pulses with voice envelope |
| [ ] Click ω again | Dictation stops; text lands in Chat composer |
| [ ] Toggle `auto-send` on, then dictate | On stop, the message auto-submits |
| [ ] Header shows `listening · on-device` | If it shows `listening · Apple cloud`, your locale's on-device model isn't installed (System Settings → Accessibility → Spoken Content → English) |

---

## 4. Code tab

### Folder picker

| Action | Expected |
|---|---|
| [ ] Click `open folder` | macOS folder picker opens |
| [ ] Pick a folder | Tree populates with directories first, alphabetical, skipping `.git` / `node_modules` / `.build` / `DerivedData` etc. |
| [ ] Click `change` (same button after first pick) | Picker reopens; new folder replaces the tree |

### File tree

| Action | Expected |
|---|---|
| [ ] Click a folder | Chevron rotates, children expand |
| [ ] Click again | Chevron rotates back, children collapse |
| [ ] Click a file | File highlights with aurora stripe; right pane updates header |

### Analysis pane

| Action | Expected |
|---|---|
| [ ] With a file selected, click `analyze` | ω streams a review into the pane |
| [ ] Type a freeform question in the prompt, ⌘↵ | Reply uses your question instead of the default review prompt |
| [ ] Select a different file | Analysis resets; `analyze` button reappears |
| [ ] Quit, relaunch | Same folder + selected file restored |

---

## 5. Agents tab

### Empty state

| Action | Expected |
|---|---|
| [ ] On first visit | Six idea chips appear with the sparkles icon |
| [ ] Click any idea chip | The chip's full text appears in the composer |

### Tool chips header

| Action | Expected |
|---|---|
| [ ] Four read-only chips visible: `read_file` / `write_file` / `list_dir` / `run_shell` (lock.shield icon) | Just informational |
| [ ] Toggle `web_search` switch | Header subtitle flips to include `· web on` |

### Running an agent

| Action | Expected |
|---|---|
| [ ] Send the "List the 5 largest files in ~/Downloads" prompt | Assistant text streams; a `#1` tool call card appears for `list_dir` / `run_shell` / `read_file` as needed |
| [ ] Send a prompt that triggers `run_shell` | A consent sheet opens showing the exact command; click approve / deny matches behaviour |
| [ ] On a tool-call card, click the chevron | Card collapses to header row; click again → expands |
| [ ] On a tool-result card, click the clipboard icon | Icon briefly shows a checkmark; paste elsewhere → matches the card's output |
| [ ] Click `reset` (top-right of the toolbar) | Transcript clears |
| [ ] Quit, relaunch | Last transcript is still there (persistence) |

---

## 6. Video tab

| Action | Expected |
|---|---|
| [ ] Click `start camera` | First time: camera permission dialog; grant it |
| [ ] Preview appears | Live feed visible; "live" chip + spinner overlay in the corner |
| [ ] Hold the big ω button (or tap, depending on platform) | Dictation starts; live transcription appears in the sidebar |
| [ ] Release (or tap again) | Latest frame + your words go to any vision-capable model; reply streams into transcript AND is spoken via TTS |
| [ ] If you're on a text-only model | Sidebar shows "X can't accept images/frames — switch to a vision-capable model" |
| [ ] Click `watch 10s` | Countdown runs, frames are sampled, and the final reply focuses on change over time |
| [ ] Click ✕ in the control bar | Camera stops, preview disappears |

---

## 7. Settings

### Runtimes section

| Action | Expected |
|---|---|
| [ ] `Ollama · local daemon` row: green AuroraRing if daemon running, grey if not | Grey row shows error text "runtime not reachable" |
| [ ] `llama.cpp · llama-server` row: same logic on port 8080 | — |
| [ ] `MLX · Apple Silicon native` row: green if `mlx_lm` on PATH | — |
| [ ] Click `rescan` (top-right of header) | Spinner briefly appears; rows re-populate |

### Models section

| Action | Expected |
|---|---|
| [ ] Every discoverable model listed | Each row shows display name, runtime id, capability badges (img / aud / vid / tool / think / context-K) |
| [ ] Click a row | Row gets aurora outline + glowing ω; row becomes "active" everywhere in the app |
| [ ] Active model has `loaded` tag if the runtime reports it loaded | Ollama `/api/ps` reported models |

### Pull section (Ollama only)

| Action | Expected |
|---|---|
| [ ] Type a tag (e.g. `gemma3:4b`) in the field | — |
| [ ] Click `pull` | Spinner; progress bar fills as Ollama streams bytes; on finish the model appears in Models above |
| [ ] Error (typo'd tag) | Red error message below the button |

### Voice section

| Action | Expected |
|---|---|
| [ ] Picker first row: `auto (best British voice installed)` | Clicking this uses the automatic en-GB chooser |
| [ ] Other rows labelled `en-GB · Daniel (Premium)` etc. | Sorted British-first, premium-first |
| [ ] Pick any voice | "Hello — this is ω…" sentence speaks in the picked voice |
| [ ] Quit, relaunch | Picker still on the same voice |

---

## 8. Persistence across launches

| Action | Expected |
|---|---|
| [ ] Type half a message in Chat, don't send, ⌘Q | On relaunch, text is still in composer |
| [ ] Have a conversation, ⌘Q | On relaunch, conversation is present |
| [ ] Open a folder in Code tab, ⌘Q | On relaunch, folder and selected file are restored |
| [ ] Pick a model + voice in Settings, ⌘Q | On relaunch, both still selected |
| [ ] Agent transcript, ⌘Q mid-stream | On relaunch, transcript up to the last completed turn is present (in-flight tokens may be lost by design; debounce window is 0.4 s) |

---

## 9. Regressions to watch for after every PR

- [ ] Window still opens (no black screen)
- [ ] Font size consistent across tabs (nothing 4 pt or 40 pt by accident)
- [ ] Aurora gradient renders the Google-fade palette (blue → green → yellow → red → pink → purple), not the old neon rainbow
- [ ] ω mark still drifts in the title bar
- [ ] No permission dialogs re-appear every session (cached once granted)

---

## Filing a bug

If a row fails:
1. Note the row # + action
2. Screenshot if visual
3. Copy any console output from Xcode's Debug area
4. Open an issue at <https://github.com/finnsrnmarx-cloud/LLMAB/issues>

Include the commit SHA from `git rev-parse --short HEAD` so we know which
state failed.

---

## 10. Evidence capture and failure signatures

For any failed row, record:

- exact checklist row and action text
- visible error text in-app
- log source (`xcodebuild`, Xcode debug console, or runtime logs)
- whether issue reproduces after app relaunch

Common failure signatures to call out verbatim:

- runtime unavailable / unreachable on loopback
- model does not accept selected modality (image/audio/video)
- consent denied (agent tools)
- request cancelled by user
- step budget exhausted

When filing the issue, include:

- commit SHA (`git rev-parse --short HEAD`)
- runtime used (Ollama / MLX / llama.cpp)
- selected model id
- macOS version + machine RAM tier
