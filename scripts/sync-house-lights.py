#!/usr/bin/env python3
"""assets/house/module-lights.json → Resources/House/*-lights.json + house-cutaway.json"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/house/module-lights.json"
OUT = ROOT / "Sources/MijiaBarApp/Resources/House"

MODULE_PREFIX = {
    "living": "living-room",
    "bedroom": "bedroom",
    "study": "study",
    "generic": "generic",
}


def legacy_anchors(layout: dict) -> dict:
    """旧 *-anchors.json 形状，供单房间 tile 与工具兼容。"""
    lamps = []
    tv = ac = window = None
    for L in layout.get("lights", []):
        k = L["kind"]
        if k in ("lamp", "sconce", "entry") and L.get("at"):
            lamps.append(L["at"])
        elif k == "screen" and L.get("rect"):
            tv = L["rect"]
        elif k == "ac" and L.get("rect"):
            ac = L["rect"]
        elif k == "window" and L.get("rect"):
            window = L["rect"]
    out: dict = {"size": layout.get("size", [640, 359])}
    if lamps:
        out["lamps"] = lamps
    if tv:
        out["tv"] = tv
    if ac:
        out["ac"] = ac
    if window:
        out["window"] = window
    if layout.get("label"):
        out["label"] = layout["label"]
    return out


def main() -> None:
    subprocess.run(["python3", str(ROOT / "scripts/gen-house-light-overlays.py")], check=True)
    data = json.loads(SRC.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    cut_size = data.get("cutawaySize", [960, 540])
    cutaway_modules: dict = {}
    for mod, block in data["modules"].items():
        prefix = MODULE_PREFIX[mod]
        tile = dict(block["tile"])
        cut = dict(block["cutaway"])
        cut["size"] = cut_size
        tile.setdefault("size", [640, 359])
        lights_doc = {"module": mod, "tile": tile, "cutaway": cut}
        (OUT / f"{prefix}-lights.json").write_text(json.dumps(lights_doc, indent=2) + "\n", encoding="utf-8")
        (OUT / f"{prefix}-anchors.json").write_text(
            json.dumps(legacy_anchors(tile), indent=2) + "\n", encoding="utf-8"
        )
        cutaway_modules[mod] = {
            "clip": cut["clip"],
            "label": cut.get("label"),
            "lights": cut["lights"],
        }
        print(f"{prefix}-lights.json")
    cutaway = {"size": cut_size, "modules": cutaway_modules}
    (OUT / "house-cutaway.json").write_text(json.dumps(cutaway, indent=2) + "\n", encoding="utf-8")
    # 旧名别名，避免遗漏引用
    (OUT / "house-cutaway-anchors.json").write_text(
        json.dumps(
            {
                "size": cut_size,
                "modules": {
                    m: legacy_anchors({**cutaway_modules[m], "size": cut_size, "lights": cutaway_modules[m]["lights"]})
                    for m in cutaway_modules
                },
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("house-cutaway.json")


if __name__ == "__main__":
    main()
