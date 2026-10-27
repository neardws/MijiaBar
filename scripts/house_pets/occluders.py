"""Generate furniture footprints and tip-relative masks without imaging dependencies."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIECES = {
    "living": [(0, "sofa", 16, ["sofa"]), (1, "coffee-table", 16, [])],
    "bedroom": [(0, "bed", 22, ["bed"])],
    "bathroom": [(1, "vanity", 26, [])],
}
COZY_OUTLINES = {
    "sofa": [[48, 133], [130, 101], [157, 108], [161, 136], [168, 142], [168, 155], [73, 192], [48, 181]],
    "coffee-table": [[125, 178], [171, 160], [204, 173], [204, 184], [193, 189], [193, 200],
                     [185, 203], [185, 193], [158, 204], [158, 214], [149, 211], [149, 201], [125, 190]],
    "bed": [[145, 158], [237, 121], [303, 147], [304, 176], [219, 215], [143, 182]],
    "vanity": [[215, 128], [245, 115], [288, 132], [288, 165], [259, 181], [215, 159]],
}


def populate(data):
    blocks = json.loads(Path(__file__).with_name("blocks.json").read_text())
    catalog = json.loads((ROOT / "Sources/MijiaBarApp/Resources/House/modules/catalog.json").read_text())
    for art_set, modules in data["sets"].items():
        for module, pieces in PIECES.items():
            if module not in modules:
                continue
            rectangles = blocks.get(art_set, {}).get(module, blocks["cozy"][module])
            modules[module]["occluders"] = [
                dict(id=kind, kind=kind, footprint=[value / data["cellsPerGrid"] for value in rectangles[index]],
                     z=height, perches=perches)
                for index, kind, height, perches in pieces
            ]
            if art_set == "cozy":
                tip = catalog["modules"][module]["tip"]
                for occluder in modules[module]["occluders"]:
                    occluder["silhouette"] = [[point[0] - tip[0], point[1] - tip[1]]
                                              for point in COZY_OUTLINES[occluder["id"]]]


if __name__ == "__main__":
    path = ROOT / "Sources/MijiaBarApp/Resources/House/pets/pet-spots.json"
    data = json.loads(path.read_text())
    populate(data)
    path.write_text(json.dumps(data, indent=1) + "\n")
