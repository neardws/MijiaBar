#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "Sources/MijiaBarApp/Resources/House/style-packs.json"


def build(output):
    packs = []
    for style in ("japanese", "modern", "light-wood", "walnut"):
        source = ROOT / "assets/house/styles" / style
        manifest = json.loads((source / "manifest.json").read_text())
        version = manifest["version"]
        assert manifest["id"] == style and isinstance(version, int) and version > 0
        relative = f"{style}/{version}.zip"
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        files = [source / "manifest.json"]
        for sub in ("modules", "classic"):
            files += [path for path in (source / sub).glob("*") if path.suffix in (".png", ".json")]
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED) as archive:
            for path in sorted(files, key=lambda path: path.relative_to(source).as_posix()):
                if path.is_symlink() or not path.is_file():
                    raise ValueError(f"Not a regular file: {path}")
                entry = zipfile.ZipInfo(path.relative_to(source).as_posix(), (2020, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                archive.writestr(entry, path.read_bytes())
        data = target.read_bytes()
        pack = dict(id=style, version=version, url=relative, sha256=hashlib.sha256(data).hexdigest(), size=len(data))
        if "minAppVersion" in manifest:
            pack["minAppVersion"] = manifest["minAppVersion"]
        packs.append(pack)
        print(f"{relative}: {len(data):,} bytes ({len(data) / 1_000_000:.2f} MB)")
    encoded = json.dumps(dict(schema=1, packs=packs), indent=2) + "\n"
    (output / "index.json").write_text(encoded)
    return encoded


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("outdir", nargs="?", default="dist/style-packs")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="mijiabar-style-packs-") as temporary:
            generated = build(Path(temporary))
        if not INDEX.exists() or INDEX.read_text() != generated:
            raise SystemExit("Baked index differs; run scripts/build-style-packs.sh and upload the regenerated packs.")
        print("Baked index matches freshly built packs.")
    else:
        output = Path(args.outdir)
        output.mkdir(parents=True, exist_ok=True)
        INDEX.write_text(build(output))


if __name__ == "__main__":
    main()
