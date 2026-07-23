# App icon

`George.png` (a portrait of George himself, with a speech bubble) is the
source of truth; `AppIcon.icns` is the packed bundle icon (all 10 macOS
representations, 16–1024 px, PNG-based). The earlier G-monogram SVG was
retired when this artwork arrived (it's in git history if ever wanted).

The source PNG has opaque white padding around its squircle, so packing
isn't a straight resize: the pipeline auto-crops to the art's bounding
box, scales it into the standard macOS icon grid (824×824 centered on a
transparent 1024 canvas), and clips to the grid squircle (corner radius
185.4) — that supplies the transparency and the margin that makes it sit
at the same visual size as neighboring Dock icons.

To regenerate: any Chromium+Playwright (canvas `roundRect` clip +
stepped-halving downscale for the small sizes), then pack the PNGs into
an icns container — `icns` header plus `(type, length, png-bytes)`
chunks, types icp4/icp5/ic07–ic14. On a Mac, `iconutil -c icns` over a
standard `.iconset` folder does the same, but crop/mask the source
first. The menu-bar icon reuses this same artwork while idle (an SF
Symbols mic looked like the system's own input indicator — owner
request, 2026-07-22); recording/processing/error still use SF Symbol
glyphs for state feedback.
