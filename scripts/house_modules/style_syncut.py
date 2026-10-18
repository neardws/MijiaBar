"""Synthesize low walls from a plain-wall canonical image, preserving furniture."""


def syncut(rgba, geometry, scale=2, drop_rects=()):
    """drop_rects: [x0,y0,x1,y1] in module px; always cut wall pixels above CUT_H inside them."""
    import cv2
    import numpy as np
    import pipeline
    from geom import CUT_H, WALL_H

    rgb = rgba[..., :3].astype(np.float32)
    height, width = rgb.shape[:2]
    masks = pipeline.region_masks(geometry, scale)
    wall = masks['nw'] | masks['ne']
    vertical, horizontal = np.mgrid[0:height, 0:width].astype(np.float32)
    tip, right, left = [np.array(position, np.float32) * scale for position in (geometry['T'], geometry['R'], geometry['L'])]
    edge = np.where(horizontal < tip[0],
                    tip[1] + (horizontal - tip[0]) * (left[1] - tip[1]) / (left[0] - tip[0]),
                    tip[1] + (horizontal - tip[0]) * (right[1] - tip[1]) / (right[0] - tip[0]))
    elevation = (edge - vertical) / scale
    above = wall & (elevation > CUT_H)
    output = rgba.copy()
    for side in ('nw', 'ne'):
        zone = above & masks[side] & (elevation > CUT_H + 8) & (rgba[..., 3] > 0)
        if not zone.any(): continue
        reference = np.median(rgb[zone], 0)
        difference = np.abs(rgb - reference).sum(-1)
        furniture = (difference > 55) & above & masks[side] & (rgba[..., 3] > 0)
        furniture = cv2.morphologyEx(furniture.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0
        count, labels, statistics, _ = cv2.connectedComponentsWithStats(furniture.astype(np.uint8))
        keep = np.zeros_like(furniture)
        band = above & masks[side] & (elevation < CUT_H + 4)
        for index in range(1, count):
            component = labels == index
            if (component & band).any() and statistics[index, cv2.CC_STAT_AREA] > 30 and not (component & (elevation > WALL_H - 14)).any():
                keep |= component
        output[above & masks[side] & ~keep, 3] = 0
    for x0, y0, x1, y1 in drop_rects:
        rectangle = above & (horizontal >= x0 * scale) & (horizontal < x1 * scale) & (vertical >= y0 * scale) & (vertical < y1 * scale)
        output[rectangle, 3] = 0
    cap = wall & (elevation > CUT_H - 3) & (elevation <= CUT_H) & (output[..., 3] > 0)
    output[cap, :3] = (output[cap, :3].astype(np.float32) * .55).astype(np.uint8)
    return output
