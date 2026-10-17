# House cutaway: baked lighting

The light is painted **into the base art**, not layered on as glow PNGs. For each phase there are two
pixel-identical images that differ only in lighting:

| File (`Sources/MijiaBarApp/Resources/House/`) | Content |
|---|---|
| `house-cutaway-day-unlit.png` / `house-cutaway-day-lit.png` | Daytime, all devices off / on |
| `house-cutaway-night-unlit.png` / `house-cutaway-night-lit.png` | Night (readable moonlight) / lamps, screens, AC on |

At runtime `HouseCutawaySceneView` shows the **unlit** image, and for each light that is on it reveals the
**lit** image through `room region ∩ light reveal mask`, fading opacity for on/off. Off fixtures (lamp
shades, screens, AC) are covered back with unlit pixels so another light's mask can't switch them on.
Because both layers are the same artwork, light can't drift away from its lamp.

## Source of truth: `house-cutaway.json`

Pixel coordinates on the 960×540 canvas. Per module (`living`, `bedroom`, `study`, `generic`):

- `label`: `[x, y]` room name pill
- `region`: room polygon (floor + walls); light never leaves it
- `lights[]`:
  - `id`, `kind` (`lamp` | `sconce` | `ceiling` | `screen` | `ac`), `role` (`light` + `slot`, `tv`, `ac`)
  - `reveal`: `"room"` or `[cx, cy, rx, ry]` ellipse (full to 0.55 radius, linear fade to 1.0). Same math in
    Swift, in the bake script and in the preview script.
  - bake-only: `source`, `radius`, `pool` `[cx, cy, rx, ry]`, `strength`, `throw`, `vent`, `led`, `style`
  - fixture body: `shade` (lamp shade polygon), `screen` (TL, TR, BR, BL quad), `core` (any polygon)

## Regenerate

```bash
python3 scripts/gen-house-cutaway-art.py      # source JPGs → assets/house/house-cutaway-{day,night}-base.png, then bakes
python3 scripts/gen-house-baked-lighting.py   # bake only: base PNGs + house-cutaway.json → *-unlit.png / *-lit.png
python3 scripts/preview-house-snapshots.py    # docs/house-pilot/house-{day,night}-{on,off}.png (same compositing as Swift)
```

On a Mac, `MijiaBarApp --house-snapshot <dir>` writes `house-{day,night}-{on,off}.png` from the real view.
