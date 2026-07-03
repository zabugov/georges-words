# App icon

`AppIcon.svg` is the source of truth; `AppIcon.icns` is the packed bundle icon
(all 10 macOS representations, 16–1024 px, PNG-based). The mark is a "G" whose
crossbar is a voice waveform — the heavy right bar doubles as the G's upright
stem. The menu-bar icon is *not* this artwork: it stays an SF Symbols template
image (`mic.fill` / `waveform`) so it adapts to light/dark menu bars.

To regenerate after editing the SVG (any machine with Chromium + Playwright,
or swap in `rsvg-convert`): render the SVG to transparent PNGs at 16, 32, 64,
128, 256, 512, 1024 px, then pack them into the icns container — the format is
just an `icns` header plus `(type, length, png-bytes)` chunks with types
icp4/icp5/ic07–ic14. On a Mac, `iconutil -c icns` over a standard `.iconset`
folder of those PNGs does the same thing.
