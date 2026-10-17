# House modules (Phase 2)

Custom layouts are stitched at runtime from per-room **modules**. The classic four-room preset keeps
using the single hand-tuned cutaway (`house-cutaway-*`), so it is pixel-identical to Phase 1.

## Grid geometry (v2)

| constant | value | meaning |
|---|---|---|
| `W` | 320 | cell width (left vertex → right vertex) |
| `FH` | 132 | cell floor height (back vertex → front vertex) |
| `WALL_H` | 104 | outer back wall height |
| `CUT_H` | 40 | shared (interior) wall height — wainscot height, with a wood cap |
| `SLAB` | 14 | floor slab thickness on open front edges |
| `PX` | 2 | art pixel size (same as the classic cutaway) |

`tip(col,row) = ((col-row)·W/2, (col+row)·FH/2)`; `row` grows toward the front-left, `col` toward the front-right.
The grid is at most 3 cols × 2 rows; living spans 2 cols.

Every module contains only **its own floor + its two back walls (NW, NE) + front slab**. Consequences:

* **One owner per shared wall.** The wall between two neighbours is always the *front/right* cell's back wall;
  the back cell never draws a front wall (the cutaway is open toward the camera).
* **Shared walls are cut.** A back-wall segment that has a neighbour behind it is drawn from the module's
  `-cut` variant (walls at `CUT_H`); outer back walls use the full variant. Living's NE wall is planned per cell.
* **Painter's order** is `(row, col)` ascending = back to front.
* The composer draws the wall **caps**, **exposed end faces** (where a wall is taller than the one continuing it),
  **pilasters** over module seams, and an **outer outline**. The canvas is transparent.
* Scene JSON gives each module its `region` and a `visible` multi-polygon (region minus everything drawn later),
  so light masks never bleed through a front room's wall.

## Module art

`assets/house/modules/` (synced into `Resources/House/modules/` by `scripts/sync-house-modules.sh`):

```
module-<id>-{day,night}-{unlit,lit}.png       full walls
module-<id>-{day,night}-{unlit,lit}-cut.png   both back walls cut to CUT_H (pixel-aligned with the full one)
catalog.json                                  footprint, size, tip, region, label, badges, lights (+ wall), variants
```

Pipeline (`scripts/house_modules/build.py`), same treatment as `gen-house-cutaway-art.py` + `gen-house-baked-lighting.py`:

1. **Source**: one single-room cutaway per module from the image generator, with the classic cutaway as style
   reference: `<id>-day-full.jpg` plus an aligned edit `<id>-day-cut.jpg` (back walls cut to wainscot height,
   wall-mounted items removed). Optional `<id>-corners.json` overrides auto-detected corners.
2. **Fit**: auto-detect the room silhouette corners, then warp floor / NW wall / NE wall / slabs with one
   homography each onto the canonical geometry.
3. **Pixelize**: half-resolution LANCZOS + brightness/contrast + NEAREST ×2 + sharpen (classic parameters).
4. **Night**: 3D LUT learned from the aligned classic `day-base → night-base` pair (pixel-aligned by construction),
   window glass replaced with night sky.
5. **Bake**: the classic light functions (`light_field`, `band`, `paint_shade`, `paint_screen`, `paint_ac`).
   Wall-mounted lights (`"wall": "nw"|"ne"`) are skipped in the `-cut` bake; the composer marks them `hidden`
   when their wall is cut.

Fixture ids: living `floor_lamp`/`sconce`/`tv`, bedroom `bedside`/`ac`, study `ceiling`/`monitor`,
generic `entry_light` (Phase 1 ids), kitchen `pendant`, bathroom `ceiling`, balcony `wall_lamp`.

Without generator sources, `build.py` falls back to **geometry shells** (empty rooms) and marks
`catalog.style = "shell-standin"`. Those are for geometry review only, not final art.

## Timing

`swift test --filter HouseComposerTests` composes 2/3/4/5/6-room layouts; debug build ≈ 1–5 ms per layout
(target < 30 ms). `HOUSE_COMPOSE_OUT=/dir swift test --filter writesSpikeImages` writes every layout × day/night × unlit/lit.
