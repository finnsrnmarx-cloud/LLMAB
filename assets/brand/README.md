# Brand assets

Brand kit lands in **chunk 2**. Expected contents:

- `omega-mark.svg` — the lowercase ω glyph with live aurora-gradient stroke.
- `app-icon-1024.png` — ω on a midnight radial, rendered for macOS/iOS.
- `aurora-tokens.json` — hex stops for the full-spectrum aurora gradient.
- `midnight-tokens.json` — `#050712` / `#0A0B14` / `#141828` base colors.

All downstream SwiftUI components (`UIKitOmega`) read from these tokens so the palette is defined in one place.
