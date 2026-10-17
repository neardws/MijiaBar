# House module light anchors

Glow overlays (lamps, screens, AC, windows) are **owned per room module**, not a single global cutaway list.

## Source of truth

Edit **`assets/house/module-lights.json`**, then run:

```bash
python3 scripts/sync-house-lights.py
```

This writes:

| Output | Purpose |
|--------|---------|
| `{module}-lights.json` | Full schema (`tile` + `cutaway`) for Swift |
| `{module}-anchors.json` | Legacy tile-only shape for older tools |
| `house-cutaway.json` | Cutaway canvas size + per-module `clip`, `label`, `lights[]` |
| `house-cutaway-anchors.json` | Generated legacy cutaway map (compat) |

Regenerate cutaway **base PNGs** separately: `python3 scripts/gen-house-cutaway-art.py` (does not move anchors).

## Schema (`module-lights.json`)

- **`cutawaySize`**: `[960, 540]` — normalized coords are fractions of this canvas.
- Per **`modules.<id>`** (`living`, `bedroom`, `study`, `generic`):
  - **`tile`**: single-room module art (`size` typically `[640, 359]`).
  - **`cutaway`**: same logical lights on the connected剖面底图.
  - **`clip`**: normalized rect; Swift **masks** overlays so glows cannot spill into the black void.
  - **`lights[]`** entries:
    - **`id`**: stable name (`floor_lamp`, `tv`, `window`, …)
    - **`kind`**: `lamp` | `sconce` | `screen` | `ac` | `window` | `entry`
    - **`role`**: maps to device slots — `light` (use **`slot`** index), `tv`, `ac`, or `window` (ambient / phase)
    - **`at`**: `{x,y}` for point glows (lamps)
    - **`rect`**: `{x,y,w,h}` top-left normalized box for screens, AC, windows
    - **`overlay`**: static alpha PNG in `Resources/House/glows/` — `image` (or `imageDay` / `imageNight` for windows), optional `w`/`h` for point lights

Regenerate glow PNGs: `python3 scripts/gen-house-light-overlays.py` (also runs from `sync-house-lights.py`). Swift draws overlays with **opacity = device/phase strength**; no procedural `Glow` blobs.

## Verifying alignment

1. Overlay anchors on the night base (debug): adjust JSON, `sync-house-lights.py`, rebuild app or `scripts/preview-house-snapshots.py`.
2. On Mac: `.build/debug/MijiaBarApp --house-snapshot /tmp/house` — compare `house-*-on.png` / `house-*-off.png` to concept art.
3. Check **off** shots: no warm/cool device glows; day windows may still show daylight wash; night windows only when that room has devices on.

## Cutaway clips (verified layout)

| Module | clip `(x,y,w,h)` |
|--------|------------------|
| living | 0.04, 0.33, 0.50, 0.64 |
| bedroom | 0.02, 0.02, 0.56, 0.50 |
| study | 0.48, 0.02, 0.50, 0.50 |
| generic (entry) | 0.50, 0.48, 0.48, 0.50 |

Positions in `module-lights.json` were tuned against `house-cutaway-day-base.png` window glass and dark screen patches on the 960×540 cutaway.
