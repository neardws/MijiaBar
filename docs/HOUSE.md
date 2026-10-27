# House config (`house.json`) — schema 1

The pixel **house cutaway** at the top of the device list is laid out automatically from your Mi Home rooms and
devices. Anything you change — in the House window's edit mode, with `mijiabar house …`, or through MCP — is stored
as a small set of **overrides** in one JSON file. Delete an override (or run `reset`) and that part goes back to automatic.

## Where the file lives and how it syncs

| Mode | Path | Notes |
|---|---|---|
| `icloud` (default when iCloud Drive is on) | `~/Library/Mobile Documents/com~apple~CloudDocs/MijiaBar/house.json` | Synced to every Mac signed in to the same iCloud account |
| `local` | `~/Library/Application Support/MijiaBar/house.json` | This Mac only |
| `folder` | `<folder>/house.json` | Any synced folder you choose (Dropbox, Syncthing, a NAS share…) |

- Switch with `mijiabar house sync icloud|local|<folder>`. The current content is merged into the new location; the old file is left in place.
  The choice is per Mac, stored in `~/Library/Application Support/MijiaBar/house-location.json`.
- `MIJIABAR_HOUSE_FILE=/path/house.json` overrides everything (tests, scripts).
- MijiaBar is a non-sandboxed Developer ID app, so it reads and writes the iCloud Drive folder directly — no iCloud entitlement
  or provisioning profile, and the CLI and agents see exactly the same file.

**Concurrent edits.** Every room/device override carries `updatedAt`. Writers (app, CLI, MCP) always read → modify → write under
`NSFileCoordinator`, so processes on one Mac never overwrite each other. Edits from different Macs are merged **per entry,
last writer wins**; iCloud conflict copies (`house 2.json`, `house (conflicted copy …).json`) and unresolved iCloud versions are
merged on read and removed on the next write. "Reset" writes an empty entry (a tombstone) so the reset also syncs; tombstones are
pruned after 30 days. The app watches the folder and refreshes the house within a second of a change.

## Format

```jsonc
{
  "schema": 1,
  "homes": {
    "<Mi Home home id>": {
      "rooms": {
        // key = Mi Home room id; "name:<room name>" when the id is unknown (older device cache)
        "1234567": { "module": "bedroom", "updatedAt": "2026-10-17T12:00:00.000Z" },   // show 儿童房 as a bedroom
        "7654321": { "module": "none",    "updatedAt": "…" }                           // keep this room out of the house
      },
      "devices": {
        // key = device did
        "93028185":  { "place": "fixture:sconce", "updatedAt": "…" },   // put this light on the wall sconce
        "557081817": { "visible": false,          "updatedAt": "…" },   // don't show in the house (list unaffected)
        "1122334":   { "place": "badge",          "updatedAt": "…" },   // small pixel badge on the floor
        "998877":    { "place": "none",           "updatedAt": "…" }    // only as a chip under the house
      }
    }
  }
}
```

| Field | Values | Meaning |
|---|---|---|
| `rooms.*.module` | `living` `bedroom` `study` `generic` (`kitchen` `bathroom` `balcony` have no art yet) · `none` · `null` | Which room module shows this Mi Home room; `none` = not in the house; `null` = automatic |
| `devices.*.visible` | `true` · `false` · `null` | `false` hides the device in the house only; `true` shows it even if hidden in the list; `null` follows the list |
| `devices.*.place` | `fixture:<id>` · `badge` · `badge:<id>` · `none` · `null` | A fixture slot of the device's room module, any badge spot, a specific badge spot (`b1`, `b2`, …; falls back to any free badge), chip only, or automatic |
| `*.updatedAt` | ISO 8601 date-time | Required; used for merging |

Unknown fields are ignored, so newer versions can add fields without breaking older ones. `mijiabar house schema` prints the JSON Schema.

## Fixed decorations (Phase 3b, milestone 1)

Decorations are appearance-only sprites in fixed module slots, never device commands or freely placed objects.
Module catalogs optionally provide `decor` slots (`id`, `surface`, `sizes`, `at`, optional `wall`, `default`, `holiday`).
Older catalogs without slots render unchanged. Composed houses use the same decorated images in the window and menu bar;
the legacy hand-drawn classic scene does not have module decor slots. Palette styles share cozy-wood's slots.

