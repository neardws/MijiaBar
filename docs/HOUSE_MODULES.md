# House modules (Phase 2)

Custom layouts are stitched at runtime from per-room **modules**. For builtin/palette styles, the classic four-room preset keeps
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
  **pilasters** at module corners, and an **outer outline**. The canvas is transparent. Caps / end faces / pilasters
  sit *behind* the wall plane, so they are drawn **before** the module image: tall furniture standing against a
  wall (bookshelf, floor lamp, fridge) occludes them instead of being crossed by a cap bar.
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

1. **Source** (`assets/house/modules/src/`, committed so the build is reproducible): one single-room cutaway per
   module from the image generator (canonical-geometry template + the classic cutaway as style reference):
   `<id>-day-full.jpg` plus a generator *edit* of that image, `<id>-day-cut.jpg` (both back walls cut to wainscot
   height, wall-mounted items removed, floor furniture unchanged). Optional `<id>-corners.json` overrides corners.
   * **Living (2×1)**: the generator will not paint a 2:1 room (it always comes out ≈1.5:1; stretching it shears
     the furniture). `extend.py pair living livingR` stitches two sources instead — `living` (1×1: sofa, floor lamp,
     window, sconce) for the left cell and `livingR` (a same-style long room, ≈1.45:1, with only a free-standing TV
     stand and a plant) for the right cell. Because `livingR` is longer than one cell, its right 1.16 cells are taken
     at 1:1 — nothing is stretched. The right cell is colour-matched per zone (wallpaper band, wainscot band, floor:
     per-channel median gains from a strip on each side of the seam, so the wallpaper's warm/cool cast matches, not
     just its brightness); the front slab, NE top trim and wainscot rail are re-drawn from the left cell's profile →
     `$HOUSE_WORK/living-day-{full,cut}-stitched.png`.
   * **Retouch** (`retouch.py`, offline, needs torch + the LaMa `big-lama.pt` TorchScript model; the build itself
     doesn't): living — LaMa repaints the seam band so the wallpaper pattern runs through, and the TV stand is moved
     off the NE wall to the middle of the right cell (0.35 cell forward; LaMa fills the old spot, a contact shadow is
     added). In composed layouts the NE wall is a cut wall, so a TV against it looked like it stood on the shared
     wall. Study — the 2 m bookshelf on the NW wall (usually a cut wall shared with the bedroom) poked far above
     the cut and read as furniture in the next room; it is shortened to a one-shelf low bookcase (≈37 px, below
     `CUT_H`). Kitchen: the fridge stands against the NW wall too. With split levels the room behind is often higher,
     so a full-height fridge looked like it stood in the next room. It is shortened the same way (`shorten()`: a
     z-band of the lower door is removed and the freezer section drops down) to ≈34 px. In `-cut` variants the wall
     top inside a retouched hole follows the generator's actual wall top next to it; for the kitchen it blends
     linearly from the left to the right side. Output: `src/{living,study,kitchen}-day-{full,cut}-canon.png`, used
     by `build.py` directly.
   * **Wall AC** (`add_ac.py modules`, after `retouch.py`): the bedroom's wall unit (warped to the 2x canonical frame
     the same way `build.py` does) is pasted onto living's NW wall above the sofa (same spot — all modules share the
     tip) and, mirrored about the tip column (`P(0,v,z) ↔ P(u=v,0,z)`) and shortened, onto study's NE wall right of
     the window; tone matched to the target wallpaper. Slots: `ac_nw` / `ac_ne` in `fixtures.py`.
     `add_ac.py classic` did the same for the classic cutaway (living: replaces the large painting, LaMa fills the
     rest; study: NE wall left of the window) and patched its unlit/lit incrementally.
   * The kitchen pendant was edited out of the source: a pendant hanging in mid-air would be sliced in half by a
     cut-wall strip, so the kitchen light is an invisible ceiling light with its pool on the table.
