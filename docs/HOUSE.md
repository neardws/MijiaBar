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
| `living` | `floor_lamp` (light), `sconce` (light), `tv` (tv) | 4 |
| `bedroom` | `bedside` (light), `ac` (ac) | 3 |
| `study` | `ceiling` (light), `monitor` (light/tv/other, name must mention 显示器/monitor/screen…) | 3 |
| `generic` | `entry_light` (light) | 3 |

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