Optional home fields keep **schema 1** compatible:

- `decorPrefs: {enabled: true, seasonal: true, updatedAt: "…"}`; defaults apply when absent.
- `decor: {"<room key>/<slot id>": {item: "monstera", updatedAt: "…"}}`.
  `item: "none"` keeps a slot empty; `item: null` (or omitted) is a tombstone restoring automatic placement.
- Overrides merge independently by `updatedAt`, including tombstones. Preferences merge as one timestamped entry.
  `decor reset` tombstones every decor override without changing preferences. A full `house reset` also resets preferences.

```sh
mijiabar house decor list --json
mijiabar house decor list --room '<room key>'
mijiabar house decor items --json
mijiabar house decor set '<room key>/<slot id>' monstera
mijiabar house decor set '<room key>/<slot id>' none
mijiabar house decor set '<room key>/<slot id>' auto
mijiabar house decor on
mijiabar house decor seasonal off
mijiabar house decor reset
```

Listing reports preferences, active seasons, overrides, and each module slot's item/source and `hidden: "wall cut"`
when the composer's wall-light rule hides that wall. If module catalogs are unavailable, overrides are still listed;
setting an unknown slot or incompatible item returns error JSON rather than guessing. All mutations return JSON.
The MCP tools `get_house_decor` and `set_house_decor` use the same resolver and validation.
In the edit window, **Style & decor** combines style cards, decoration/holiday toggles, and categorized sprite tiles.
Drag a tile onto a compatible visible slot (surface and size), or click a slot to choose an item, None, or Automatic.
Drag placed decor back to the panel or outside the house to remove it; cut-wall slots are hidden.
Edits save through the same `house.json`/undo path as device edits. Reset to automatic in this tab resets only decor overrides.

The adjacent **Pets** editor tab adds up to three customizable pixel cats (manual
palette or on-device photo analysis), with room restrictions and independent
visibility toggles. Pet edits/removal support ⌘Z and sync through the same store.
See [HOUSE_PETS.md](HOUSE_PETS.md) for rendering, privacy and manual snapshot review.

Automatic holiday items replace defaults only in compatible `holiday` slots with no live override. An invalid live override
falls back to its default but still blocks holiday substitution. Dates use local calendar days (including both window endpoints);
Chinese-calendar holidays ignore leap months and handle lunar-year boundaries. Disabled seasonal placement does not block
explicit user holiday items. Missing PNGs are skipped, with a single stderr diagnostic per filename.

For asset review, run `MijiaBarApp --house-decor-snapshot /tmp/house-decor --date 2026-10-18`.
It uses only demo rooms/in-memory overrides, never the real home or `house.json`. Outputs include decor/no-decor day/night
pairs for three styles, fixed-date holiday scenes, labelled slot overlays with scene JSON, a 3× nearest-neighbour catalog sheet,
and `edit-decor-{cozy-wood,japanese,modern}.png` editor windows with visible slots (`-light` variants included).
The optional date controls regular demos; holiday examples always use their documented 2026/2027 dates.
Each style uses identical demo overrides for day and night; every slot receives a compatible item.
Slots too scarce to show every catalog item are reported on stderr. Slot overlays describe the day example.
Composed PNGs are written directly from the composer's CGImage, at the scene JSON's pixel dimensions, without display/Retina scaling.
The current six-room demo composes at 848×568 pixels; exporting 1696×1136 would be a 2× enlargement, not native 1×.

## Automatic layout

1. **Room → module** by name (Simplified/Traditional Chinese and English): 客厅/living → `living`; 卧/儿童房/客房/bedroom → `bedroom`;
   书房/办公/study/office → `study`; 玄关/门口/走廊/entry/hall → `generic`. Kitchen, bathroom, balcony and other rooms are recognised but have no
   art yet, so they stay out unless you map them to a module.
2. **One Mi Home room per module.** The house currently has one living room, bedroom, study and entry. If two rooms match the same module,
   a room you pinned wins, then the one with more devices that fit a fixture, then the room key. The others are listed as `spotTaken`.
