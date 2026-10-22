# House pets art pipeline (Phase 3c)

Python 3 + numpy + Pillow + OpenCV (same as `scripts/house_modules`). Everything is regenerated from code; the app never runs these.

For the bundled sheets, use `python3 scripts/house_pets/export.py OUT 6` from the
repository root (6× supersampling matches the existing art). Use a fresh output
directory after changing geometry or the render bounds; otherwise `frames.pkl`
reuses old renders. Preserve the bundled JSON's `lighting` block when copying the
generated rig and six pattern PNGs, then run `python3 scripts/house_pets/golden.py OUT`
with that lighting block restored and copy `cat-short-golden.json` into `Tests/Fixtures/pets/`.

Sleep geometry stays curled with closed eyes; its opaque bounds (alpha 255,
excluding ground shadows) must reach at least 85% of the largest sit-frame width
and height for the same facing. `sleepingOpaqueBoundsMatchSittingVisualWeight`
checks every sleep frame in both facings and all six patterns. Runtime scale
remains integer nearest-neighbour; the expanded render bounds accommodate the
wider curl without clipping it.

- `sdfcat.py` – SDF primitives + ray-marcher in the module iso camera (`house_modules/appliance_render.py`), at cell resolution (1 cell = 2 module px).
- `cat.py` – the short-hair cat rig: pose builders (`stand`, `walk`, `sit`, `groom`, `lookup`, `sleep`, `stretch`, `jump`) and `ACTIONS` (fps, loop, frames).
- `patterns.py` – region codes per coat pattern (solid, tabby, tabbyWhite, bicolor, calico, colorpoint) from part-local coordinates, so stripes/patches stick to the body in every frame.
- `frames.py`, `paint.py` – render → cells (coverage, majority region, shade, spec), eye/nose stamps, outline ring + depth lines, tone curve, encoding.
- `export.py OUT [ss]` – renders all frames (SE + NE; SW/NW are mirrored at runtime) and writes `cat-short.json` + `cat-short-<pattern>.png`. Then copy into `Sources/MijiaBarApp/Resources/House/pets/` and add the `lighting` block (see docs/HOUSE_PETS.md).
- `golden.py OUT` – reference recolour (`recolor_px`, the spec the Swift code matches) + golden vectors for tests.
- `contact.py`, `place.py`, `view.py` – contact sheets / previews.
- `blocks.json` + `spots_src.json` → `mkspots.py` → `pet-spots.json` (walk grids, 8 cells per floor grid unit; blocked rects are `[col0,row0,col1,row1)`); `gridsheet.py STYLE MODULE out.png x` draws the labelled grid over a module for authoring.
