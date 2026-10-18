"""Detect robust corners in black-background generated art.

python3 scripts/house_modules/style_corners.py RAW_DIR MODULE
"""
import argparse
import json
from pathlib import Path


def detect(raw, module):
    import cv2
    import numpy as np
    from PIL import Image
    from geom import SLAB, WALL_H

    raw = Path(raw)
    pixels = np.asarray(Image.open(raw / f'{module}-day-full.jpg').convert('RGB')).astype(np.float32)
    luminance = pixels.mean(-1)
    height, width = luminance.shape
    mask = cv2.morphologyEx((luminance > 8).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    _, labels, statistics, _ = cv2.connectedComponentsWithStats(mask)
    if len(statistics) < 2: raise ValueError(f'{module}: no room silhouette')
    mask = labels == 1 + np.argmax(statistics[1:, cv2.CC_STAT_AREA])
    columns = np.arange(width)
    occupied = mask.any(0)
    top_edge = np.where(occupied, np.argmax(mask, 0), -1)
    bottom_edge = np.where(occupied, height - 1 - np.argmax(mask[::-1], 0), -1)
    minimum, maximum = columns[occupied].min(), columns[occupied].max()
    span = maximum - minimum

    def fit(start, end, edge):
        horizontal = columns[int(start):int(end)]
        vertical = edge[int(start):int(end)]
        valid = vertical >= 0
        horizontal, vertical = horizontal[valid], vertical[valid]
        for _ in range(4):
            if len(horizontal) < 2: raise ValueError(f'{module}: insufficient edge samples')
            coefficients = np.polyfit(horizontal, vertical, 1)
            residual = np.abs(np.polyval(coefficients, horizontal) - vertical)
            keep = residual < max(2.0, np.percentile(residual, 80))
            horizontal, vertical = horizontal[keep], vertical[keep]
        return coefficients

    top_column = columns[occupied][np.argmin(top_edge[occupied])]
    upper_left = fit(minimum + .08 * span, top_column - .12 * span, top_edge)
    upper_right = fit(top_column + .12 * span, maximum - .08 * span, top_edge)
    top_x = (upper_right[1] - upper_left[1]) / (upper_left[0] - upper_right[0])
    top = [top_x, np.polyval(upper_left, top_x)]
    left_top = [minimum, np.polyval(upper_left, minimum)]
    right_top = [maximum, np.polyval(upper_right, maximum)]
    bottom_column = columns[occupied][np.argmax(bottom_edge[occupied])]
    lower_left = fit(minimum + .06 * span, bottom_column - .08 * span, bottom_edge)
    lower_right = fit(bottom_column + .08 * span, maximum - .06 * span, bottom_edge)
    bottom_x = (lower_right[1] - lower_left[1]) / (lower_left[0] - lower_right[0])
    bottom = [bottom_x, np.polyval(lower_left, bottom_x)]
    left_bottom = [minimum, np.polyval(lower_left, minimum)]
    right_bottom = [maximum, np.polyval(lower_right, maximum)]
    total_height = ((left_bottom[1] - left_top[1]) + (right_bottom[1] - right_top[1])) / 2
    slab = total_height * SLAB / (WALL_H + SLAB)
    wall_height = total_height - slab
    corners = dict(top=top, lt=left_top, lb=left_bottom, rt=right_top, rb=right_bottom, bottom=bottom,
                   B=[top[0], top[1] + wall_height], L=[left_bottom[0], left_bottom[1] - slab],
                   R=[right_bottom[0], right_bottom[1] - slab], F=[bottom[0], bottom[1] - slab], wall_h=wall_height, slab=slab)
    corners = {key: [float(round(number, 1)) for number in value] if isinstance(value, list) else float(round(value, 1))
               for key, value in corners.items()}
    (raw / f'{module}-corners.json').write_text(json.dumps(corners) + '\n')
    return corners


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('module')
    arguments = parser.parse_args()
    print(json.dumps(detect(arguments.raw, arguments.module)))
