#!/usr/bin/env python3
"""Obrazovka menu. Celá plocha je povrch skály, občas na ní leží materiál.

Světlo a zrno jdou jako u skal v gen_rocks.py. Materiály jsou masky z gen_crystal.py.
Střed zůstává volný, ať je vidět panel menu.

  py tools/gen_menu.py
  py tools/gen_menu.py --seed 4
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

from gen_crystal import MATERIALS, colorize
from gen_terrain_tiles import parse_hex
from gen_trees import hash01, shade

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot" / "graphics" / "menu" / "background.png"
CRYSTAL_DIR = ROOT / "godot" / "graphics" / "objects" / "crystal"

WIDTH = 1920
HEIGHT = 1080
COARSE = 4
# Střed nechává volný panel. Okraj drží materiály v záběru i při širším okně.
ANCHORS = (
    (0.10, 0.16),
    (0.10, 0.50),
    (0.10, 0.84),
    (0.90, 0.18),
    (0.90, 0.52),
    (0.90, 0.84),
    (0.34, 0.10),
    (0.66, 0.10),
    (0.34, 0.90),
    (0.66, 0.90),
)
WARM = parse_hex("746C62")
COOL = parse_hex("5C6358")
DARK = parse_hex("3E3B36")
CRACK = (*shade(parse_hex("2A2724"), 1.0), 255)


def noise(x: float, y: float, salt: int) -> float:
    x0 = math.floor(x)
    y0 = math.floor(y)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    a = hash01(x0, y0, salt)
    b = hash01(x0 + 1, y0, salt)
    c = hash01(x0, y0 + 1, salt)
    d = hash01(x0 + 1, y0 + 1, salt)
    top = a + (b - a) * fx
    bottom = c + (d - c) * fx
    return top + (bottom - top) * fy


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def bumps(rng: random.Random) -> list[tuple[float, float, float, float]]:
    return [
        (rng.uniform(0, WIDTH / COARSE), rng.uniform(0, HEIGHT / COARSE), rng.uniform(10, 26), rng.uniform(0.08, 0.2))
        for _ in range(22)
    ]


def rock(rng: random.Random, salt: int) -> Image.Image:
    cw = math.ceil(WIDTH / COARSE)
    ch = math.ceil(HEIGHT / COARSE)
    knobs = bumps(rng)
    small = Image.new("RGB", (cw, ch))
    pixels = small.load()
    for y in range(ch):
        for x in range(cw):
            wx = (x + 0.5) * COARSE
            wy = (y + 0.5) * COARSE
            broad = noise(wx / 240.0, wy / 240.0, salt)
            mottled = noise(wx / 46.0, wy / 46.0, salt + 2)
            light = max(-1.0, min(1.0, -0.55 * (wx / WIDTH * 2.0 - 1.0) - 0.7 * (wy / HEIGHT * 2.0 - 1.0)))
            lit = light * 0.5 + 0.5
            value = (0.74 + 0.24 * lit) * (0.88 + 0.2 * broad) * (0.9 + 0.14 * mottled)
            for bx, by, radius, strength in knobs:
                dx = x + 0.5 - bx
                dy = y + 0.5 - by
                dist = math.hypot(dx, dy) / radius
                if dist >= 1.0:
                    continue
                dome = (1.0 - dist * dist) * strength
                side = max(-1.0, min(1.0, -(dx + dy) / radius))
                value *= 1.0 + dome * (0.28 + 0.8 * side)
            color = mix(COOL, WARM, broad)
            color = mix(color, DARK, max(0.0, 0.62 - mottled) * 0.55)
            pixels[x, y] = shade(color, min(1.12, max(0.5, value)))
    full = small.resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)
    src = full.tobytes()
    raw = bytearray(WIDTH * HEIGHT * 4)
    cursor = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            grain = (0.9 + 0.16 * hash01(x, y, salt)) * (0.92 + 0.14 * hash01(x // 4, y // 4, salt + 9))
            if hash01(x, y, salt + 3) > 0.975:
                grain *= 0.68
            raw[cursor] = min(255, int(src[cursor // 4 * 3] * grain))
            raw[cursor + 1] = min(255, int(src[cursor // 4 * 3 + 1] * grain))
            raw[cursor + 2] = min(255, int(src[cursor // 4 * 3 + 2] * grain))
            raw[cursor + 3] = 255
            cursor += 4
    image = Image.frombytes("RGBA", (WIDTH, HEIGHT), bytes(raw))
    draw = ImageDraw.Draw(image)
    for _crack in range(18):
        x = rng.uniform(0, WIDTH)
        y = rng.uniform(0, HEIGHT)
        points = [(x, y)]
        angle = rng.uniform(0, math.tau)
        for _step in range(rng.randint(10, 36)):
            angle += rng.uniform(-0.55, 0.55)
            x += math.cos(angle) * rng.uniform(6, 14)
            y += math.sin(angle) * rng.uniform(6, 14)
            points.append((x, y))
        draw.line(points, fill=CRACK, width=rng.choice((1, 2, 2)))
    return image


def place_materials(image: Image.Image, rng: random.Random) -> int:
    masks = {
        "crystal": Image.open(CRYSTAL_DIR / "crystal.png").convert("RGBA"),
        "stone": Image.open(CRYSTAL_DIR / "stone.png").convert("RGBA"),
    }
    names = list(MATERIALS)
    rng.shuffle(names)
    anchors = list(ANCHORS)
    rng.shuffle(anchors)
    placed = 0
    for name, anchor in zip(names, anchors):
        if placed >= 8:
            break
        info = MATERIALS[name]
        scale = rng.uniform(3.0, 4.2)
        if info["shape"] == "crystal":
            scale += 0.35
        swatch = colorize(masks[info["shape"]], info["color"])
        size = max(1, round(swatch.width * scale))
        swatch = swatch.resize((size, size), Image.Resampling.NEAREST)
        swatch = swatch.rotate(rng.uniform(-16, 16), resample=Image.Resampling.NEAREST, expand=True)
        x = anchor[0] * WIDTH + rng.uniform(-36, 36)
        y = anchor[1] * HEIGHT + rng.uniform(-28, 28)
        left = int(round(x - swatch.width / 2))
        top = int(round(y - swatch.height / 2))
        image.alpha_composite(swatch, (left, top))
        placed += 1
    return placed


def main() -> None:
    parser = argparse.ArgumentParser(description="Obrázek pozadí menu.")
    parser.add_argument("--seed", type=int, default=4)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    image = rock(rng, args.seed)
    count = place_materials(image, rng)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    print(f"{OUT.relative_to(ROOT)} {WIDTH}x{HEIGHT}, materialu {count}")


if __name__ == "__main__":
    main()
