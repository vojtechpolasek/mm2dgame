#!/usr/bin/env python3
"""Dřevěný most přes řeku pro pohled kolmo shora.

Most leží podél osy x: fošny jdou napříč (svisle v obrázku), po stranách trámy se sloupky
zábradlí. Ve hře ho river.gd natočí podle cesty a natáhne po délce přes šířku řeky, proto
je světlo kolmo shora a ze všech stran stejné a stín na vodě v obrázku není (kreslí ho hra).
Výstup je godot/graphics/objects/bridge/most.png.

Příklad:
  py tools/gen_bridge.py
"""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image

from gen_terrain_tiles import hash_unit, lerp_rgb, scale_rgb

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot" / "graphics" / "objects" / "bridge" / "most.png"
PREVIEW = ROOT / "tools" / "preview" / "most.png"
LENGTH = 320
WIDTH = 150
# Šířka trámu po straně a fošny v px.
BEAM = 13
PLANK = 12
POST_EVERY = 64
WOOD = (138, 100, 62)
WOOD_DARK = (92, 64, 38)


def generate(seed: int = 3) -> Path:
    rng = random.Random(seed)
    image = Image.new("RGBA", (LENGTH, WIDTH), (0, 0, 0, 0))
    pixels = image.load()
    top = BEAM
    bottom = WIDTH - BEAM
    # Fošny: každá jiný odstín, letokruhy podélně, tmavá spára mezi nimi.
    x = 0
    while x < LENGTH:
        width = PLANK + rng.randint(-2, 2)
        tone = rng.uniform(0.86, 1.12)
        shift = rng.randint(-2, 2)
        for px in range(x, min(LENGTH, x + width)):
            for py in range(top - 2 + shift, bottom + 2 + shift):
                if not 0 <= py < WIDTH:
                    continue
                if px == x:
                    color = scale_rgb(WOOD_DARK, 0.6)
                else:
                    grain = hash_unit(px - x, py // 5, x)
                    color = scale_rgb(WOOD, tone * (0.92 + 0.12 * grain))
                    if hash_unit(px, py, 7) > 0.985:
                        color = scale_rgb(color, 0.7)
                pixels[px, py] = (*color, 255)
        # Hřebíky u trámů.
        for ny in (top + 3, bottom - 4):
            pixels[min(LENGTH - 1, x + width // 2), ny] = (60, 58, 56, 255)
        x += width
    # Trámy po stranách: světlý hřbet uprostřed, k oběma hranám tmavší.
    for side_top in (0, bottom):
        for y in range(side_top, side_top + BEAM):
            for px in range(LENGTH):
                t = abs((y - side_top + 0.5) / BEAM - 0.5) * 2.0
                color = lerp_rgb(scale_rgb(WOOD_DARK, 1.25), WOOD_DARK, t)
                color = scale_rgb(color, 0.94 + 0.1 * hash_unit(px // 6, y, side_top))
                pixels[px, y] = (*color, 255)
    # Sloupky zábradlí, shora čtverečky: světlý vršek, tmavší obvod.
    for px in range(10, LENGTH - 8, POST_EVERY):
        for side_top in (0, bottom):
            for y in range(side_top + 1, side_top + BEAM - 1):
                for dx in range(10):
                    inner = 2 <= dx < 8 and side_top + 3 <= y < side_top + BEAM - 3
                    light = 1.2 if inner else 0.95
                    pixels[px + dx, y] = (*scale_rgb(WOOD_DARK, light * 0.9), 255)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    preview = Image.new("RGB", (LENGTH + 40, WIDTH + 48), (44, 110, 138))
    preview.paste(image, (20, 20), image)
    preview.resize((preview.width * 2, preview.height * 2), Image.Resampling.NEAREST).save(PREVIEW)
    print(OUT)
    return OUT


if __name__ == "__main__":
    generate()
