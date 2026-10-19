#!/usr/bin/env python3
"""Jehličí pro jehličnaté stromy: sprity 16 × 16 stejně jako listy v assets/leaves.

Špička míří nahoru, stopka je dole uprostřed, gen_trees je natáčí a tónuje jako list.
  needle1.png  větvička smrku: středová osa a krátké jehlice šikmo do stran
  needle2.png  svazek borovice: dlouhé jehlice z jednoho místa do vějíře

Příklad:
  py tools/gen_needles.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

LEAVES = Path(__file__).resolve().parent / "assets" / "leaves"
SIZE = 16
# Modrozelená paleta, tmavší a chladnější než listí.
DARK = (28, 74, 50)
MID = (40, 98, 64)
LIGHT = (62, 128, 84)
SHINE = (96, 160, 110)
TWIG = (70, 74, 48)


def put(pixels, x: float, y: float, color: tuple[int, int, int]) -> None:
    px, py = int(round(x)), int(round(y))
    if 0 <= px < SIZE and 0 <= py < SIZE:
        pixels[px, py] = (*color, 255)


def spruce() -> Image.Image:
    """Osa od stopky ke špičce, po obou stranách husté krátké jehlice šikmo nahoru.
    Uprostřed jsou nejdelší, ke špičce se zkracují. Levá strana je ke světlu."""
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(2, 14, 2):
        t = (y - 2) / 11
        reach = int(round(1.5 + 3.5 * math.sin(math.pi * (0.2 + 0.8 * t))))
        for side in (-1, 1):
            start = 6 if side < 0 else 9
            for step in range(reach):
                x = start + side * step
                row = y - step // 2
                tip = step == reach - 1
                color = (SHINE if tip else LIGHT) if side < 0 else (LIGHT if tip else MID)
                put(pixels, x, row, color)
                put(pixels, x, row + 1, DARK)
    for y in range(1, 16):
        put(pixels, 7, y, TWIG if y > 12 else MID)
        put(pixels, 8, y, DARK if y <= 12 else TWIG)
    put(pixels, 7, 0, LIGHT)
    return image


def pine() -> Image.Image:
    """Dlouhé jehlice z jednoho místa dole do vějíře, světlejší a žlutozelené."""
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    base = (7.5, 14.5)
    count = 9
    for index in range(count):
        angle = -math.pi / 2 + (index - (count - 1) / 2) * 0.17
        length = 12.5 - abs(index - (count - 1) / 2) * 0.9
        for step in range(int(length) + 1):
            t = step / length
            color = (52, 104, 58) if t < 0.4 else (74, 128, 66) if t < 0.8 else (110, 160, 84)
            if index < count // 2 and t > 0.4:
                color = (min(255, color[0] + 14), min(255, color[1] + 16), min(255, color[2] + 10))
            put(pixels, base[0] + math.cos(angle) * step, base[1] + math.sin(angle) * step, color)
    put(pixels, 7, 15, TWIG)
    put(pixels, 8, 15, TWIG)
    return image


def main() -> None:
    LEAVES.mkdir(parents=True, exist_ok=True)
    spruce().save(LEAVES / "needle1.png")
    pine().save(LEAVES / "needle2.png")
    print(LEAVES / "needle1.png")
    print(LEAVES / "needle2.png")


if __name__ == "__main__":
    main()
