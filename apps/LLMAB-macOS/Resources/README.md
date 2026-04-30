# Resources

Runtime resources copied into the macOS app bundle:

- `PrivacyInfo.xcprivacy` — privacy manifest (see `docs/APP-STORE.md`)

The Dock icon is generated on demand from `assets/brand/app-icon.svg` via:

```sh
make icon
```

That command writes `AppIcon.icns` into this directory. The generated binary is
not checked in, so rerun it after changing the source SVG.
