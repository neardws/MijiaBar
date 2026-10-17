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
| `devices.*.place` | `fixture:<id>` · `badge` · `none` · `null` | A fixture slot of the device's room module, a badge, chip only, or automatic |
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
mijiabar house assign <device> <spot>         # floor_lamp | fixture:floor_lamp | badge | none | auto
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

- Dashed frames mark every fixture spot (round) and badge spot (square) in the cutaway. Click one to choose which device in that room goes there, or click "Empty this spot".
- The right panel lists the devices of each house room. The **eye** button shows or hides a device *in the house only* (`visible`), and the menu sets its spot (`automatic / <fixture> / badge / button row only`, plus a per-device reset). A pin marks devices with an override.
- **Rooms** maps Mijia rooms to house modules (`automatic / Living room / Bedroom / Study / Entry / Not in house`).
- **Reset to automatic** removes every override for the current home.

Edits are written to `house.json` right away. There is no draft or undo. Changes from the CLI, agents or other Macs show up live through the file watcher.

Screenshots with demo data: `MijiaBar --house-window-snapshot <dir>` (set `MIJIABAR_LANG=en|zh-Hans` and `MIJIABAR_HOUSE_PHASE=day|night`).
