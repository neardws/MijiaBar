"""Prefer furniture-safe intervals, carving range-only gaps without changing art or pet blocks."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def clear_intervals(rectangles, wall, width, height, depth):
    length = height if wall in ("nw", "se") else width
    blocked = []
    for left, top, right, bottom in rectangles:
        touches = {"nw": left < depth, "ne": top < depth,
                   "se": right > width - depth, "sw": bottom > height - depth}[wall]
        if touches:
            blocked.append((top, bottom) if wall in ("nw", "se") else (left, right))
    intervals, cursor = [], 0
    for lower, upper in sorted(blocked):
        lower, upper = max(0, lower), min(length, upper)
        if lower > cursor:
            intervals.append([cursor / 8, lower / 8])
        cursor = max(cursor, upper)
    if cursor < length:
        intervals.append([cursor / 8, length / 8])
    return intervals


def carve_gap(rectangles, wall, lower, upper):
    carved = []
    axis = 1 if wall in ("nw", "se") else 0
    for rectangle in rectangles:
        if rectangle[axis + 2] <= lower or rectangle[axis] >= upper:
            carved.append(rectangle)
            continue
        if rectangle[axis] < lower:
            before = list(rectangle)
            before[axis + 2] = lower
            carved.append(before)
        if rectangle[axis + 2] > upper:
            after = list(rectangle)
            after[axis] = upper
            carved.append(after)
    return carved


def doorway_ranges(module, footprint, style="cozy", depth=1):
    blocks = json.loads((ROOT / "scripts/house_pets/blocks.json").read_text())
    rectangles = blocks.get(style, {}).get(module, blocks["cozy"].get(module, []))
    width, height = (dimension * 8 for dimension in footprint)
    result = {}
    for wall, length in (("nw", height), ("ne", width), ("se", height), ("sw", width)):
        intervals = clear_intervals(rectangles, wall, width, height, depth)
        if depth == 1 and not any(upper - lower >= 0.3 - 1e-9 for lower, upper in intervals):
            gap_start = (length - 2.4) / 2
            range_rectangles = carve_gap(rectangles, wall, gap_start, gap_start + 2.4)
            intervals = clear_intervals(range_rectangles, wall, width, height, depth)
        result[wall] = intervals
    return result


def stair_ranges(module, footprint, style="cozy"):
    return {str(depth): doorway_ranges(module, footprint, style, depth) for depth in (2, 3)}


def main():
    paths = [ROOT / "assets/house/modules/catalog.json", ROOT / "Sources/MijiaBarApp/Resources/House/modules/catalog.json"]
    paths += sorted((ROOT / "assets/house/styles").glob("*/modules/catalog.json"))
    paths += sorted((ROOT / "Sources/MijiaBarApp/Resources/House/styles").glob("*/modules/catalog.json"))
    for path in paths:
        catalog = json.loads(path.read_text())
        style = path.parent.parent.name if "styles" in path.parts else "cozy"
        for module, art in catalog["modules"].items():
            art["doorwayRanges"] = doorway_ranges(module, art["footprint"], style)
            art["stairRanges"] = stair_ranges(module, art["footprint"], style)
        path.write_text(json.dumps(catalog, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