3. **Device → spot**, inside its own Mi Home room only, independent of list order (ties broken by did):
   your `place` → a fixture whose name hints match (床头灯 → `bedside`, 显示器挂灯 → `monitor`, 壁灯 → `sconce`…) → any free fixture that
   accepts the device type → a badge → chip only.
4. Devices hidden in the device list (manually, or automatically because they are offline/stale) are not shown unless `visible: true`.

Fixture slots (`mijiabar house slots --json`):

| Module | Fixtures (accepts) | Badges |
|---|---|---|
| `living` | `floor_lamp` (light), `sconce` (light), `tv` (tv), `ac` (ac, wall unit above the sofa), `curtain`, `fan`, `air_purifier`, `dehumidifier`, `heater`, `humidifier`, `vacuum` | 4 |
| `bedroom` | `bedside` (light), `ac` (ac), `curtain`, `fan`, `air_purifier`, `dehumidifier`, `heater`, `humidifier`, `vacuum` | 3 |
| `study` | `ceiling` (light), `monitor` (light/tv/other, name must mention 显示器/monitor/screen…), `ac` (ac, wall unit beside the window) | 3 |
| `generic` | `entry_light` (light) | 3 |
| `kitchen` / `bathroom` / `balcony` (composed layouts) | `pendant` / `ceiling` / `wall_lamp` (light) | 3 |

### Device classes (fixture vs badge)

Devices are either **(A) fixtures** drawn into the room art with an on/off state, or **(B) badges** (pixel icon on the floor).
`HouseCatalog.deviceClass(category:model:)` decides; `mijiabar house --json` reports it per device as `class`
(`fixture:<kind>`, `fixture:<kind>(badge)` = type A without art yet, or `badge`), and `house slots --json` lists every fixture's `kind`.

| Class | Kinds | Shown as |
|---|---|---|
| A, has art (baked light) | `light`, `screen` (TV / monitor), `ac` (wall unit) | Baked into the module art: lit layer fades in when the device is on (lamp glow, screen picture, AC airflow + green LED) |
| A, has art (live state) | `curtain`, `fridge`, `water-heater`, `washer` | Drawn into the art; the state is drawn live by the app (never baked, so another light's lit layer can't leak it): **curtain** = closed-curtain patch over the window, sliding in from both sides by `current-position` (0–100 %, partial supported; on/off when there is no position), and the room dims a little in daytime while closed; **fridge** = cyan display on the door (dark when off/offline); **water heater** = display window glows orange with flickering flame cells + red LED while heating (`status` option text contains heat/work/busy…), blue + green LED when on but idle, dark when off; **washer** = green panel display + clothes tumbling in the drum (8 fps) while running, dark when off |
| A, has art (live state) | `fan`, `air-purifier`, `dehumidifier`, `heater` | Floor sprites with on/off frames, drawn above furniture and below pets; cyan glow while running (orange for heaters), translucent while offline |
| A, has art (live state) | `humidifier`, `vacuum` | Fixed floor sprites: humidifier tank with cyan mist and LED; round vacuum with dock, cleaning indicator and motion marks when on, docked idle when off; cyan glow while running, translucent while offline |
| B | plugs, switches, sensors, gateways, remotes, locks, cameras, speakers, printers, water purifiers, kitchen appliances | Badge |