2. **Fit**: auto-detect the room silhouette (outer edges, wall-top lines fitted by least squares so hanging items
   don't move the back corner, slab from the strongest brightness step), then warp floor / NW wall / NE wall /
   slabs with one homography each onto the canonical geometry; the wall map blends into the floor map over 36 px
   above the floor's back edge so furniture standing against a wall doesn't kink. Both maps are column-preserving
   in that band (the wall map takes its horizontal position from the floor map along the back edge, the floor map
   is extruded straight up), so camera differences between generated rooms no longer lean doors, shelves, TVs or
   wainscot planks. The `-cut` edit is ECC-aligned to
   the full image; its low wall height is measured and the wall mapping rescaled so the wall top lands exactly on
   `CUT_H`. Cut alpha removes only what was wall in the full image (bright wallpaper there, dark in the edit), so
   dark furniture sides survive; near-black 1–3 px fringes left by the generator along the cut edge are peeled off.
3. **Pixelize**: half-resolution LANCZOS + brightness/contrast + NEAREST ×2 + sharpen (classic parameters).
4. **Night**: 3D LUT learned from the aligned classic `day-base → night-base` pair (pixel-aligned by construction),
   window glass replaced with night sky. The LUT is frozen in `assets/house/modules/night-lut.npz` (learned before the
   classic bases got the AC units); delete it to re-learn.
   * **Curtain patches** (`curtains.py build`): one "fully closed" patch per curtained window (classic living / bedroom /
     study; modules living / bedroom / study / kitchen) × day/night × unlit/lit. Fabric = 4-level palette k-means'd from the
     existing side curtains + vertical folds, header and wavy hem; module night = the frozen day→night LUT, lit = the lit
     art's own per-level side-curtain colours (so it never over-exposes). Every variant is then scaled so its mean luminance
     matches the original side curtains in the same image (the fold pattern alone over-weights the bright level and read as
     backlit). Occlusion polygons keep the study monitor / plant in
     front. The app slides the two halves in from the window edges by curtain position (2px-aligned x ranges).
     `curtains.py geometry <name>` gives `patch / rect / mid / quad` for `fixtures.py` without reading images.
   * **Water heater + washer** (`add_appliances.py canon && LAMA=big-lama.pt add_appliances.py paint`): small 3D
     SDF models (`appliance_models.py`) rendered with the module art's own orthographic camera (`appliance_render.py`:
     rounded edges, AO, soft shadow onto wall / floor, Blinn highlights, environment reflection, warm room tint, dark
     outline ring), supersampled into the 2x canon so they go through the same pixelize as the painted furniture —
     a horizontal enamel storage heater (straps, chrome-bezel round gauge, knob, pipes + valves) on the bathroom NW wall,
     a front-loader (chrome door ring + glass, gasket, drawer, dial, display recess) on the balcony after LaMa-removing
     the plants there. Overlay anchors (`display`, `led`, `door` with `r`/`ry`) come from the same models. Rerun `build.py` after.
   * Live-state fixtures (`curtain`, `fridge`, `water-heater`, `washer`) are listed in `catalog.json` lights but are
     **never baked**: `pipeline.bake_module` only bakes roles `light` / `tv` / `ac`, and the app only reveals lit art for those.
5. **Bake**: the classic light functions (`light_field`, `band`, `paint_shade`, `paint_screen`); AC airflow (dashed
   pixel streams + particles + green LED, `acsprite.paint_airflow`) drifts away from the wall the unit hangs on. An AC's
   `reveal` is the airflow area right under the vent, so the lit airflow actually shows when the AC is on.
   Wall-mounted lights (`"wall": "nw"|"ne"`, with an `anchor` point) are skipped in the `-cut` bake.

