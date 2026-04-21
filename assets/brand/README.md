# Brand assets

Landed in chunk 2.

| File                       | Purpose                                                                 |
|----------------------------|-------------------------------------------------------------------------|
| `omega-mark.svg`           | The lowercase ω glyph with aurora-gradient stroke on a midnight disk.   |
| `app-icon-concept.svg`     | Concept icon at 1024² — midnight squircle + aurora halo + ω.            |
| `aurora-tokens.json`       | Full-spectrum aurora stops + cooler `codeStops` for the Code tab.       |
| `midnight-tokens.json`     | Near-black palette (void, midnight, abyss, indigo-deep, navy, …).       |

Token values are mirrored in Swift at `packages/UIKitOmega/Sources/UIKitOmega/Midnight.swift` and `…/AuroraGradient.swift`. Any palette change must be made in both places; chunk 15 introduces a code-gen step to keep them in sync.

The final `.icns` and iOS/iPadOS variants ship with the Xcode project in chunk 7.
