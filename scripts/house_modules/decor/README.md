# Decor sprites (Phase 3b)

SDF models rendered with the same orthographic camera as the module art (`../appliance_render.py`), then pixelized to the PX=2 grid.
Night sprites use the module night LUT (`assets/house/modules/night-lut.npz`); emissive materials (lantern, rabbit lamp, pumpkin, tree bulbs) keep their day colour at night.
Wall items are rendered on the NW wall; the NE file is a horizontal mirror (the 福 character is re-rendered with a pre-flipped texture so it reads correctly).

    cd scripts/house_modules/decor
    python3 build.py OUT            # all items → OUT/decor-*.png + OUT/anchors.json
    python3 sheet.py OUT sheet.png  # contact sheet

Copy `OUT/decor-*.png` to `Sources/MijiaBarApp/Resources/House/decor/` and the anchors into `decor-catalog.json`.
Slot positions per module / style live in the module catalogs (`"decor"` arrays).