**Hidden wall fixtures.** The composer finds the wall segment under a fixture's `anchor`; if that segment is cut,
the fixture's body went with the wall: the scene marks it `"hidden": true` and drops its `shade`/`screen`/`core`
polygons (nothing paints a body that isn't there; the tap target falls back to the reveal ellipse). Lamps keep
their light — the floor pool comes from the full-wall lit image, which is what's under the strip. ACs have no
pool, so they carry an `alt` floor point where the app shows an AC badge instead (curtains / water heater / wall lamp
too). Each `alt` is hand-picked clear floor near the fixture's wall — not on furniture, ≥38px from the module's
badge spots and from other alts (`moduleAltSpotsClearOfBadges`). The composer keeps it (lifted with the floor) and only
nudges it ≤12px if a composed badge lands within 30px; ceiling-light edit spots still dodge badges upward.
An optional `alt2` is used when `floorPointLift` would push `alt` inward onto furniture (bedroom curtain, study AC).
Modules also carry a `floorLabel` used when both back walls are cut, so the room name sits on clear floor, not the bed. Only the segment that
actually holds the fixture matters (living's sconce is on NE segment 0; a room behind segment 1 doesn't hide it).

Fixture ids: living `floor_lamp`/`sconce`/`tv`/`ac`, bedroom `bedside`/`ac`, study `ceiling`/`monitor`/`ac`,
generic `entry_light` (Phase 1 ids), kitchen `pendant`, bathroom `ceiling`, balcony `wall_lamp`.

All seven modules now have generated art (`catalog.style = "generated"`). Without sources, `build.py` falls
back to **geometry shells** (empty rooms) marked `shell-standin` — geometry review only, not final art.

Regenerate: `python3 scripts/house_modules/extend.py pair living livingR && LAMA=big-lama.pt python3
scripts/house_modules/retouch.py living && … retouch.py study && … retouch.py kitchen && python3 scripts/house_modules/add_ac.py modules && python3 scripts/house_modules/add_appliances.py canon && LAMA=big-lama.pt python3 scripts/house_modules/add_appliances.py paint && python3 scripts/house_modules/build.py
assets/house/modules --raw assets/house/modules/src --classic <dir with house-cutaway-{day,night}-base.png> &&
scripts/sync-house-modules.sh && python3 scripts/house_modules/curtains.py build`. Screenshots of every live-state fixture:
`MijiaBarApp --house-fixtures-snapshot <dir>` (classic curtains open/half/closed, two composed layouts × day/night × on/off, `crops.json`). `fitcheck.py <id> <fw>` writes a corner overlay + full/cut fit preview to /tmp.

## Timing

`swift test --filter HouseComposerTests` composes 2/3/4/5/6-room layouts; debug build ≈ 1–5 ms per layout
(target < 30 ms). `HOUSE_COMPOSE_OUT=/dir swift test --filter writesSpikeImages` writes every layout × day/night × unlit/lit.
## Full-redraw style packs

Full-redraw (`kind: art`) packs live in `assets/house/styles/<id>/`:

```
manifest.json
src/<prefix>-<module>-{full,cut,cutsrc}.jpg
src/windows.json
src/offsets.json
modules/catalog.json
modules/module-<module>-{day,night}-{unlit,lit}[-cut].png
modules/curtain-<module>-{day,night}-{unlit,lit}.png
```

Each art pack owns its catalog, light/fixture anchors and curtain geometry; fixture
IDs remain compatible with the default catalog. Palette packs still share the
cozy-wood catalog. An art catalog lookup is confined to its own pack; a missing
catalog or module PNG is logged before falling back to cozy-wood. Art packs have
no `classic/` directory: classic four-room geometry is rendered through the module
composer in previews, the full house and edit mode, never the default cutaway.
Cards without a living-room preview are disabled as “Art in progress”.

Build from the repository root (requires the existing pipeline's Pillow, NumPy,
OpenCV and SciPy environment; no Swift dependencies):

```bash
python3 scripts/house_modules/build_style.py japanese --prefix jp
python3 scripts/house_modules/build_style.py modern living bedroom
python3 scripts/house_modules/build_style.py sheet japanese /tmp/japanese-anchors.png
```

The default prefix is the style ID; Japanese sources use `jp`. Each module needs a
full JPG and either cut or cutsrc JPG. `cutsrc` is a plain-wall source used to
synthesize a low-wall image. Intermediate normalized art/corners go into `raw/`;
`windows.json` sets the window bounds/exclusions, and `offsets.json` shifts fixture
anchors before baking. Subset builds preserve other catalog entries and images.
The sheet shows day/unlit anchors, cut walls and night/lit art side by side.

`MijiaBarApp --house-style-snapshot <dir>` writes deterministic demo-only classic
and composed day/night × unlit/lit images, edit-slot overlays, and closed-curtain
night/lit images for installed cozy-wood/japanese/modern packs. It passes phases
directly, without changing the clock or process environment. The six-room snapshot
showcase extends to a third row because living occupies two cells; this does not
change the editor's 3×2 limit. Snapshot rendering is opt-in, not part of a build.
