#!/usr/bin/env python3
"""Generuje navazující dlaždice povrchu pro pohled kolmo shora.

Všechny dlaždice jedné sady mají stejný vnější okraj. Ten není kopie
stejných pixelů vlevo i vpravo: pravý okraj je první půlka vzoru a levý
okraj druhé dlaždice je jeho pokračování. Proto jde každou dlaždici
položit vedle každé jiné, včetně sebe samé, bez otočení.

Příklad:
  py tools/generate.py
  py tools/gen_terrain_tiles.py --kind dirt --variants 16
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GRAPHICS = ROOT / "godot" / "graphics"


def parse_hex(value: str) -> tuple[int, int, int]:
    text = value.strip().lstrip("#")
    if len(text) != 6 or any(c not in "0123456789abcdefABCDEF" for c in text):
        raise argparse.ArgumentTypeError("barva má být hex ve tvaru RRGGBB")
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))


def rgb_to_hsv(r: int, g: int, b: int) -> tuple[float, float, float]:
    rf, gf, bf = r / 255, g / 255, b / 255
    hi = max(rf, gf, bf)
    lo = min(rf, gf, bf)
    delta = hi - lo
    if delta == 0:
        hue = 0.0
    elif hi == rf:
        hue = 60 * (((gf - bf) / delta) % 6)
    elif hi == gf:
        hue = 60 * ((bf - rf) / delta + 2)
    else:
        hue = 60 * ((rf - gf) / delta + 4)
    saturation = 0.0 if hi == 0 else delta / hi
    return hue, saturation, hi


def hsv_to_rgb(hue: float, saturation: float, value: float) -> tuple[int, int, int]:
    hue = hue % 360
    value = min(1.0, max(0.0, value))
    saturation = min(1.0, max(0.0, saturation))
    chroma = value * saturation
    hp = hue / 60
    x = chroma * (1 - abs(hp % 2 - 1))
    if hp < 1:
        red, green, blue = chroma, x, 0.0
    elif hp < 2:
        red, green, blue = x, chroma, 0.0
    elif hp < 3:
        red, green, blue = 0.0, chroma, x
    elif hp < 4:
        red, green, blue = 0.0, x, chroma
    elif hp < 5:
        red, green, blue = x, 0.0, chroma
    else:
        red, green, blue = chroma, 0.0, x
    match = value - chroma
    return (
        int(round((red + match) * 255)),
        int(round((green + match) * 255)),
        int(round((blue + match) * 255)),
    )


def fade(t: float) -> float:
    return t * t * (3 - 2 * t)


def value_noise(size: int, cells: int, rng: random.Random) -> list[list[float]]:
    """Hladký šum, který se na protilehlých okrajích spojuje."""
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        gy = (y + 0.5) / size * cells
        y0 = int(math.floor(gy)) % cells
        y1 = (y0 + 1) % cells
        fy = fade(gy - math.floor(gy))
        row0 = grid[y0]
        row1 = grid[y1]
        for x in range(size):
            gx = (x + 0.5) / size * cells
            x0 = int(math.floor(gx)) % cells
            x1 = (x0 + 1) % cells
            fx = fade(gx - math.floor(gx))
            top = row0[x0] + (row0[x1] - row0[x0]) * fx
            bottom = row1[x0] + (row1[x1] - row1[x0]) * fx
            out[y][x] = top + (bottom - top) * fy
    return out


def fbm(size: int, base_cells: int, rng: random.Random, octaves: int = 3) -> list[list[float]]:
    acc = [[0.0] * size for _ in range(size)]
    weight_sum = 0.0
    cells = base_cells
    amplitude = 1.0
    for _ in range(octaves):
        cells = max(2, min(cells, max(2, size // 2)))
        layer = value_noise(size, cells, rng)
        for y in range(size):
            row_acc = acc[y]
            row_layer = layer[y]
            for x in range(size):
                row_acc[x] += row_layer[x] * amplitude
        weight_sum += amplitude
        amplitude *= 0.5
        cells *= 2
    for y in range(size):
        for x in range(size):
            acc[y][x] /= weight_sum
    return acc


def hash_unit(x: int, y: int, seed: int) -> float:
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return (n & 0xFFFFFF) / 0xFFFFFF


def lerp_rgb(
    a: tuple[int, int, int], b: tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def scale_rgb(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(min(255, max(0, int(round(channel * factor)))) for channel in color)


class Field:
    def __init__(self, size: int):
        black = (0, 0, 0)
        self.size = size
        self.px = [[black for _ in range(size)] for _ in range(size)]
        self.mask = [[0.0 for _ in range(size)] for _ in range(size)]

    def get(self, x: int, y: int) -> tuple[int, int, int]:
        return self.px[y % self.size][x % self.size]

    def set(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        self.px[y % self.size][x % self.size] = color

    def blend(self, x: int, y: int, color: tuple[int, int, int], alpha: float) -> None:
        if alpha <= 0:
            return
        if alpha >= 1:
            self.set(x, y, color)
            return
        self.set(x, y, lerp_rgb(self.get(x, y), color, alpha))

    def contains(self, x: int, y: int) -> bool:
        return 0 <= x < self.size and 0 <= y < self.size

    def set_inside(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if self.contains(x, y):
            self.px[y][x] = color

    def blend_inside(self, x: int, y: int, color: tuple[int, int, int], alpha: float) -> None:
        if self.contains(x, y):
            self.blend(x, y, color, alpha)

    def set_mask(self, x: int, y: int, value: float) -> None:
        self.mask[y][x] = value

    def fill_mask(self, value: float) -> None:
        for y in range(self.size):
            row = self.mask[y]
            for x in range(self.size):
                row[x] = value

    def image(self) -> Image.Image:
        img = Image.new("RGB", (self.size, self.size))
        img.putdata([self.px[y][x] for y in range(self.size) for x in range(self.size)])
        return img

    def rgba_image(self) -> Image.Image:
        img = Image.new("RGBA", (self.size, self.size))
        data = []
        for y in range(self.size):
            colors = self.px[y]
            mask = self.mask[y]
            for x in range(self.size):
                color = colors[x]
                data.append((color[0], color[1], color[2], int(round(min(1.0, max(0.0, mask[x])) * 255))))
        img.putdata(data)
        return img


def color_at(
    hue_n: float,
    val_n: float,
    fine_h: float,
    fine_v: float,
    base_h: float,
    base_s: float,
    base_v: float,
    hue_span: float,
    contrast: float,
) -> tuple[int, int, int]:
    shared_h = (hue_n - 0.5) * 2
    shared_v = (val_n - 0.5) * 2
    hue_off = (0.75 * shared_h + 0.25 * fine_h) * hue_span
    # Světlejší místa jdou mírně do žluta, tmavší do sytější zeleně. Pořád uvnitř rozsahu.
    hue_off += shared_v * hue_span * 0.3
    hue_off = min(hue_span, max(-hue_span, hue_off))
    contrast_off = (0.75 * shared_v + 0.25 * fine_v) * contrast
    contrast_off = min(contrast, max(-contrast, contrast_off))
    value = min(1.0, max(0.0, base_v * (1 + contrast_off)))
    return hsv_to_rgb(base_h + hue_off, base_s, value)


def paint_field(
    size: int,
    rng: random.Random,
    seed: int,
    base: tuple[int, int, int],
    hue_span: float,
    contrast: float,
    coarseness: float,
    kind: str,
) -> Field:
    base_h, base_s, base_v = rgb_to_hsv(*base)
    cells = max(3, int(round(10 / coarseness)))
    hue_noise = fbm(size, cells, rng)
    value_noise_field = fbm(size, max(2, cells + 1), rng)
    field = Field(size)

    for y in range(size):
        hue_row = hue_noise[y]
        val_row = value_noise_field[y]
        for x in range(size):
            fine_h = hash_unit(x, y, seed) * 2 - 1
            fine_v = hash_unit(x, y, seed + 97) * 2 - 1
            field.set(
                x,
                y,
                color_at(
                    hue_row[x],
                    val_row[x],
                    fine_h,
                    fine_v,
                    base_h,
                    base_s,
                    base_v,
                    hue_span,
                    contrast,
                ),
            )

    if kind == "dirt":
        paint_dirt(field, rng, base, hue_span, contrast, coarseness)
        return field
    if kind == "desert":
        paint_desert(field, rng, base, hue_span, contrast, coarseness)
        return field
    if kind == "snow":
        paint_snow(field, rng, base, hue_span, contrast, coarseness)
        return field
    if kind == "water":
        paint_water(field, rng, base, hue_span, contrast, coarseness)
        return field

    clump_count = max(8, int(round(22 / coarseness)))
    for _ in range(clump_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        radius = rng.uniform(2.2, 4.2) * math.sqrt(coarseness)
        hue_off = rng.uniform(-hue_span, hue_span)
        value_mul = 1 + rng.uniform(-contrast, contrast)
        color = hsv_to_rgb(base_h + hue_off, base_s, min(1.0, max(0.0, base_v * value_mul)))
        reach = int(math.ceil(radius))
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox, oy) / radius
                if dist > 1:
                    continue
                alpha = (1 - dist) ** 1.4 * 0.8
                field.blend(cx + ox, cy + oy, color, alpha)

    return field


def point_inside(rng: random.Random, size: int, margin: int) -> tuple[int, int] | None:
    margin = max(0, margin)
    if margin * 2 >= size:
        return None
    return rng.randrange(margin, size - margin), rng.randrange(margin, size - margin)


def paint_grass_marks(field: Field, rng: random.Random, coarseness: float, allow=None, density: float = 1.0) -> None:
    size = field.size
    leaf_count = max(1, int(round(90 / math.sqrt(coarseness) * density)))
    for _ in range(leaf_count):
        length = rng.randint(2, max(3, int(round(2 + 2 * coarseness))))
        angle = rng.random() * math.tau
        placed = False
        for _try in range(24):
            origin = point_inside(rng, size, length)
            if origin is None:
                break
            x, y = origin
            points: list[tuple[int, int]] = []
            for step in range(length):
                px = int(round(x + math.cos(angle) * step))
                py = int(round(y + math.sin(angle) * step))
                if not field.contains(px, py):
                    points = []
                    break
                points.append((px, py))
            if not points or (allow is not None and any(not allow(px, py) for px, py in points)):
                continue
            factor = rng.uniform(0.58, 0.78) if rng.random() < 0.7 else rng.uniform(1.16, 1.34)
            color = scale_rgb(field.get(x, y), factor)
            for step, (px, py) in enumerate(points):
                field.set_inside(px, py, scale_rgb(color, 1 - step * 0.08))
            placed = True
            break
        if not placed:
            continue

    speck_count = max(1, int(round(28 / coarseness * density)))
    placed = 0
    tries = 0
    while placed < speck_count and tries < speck_count * 12:
        tries += 1
        x = rng.randrange(size)
        y = rng.randrange(size)
        if allow is not None and not allow(x, y):
            continue
        factor = 0.5 if rng.random() < 0.75 else 1.4
        field.set_inside(x, y, scale_rgb(field.get(x, y), factor))
        placed += 1


def paint_dirt(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    clod_count = max(6, int(round(14 / coarseness)))
    for _ in range(clod_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        radius = rng.uniform(3.2, 6.4) * math.sqrt(coarseness)
        lobes = [rng.uniform(0.72, 1.28) for _ in range(8)]
        hue_off = rng.uniform(-hue_span, hue_span)
        value_mul = 1 + rng.uniform(-contrast, contrast)
        saturation = min(1.0, max(0.2, base_s * rng.uniform(0.8, 1.2)))
        color = hsv_to_rgb(base_h + hue_off, saturation, min(1.0, max(0.0, base_v * value_mul)))
        reach = int(math.ceil(radius * 1.3))
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                if ox == 0 and oy == 0:
                    dist = 0.0
                else:
                    angle = math.atan2(oy, ox) % math.tau
                    index = angle / math.tau * 8
                    i0 = int(index) % 8
                    i1 = (i0 + 1) % 8
                    lobe = lobes[i0] + (lobes[i1] - lobes[i0]) * (index - int(index))
                    dist = math.hypot(ox, oy) / (radius * lobe)
                if dist > 1:
                    continue
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.5 * 0.85)


def paint_dirt_marks(field: Field, rng: random.Random, coarseness: float, allow=None, density: float = 1.0) -> None:
    size = field.size
    stone_count = max(1, int(round(8 / coarseness * density)))
    made = 0
    tries = 0
    while made < stone_count and tries < stone_count * 16:
        tries += 1
        rx = rng.uniform(1.5, 2.6) * math.sqrt(coarseness)
        ry = rx * rng.uniform(0.7, 1.2)
        reach = int(math.ceil(max(rx, ry)))
        origin = point_inside(rng, size, reach)
        if origin is None:
            continue
        cx, cy = origin
        pixels: list[tuple[int, int, tuple[int, int, int]]] = []
        local_h, local_s, local_v = rgb_to_hsv(*field.get(cx, cy))
        fill = hsv_to_rgb(local_h + rng.uniform(-6, 8), local_s * rng.uniform(0.45, 0.7), min(1.0, local_v * rng.uniform(1.05, 1.2)))
        rim = hsv_to_rgb(local_h, local_s * 0.55, local_v * 0.62)
        blocked = False
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox / rx, oy / ry)
                if dist > 1:
                    continue
                px, py = cx + ox, cy + oy
                if allow is not None and not allow(px, py):
                    blocked = True
                    break
                pixels.append((px, py, rim if dist > 0.68 else fill))
            if blocked:
                break
        if blocked or not pixels:
            continue
        for px, py, color in pixels:
            field.blend_inside(px, py, color, 0.95)
        made += 1

    crack_count = max(1, int(round(6 / math.sqrt(coarseness) * density)))
    for _ in range(crack_count):
        length = rng.randint(4, max(5, int(round(6 + coarseness * 2))))
        for _try in range(24):
            origin = point_inside(rng, size, length)
            if origin is None:
                break
            x, y = origin
            angle = rng.random() * math.tau
            points: list[tuple[int, int]] = []
            for step in range(length):
                if step:
                    angle += rng.uniform(-0.45, 0.45)
                px = int(round(x + math.cos(angle) * step))
                py = int(round(y + math.sin(angle) * step))
                if not field.contains(px, py):
                    points = []
                    break
                points.append((px, py))
            if not points or (allow is not None and any(not allow(px, py) for px, py in points)):
                continue
            for px, py in points:
                field.set_inside(px, py, scale_rgb(field.get(px, py), 0.4))
            break

    crumb_count = max(1, int(round(24 / coarseness * density)))
    placed = 0
    tries = 0
    while placed < crumb_count and tries < crumb_count * 12:
        tries += 1
        x = rng.randrange(size)
        y = rng.randrange(size)
        if allow is not None and not allow(x, y):
            continue
        factor = 0.62 if rng.random() < 0.6 else 1.22
        field.set_inside(x, y, scale_rgb(field.get(x, y), factor))
        placed += 1


def paint_desert(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    wind = rng.random() * math.tau
    dune_count = max(3, int(round(5 / coarseness)))
    for _ in range(dune_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        along = rng.uniform(12.0, 22.0) * math.sqrt(coarseness)
        across = along * rng.uniform(0.22, 0.42)
        lighter = rng.random() < 0.62
        if lighter:
            value_mul = 1.0 + contrast * rng.uniform(0.2, 0.55)
        else:
            value_mul = 1.0 - contrast * rng.uniform(0.7, 1.35)
        color = hsv_to_rgb(
            base_h + rng.uniform(-hue_span, hue_span) * 0.2,
            base_s * (rng.uniform(0.72, 0.92) if lighter else rng.uniform(1.05, 1.25)),
            min(1.0, max(0.0, base_v * value_mul)),
        )
        _paint_dune(field, cx, cy, along, across, wind + rng.uniform(-0.35, 0.35), color, 0.5 if lighter else 0.38)


def _paint_dune(
    field: Field,
    cx: int,
    cy: int,
    along: float,
    across: float,
    wind: float,
    color: tuple[int, int, int],
    strength: float,
) -> None:
    reach = int(math.ceil(max(along, across)))
    cosine = math.cos(wind)
    sine = math.sin(wind)
    for oy in range(-reach, reach + 1):
        for ox in range(-reach, reach + 1):
            along_pos = ox * cosine + oy * sine
            across_pos = -ox * sine + oy * cosine
            dist = math.hypot(along_pos / along, across_pos / across)
            if dist > 1:
                continue
            field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.8 * strength)


def paint_desert_marks(field: Field, rng: random.Random, coarseness: float, allow=None, density: float = 1.0) -> None:
    size = field.size
    wind = rng.random() * math.pi
    ripple_count = max(2, int(round(7 / math.sqrt(coarseness) * density)))
    for _ in range(ripple_count):
        length = rng.randint(6, max(7, int(round(9 + coarseness * 2))))
        for _try in range(24):
            origin = point_inside(rng, size, length)
            if origin is None:
                break
            x, y = origin
            angle = wind + rng.uniform(-0.2, 0.2)
            points: list[tuple[int, int]] = []
            for step in range(length):
                if step:
                    angle += rng.uniform(-0.08, 0.08)
                px = int(round(x + math.cos(angle) * step))
                py = int(round(y + math.sin(angle) * step))
                if not field.contains(px, py):
                    points = []
                    break
                points.append((px, py))
            if not points or (allow is not None and any(not allow(px, py) for px, py in points)):
                continue
            factor = 1.14 if rng.random() < 0.55 else 0.84
            for px, py in points:
                field.set_inside(px, py, scale_rgb(field.get(px, py), factor))
            break

    pebble_count = max(1, int(round(3 / coarseness * density)))
    made = 0
    tries = 0
    while made < pebble_count and tries < pebble_count * 16:
        tries += 1
        rx = rng.uniform(1.1, 1.8)
        ry = rx * rng.uniform(0.7, 1.15)
        reach = int(math.ceil(max(rx, ry)))
        origin = point_inside(rng, size, reach)
        if origin is None:
            continue
        cx, cy = origin
        local_h, local_s, local_v = rgb_to_hsv(*field.get(cx, cy))
        fill = hsv_to_rgb(local_h + rng.uniform(-4, 6), local_s * rng.uniform(0.25, 0.45), min(1.0, local_v * rng.uniform(0.72, 0.88)))
        pixels: list[tuple[int, int]] = []
        blocked = False
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox / rx, oy / ry)
                if dist > 1:
                    continue
                px, py = cx + ox, cy + oy
                if allow is not None and not allow(px, py):
                    blocked = True
                    break
                pixels.append((px, py))
            if blocked:
                break
        if blocked or not pixels:
            continue
        for px, py in pixels:
            field.blend_inside(px, py, fill, 0.9)
        made += 1

    speck_count = max(4, int(round(18 / coarseness * density)))
    placed = 0
    tries = 0
    while placed < speck_count and tries < speck_count * 12:
        tries += 1
        x = rng.randrange(size)
        y = rng.randrange(size)
        if allow is not None and not allow(x, y):
            continue
        factor = 0.7 if rng.random() < 0.45 else 1.18
        field.set_inside(x, y, scale_rgb(field.get(x, y), factor))
        placed += 1


def paint_snow(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    drift_count = max(4, int(round(7 / coarseness)))
    for _ in range(drift_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        radius = rng.uniform(7.0, 14.0) * math.sqrt(coarseness)
        color = hsv_to_rgb(
            base_h + rng.uniform(-hue_span, hue_span) * 0.35,
            base_s * rng.uniform(0.35, 0.7),
            min(1.0, base_v * rng.uniform(1.02, 1.07)),
        )
        reach = int(math.ceil(radius))
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox, oy) / radius
                if dist > 1:
                    continue
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.8 * 0.45)

    hollow_count = max(2, int(round(5 / coarseness)))
    for _ in range(hollow_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        radius = rng.uniform(3.5, 7.0) * math.sqrt(coarseness)
        color = hsv_to_rgb(
            base_h + rng.uniform(0, hue_span),
            min(1.0, base_s * rng.uniform(1.3, 1.8) + 0.03),
            max(0.0, base_v * rng.uniform(0.86, 0.94)),
        )
        reach = int(math.ceil(radius))
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox, oy) / radius
                if dist > 1:
                    continue
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.6 * 0.38)


def paint_snow_marks(field: Field, rng: random.Random, coarseness: float, allow=None, density: float = 1.0) -> None:
    size = field.size
    sparkle_count = max(4, int(round(18 / coarseness * density)))
    placed = 0
    tries = 0
    while placed < sparkle_count and tries < sparkle_count * 12:
        tries += 1
        x = rng.randrange(size)
        y = rng.randrange(size)
        if allow is not None and not allow(x, y):
            continue
        strength = rng.uniform(0.55, 0.9)
        field.blend_inside(x, y, (255, 255, 255), strength)
        if rng.random() < 0.35:
            ox = x + rng.choice((-1, 1))
            oy = y + rng.choice((-1, 0, 1))
            if field.contains(ox, oy) and (allow is None or allow(ox, oy)):
                field.blend_inside(ox, oy, (255, 255, 255), strength * 0.55)
        placed += 1

    pit_count = max(1, int(round(5 / coarseness * density)))
    made = 0
    tries = 0
    while made < pit_count and tries < pit_count * 16:
        tries += 1
        radius = rng.uniform(1.3, 2.3)
        reach = int(math.ceil(radius))
        origin = point_inside(rng, size, reach)
        if origin is None:
            continue
        cx, cy = origin
        local_h, local_s, local_v = rgb_to_hsv(*field.get(cx, cy))
        fill = hsv_to_rgb(
            local_h + rng.uniform(6, 16),
            min(1.0, local_s * rng.uniform(1.4, 2.0) + 0.05),
            local_v * rng.uniform(0.76, 0.88),
        )
        pixels: list[tuple[int, int, float]] = []
        blocked = False
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox, oy) / radius
                if dist > 1:
                    continue
                px, py = cx + ox, cy + oy
                if allow is not None and not allow(px, py):
                    blocked = True
                    break
                pixels.append((px, py, (1 - dist) * 0.72))
            if blocked:
                break
        if blocked or not pixels:
            continue
        for px, py, alpha in pixels:
            field.blend_inside(px, py, fill, alpha)
        made += 1

    crust_count = max(1, int(round(3 / math.sqrt(coarseness) * density)))
    for _ in range(crust_count):
        length = rng.randint(3, max(4, int(round(4 + coarseness))))
        for _try in range(24):
            origin = point_inside(rng, size, length)
            if origin is None:
                break
            x, y = origin
            angle = rng.random() * math.tau
            points: list[tuple[int, int]] = []
            for step in range(length):
                if step:
                    angle += rng.uniform(-0.35, 0.35)
                px = int(round(x + math.cos(angle) * step))
                py = int(round(y + math.sin(angle) * step))
                if not field.contains(px, py):
                    points = []
                    break
                points.append((px, py))
            if not points or (allow is not None and any(not allow(px, py) for px, py in points)):
                continue
            for px, py in points:
                field.set_inside(px, py, scale_rgb(field.get(px, py), 0.82))
            break


def paint_water(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    pool_count = max(3, int(round(5 / coarseness)))
    for _ in range(pool_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        radius = rng.uniform(8.0, 16.0) * math.sqrt(coarseness)
        color = hsv_to_rgb(
            base_h + rng.uniform(-hue_span, hue_span) * 0.4,
            min(1.0, base_s * rng.uniform(1.05, 1.25)),
            max(0.0, base_v * rng.uniform(0.72, 0.88)),
        )
        reach = int(math.ceil(radius))
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox, oy) / radius
                if dist > 1:
                    continue
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.7 * 0.5)

    shoal_count = max(2, int(round(4 / coarseness)))
    for _ in range(shoal_count):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        radius = rng.uniform(5.0, 10.0) * math.sqrt(coarseness)
        color = hsv_to_rgb(
            base_h + rng.uniform(0, hue_span),
            base_s * rng.uniform(0.55, 0.8),
            min(1.0, base_v * rng.uniform(1.08, 1.22)),
        )
        reach = int(math.ceil(radius))
        for oy in range(-reach, reach + 1):
            for ox in range(-reach, reach + 1):
                dist = math.hypot(ox, oy) / radius
                if dist > 1:
                    continue
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.6 * 0.42)


def paint_water_marks(field: Field, rng: random.Random, coarseness: float, allow=None, density: float = 1.0) -> None:
    size = field.size
    glint_count = max(3, int(round(10 / coarseness * density)))
    placed = 0
    tries = 0
    while placed < glint_count and tries < glint_count * 12:
        tries += 1
        length = rng.randint(2, 3)
        angle = rng.random() * math.tau
        origin = point_inside(rng, size, length)
        if origin is None:
            continue
        x, y = origin
        points: list[tuple[int, int]] = []
        for step in range(length):
            px = int(round(x + math.cos(angle) * step))
            py = int(round(y + math.sin(angle) * step))
            if not field.contains(px, py):
                points = []
                break
            points.append((px, py))
        if not points or (allow is not None and any(not allow(px, py) for px, py in points)):
            continue
        local_h, local_s, local_v = rgb_to_hsv(*field.get(x, y))
        color = hsv_to_rgb(local_h, local_s * 0.35, min(1.0, local_v * 1.35))
        for step, (px, py) in enumerate(points):
            field.blend_inside(px, py, color, 0.7 - step * 0.15)
        placed += 1

    fleck_count = max(2, int(round(8 / coarseness * density)))
    placed = 0
    tries = 0
    while placed < fleck_count and tries < fleck_count * 12:
        tries += 1
        x = rng.randrange(size)
        y = rng.randrange(size)
        if allow is not None and not allow(x, y):
            continue
        field.set_inside(x, y, scale_rgb(field.get(x, y), 0.72))
        placed += 1


def paint_marks(field: Field, rng: random.Random, kind: str, coarseness: float, allow=None, density: float = 1.0) -> None:
    if kind == "dirt":
        paint_dirt_marks(field, rng, coarseness, allow, density)
    elif kind == "desert":
        paint_desert_marks(field, rng, coarseness, allow, density)
    elif kind == "snow":
        paint_snow_marks(field, rng, coarseness, allow, density)
    elif kind == "water":
        paint_water_marks(field, rng, coarseness, allow, density)
    else:
        paint_grass_marks(field, rng, coarseness, allow, density)


def master_weight(x: int, y: int, size: int, border: int, blend: int) -> float:
    distance = min(x, y, size - 1 - x, size - 1 - y)
    if distance < border:
        return 1.0
    if distance >= border + blend:
        return 0.0
    t = (distance - border) / blend
    t = t * t * (3 - 2 * t)
    return 1.0 - t


def apply_shared_border(master: Field, variant: Field, border: int, blend: int) -> Field:
    size = master.size
    out = Field(size)
    for y in range(size):
        for x in range(size):
            weight = master_weight(x, y, size, border, blend)
            if weight >= 1:
                out.set(x, y, master.get(x, y))
            elif weight <= 0:
                out.set(x, y, variant.get(x, y))
            else:
                out.set(x, y, lerp_rgb(variant.get(x, y), master.get(x, y), weight))
    return out


def edge_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def mean_interior_step(field: Field) -> float:
    size = field.size
    total = 0
    count = 0
    for y in range(size):
        for x in range(size - 1):
            total += edge_distance(field.get(x, y), field.get(x + 1, y))
            count += 1
    return total / count


def mean_seam_step(left: Field, right: Field) -> float:
    size = left.size
    total = 0
    for y in range(size):
        total += edge_distance(left.get(size - 1, y), right.get(0, y))
    return total / size


def borders_match(master: Field, tile: Field, border: int) -> bool:
    size = master.size
    for y in range(size):
        for x in range(size):
            if min(x, y, size - 1 - x, size - 1 - y) < border:
                if master.get(x, y) != tile.get(x, y):
                    return False
    return True


def save_preview(tiles: list[Image.Image], path: Path, seed: int) -> None:
    count = len(tiles)
    tile_size = tiles[0].width
    columns = 8
    ordered_rows = math.ceil(count / columns)
    rows = ordered_rows + 1 + 4
    sheet = Image.new("RGB", (columns * tile_size, rows * tile_size))
    for index, tile in enumerate(tiles):
        sheet.paste(tile, ((index % columns) * tile_size, (index // columns) * tile_size))
    repeat_y = ordered_rows * tile_size
    for col in range(columns):
        sheet.paste(tiles[0], (col * tile_size, repeat_y))
    rng = random.Random(seed + 5000)
    for row in range(4):
        for col in range(columns):
            tile = tiles[rng.randrange(count)]
            sheet.paste(tile, (col * tile_size, (ordered_rows + 1 + row) * tile_size))
    scale = 3
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def generate_surface(
    kind: str,
    *,
    name: str,
    base: tuple[int, int, int],
    hue: float,
    contrast: float,
    coarseness: float,
    tile_size: int = 64,
    variants: int = 16,
    seed: int = 1,
    border: int = 4,
    out: Path | None = None,
    preview: Path | None = None,
) -> Path:
    if tile_size < 16:
        raise SystemExit("tile-size musí být aspoň 16")
    if variants < 1:
        raise SystemExit("variants musí být aspoň 1")
    if coarseness <= 0:
        raise SystemExit("coarseness musí být větší než 0")
    if not 0 <= hue <= 50:
        raise SystemExit("hue má být 0 až 50 procent kola")
    if not 0 <= contrast <= 80:
        raise SystemExit("contrast má být 0 až 80 procent")
    if border < 2 or border >= tile_size // 3:
        raise SystemExit("border je mimo rozsah pro tuto velikost dlaždice")

    out_dir = out or (GRAPHICS / "terrain" / name)
    out_dir.mkdir(parents=True, exist_ok=True)
    (GRAPHICS / "objects").mkdir(parents=True, exist_ok=True)
    (GRAPHICS / "characters").mkdir(parents=True, exist_ok=True)

    hue_span = hue / 100 * 360
    contrast_span = contrast / 100
    blend = max(4, border)
    if border + blend >= tile_size // 2:
        blend = max(1, tile_size // 2 - border - 1)

    master = paint_field(
        tile_size,
        random.Random(seed),
        seed,
        base,
        hue_span,
        contrast_span,
        coarseness,
        kind=kind,
    )
    from generate import BLEND_SHARP

    tiles: list[Field] = []
    liquid = 1.0 if kind in BLEND_SHARP else 0.0
    for index in range(variants):
        variant_seed = seed + 1000 * (index + 1)
        variant = paint_field(
            tile_size,
            random.Random(variant_seed),
            variant_seed,
            base,
            hue_span,
            contrast_span,
            coarseness,
            kind=kind,
        )
        tile = apply_shared_border(master, variant, border, blend)
        if not borders_match(master, tile, border):
            raise SystemExit("okraje dlaždic nesedí")
        paint_marks(tile, random.Random(variant_seed + 50), kind, coarseness)
        tile.fill_mask(liquid)
        tiles.append(tile)

    images = [tile.image() for tile in tiles]
    columns = 4
    sheet = Image.new("RGBA", (columns * tile_size, ((variants + columns - 1) // columns) * tile_size))
    for index, tile in enumerate(tiles):
        sheet.paste(tile.rgba_image(), ((index % columns) * tile_size, (index // columns) * tile_size))
    sheet.convert("RGB").save(out_dir / "atlas.png")

    if preview:
        save_preview(images, preview, seed)

    interior = mean_interior_step(tiles[0])
    seam = mean_seam_step(tiles[0], tiles[min(1, len(tiles) - 1)])
    print(f"{variants} dlaždic {tile_size}x{tile_size} -> {out_dir / 'atlas.png'}")
    print(f"skok sousedních pixelů uvnitř {interior:.1f}, na spoji {seam:.1f}")
    return out_dir


def build_parser() -> argparse.ArgumentParser:
    from generate import TERRAINS

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--kind", choices=tuple(TERRAINS), default=next(iter(TERRAINS)), help="který terén z generate.py")
    parser.add_argument("--name", help="název sady a předpona souborů")
    parser.add_argument("--tile-size", type=int, default=64, help="strana dlaždice v pixelech")
    parser.add_argument("--variants", type=int, default=16, help="počet dlaždic v sadě")
    parser.add_argument("--seed", type=int, default=1, help="seed generátoru")
    parser.add_argument("--base", type=parse_hex, help="základní barva RRGGBB")
    parser.add_argument("--hue", type=float, help="± procenta barevného kola pro odstín")
    parser.add_argument("--contrast", type=float, help="± procenta světlosti")
    parser.add_argument("--coarseness", type=float, help="1 = jemné skvrny, vyšší = větší")
    parser.add_argument("--border", type=int, default=4, help="šířka společného okraje v pixelech")
    parser.add_argument("--out", type=Path, help="složka výstupu, jinak godot/graphics/terrain/<name>")
    parser.add_argument("--preview", type=Path, help="volitelný náhled složené plochy")
    return parser


def main() -> None:
    from generate import TERRAINS

    args = build_parser().parse_args()
    preset = TERRAINS[args.kind]
    generate_surface(
        args.kind,
        name=args.name or preset["name"],
        base=args.base or parse_hex(preset["base"]),
        hue=preset["hue"] if args.hue is None else args.hue,
        contrast=preset["contrast"] if args.contrast is None else args.contrast,
        coarseness=preset["coarseness"] if args.coarseness is None else args.coarseness,
        tile_size=args.tile_size,
        variants=args.variants,
        seed=args.seed,
        border=args.border,
        out=args.out,
        preview=args.preview,
    )


if __name__ == "__main__":
    main()