A type-A device falls back to a badge when its room module has no free slot of that kind (no such slot, already taken, or the wall it
hangs on is cut away in a composed layout — then the badge sits on the slot's floor `alt` point). Every art set — the classic cutaway
(`house-cutaway.json`), the module catalog and every style pack — must define exactly the fixture set of `HouseCatalog.fixtures`
(`HouseCatalog.fixtureSetProblems`, checked by unit tests).

Live-state fixture slots:

An empty drawable fixture can opt into `"absentVariant": {"patch": "absent-living-tv", "rect": [304, 164, 74, 88]}`.
This nested object is separate from the curtain's top-level `patch` / `rect`. When no device is assigned to the slot,
the app overlays alternate furniture after the baked light layers: the unlit patch is always visible, with the lit patch
revealed by other active room lights. The overlay is non-interactive. An assigned device, even off or offline, keeps the
original fixture; a wall-hidden fixture never draws an alternate patch. Composer translates the module-local rectangle
to canvas coordinates and omits the object for hidden walls; classic coordinates are already absolute.

Cozy modules and classic art include living TV → bookshelf, living/bedroom AC → landscape painting, and study monitor →
small bookshelf. Assets are `modules/<patch>-{day,night}-{unlit,lit}.png`, generated by
`python3 scripts/house_modules/absent_variants.py` (also updates both module catalogs and classic anchors).
Light-wood/walnut use the default patch fallback; independently authored style catalogs remain opt-in.
For mock-only before/after verification, `MijiaBarApp --house-absent-variant-snapshot <dir>` writes
`{classic,composed}-{day,night}-{present,absent}.png`. The pair keeps the same rooms and other light states;
target fixtures are off in the present image and unassigned in the absent image. This command opens snapshot windows.

| Slot id | Kind | Modules (classic cutaway / composed modules) | Notes |
|---|---|---|---|
| `curtain` | `curtain` | living, bedroom, study (classic + modules), kitchen (modules) | Wall fixture (`ne`; kitchen `nw`): hidden + badge at `alt` when its wall is cut. Patch `curtain-<module>-{day,night}-{unlit,lit}.png` (classic: `curtain-classic-<room>-…`); the lit patch is revealed with the same per-light reveal masks as the room art |
| `fridge` | `fridge` | kitchen (modules only) | The fridge already in the kitchen art; `display` quad on the door |
| `water_heater` | `water-heater` | bathroom (modules only) | Wall unit on the bathroom `nw` wall; hidden + badge when that wall is cut |
| `washer` | `washer` | balcony (modules only) | Floor appliance (front-loader), visible in every layout |
| `fan` | `fan` | living, bedroom, study (classic + modules) | Floor sprite, no wall or `alt` |
| `air_purifier` | `air-purifier` | living, bedroom (classic + modules) | Floor sprite, no wall or `alt` |
| `dehumidifier` | `dehumidifier` | living, bedroom (classic + modules), bathroom (modules) | Floor sprite, no wall or `alt` |
| `heater` | `heater` | living, bedroom, study (classic + modules) | Floor sprite, no wall or `alt` |
| `humidifier` | `humidifier` | living, bedroom (classic + modules) | Tank and mist floor sprite, no wall or `alt` |
| `vacuum` | `vacuum` | living, bedroom (classic + modules) | Robot and dock floor sprite, no wall or `alt`; no pathing |

Floor appliance art is generated by `scripts/gen-house-floor-fixtures.py` as `fixture-<kind>-{on,off}.png` in
`Sources/MijiaBarApp/Resources/House/`. Sprites use native 1:1 pixels with nearest-neighbor interpolation.
Each slot's `anchor` is the bottom-center foot point (falling back to the bottom-center of `body`); `body` is the toggle hit area.
They are never baked into lighting, stay visible when walls are cut, and appear only when a device occupies the slot.
All four style catalogs use the same slot IDs and floor coordinates as the base catalog.

Classic has no kitchen / bathroom / balcony rooms, so fridge / water heater / washer only appear in composed layouts.
New device categories: `curtain`, `fridge`, `washer`, `water-heater` (`DeviceCategory.guess`: `curtain`; `fridge` / `refrigerator`;
`washer` / `dryer` / `.wash.` (not `dishwasher` → kitchen, not `hairdryer`); `waterheater` / `water_heater` / `gasheater`).

## CLI

All commands accept `--json`; commands that change something always print JSON.

```bash
mijiabar house show [--home H] [--json]       # rooms, spots, rooms/devices not in the house
mijiabar house slots [--json]                 # module catalog
mijiabar house hide <device>                  # visible = false
mijiabar house unhide <device>                # visible = true
mijiabar house assign <device> <spot>         # floor_lamp | fixture:floor_lamp | badge | badge:b2 | none | auto
mijiabar house set <device> [--visible true|false|auto] [--place <spot>]
mijiabar house room <room> <module>           # living | bedroom | study | generic | none | auto
mijiabar house reset [<device> | --room <room>] [--home H]
mijiabar house sync [icloud | local | <folder>]
mijiabar house schema
```

`<device>` is a did or name (same as `mijiabar get`); `<room>` is a Mi Home room id or name. House commands only change the layout, never a
device, so they work in every Agent mode except **disabled**, without a confirmation dialog. They read the local device cache and do not
touch the keychain.

## MCP tools

`get_house`, `get_house_slots`, `set_house_device` (`device`, `visible`: true/false/"auto", `place`), `set_house_room` (`room`, `module`),
`reset_house` (`home` | `device` | `room`). Results use the same JSON as the CLI.

## Edit mode (HouseWindow)

Open the house window (**Enlarge**) and click **Edit**. The window widens:

- **Drag and drop.**
  - Drag a device row from the right panel onto a dashed spot in the cutaway: round spots are fixtures, square spots are badges. While you drag, spots that can take the device turn green and the rest fade. The spot under the pointer shows "Drop here" / "Swap with …", or a red reason: *Devices can only go in their own Mijia room* or *This spot doesn't take this kind of device*.
  - Drag a placed device to another spot to move it. If the spot is taken, the two swap; the other device goes back to the old spot when it fits there, otherwise it becomes a badge.
  - Drag a placed device back to the panel, or onto an empty part of the cutaway, to take it off: fixture → badge, badge → button row. Dropping outside the window cancels.
  - Dropping a device that is hidden in the house also shows it.
- **Click.** Click a dashed spot to pick the device from a list in the panel, or click "Empty this spot".
- **Panel.** The **eye** button shows or hides a device *in the house only* (`visible`). The menu sets its spot (`automatic / <fixture> / badge / button row only`, plus a per-device reset). A pin marks devices with an override.
- **Rooms** maps Mijia rooms to house modules (`automatic / Living room / Bedroom / Study / Entry / Not in house`).
- **Reset to automatic** removes every override for the current home.
- **Undo / Redo** (toolbar buttons, ⌘Z / ⇧⌘Z) cover every edit above for as long as the house window stays open.

Edits are written to `house.json` right away. Undo writes the previous values back with a fresh `updatedAt`, so it wins the merge on other Macs like any other edit. If the CLI, an agent or another Mac changes an entry that is in the undo history, the history is cleared with a notice, so undo never reverts someone else's change. External edits to other entries keep the history.

Screenshots with demo data: `MijiaBar --house-window-snapshot <dir>` (set `MIJIABAR_LANG=en|zh-Hans` and `MIJIABAR_HOUSE_PHASE=day|night`). It renders the window, edit mode, two mid-drag states (`house-drag-valid`, `house-drag-invalid`, with the drag image drawn by the app because the system drag image can't be captured) and `house-edit-undo`.

## Layout (Phase 2)

`homes.<id>.layout` is an optional array of `{room, module, col, row, level?}`. Max grid 3×2; living footprint is 2×1.

- `null` / absent → classic four-room cutaway (Phase 1 single PNGs).
- Non-classic geometry → modules are stitched by `HouseComposer` (see `docs/HOUSE_MODULES.md`).

```
mijiabar house layout [--json]
mijiabar house layout set <room:module:col:row[@level]> ...
mijiabar house layout level <room> <-1|0|1|auto>
mijiabar house layout flat | stagger [--home H]
mijiabar house layout auto [--home H]
mijiabar house layout classic [--home H]
mijiabar house reset --layout
```

MCP: `get_house_layout`, `set_house_layout` (`mode`: classic / auto / flat / stagger, cells may carry `level`), `set_house_room_level` (`room`, `level`). Undo covers layout changes (same `updatedAt` merge via `layoutUpdatedAt`).

### Split levels (staggered heights)

Composed layouts are drawn with rooms at clearly different floor heights, like the original concept art. Each cell has an optional `level` of -1, 0 or +1. Each step moves the room's floor, walls and furniture up by `HouseGrid.levelStep` (48 px at 1×).

- `level` absent → automatic pattern: back row `+1 0 +1`, front row `0 0 -1` (so the back corners are high and the front-right cell is low). `house layout stagger` clears all explicit levels back to this.
- `house layout flat` sets every cell to 0. The House window → Room layout has a "Split levels" checkbox and ▼/▲ on each card. A "·" after the number means the level is automatic.
- Classic four (layout `null`, or classic geometry with no explicit non-zero level) stays the single hand-drawn cutaway. An explicit non-zero level on classic geometry switches it to the composed renderer.
- **Step faces:** one step (48 px) is taller than a cut wall (40 px), so a raised room's base shows above the cut wall of the lower room in front of it. The composer extends every room's base down to the lowest floor in the house and draws it as a stone plinth (`HouseComposer.plinth`). The plinth has 10 px courses of staggered 26 px blocks with a jittered tone per block, 1 px mortar, a shadow under the wooden slab and a ground line. The left-front (SW) face is lighter than the right-front (SE) face, and the night palette darkens it like the walls. Both lit and unlit renders draw the plinth identically, so light masks never reveal light on step faces. Two steps (96 px) stay below a full wall (104 px).
- Shared and cut walls, end faces, the outline and the silhouette are computed from absolute heights. At the back corner the silhouette follows each wall's own height, so no outline-coloured triangle shows above a lower neighbour.
- **Badges and floor spots:** a badge, floor `alt` spot or floor room label that would sit behind a front neighbour's cut wall (taller when that room is higher) moves along the floor into the room until it clears the wall top. Badges in a room are then kept ≥ 54 px apart. Ceiling and hidden-fixture spots move up to clear the badges, and a floor room label moves sideways (or above the badges) so it covers neither a badge nor a ceiling spot.
- `house layout --json` reports `level` (or `"auto"`), `effective_level` and `level_step_px`. Out-of-range levels are rejected by validation (`levelOutOfRange`).

### Composed doorways and stairs

`HouseDoorwayPlanner.plan(layout:catalog:)` is the shared, deterministic source for the composer and pet world.
For each adjoining pair it intersects both walls' allowed intervals with their actual shared span (including partial
overlaps of the two-cell living room). It prefers one **0.3 floor-grid-unit** opening, falling back to the widest
clear interval of at least **0.2 units**. If neither exists, it still places a **min(0.3, shared-span length)**
opening at the shared midpoint, clamped into the span. Equal-width preferred candidates choose the deepest safe
approach, then the shared span's midpoint, then the smaller coordinate. Input ordering does not matter.
Same-height rooms get a floor-level passage. A 48 px difference gets **three 16 px wooden steps**, extending 0.3 units
into the lower room, shortened to 0.25 or 0.125 units when necessary. Only the lower side needs approach clearance.
A 96 px difference never gets a doorway or stairs and is not reported as an eligible uncovered pair.

Module catalogs may contain `doorwayRanges`, mapping `nw`, `ne`, `sw`, `se` to arrays of `[start,end]` intervals in
local floor units, **not normalized fractions**. NW/SE run along +v (0…fh); NE/SW along +u (0…fw).
For example, `"doorwayRanges":{"nw":[[0.25,0.95]],"ne":[],"sw":[[0.3,1.0]],"se":[[0.25,0.95]]}`
prefers a NW passage and supplies no preferred NE range; an empty range is **not a veto**. An absent wall entry,
or an old catalog with no field, uses `[0.12, wallLength-0.12]`. Only curtain/window/AC/water-heater bodies on the
shared wall exclude preferred positions (body/quad/shade/core or anchor, with a 0.08-unit margin).
Fallback ignores floor furniture, badges and deep approach strips; it nudges to the nearest fixture-clear position
if possible. If the entire span is obstructed by wall fixtures, coverage takes precedence: the midpoint opening
is still placed and `overlapsWallFixture` records that unavoidable overlap. `usedFallback` distinguishes these
placements from preferred intersections. Badge overlays use the composer's passage-clearing helper.
Every eligible adjoining pair gets an opening; `coverage.uncovered` is empty, not a waived test condition.

`python3 scripts/house_modules/doorways.py` updates the module catalog, all style catalogs and available Resources
mirrors without rendering any art. It derives flat-door intervals from only the one walk-cell strip touching each
wall in `scripts/house_pets/blocks.json`. If a wall lacks a 0.3-unit clear interval, the script splits/shrinks
temporary occupancy rectangles around a mid-wall 0.3-unit gap **for doorwayRanges only**. It never writes the
source blocks, pet walk grids or PNG art. Every authored wall consequently has at least one 0.3-unit interval.
Optional `stairRanges` entries `"2"` and `"3"` retain the original occupancy and describe deeper strips;
the planner tries them only on the lower side, then the one-cell strip. Module/style generators emit both fields.
For new art, author/review those furniture bounds (and any style-specific overrides) before regenerating the intervals.
Old external catalogs still render using the fallback, but cannot protect furniture whose bounds were never supplied.

The composer clips the wall face and cap before drawing, revealing the room behind instead of painting a flat-colored
patch. Openings extend down to the lower floor, including the raised plinth face. Dark jamb posts with 1 px outlines,
a wooden threshold, three wooden treads/risers and side stringers use the day/night palette identically in lit and
unlit images. They render after the adjoining room's plinth and wall cap, before unrelated foreground rooms. Visibility
polygons also subtract the openings for light occlusion. Separate `petVisible` polygons share the passage between both
rooms, so a walking cat is not clipped away when its destination changes rooms (old scenes fall back to `visible`). This is baked into the composed
image; the menu-bar embed requires no extra animation or rendering path.

All current styles use these procedural doorways; no new PNGs are required for an eligible wall. Forced passages
may overlap existing furniture artwork; art cleanup is separate from the full-coverage contract. Pet navigation
adds deterministic, shortest grid connectors from each opening to existing walkable floor at runtime, without
changing the authored walkability assets.
**Classic follow-up:** the hand-drawn four-room cutaway and `house-cutaway.json` are unchanged; add matching doors to
new source art later via `scripts/gen-house-cutaway-art.py`, not by patching its generated PNGs or JSON here.
Configured pets already force a composed module scene, including classic four-room layouts,
so eligible doorways appear there now. Small-scale visual acceptance remains a manual check outside the sandbox.

#### Issue #58 acceptance status (2026-10-27)

`HouseSnapshotLayouts` shares the exact fixture and pet geometry with the app and tests; classic geometry references
`HouseLayoutSolver.classicFour`. Coverage is complete via preferred ranges plus midpoint fallback. The strict
`snapshotCoverage` test passes without exemptions. Widths and lower-side approach depths below are floor-grid units;
all stairs span 48 px. The 96 px composed balcony–kitchen difference remains intentionally excluded.

| Layout | Covered / eligible pairs | Door widths | Stairs (lower-side depth) | Fallback count |
| --- | --- | --- | --- | --- |
| composed | 5 / 5 | 0.3 × 3; 0.2125; 0.25 | bedroom–bathroom (0.125), bedroom–living (0.3), bathroom–balcony (0.3), living–kitchen (0.3) | 2 |
| composed2 | 6 / 6 | 0.3 × 6 | kitchen–living (0.3), kitchen–bathroom (0.125), living–balcony (0.125), bedroom–balcony (0.125) | 3 |
| pets | 7 / 7 | 0.3 × 5; 0.2125; 0.275 | none; all rooms explicitly level 0 | 2 |
| classic via composer | 4 / 4 | 0.3 × 3; 0.2125 | bedroom–study (0.3), bedroom–living (0.3), living–generic (0.3) | 1 |

Fallback pairs (all 0.3 wide, no unavoidable wall-fixture overlaps in these fixtures):
- **composed:** bathroom–living, living–kitchen.
- **composed2:** kitchen–living, living–bedroom, bathroom–bedroom.
- **pets:** study–living, living–kitchen.
- **classic via composer:** study–living.

Narrow preferred widths are bedroom–living (0.2125 in composed/pets/classic), bathroom–balcony (0.25 in composed),
and bathroom–kitchen (0.275 in pets). All other openings are 0.3 wide.
Regression checks cover every placed doorway's walking access, the pets bedroom–study no-jump route,
fixture-only nudging/forced overlap, and day/night lit/unlit compositing. No app or GUI/snapshot command was run.
Actual 1× screenshot inspection remains unchecked. Classic hand-drawn cutaway art/JSON remains a follow-up, unchanged.

Round 3 validation: native SwiftPM build succeeded; 248 of 249 tests passed, with only the known sandbox
`storeMergesConflictCopies` Cocoa 512 write failure. All 15 doorway tests passed. Sequential and concurrent schedule
fingerprints agree after updating goldens for the changed passage graph; calendar/reaction fingerprint is unchanged.
Both performance budgets remain unchanged and pass: 1000 cold pet poses took 73.61 ms (300 ms budget), and the
slowest measured composer fixture took 12.47 ms (30 ms budget). These are test results, not GUI screenshot acceptance.
