"""Bake palette-swap style variants from material maps into assets/house/styles/<id>/modules/."""
import json, os, sys, shutil
import numpy as np
from PIL import Image
from recolor import THEMES, recolor, bases_of

def load(path): return np.array(Image.open(path).convert("RGBA"))

def main(mod_dir, mat_dir, out_root):
    cat = json.load(open(os.path.join(mod_dir, "catalog.json")))
    # collect bases from day-unlit full modules
    pairs = []
    for mid, art in cat["modules"].items():
        rgba = load(os.path.join(mod_dir, os.path.basename(art["variants"]["day-unlit"])))
        mat = np.array(Image.open(os.path.join(mat_dir, f"mat-{mid}.png")))
        pairs.append((rgba, mat))
    bases = bases_of(pairs)
    print("bases", bases)
    for theme_id, theme in THEMES.items():
        dest = os.path.join(out_root, theme_id, "modules")
        os.makedirs(dest, exist_ok=True)
        # write manifest
        man = {
            "id": theme_id,
            "name": {"zh": {"light-wood": "浅木白墙", "walnut": "胡桃木"}.get(theme_id, theme_id),
                     "en": {"light-wood": "Light wood", "walnut": "Walnut"}.get(theme_id, theme_id)},
            "kind": "palette",
            "parent": "cozy-wood",
            "version": 1,
            "theme": theme,
            "bases": bases,
        }
        os.makedirs(os.path.join(out_root, theme_id), exist_ok=True)
        json.dump(man, open(os.path.join(out_root, theme_id, "manifest.json"), "w"), indent=2, ensure_ascii=False)
        # copy catalog (same anchors) + mat maps + recolored PNGs
        shutil.copy(os.path.join(mod_dir, "catalog.json"), os.path.join(dest, "catalog.json"))
        for mid, art in cat["modules"].items():
            for cut in (False, True):
                src_mat = os.path.join(mat_dir, f"mat-{mid}{'-cut' if cut else ''}.png")
                if os.path.exists(src_mat):
                    shutil.copy(src_mat, os.path.join(dest, os.path.basename(src_mat)))
            for key, rel in art.get("variants", {}).items():
                name = os.path.basename(rel)
                rgba = load(os.path.join(mod_dir, name))
                cut = "-cut" in key
                mat = np.array(Image.open(os.path.join(mat_dir, f"mat-{mid}{'-cut' if cut else ''}.png")))
                if mat.shape[:2] != rgba.shape[:2]:
                    mat = np.array(Image.fromarray(mat).resize((rgba.shape[1], rgba.shape[0]), Image.NEAREST))
                out = recolor(rgba, mat, bases, theme)
                Image.fromarray(out).save(os.path.join(dest, name), optimize=True)
            print(theme_id, mid)
        # also copy curtain patches as-is (fabric stays; wall/floor behind them change in modules)
        import glob
        for c in glob.glob(os.path.join(mod_dir, "curtain-*.png")):
            shutil.copy(c, dest)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
