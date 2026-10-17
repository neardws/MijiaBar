# House modules (Phase 2)

Isometric grid modules that stitch into a house. Spec: `docs/HOUSE_EDITOR_DESIGN.md` §4.

## Grid

| Constant | Value |
|---|---|
| Cell width `W` | 240 |
| Floor diamond height `FLOOR_H` | 120 |
| Wall height `WALL_H` | 150 |
| Floor thickness | 12 |
| Pixel block `PX` | 2 |

`tip(col, row)` = back tip of a cell. Painter order: ascending `(col+row, col)`.

## Module assets

`assets/house/modules/` (copied into the app as `Resources/House/modules/`):

- `catalog.json` — footprints, tips, regions, lights, badges, variant filenames
- `module-<id>-{day,night}-{unlit,lit}.png` — transparent background, tip at `tip`

**Classic rooms** (`living`, `bedroom`, `study`, `generic`): cut out of the Phase 1 cutaway with the room polygon (`scripts/house_modules/extract_classic.py`), so they keep the HD-2D look. Living is footprint 2×1; others 1×1.

**New rooms** (`kitchen`, `bathroom`, `balcony`): painted placeholders that reuse classic wall/floor colours (`scripts/house_modules/paint.py`). Full HD-2D redraw is the next art PR.

## Compose

- Python: `python3 -c 'from house_modules.compose import main; main()'` → `assets/house/spike/`
- Swift: `HouseComposer.compose` in MijiaCore (CoreGraphics). Loads catalog + CGImages, paints back-to-front into unlit and lit canvases, remaps fixture/badge coords into canvas space.

### Spike timing (Apple Silicon, debug `swift test`)

| Layout | Compose ms |
|---|---|
| living + bedroom | ~1.6 |
| bedroom + study + living | ~2.0 |
| classic 4 | ~2.6 |

Target ≤ 30 ms. Median ≈ **2 ms**.

## Classic-four preset

When the user’s layout is the classic 2×2 (bedroom+study back, living+entry front) **or** `layout` is absent, the app keeps using the single Phase 1 cutaway PNGs (pixel-identical). Composed modules are only used for custom layouts. Wiring that switch is a follow-up PR.

## Regenerating

```bash
python3 -c "import sys; sys.path.insert(0,'scripts'); from house_modules.extract_classic import extract_all; extract_all()"
# then paint kitchen/bathroom/balcony and merge, or:
python3 -c "import sys; sys.path.insert(0,'scripts'); from house_modules.compose import main; main()"
```
