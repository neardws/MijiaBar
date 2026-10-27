"""Compact erect-ear domestic dog; shared pose timing and encoded coat regions."""
import numpy as np
from cat import Cat, ACTIONS as CAT_ACTIONS, frame_from
from sdfcat import nrm
from patterns import BASE, SECOND, WHITE, UNDER, PINK


def build(pose):
    dog = Cat()
    sleeping = pose.get('head_scale', 1.2) > 1.5
    compress = np.array([1.0, 1.08, 0.84 if not sleeping else 1.0])
    point = lambda value: np.asarray(value) * compress
    up = pose.get('back_up', np.array([0, 0, 1]))
    dog.spine('body', [point(value) for value in pose['spine']],
              np.asarray(pose['spine_r']) * (1.14 if not sleeping else 1.0), up)
    dog.spine('neck', [point(value) for value in pose['neck']],
              np.asarray(pose['neck_r']) * 1.16, pose.get('neck_up', up))
    rotation = pose['head_R']
    center = point(pose['head_c'])
    scale = pose.get('head_scale', 1.2) * (0.92 if sleeping else 1.0)
    head = lambda value: center + rotation @ (np.asarray(value) * scale)
    dog.ellip('head', center, rotation, np.array([10.8, 10.0, 10.4]) * scale)
    for side in (-1, 1):
        dog.ellip('cheek', head((3, side * 5.5, -3)), rotation, np.array([6, 4.5, 5]) * scale)
    dog.ellip('muzzle', head((11.2, 0, -3.6)), rotation, np.array([8.2, 5.3, 4.5]) * scale, k=2.2)
    dog.ellip('chin', head((10, 0, -6.3)), rotation, np.array([6.8, 4.4, 2.6]) * scale, k=2.0)
    for side, name in ((1, 'earL'), (-1, 'earR')):
        dog.ear(name, head((-2.8, side * 6.4, 6.8)), head((-4.4, side * 8.8, 18.5)),
                rotation @ np.array([1, 0, 0]), r1=5.3 * scale, r2=0.8 * scale, flat=1.6)
    for name, points, radii in pose['legs']:
        dog.limb(name, [point(value) for value in points], np.asarray(radii) * 1.12)
        direction = nrm(pose.get('paw_dir', {}).get(name, np.array([1, 0, 0])))
        dog.ellip(name + 'paw', point(points[-1]) + direction, frame_from(direction, np.array([0, 0, 1])),
                  np.array([4.8, 3.8, 2.5]), k=1.5)
    for name, (center_thigh, rotation_thigh, radii) in pose.get('thighs', []):
        dog.ellip(name, point(center_thigh), rotation_thigh, np.asarray(radii) * 1.08)
    tail = [point(value) for value in pose['tail']]
    if not sleeping:
        root = tail[0]
        wag = tail[-1][1] * 0.7
        tail = [root, root + [-6, wag, 7], root + [-5, wag + 1, 16],
                root + [2, wag + 2, 19], root + [7, wag + 2, 14]]
    radii = np.linspace(5.8, 3.2, len(tail))
    dog.spine('tail', tail, radii, pose.get('tail_up', np.array([0, 0, 1])), k=1.6)
    dog.feat = dict(eyeL=head((8.3, 4.8, 2)), eyeR=head((8.3, -4.8, 2)), nose=head((18.9, 0, -2.5)),
                    mouth=head((18.1, 0, -5.7)), head_c=center, head_fwd=rotation @ np.array([1, 0, 0]),
                    head_up=rotation @ np.array([0, 0, 1]))
    dog.eyes = pose.get('eyes', 'open')
    return dog


def regions(names, local, pattern):
    along, side, height = local[:, 0], local[:, 1], local[:, 2]
    is_part = lambda *values: np.isin(names, values)
    body = is_part('body', 'neck', 'thighL', 'thighR')
    head = is_part('head', 'cheek')
    ear = is_part('earL', 'earR')
    muzzle = is_part('muzzle', 'chin')
    paws = is_part('FLpaw', 'FRpaw', 'HLpaw', 'HRpaw')
    legs = is_part('FL', 'FR', 'HL', 'HR')
    tail = is_part('tail')
    bib = (body & (height < -0.25)) | (is_part('neck') & (height < 0.2))
    blaze = head & (along > 0.45) & (np.abs(side) < 0.22)
    white = bib | blaze | muzzle | paws | (legs & (along > 0.76)) | (tail & (along > 0.86))
    result = np.full(len(names), BASE)
    result[bib | muzzle] = UNDER
    if pattern in ('tabby', 'tabbyWhite'):
        brindle = np.sin(2 * np.pi * (along * 6.0 + side * 0.35 - height * 0.45) + np.sin(side * 4)) > 0.35
        result[body & brindle & (height > -0.35)] = SECOND
        result[ear | (head & (along > 0.55) & (height < 0.15))] = SECOND
    if pattern in ('tabbyWhite', 'bicolor'):
        result[white] = WHITE
    if pattern == 'calico':
        result[body & (height > -0.1) | ear | (tail & (along < 0.85))] = SECOND
        result[head & (height > 0.25)] = SECOND
        result[white] = WHITE
    if pattern == 'colorpoint':
        result[ear | muzzle | paws | (legs & (along > 0.6)) | (tail & (along > 0.5)) |
               (head & (along > 0.35) & (height < 0.35))] = SECOND
    result[ear & (along > 0.3) & (np.abs(side) < 0.55) & (height > 0.1) & (height < 0.78)] = PINK
    return result


ACTIONS = {name: dict(action) for name, action in CAT_ACTIONS.items()}
