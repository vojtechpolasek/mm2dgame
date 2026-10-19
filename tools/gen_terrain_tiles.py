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
    if kind == "scree":
        paint_scree(field, rng, base, hue_span, contrast, coarseness)
        return field
    if kind == "ash":
        paint_ash(field, rng, base, hue_span, contrast, coarseness)
        return field
    if kind == "swamp":
        paint_swamp(field, rng, base, hue_span, contrast, coarseness)
        return field
    if kind == "heath":
        paint_heath(field, rng, base, hue_span, contrast, coarseness)
        return field
    paint_grass(field, rng, base, hue_span, contrast, coarseness)
    return field


def point_inside(rng: random.Random, size: int, margin: int) -> tuple[int, int] | None:
    margin = max(0, margin)
    if margin * 2 >= size:
        return None
    return rng.randrange(margin, size - margin), rng.randrange(margin, size - margin)


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
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.5 * 0.4)
    paint_grit(field, rng.randrange(1 << 30), 0.07, 0.04)


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
        _paint_dune(field, cx, cy, along, across, wind + rng.uniform(-0.35, 0.35), color, 0.2 if lighter else 0.15)
    paint_ripples(field, fbm(size, 3, rng, 2), crest=0.06, trough=0.05, waves=(2, 3), bend=(1, 1))


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
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.8 * 0.25)

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
                field.blend(cx + ox, cy + oy, color, (1 - dist) ** 1.6 * 0.22)
    paint_ripples(field, fbm(size, 3, rng, 2), crest=0.025, trough=0.035, waves=(2, 3), bend=(1, 1))


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
                field.set_inside(px, py, scale_rgb(field.get(px, py), 0.9))
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


# --- Suť, popel, močál a vřesoviště ---
# Podklad maluje paint_field jako u ostatních povrchů. Větší věci (kameny, louže, trsy) jsou
# předměty z paint_objects, každá dlaždice má vlastní a celé uvnitř.

# Světlo shora zleva, jednotkový vektor ve směru ke světlu.
LIGHT = (-0.6, -0.8)


class Piece:
    """Předmět na dlaždici. layer je pořadí kreslení, draw(plocha, x, y) ho nakreslí na místo."""

    __slots__ = ("x", "y", "layer", "draw")

    def __init__(self, x: float, y: float, layer: int, draw) -> None:
        self.x = x
        self.y = y
        self.layer = layer
        self.draw = draw


def soft_blob(field: Field, cx: float, cy: float, radius: float, color: tuple[int, int, int], strength: float, power: float = 1.6) -> None:
    """Měkká skvrna. Kreslí se dokola přes kraj, podklad dlaždice navazuje sám na sebe."""
    reach = int(math.ceil(radius))
    for oy in range(-reach, reach + 1):
        for ox in range(-reach, reach + 1):
            dist = math.hypot(ox, oy) / radius
            if dist > 1:
                continue
            field.blend(int(cx) + ox, int(cy) + oy, color, (1 - dist) ** power * strength)


def lobed_pixels(cx: float, cy: float, radius: float, rng: random.Random, lobes: int = 8, spread: float = 0.28) -> list[tuple[int, int, float]]:
    """Pixely nepravidelné skvrny a jejich poměrná vzdálenost od středu (0 střed, 1 kraj)."""
    sizes = [rng.uniform(1 - spread, 1 + spread) for _ in range(lobes)]
    reach = int(math.ceil(radius * (1 + spread))) + 1
    out = []
    for py in range(int(cy) - reach, int(cy) + reach + 1):
        for px in range(int(cx) - reach, int(cx) + reach + 1):
            dx = px + 0.5 - cx
            dy = py + 0.5 - cy
            index = (math.atan2(dy, dx) % math.tau) / math.tau * lobes
            i0 = int(index) % lobes
            i1 = (i0 + 1) % lobes
            frac = index - int(index)
            lobe = sizes[i0] + (sizes[i1] - sizes[i0]) * (frac * frac * (3 - 2 * frac))
            dist = math.hypot(dx, dy) / (radius * lobe)
            if dist <= 1:
                out.append((px, py, dist))
    return out


