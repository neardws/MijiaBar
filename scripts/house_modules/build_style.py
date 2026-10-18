"""Build a full-redraw pack, or draw its anchor contact sheet.

python3 scripts/house_modules/build_style.py japanese --prefix jp
python3 scripts/house_modules/build_style.py japanese living bedroom --prefix jp
python3 scripts/house_modules/build_style.py sheet japanese /tmp/japanese-sheet.png
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
MODULES = ('living', 'bedroom', 'study', 'generic', 'kitchen', 'bathroom', 'balcony')


def pack_path(style):
    if not style or Path(style).name != style or style in ('.', '..'):
        raise ValueError('style must be a directory name')
    return ROOT / 'assets/house/styles' / style


def build(style, selected, prefix):
    import cv2
    import numpy as np
    from PIL import Image
    import add_appliances as appliances
    import appliance_models as models
    import build as module_build
    import curtains
    import fixtures
    import pipeline
    from style_corners import detect
    from style_syncut import syncut

    pack = pack_path(style)
    source = pack / 'src'
    raw = pack / 'raw'
    output = pack / 'modules'
    inputs = {}
    for module in selected:
        full = source / f'{prefix}-{module}-full.jpg'
        cut = source / f'{prefix}-{module}-cut.jpg'
        cut_source = source / f'{prefix}-{module}-cutsrc.jpg'
        if not full.exists() or not (cut.exists() or cut_source.exists()):
            raise FileNotFoundError(f'{module}: need {full.name} and cut or cutsrc JPG in {source}')
        inputs[module] = (full, cut, cut_source)
    raw.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    for module, (full, cut, cut_source) in inputs.items():
        _, geometry, _ = fixtures.spec(module)
        full_image = Image.open(full).convert('RGB').resize((1280, 720), Image.Resampling.LANCZOS)
        full_image.save(raw / f'{module}-day-full.jpg', quality=95)
        corners = detect(raw, module)
        canonical_full = pipeline.warp_to_canonical(np.asarray(full_image), corners, geometry)
        if cut_source.exists():
            Image.open(cut_source).convert('RGB').resize((1280, 720), Image.Resampling.LANCZOS).save(raw / f'{module}-cutsrc-day-full.jpg', quality=95)
            cut_corners = detect(raw, f'{module}-cutsrc')
            cut_rgb = np.asarray(Image.open(raw / f'{module}-cutsrc-day-full.jpg').convert('RGB'))
            canonical_cut = Image.fromarray(syncut(np.asarray(pipeline.warp_to_canonical(cut_rgb, cut_corners, geometry)).copy(), geometry))
        else:
            cut_image = Image.open(cut).convert('RGB').resize((1280, 720), Image.Resampling.LANCZOS)
            cut_image.save(raw / f'{module}-day-cut.jpg', quality=95)
            cut_corners = pipeline.cut_corners(np.asarray(full_image), np.asarray(cut_image), corners, geometry)
            canonical_cut = pipeline.warp_to_canonical(np.asarray(cut_image), cut_corners, geometry, cut=True, full_rgb=np.asarray(canonical_full)[..., :3])
            pixels = np.asarray(canonical_cut).copy()
            dark = (pixels[..., :3].astype(np.float32).mean(-1) < 13) | (pixels[..., 3] == 0)
            _, labels = cv2.connectedComponents(dark.astype(np.uint8))
            outside = set(np.unique(labels[0])) - {0}
            masks = pipeline.region_masks(geometry, 2)
            pixels[np.isin(labels, list(outside)) & dark & (masks['nw'] | masks['ne']), 3] = 0
            canonical_cut = Image.fromarray(pixels)
        for variant, image in (('full', canonical_full), ('cut', canonical_cut)):
            pixels = np.asarray(image).copy()
            if module == 'bathroom' and variant == 'full': appliances.paint_model(pixels, geometry, models.Heater())
            if module == 'balcony': appliances.paint_model(pixels, geometry, models.Washer())
            Image.fromarray(pixels).save(raw / f'{module}-day-{variant}-canon.png')

    windows = {key: value for key, value in curtains.WINDOWS.items() if not key.startswith('classic')}
    window_file = source / 'windows.json'
    if window_file.exists():
        for key, values in json.loads(window_file.read_text()).items():
            exclusions = values[6] if len(values) > 6 else []
            windows[key] = (windows[key][0], values[:6], exclusions)
    offsets_file = source / 'offsets.json'
    offsets = json.loads(offsets_file.read_text()) if offsets_file.exists() else {}
    shifted_fields = {'source', 'anchor', 'shade', 'core', 'vent', 'led', 'screen', 'reveal', 'display', 'body'}

    def shift(value, delta):
        if isinstance(value, list) and len(value) >= 2 and all(isinstance(number, (int, float)) for number in value):
            return [value[0] + delta[0], value[1] + delta[1]] + value[2:]
        if isinstance(value, list): return [shift(item, delta) for item in value]
        return value

    original_spec = fixtures.spec

    def style_spec(module):
        width, geometry, specification = copy.deepcopy(original_spec(module))
        for light in specification.get('lights', []):
            delta = offsets.get(module, {}).get(light['id'])
            if delta:
                for field in light:
                    if field in shifted_fields or (field == 'pool' and abs(delta[0]) > 10):
                        light[field] = shift(light[field], delta)
        return width, geometry, specification

    previous = (module_build.spec, module_build.MODULES, curtains.MOD, curtains.WINDOWS, sys.argv)
    try:
        module_build.spec = style_spec
        module_build.MODULES = selected
        curtains.MOD, curtains.WINDOWS = output, windows
        sys.argv = ['build.py', str(output), '--raw', str(raw), '--classic', str(ROOT / 'assets/house')]
        catalog_path = output / 'catalog.json'
        existing = json.loads(catalog_path.read_text()) if catalog_path.exists() else None
        module_build.main()
        catalog = json.loads(catalog_path.read_text())
        if existing:
            catalog['modules'] = {**existing['modules'], **catalog['modules']}
        curtains.WINDOWS = {key: value for key, value in windows.items() if key in selected}
        definitions = curtains.build(str(output))
        for module, definition in definitions.items():
            for light in catalog['modules'][module]['lights']:
                if light['role'] == 'curtain': light.update(definition)
        catalog_path.write_text(json.dumps(catalog, indent=1, ensure_ascii=False) + '\n')
    finally:
        module_build.spec, module_build.MODULES, curtains.MOD, curtains.WINDOWS, sys.argv = previous


def sheet(style, destination):
    from PIL import Image, ImageDraw

    directory = pack_path(style) / 'modules'
    catalog = json.loads((directory / 'catalog.json').read_text())
    rows = []
    for module, art in catalog['modules'].items():
        variants = art['variants']
        images = [Image.open(directory / variants[key]).convert('RGBA') for key in ('day-unlit', 'day-unlit-cut', 'night-lit')]
        overlay = images[0].copy()
        draw = ImageDraw.Draw(overlay)

        def point(position, color, radius=3):
            horizontal, vertical = position[:2]
            draw.ellipse((horizontal-radius, vertical-radius, horizontal+radius, vertical+radius), outline=color)

        for light in art['lights']:
            for field, color in (('source', 'yellow'), ('anchor', 'magenta'), ('alt', 'cyan'), ('alt2', 'blue')):
                if field in light: point(light[field], color)
            for field in ('core', 'shade', 'quad', 'body', 'screen', 'display'):
                polygon = light.get(field)
                if isinstance(polygon, list) and len(polygon) >= 3 and isinstance(polygon[0], list):
                    draw.polygon([tuple(position) for position in polygon], outline='red')
            for field in ('display', 'led'):
                position = light.get(field)
                if isinstance(position, list) and len(position) >= 2 and not isinstance(position[0], list): point(position, 'lime', 2)
            if 'vent' in light: draw.line([tuple(position) for position in light['vent']], fill='cyan', width=2)
            draw.text(tuple((light.get('source') or light.get('anchor') or light.get('alt') or [5, 5])[:2]), light['id'], fill='white')
        for badge in art.get('badges', []):
            position = badge if isinstance(badge, list) else badge.get('at', badge.get('p'))
            if position: point(position, 'white', 4)
        point(art['label'], 'orange', 4)
        row = Image.new('RGBA', (sum(image.width for image in images) + 20, max(image.height for image in images)), (30, 32, 44, 255))
        offset = 0
        for image in [overlay, *images[1:]]:
            row.alpha_composite(image, (offset, 0))
            offset += image.width + 10
        ImageDraw.Draw(row).text((5, 5), module, fill='white')
        rows.append(row)
    result = Image.new('RGBA', (max(row.width for row in rows), sum(row.height for row in rows)), (30, 32, 44, 255))
    offset = 0
    for row in rows:
        result.alpha_composite(row, (0, offset))
        offset += row.height
    result.save(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    if sys.argv[1:2] == ['sheet']:
        parser.add_argument('command', choices=['sheet'])
        parser.add_argument('style')
        parser.add_argument('output', type=Path)
        arguments = parser.parse_args()
        sheet(arguments.style, arguments.output)
    else:
        parser.add_argument('style')
        parser.add_argument('modules', nargs='*')
        parser.add_argument('--prefix')
        arguments = parser.parse_args()
        unknown = set(arguments.modules) - set(MODULES)
        if unknown: parser.error('unknown modules: ' + ', '.join(sorted(unknown)))
        build(arguments.style, arguments.modules or list(MODULES), arguments.prefix or arguments.style)


if __name__ == '__main__':
    main()
