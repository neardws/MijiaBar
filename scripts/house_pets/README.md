# House pets art pipeline (Phase 3c)

Python 3 + numpy + Pillow + OpenCV (same as `scripts/house_modules`). Everything is regenerated from code; the app never runs these.

For the bundled sheets, use `python3 scripts/house_pets/export.py OUT 6` from the
repository root (6× supersampling matches the existing art). Use a fresh output
directory after changing geometry or the render bounds; otherwise `frames.pkl`
reuses old renders. Preserve the bundled JSON's `lighting` block when copying the
generated rig and six pattern PNGs, then run `python3 scripts/house_pets/golden.py OUT`
with that lighting block restored and copy `cat-short-golden.json` into `Tests/Fixtures/pets/`.

For the single dog template, run `python3 scripts/house_pets/export.py OUT 6 --dog`
in a fresh output directory. This uses `dog.py` geometry and dog-specific region
painting while leaving the default cat path unchanged. The cache records rig/SS
and render bounds in `render.json`; changing these requires a fresh directory. Geometry changes
also require a fresh directory (or `--rerender`). Copy the existing cat JSON's
`lighting` block into generated `dog-short.json`, then copy that JSON and six
`dog-short-*.png` sheets to `Sources/MijiaBarApp/Resources/House/pets/`. Run
`python3 scripts/house_pets/golden.py OUT dog-short` after restoring lighting and
copy `dog-short-golden.json` to `Tests/Fixtures/pets/`. Do not regenerate cat assets.
Dog has 68 frames, eight actions and the same six IDs; the coat mapping and
deferred breed/ear variants are documented in `docs/HOUSE_PETS.md`.
The dog export rejects clipped body samples and nonfinite hit data before encoding;
its wider render bounds accommodate the muzzle in the NE curled sleep pose.

Sleep geometry stays curled with closed eyes; its opaque bounds (alpha 255,
excluding ground shadows) must reach at least 85% of the largest sit-frame width
and height for the same facing. `sleepingOpaqueBoundsMatchSittingVisualWeight`
checks every sleep frame in both facings and all six patterns. Runtime scale
remains integer nearest-neighbour; the expanded render bounds accommodate the
wider curl without clipping it.

- `sdfcat.py` – SDF primitives + ray-marcher in the module iso camera (`house_modules/appliance_render.py`), at cell resolution (1 cell = 2 module px).
- `cat.py` – the short-hair cat rig: pose builders (`stand`, `walk`, `sit`, `groom`, `lookup`, `sleep`, `stretch`, `jump`) and `ACTIONS` (fps, loop, frames).
- `dog.py` – compact erect-ear dog geometry and brindle/tricolor/mask painting; shares pose timing and SDF primitives, not cat sheets.
- `patterns.py` – region codes per coat pattern (solid, tabby, tabbyWhite, bicolor, calico, colorpoint) from part-local coordinates, so stripes/patches stick to the body in every frame.
- `frames.py`, `paint.py` – render → cells (coverage, majority region, shade, spec), eye/nose stamps, outline ring + depth lines, tone curve, encoding.
- `export.py OUT [ss]` – renders all frames (SE + NE; SW/NW are mirrored at runtime) and writes `cat-short.json` + `cat-short-<pattern>.png`. Then copy into `Sources/MijiaBarApp/Resources/House/pets/` and add the `lighting` block (see docs/HOUSE_PETS.md).
- `golden.py OUT` – reference recolour (`recolor_px`, the spec the Swift code matches) + golden vectors for tests.
- `contact.py`, `place.py`, `view.py` – contact sheets / previews.
- `blocks.json` + `spots_src.json` → `mkspots.py` → `pet-spots.json` (walk grids, 8 cells per floor grid unit; blocked rects are `[col0,row0,col1,row1)`); `gridsheet.py STYLE MODULE out.png x` draws the labelled grid over a module for authoring.