def polygon_pixels(points: list[tuple[float, float]]) -> set[tuple[int, int]]:
    """Pixely, jejichž střed leží v mnohoúhelníku."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    inside = set()
    count = len(points)
    for py in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        sy = py + 0.5
        for px in range(int(math.floor(min(xs))), int(math.ceil(max(xs))) + 1):
            sx = px + 0.5
            hit = False
            j = count - 1
            for i in range(count):
                xi, yi = points[i]
                xj, yj = points[j]
                if (yi > sy) != (yj > sy) and sx < (xj - xi) * (sy - yi) / (yj - yi) + xi:
                    hit = not hit
                j = i
            if hit:
                inside.add((px, py))
    return inside


def facing_light(dx: float, dy: float) -> float:
    """Kosinus mezi směrem od středu a směrem ke světlu, -1 až 1."""
    length = math.hypot(dx, dy)
    if length < 0.001:
        return 0.0
    return (dx * LIGHT[0] + dy * LIGHT[1]) / length


def draw_stone(field: Field, cx: float, cy: float, radius: float, color: tuple[int, int, int], seed: int) -> None:
    """Ostrohranný kámen: dvě plošky lomené hřbetem, nasvícená hrana, stín vpravo dole."""
    rng = random.Random(seed)
    sides = rng.randint(5, 7)
    start = rng.uniform(0, math.tau)
    squash = rng.uniform(0.62, 1.0)
    tilt = rng.uniform(0, math.pi)
    points = []
    for i in range(sides):
        angle = start + math.tau * (i + rng.uniform(-0.3, 0.3)) / sides
        reach = radius * rng.uniform(0.78, 1.1)
        ox = math.cos(angle) * reach
        oy = math.sin(angle) * reach * squash
        points.append((
            cx + ox * math.cos(tilt) - oy * math.sin(tilt),
            cy + ox * math.sin(tilt) + oy * math.cos(tilt),
        ))
    inside = polygon_pixels(points)
    shadow = (24, 22, 20)
    for px, py in inside:
        if (px + 1, py + 1) not in inside:
            field.blend(px + 1, py + 1, shadow, 0.42)
    ridge = rng.uniform(0, math.pi)
    nx, ny = math.cos(ridge), math.sin(ridge)
    shift = rng.uniform(-0.3, 0.3) * radius
    lit = 1 + 0.2 * (nx * LIGHT[0] + ny * LIGHT[1])
    unlit = 1 - 0.2 * (nx * LIGHT[0] + ny * LIGHT[1])
    for px, py in inside:
        dx = px + 0.5 - cx
        dy = py + 0.5 - cy
        factor = lit if dx * nx + dy * ny > shift else unlit
        if any(n not in inside for n in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1))):
            factor *= 1.16 if facing_light(dx, dy) > 0.2 else 0.74
        factor *= 1 + (hash_unit(px, py, seed) - 0.5) * 0.1
        field.set(px, py, scale_rgb(color, factor))


def scatter_scree(rng: random.Random, size: int) -> list[Piece]:
    pieces = []
    for _ in range(90):
        roll = rng.random()
        if roll < 0.5:
            radius = rng.uniform(1.2, 2.2)
        elif roll < 0.82:
            radius = rng.uniform(2.2, 3.4)
        elif roll < 0.97:
            radius = rng.uniform(3.4, 5.4)
        else:
            radius = rng.uniform(5.4, 7.5)
        # Teplejší pískovec i chladnější žula, šedé s nízkou sytostí.
        hue = rng.choice((32.0, 36.0, 28.0, 205.0, 40.0))
        color = hsv_to_rgb(hue, rng.uniform(0.04, 0.14), rng.uniform(0.44, 0.74))
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        seed = rng.randrange(1 << 30)
        # Velké kameny dospod, drobné leží na nich.
        layer = 0 if radius >= 3.0 else 1
        pieces.append(Piece(x, y, layer, lambda f, x, y, r=radius, c=color, s=seed: draw_stone(f, x, y, r, c, s)))
    return pieces


def paint_scree(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    # Hlína mezi kameny a světlejší drť.
    for _ in range(max(4, int(round(8 / coarseness)))):
        color = hsv_to_rgb(base_h + rng.uniform(-hue_span, hue_span), base_s * rng.uniform(1.1, 1.6), base_v * rng.uniform(0.62, 0.78))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(4.0, 8.0) * math.sqrt(coarseness), color, 0.55)
    for _ in range(max(3, int(round(6 / coarseness)))):
        color = hsv_to_rgb(base_h, base_s * 0.6, min(1.0, base_v * rng.uniform(1.1, 1.22)))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(3.0, 6.0) * math.sqrt(coarseness), color, 0.45)
    paint_grit(field, rng.randrange(1 << 30), 0.16, 0.1)


def paint_grit(field: Field, salt: int, dark: float, light: float) -> None:
    """Drť po celé ploše: tmavé škvíry a světlá zrnka se stínem vpravo dole. Navazuje přes kraj."""
    size = field.size
    for y in range(size):
        for x in range(size):
            roll = hash_unit(x, y, salt)
            if roll < dark:
                field.set(x, y, scale_rgb(field.get(x, y), 0.74))
            elif roll > 1 - light:
                field.set(x, y, scale_rgb(field.get(x, y), 1.2))
                field.set(x + 1, y + 1, scale_rgb(field.get(x + 1, y + 1), 0.82))


def draw_charcoal(field: Field, cx: float, cy: float, length: float, width: float, angle: float, seed: int) -> None:
    """Uhlík: podlouhlý, téměř černý, s popraskanou kůrkou a odleskem na horní hraně."""
    ux, uy = math.cos(angle), math.sin(angle)
    vx, vy = -uy, ux
    half_l = length / 2
    half_w = width / 2
    corners = [
        (cx + ux * sx * half_l + vx * sw * half_w, cy + uy * sx * half_l + vy * sw * half_w)
        for sx, sw in ((-1, -1), (1, -1), (1, 1), (-1, 1))
    ]
    inside = polygon_pixels(corners)
    if not inside:
        inside = {(int(cx), int(cy))}
    rng = random.Random(seed)
    crack_every = rng.uniform(1.8, 2.8)
    for px, py in inside:
        if (px + 1, py + 1) not in inside:
            field.blend(px + 1, py + 1, (8, 8, 8), 0.4)
    for px, py in inside:
        dx = px + 0.5 - cx
        dy = py + 0.5 - cy
        along = dx * ux + dy * uy
        color = (27, 25, 24)
        if abs(math.fmod(along + half_l, crack_every)) < 0.55:
            color = (14, 13, 12)
        elif any(n not in inside for n in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1))) and facing_light(dx, dy) > 0.1:
            color = (84, 80, 76)
        field.set(px, py, color)


def draw_ember(field: Field, cx: float, cy: float, seed: int) -> None:
    """Doutnající uhlík: tlumená záře a jasné jádro."""
    rng = random.Random(seed)
    soft_blob(field, cx, cy, rng.uniform(3.0, 4.2), (130, 44, 18), 0.5, 2.0)
    core = [(0, 0)] + rng.sample([(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1)], rng.randint(0, 2))
    for ox, oy in core:
        field.set(int(cx) + ox, int(cy) + oy, (232, 126, 52) if (ox, oy) != (0, 0) else (255, 196, 104))


def scatter_ash(rng: random.Random, size: int) -> list[Piece]:
    pieces = []
    # Kusy uhlí: lomené jako kámen, skoro černé, s mdlým leskem.
    for _ in range(9):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(1.4, 3.4)
        tone = rng.randint(30, 40)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 0, lambda f, x, y, r=radius, t=tone, s=seed: draw_stone(f, x, y, r, (t, t - 2, t - 3), s)))
    # Ohořelé třísky.
    for _ in range(3):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        length = rng.uniform(5.0, 10.0)
        width = rng.uniform(1.6, 2.4)
        angle = rng.uniform(0, math.pi)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 0, lambda f, x, y, l=length, w=width, a=angle, s=seed: draw_charcoal(f, x, y, l, w, a, s)))
    # Doutnající uhlík je vzácný, asi na každé třetí dlaždici.
    if rng.random() < 0.35:
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 2, lambda f, x, y, s=seed: draw_ember(f, x, y, s)))
    return pieces


def paint_ash(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    wind = rng.random() * math.tau
    # Závěje světlejšího popela po větru a černé saze.
    for _ in range(max(3, int(round(6 / coarseness)))):
        along = rng.uniform(10.0, 18.0) * math.sqrt(coarseness)
        color = hsv_to_rgb(base_h, base_s * 0.7, min(1.0, base_v * rng.uniform(1.45, 1.8)))
        _paint_dune(field, rng.randrange(size), rng.randrange(size), along, along * rng.uniform(0.25, 0.4), wind + rng.uniform(-0.3, 0.3), color, 0.6)
    for _ in range(max(3, int(round(6 / coarseness)))):
        color = hsv_to_rgb(base_h, base_s, base_v * rng.uniform(0.45, 0.6))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(4.0, 8.0) * math.sqrt(coarseness), color, 0.55)
    paint_grit(field, rng.randrange(1 << 30), 0.08, 0.05)


def draw_puddle(field: Field, cx: float, cy: float, radius: float, weed: bool, seed: int) -> None:
    """Louže: tmavá voda s bahnitým lemem, odlesk nebe vlevo nahoře, někdy okřehek."""
    rng = random.Random(seed)
    pixels = lobed_pixels(cx, cy, radius, rng, 7, 0.32)
    deep = (30, 42, 38)
    shallow = (52, 64, 54)
    rim = (44, 40, 27)
    glint = (124, 146, 140)
    for px, py, dist in pixels:
        dx = px + 0.5 - cx
        dy = py + 0.5 - cy
        if dist > 0.84:
            field.blend(px, py, rim, 0.8)
            continue
        color = lerp_rgb(deep, shallow, (dist / 0.84) ** 1.6)
        toward = (dx * LIGHT[0] + dy * LIGHT[1]) / radius
        if dist < 0.72 and 0.32 < toward < 0.5 and hash_unit(px, py, seed) < 0.8:
            color = lerp_rgb(color, glint, 0.4)
        if weed and hash_unit(px, py, seed + 7) < 0.14:
            color = (126, 156, 58) if hash_unit(px, py, seed + 9) < 0.6 else (98, 128, 46)
        field.set(px, py, color)


def draw_tuft(field: Field, cx: float, cy: float, seed: int, dark: tuple[int, int, int], tip: tuple[int, int, int], blades: tuple[int, int], length: tuple[float, float]) -> None:
    """Trs stébel shora: stébla se rozbíhají z jednoho místa."""
    rng = random.Random(seed)
    field.blend(int(cx) + 1, int(cy) + 1, (20, 22, 12), 0.5)
    for _ in range(rng.randint(*blades)):
        angle = rng.uniform(0, math.tau)
        steps = int(round(rng.uniform(*length)))
        bend = rng.uniform(-0.12, 0.12)
        for step in range(steps + 1):
            t = step / max(1, steps)
            px = int(round(cx + math.cos(angle) * step))
            py = int(round(cy + math.sin(angle) * step))
            field.set(px, py, lerp_rgb(dark, tip, t))
            angle += bend
    field.set(int(cx), int(cy), scale_rgb(dark, 0.7))


def scatter_swamp(rng: random.Random, size: int) -> list[Piece]:
    pieces = []
    for _ in range(rng.randint(0, 3)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(4.0, 10.5)
        weed = rng.random() < 0.45
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 0, lambda f, x, y, r=radius, w=weed, s=seed: draw_puddle(f, x, y, r, w, s)))
    for _ in range(rng.randint(8, 12)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        seed = rng.randrange(1 << 30)
        reed = rng.random() < 0.4
        dark = (58, 70, 30) if reed else (70, 86, 36)
        tip = (164, 158, 92) if reed else (138, 150, 70)
        pieces.append(Piece(x, y, 1, lambda f, x, y, s=seed, d=dark, t=tip, r=reed: draw_tuft(
            f, x, y, s, d, t, (7, 11) if r else (5, 8), (4.0, 7.5) if r else (2.5, 5.0))))
    return pieces


def paint_swamp(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    # Mech a ostřice v zelenějších polštářích, mokré bahno v tmavších.
    for _ in range(max(4, int(round(8 / coarseness)))):
        color = hsv_to_rgb(base_h + rng.uniform(12, 26), min(1.0, base_s * rng.uniform(1.1, 1.35)), min(1.0, base_v * rng.uniform(1.05, 1.25)))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(5.0, 9.0) * math.sqrt(coarseness), color, 0.6)
    for _ in range(max(3, int(round(6 / coarseness)))):
        color = hsv_to_rgb(base_h - rng.uniform(0, 8), base_s * rng.uniform(0.8, 1.0), base_v * rng.uniform(0.6, 0.72))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(4.0, 7.0) * math.sqrt(coarseness), color, 0.55)


HEATHER = ((66, 50, 46), (110, 66, 98), (138, 90, 124), (162, 116, 148))
HEATHER_DRY = ((70, 56, 44), (110, 92, 72), (132, 112, 88), (150, 128, 100))
BILBERRY = ((56, 74, 38), (72, 94, 44), (92, 116, 54), (112, 134, 64))


def draw_clump(field: Field, cx: float, cy: float, radius: float, palette: tuple, fill: float, seed: int) -> None:
    """Keřík shora: hustě tečkovaný, tmavý spodek prosvítá, stín vpravo dole."""
    rng = random.Random(seed)
    pixels = lobed_pixels(cx, cy, radius, rng, 7, 0.3)
    spots = {(px, py) for px, py, _ in pixels}
    for px, py, _ in pixels:
        if (px + 1, py + 1) not in spots:
            field.blend(px + 1, py + 1, (30, 24, 20), 0.35)
    for px, py, dist in pixels:
        roll = hash_unit(px, py, seed)
        if roll > fill + (1 - dist) * 0.15:
            continue
        toward = facing_light(px + 0.5 - cx, py + 0.5 - cy) * dist
        pick = hash_unit(px, py, seed + 3) + toward * 0.35 - dist * 0.15
        if pick < 0.3:
            color = palette[0]
        elif pick < 0.68:
            color = palette[1]
        elif pick < 0.9:
            color = palette[2]
        else:
            color = palette[3]
        field.set(px, py, color)


def scatter_heath(rng: random.Random, size: int) -> list[Piece]:
    pieces = []
    for _ in range(10):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(3.5, 6.5)
        seed = rng.randrange(1 << 30)
        palette = HEATHER_DRY if rng.random() < 0.22 else HEATHER
        pieces.append(Piece(x, y, 0, lambda f, x, y, r=radius, p=palette, s=seed: draw_clump(f, x, y, r, p, 0.72, s)))
    for _ in range(4):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(2.5, 4.5)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 1, lambda f, x, y, r=radius, s=seed: draw_clump(f, x, y, r, BILBERRY, 0.6, s)))
    return pieces


def smooth01(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def paint_heath(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    size = field.size
    # Olivové trávy a rašelina mezi keříky.
    for _ in range(max(4, int(round(8 / coarseness)))):
        color = hsv_to_rgb(rng.uniform(52, 64), rng.uniform(0.36, 0.46), rng.uniform(0.4, 0.48))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(5.0, 9.0) * math.sqrt(coarseness), color, 0.55)
    for _ in range(max(3, int(round(5 / coarseness)))):
        color = hsv_to_rgb(rng.uniform(18, 28), rng.uniform(0.3, 0.4), rng.uniform(0.26, 0.32))
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(4.0, 7.0) * math.sqrt(coarseness), color, 0.5)
    # Vřes a borůvčí tečkami po celé ploše. Kde je vřes hustší, rozhoduje šum, který navazuje přes kraj.
    zone = fbm(size, 4, rng, 2)
    salt = rng.randrange(1 << 30)
    for y in range(size):
        for x in range(size):
            roll = hash_unit(x, y, salt)
            # Hustý vřes ve skvrnách, mezi nimi tráva a rašelina. Tečky jdou po dvojicích pixelů.
            heather = smooth01((zone[y][x] - 0.32) * 2.6) * 0.82
            pick = hash_unit(x // 2, y, salt + 1) * 0.6 + hash_unit(x, y, salt + 5) * 0.4
            if roll < heather:
                palette = HEATHER_DRY if hash_unit(x // 3, y // 3, salt + 2) < 0.2 else HEATHER
                field.set(x, y, palette[0] if pick < 0.35 else palette[1] if pick < 0.75 else palette[2] if pick < 0.95 else palette[3])
            elif roll < heather + 0.18:
                field.set(x, y, BILBERRY[0] if pick < 0.4 else BILBERRY[1] if pick < 0.8 else BILBERRY[2])


# --- Tráva, hlína, poušť a sníh ---

def paint_grass(field: Field, rng: random.Random, base: tuple[int, int, int], hue_span: float, contrast: float, coarseness: float) -> None:
    """Tráva: světlejší a tmavší chomáče a přes ně hustá stébla. Všechno navazuje přes kraj."""
    size = field.size
    base_h, base_s, base_v = rgb_to_hsv(*base)
    for _ in range(max(8, int(round(16 / coarseness)))):
        lighter = rng.random() < 0.5
        color = hsv_to_rgb(
            base_h + (rng.uniform(-hue_span, -hue_span * 0.3) if lighter else rng.uniform(0, hue_span)),
            min(1.0, base_s * (rng.uniform(0.85, 1.0) if lighter else rng.uniform(1.0, 1.15))),
            min(1.0, base_v * (rng.uniform(1.06, 1.16) if lighter else rng.uniform(0.82, 0.92))),
        )
        soft_blob(field, rng.randrange(size), rng.randrange(size), rng.uniform(3.0, 6.5) * math.sqrt(coarseness), color, 0.6, 1.4)
    # Stébla: tmavší u země, světlejší špička. Směr je náhodný, shora se tráva rozkládá na všechny strany.
    for _ in range(int(size * size * 0.2)):
        x = rng.randrange(size)
        y = rng.randrange(size)
        angle = rng.uniform(0, math.tau)
        length = rng.randint(2, 4)
        root = scale_rgb(field.get(x, y), rng.uniform(0.74, 0.86))
        tip = scale_rgb(field.get(x, y), rng.uniform(1.08, 1.22))
        for step in range(length):
            t = step / max(1, length - 1)
            field.set(int(round(x + math.cos(angle) * step)), int(round(y + math.sin(angle) * step)), lerp_rgb(root, tip, t))


def draw_flowers(field: Field, cx: float, cy: float, seed: int) -> None:
    """Pár květů jednoho druhu: světlé tečky se žlutým středem, mezi nimi tmavší lístky."""
    rng = random.Random(seed)
    petal = rng.choice(((240, 240, 232), (244, 214, 74), (196, 160, 222), (236, 236, 236)))
    for _ in range(rng.randint(3, 6)):
        x = int(cx + rng.uniform(-3.5, 3.5))
        y = int(cy + rng.uniform(-3.5, 3.5))
        field.blend(x + 1, y + 1, (40, 70, 28), 0.5)
        for ox, oy in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)):
            field.set(x + ox, y + oy, petal)
        field.set(x, y, (232, 180, 40) if petal != (244, 214, 74) else (200, 120, 30))


def scatter_grass(rng: random.Random, size: int) -> list[Piece]:
    pieces = []
    for _ in range(rng.randint(5, 8)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 0, lambda f, x, y, s=seed: draw_tuft(f, x, y, s, (46, 96, 34), (128, 182, 74), (7, 11), (3.0, 5.5))))
    # Květy jen občas, ať louka nevypadá jako vzor.
    if rng.random() < 0.3:
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 1, lambda f, x, y, s=seed: draw_flowers(f, x, y, s)))
    return pieces


def draw_leaf(field: Field, cx: float, cy: float, length: float, angle: float, color: tuple[int, int, int], seed: int) -> None:
    """Spadlý list: lístek ze dvou oblouků, tmavší žilka, stín vpravo dole."""
    ux, uy = math.cos(angle), math.sin(angle)
    half = length / 2
    width = length * 0.36
    reach = int(math.ceil(half)) + 1
    pixels = []
    for oy in range(-reach, reach + 1):
        for ox in range(-reach, reach + 1):
            along = (ox * ux + oy * uy) / half
            across = (-ox * uy + oy * ux) / width
            if abs(along) <= 1 and abs(across) <= 1 - along * along:
                pixels.append((int(cx) + ox, int(cy) + oy, across))
    spots = {(px, py) for px, py, _ in pixels}
    for px, py, _ in pixels:
        if (px + 1, py + 1) not in spots:
            field.blend(px + 1, py + 1, (30, 22, 14), 0.35)
    for px, py, across in pixels:
        factor = 0.8 if abs(across) < 0.18 else 1.0 + 0.08 * across
        factor *= 1 + (hash_unit(px, py, seed) - 0.5) * 0.12
        field.set(px, py, scale_rgb(color, factor))


def draw_twig(field: Field, cx: float, cy: float, length: float, angle: float, seed: int) -> None:
    """Větvička: tenká zahnutá čára se světlejší horní hranou a odbočkou."""
    rng = random.Random(seed)
    bend = rng.uniform(-0.08, 0.08)
    x = cx - math.cos(angle) * length / 2
    y = cy - math.sin(angle) * length / 2
    dark = (58, 40, 26)
    light = (112, 86, 60)
    fork = rng.randint(2, max(2, int(length) - 2))
    for step in range(int(length)):
        px, py = int(round(x)), int(round(y))
        field.blend(px + 1, py + 1, (30, 20, 12), 0.35)
        field.set(px, py, dark)
        field.set(px, py - 1, lerp_rgb(field.get(px, py - 1), light, 0.5))
        if step == fork:
            side = angle + rng.choice((-1, 1)) * 0.8
            for twig in range(1, rng.randint(2, 4)):
                field.set(int(round(px + math.cos(side) * twig)), int(round(py + math.sin(side) * twig)), dark)
        x += math.cos(angle)
        y += math.sin(angle)
        angle += bend


LITTER = ((150, 104, 44), (124, 78, 36), (168, 128, 60), (110, 64, 40), (132, 120, 56))


def scatter_dirt(rng: random.Random, size: int) -> list[Piece]:
    """Lesní půda: oblázky, spadané listí a větvičky."""
    pieces = []
    for _ in range(rng.randint(6, 10)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(1.2, 2.6)
        color = hsv_to_rgb(rng.uniform(25, 38), rng.uniform(0.08, 0.2), rng.uniform(0.46, 0.66))
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 0, lambda f, x, y, r=radius, c=color, s=seed: draw_stone(f, x, y, r, c, s)))
    for _ in range(rng.randint(3, 6)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        length = rng.uniform(5.5, 8.5)
        angle = rng.uniform(0, math.tau)
        color = rng.choice(LITTER)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 1, lambda f, x, y, l=length, a=angle, c=color, s=seed: draw_leaf(f, x, y, l, a, c, s)))
    for _ in range(rng.randint(0, 2)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        length = rng.uniform(6.0, 12.0)
        angle = rng.uniform(0, math.tau)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 2, lambda f, x, y, l=length, a=angle, s=seed: draw_twig(f, x, y, l, a, s)))
    return pieces


def paint_ripples(
    field: Field,
    strength: list[list[float]],
    crest: float = 0.07,
    trough: float = 0.06,
    waves: tuple[int, int] = (3, 5),
    bend: tuple[int, int] = (1, 2),
) -> None:
    """Čeřiny od větru. waves je počet vln přes dlaždici po x a y, ohyb bend taky v celých vlnách,
    takže vzor na kraji navazuje sám na sebe. strength (0 až 1, navazující šum) čeřiny místy utlumí."""
    size = field.size
    for y in range(size):
        row = strength[y]
        for x in range(size):
            u = (waves[0] * x + waves[1] * y) / size
            warp = 0.35 * math.sin(math.tau * (bend[0] * x + bend[1] * y) / size)
            phase = math.tau * (u + warp / math.tau * 2)
            wave = math.sin(phase) + 0.35 * math.sin(phase * 2)
            fade = smooth01((row[x] - 0.25) * 2.2)
            if wave > 0.9:
                factor = 1 + crest * fade * min(1.0, (wave - 0.9) * 2.5)
            elif wave < -0.4:
                factor = 1 - trough * fade * min(1.0, (-0.4 - wave) * 1.6)
            else:
                continue
            field.set(x, y, scale_rgb(field.get(x, y), factor))


def scatter_desert(rng: random.Random, size: int) -> list[Piece]:
    pieces = []
    for _ in range(rng.randint(0, 3)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(1.1, 2.2)
        color = hsv_to_rgb(rng.uniform(26, 36), rng.uniform(0.18, 0.32), rng.uniform(0.6, 0.78))
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 0, lambda f, x, y, r=radius, c=color, s=seed: draw_stone(f, x, y, r, c, s)))
    # Suchý trs trávy je vzácný.
    if rng.random() < 0.18:
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        seed = rng.randrange(1 << 30)
        pieces.append(Piece(x, y, 1, lambda f, x, y, s=seed: draw_tuft(f, x, y, s, (150, 126, 72), (214, 192, 136), (6, 9), (3.0, 5.0))))
    return pieces


OBJECTS = {
    "grass": scatter_grass,
    "dirt": scatter_dirt,
    "desert": scatter_desert,
    "scree": scatter_scree,
    "ash": scatter_ash,
    "swamp": scatter_swamp,
    "heath": scatter_heath,
}


class Probe:
    """Náhradní plocha: nic nekreslí, jen si pamatuje, kam by předmět sáhl."""

    def __init__(self, field: Field) -> None:
        self.field = field
        self.lo = [10**9, 10**9]
        self.hi = [-(10**9), -(10**9)]

    def _touch(self, x: int, y: int) -> None:
        self.lo[0] = min(self.lo[0], x)
        self.lo[1] = min(self.lo[1], y)
        self.hi[0] = max(self.hi[0], x)
        self.hi[1] = max(self.hi[1], y)

    def get(self, x: int, y: int) -> tuple[int, int, int]:
        return self.field.get(x, y)

    def set(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        self._touch(x, y)

    def blend(self, x: int, y: int, color: tuple[int, int, int], alpha: float) -> None:
        if alpha > 0:
            self._touch(x, y)


def paint_objects(tile: Field, kind: str, seed: int) -> None:
    """Předměty dlaždice. Každý leží celý uvnitř, i se stínem.

    Společný okraj dlaždic je podklad vzoru, předmět přes spoj proto pokračovat nemůže.
    Předmět, který by přes kraj přetekl, se přisune dovnitř, ať u kraje nevzniká prázdný pás.
    """
    scatter = OBJECTS.get(kind)
    if scatter is None:
        return
    size = tile.size
    pieces = scatter(random.Random(seed), size)
    pieces.sort(key=lambda piece: piece.layer)
    for piece in pieces:
        probe = Probe(tile)
        piece.draw(probe, piece.x, piece.y)
        width = probe.hi[0] - probe.lo[0]
        height = probe.hi[1] - probe.lo[1]
        if width < 0 or width >= size or height >= size:
            continue
        dx = max(0, -probe.lo[0]) - max(0, probe.hi[0] - (size - 1))
        dy = max(0, -probe.lo[1]) - max(0, probe.hi[1] - (size - 1))
        piece.draw(tile, piece.x + dx, piece.y + dy)


def paint_specks(field: Field, rng: random.Random, kind: str, coarseness: float, allow=None, density: float = 1.0) -> None:
    """Drobné tečky: drť, zrnka popela, semínka. Jen uvnitř dlaždice."""
    size = field.size
    count = max(4, int(round(30 / coarseness * density)))
    light, dark = {
        "grass": (1.25, 0.7),
        "dirt": (1.22, 0.62),
        "desert": (1.12, 0.8),
        "scree": (1.25, 0.6),
        "ash": (1.9, 0.55),
        "swamp": (1.3, 0.6),
        "heath": (1.25, 0.65),
    }[kind]
    placed = 0
    tries = 0
    while placed < count and tries < count * 12:
        tries += 1
        x = rng.randrange(size)
        y = rng.randrange(size)
        if allow is not None and not allow(x, y):
            continue
        factor = dark if rng.random() < 0.6 else light
        field.set_inside(x, y, scale_rgb(field.get(x, y), factor))
        placed += 1


def paint_marks(field: Field, rng: random.Random, kind: str, coarseness: float, allow=None, density: float = 1.0) -> None:
    if kind == "snow":
        paint_snow_marks(field, rng, coarseness, allow, density)
    elif kind == "water":
        paint_water_marks(field, rng, coarseness, allow, density)
    else:
        paint_specks(field, rng, kind, coarseness, allow, density)


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
        paint_objects(tile, kind, variant_seed + 77)
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
