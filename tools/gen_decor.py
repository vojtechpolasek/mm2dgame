#!/usr/bin/env python3
"""Průchozí porost pro pohled kolmo shora: trsy trávy, květy, kapradí, houby, rákos, vřes.

Všechny druhy jsou v jednom atlasu, ve hře je kreslí MultiMesh po kusech mapy (ground_decor.gd)
a shader vybere buňku atlasu podle čísla instance. Porost leží na zemi, nemá výšku ani kolizi.

Buňka je CELL px, sprite sedí uprostřed a k okraji buňky nechá PAD px, ať mipmapy
nepřetečou do sousední buňky. Atlas jde do godot/graphics/objects/decor, popis do decor.json.

Příklad:
  py tools/gen_decor.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image

from gen_terrain_tiles import hash_unit, hsv_to_rgb, lerp_rgb, rgb_to_hsv, scale_rgb

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "decor"
PREVIEW = ROOT / "tools" / "preview"
CELL = 64
PAD = 4
COLUMNS = 8

# Druhy porostu. variants je počet buněk, patch jak moc se druh shlukuje (0 rovnoměrně,
# 1 jen v ostrůvcích), scale rozsah zvětšení ve hře.
DECOR = {
    "trava": {"variants": 6, "patch": 0.45, "scale": (0.85, 1.15)},
    "trava_sucha": {"variants": 4, "patch": 0.5, "scale": (0.85, 1.15)},
    "ostrice": {"variants": 4, "patch": 0.4, "scale": (0.9, 1.2)},
    "kvetiny": {"variants": 8, "patch": 0.75, "scale": (0.85, 1.1)},
    "kapradi": {"variants": 4, "patch": 0.6, "scale": (0.85, 1.15)},
    "houby": {"variants": 4, "patch": 0.55, "scale": (0.9, 1.1)},
    "rakos": {"variants": 4, "patch": 0.55, "scale": (0.9, 1.15)},
    "vres": {"variants": 4, "patch": 0.5, "scale": (0.85, 1.15)},
    "vyhonky": {"variants": 4, "patch": 0.65, "scale": (0.9, 1.2)},
}


class Sprite:
    """Průhledné plátno buňky. Kreslí se po pixelech, střed je střed buňky."""

    def __init__(self) -> None:
        self.image = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        self.pixels = self.image.load()
        self.c = CELL / 2

    def inside(self, x: int, y: int) -> bool:
        return PAD <= x < CELL - PAD and PAD <= y < CELL - PAD

    def put(self, x: float, y: float, color: tuple[int, int, int], alpha: float = 1.0) -> None:
        px, py = int(round(x)), int(round(y))
        if not self.inside(px, py) or alpha <= 0:
            return
        old = self.pixels[px, py]
        if alpha >= 1 or old[3] == 0:
            self.pixels[px, py] = (*color, max(old[3], int(alpha * 255)))
            return
        mixed = lerp_rgb(old[:3], color, alpha)
        self.pixels[px, py] = (*mixed, max(old[3], int(alpha * 255)))


def blade(sprite: Sprite, x: float, y: float, angle: float, length: float, dark, tip, bend: float,
          width: int = 1) -> tuple[float, float]:
    """Stéblo od (x, y): tmavé u země, světlá špička. Vrací konec stébla."""
    steps = max(2, int(length))
    for step in range(steps + 1):
        t = step / steps
        px = x + math.cos(angle) * step
        py = y + math.sin(angle) * step
        color = lerp_rgb(dark, tip, t ** 0.8)
        sprite.put(px, py, color)
        if width > 1 and t < 0.5:
            sprite.put(px + math.sin(angle), py - math.cos(angle), scale_rgb(color, 0.9))
        angle += bend
    return x + math.cos(angle) * steps, y + math.sin(angle) * steps


def tuft(sprite: Sprite, rng: random.Random, dark, tip, count: tuple[int, int], length: tuple[float, float],
         spread: float = 2.0, width: int = 1) -> None:
    """Trs stébel rozbíhajících se z malé plochy, shora vypadá jako hvězdice."""
    blades = []
    for _ in range(rng.randint(*count)):
        ox = sprite.c + rng.uniform(-spread, spread)
        oy = sprite.c + rng.uniform(-spread, spread)
        angle = rng.uniform(0, math.tau)
        blades.append((ox, oy, angle, rng.uniform(*length), rng.uniform(-0.06, 0.06), rng.uniform(0.85, 1.12)))
    for ox, oy, angle, size, bend, tone in blades:
        blade(sprite, ox, oy, angle, size, scale_rgb(dark, tone), scale_rgb(tip, tone), bend, width)


def draw_trava(sprite: Sprite, rng: random.Random, index: int) -> None:
    dark = hsv_to_rgb(rng.uniform(96, 108), rng.uniform(0.6, 0.7), rng.uniform(0.34, 0.42))
    tip = hsv_to_rgb(rng.uniform(80, 92), rng.uniform(0.5, 0.6), rng.uniform(0.72, 0.82))
    tuft(sprite, rng, dark, tip, (14, 22), (9, 19), 3.5)


def draw_trava_sucha(sprite: Sprite, rng: random.Random, index: int) -> None:
    dark = hsv_to_rgb(rng.uniform(38, 46), rng.uniform(0.4, 0.5), rng.uniform(0.45, 0.52))
    tip = hsv_to_rgb(rng.uniform(42, 50), rng.uniform(0.3, 0.38), rng.uniform(0.82, 0.9))
    tuft(sprite, rng, dark, tip, (12, 18), (9, 17), 3.0)


def draw_ostrice(sprite: Sprite, rng: random.Random, index: int) -> None:
    dark = hsv_to_rgb(rng.uniform(70, 80), rng.uniform(0.55, 0.65), rng.uniform(0.3, 0.36))
    tip = hsv_to_rgb(rng.uniform(58, 66), rng.uniform(0.45, 0.55), rng.uniform(0.62, 0.7))
    tuft(sprite, rng, dark, tip, (14, 22), (11, 21), 3.0)


FLOWERS = (
    ((246, 246, 240), (236, 190, 40)),
    ((248, 214, 60), (210, 140, 30)),
    ((176, 120, 214), (240, 220, 120)),
    ((214, 52, 40), (40, 30, 30)),
    ((96, 140, 230), (240, 240, 230)),
    ((240, 160, 200), (250, 230, 140)),
)


def draw_kvetiny(sprite: Sprite, rng: random.Random, index: int) -> None:
    """Pár listů a tři až šest květů jedné barvy. Okvětí pět teček kolem středu."""
    petal, middle = FLOWERS[index % len(FLOWERS)]
    leaf_dark = (52, 102, 38)
    leaf_tip = (110, 170, 70)
    tuft(sprite, rng, leaf_dark, leaf_tip, (8, 12), (6, 10), 5.0)
    heads = []
    for _ in range(rng.randint(5, 9)):
        heads.append((sprite.c + rng.uniform(-12, 12), sprite.c + rng.uniform(-12, 12)))
    for x, y in heads:
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            edge = abs(ox) + abs(oy) == 2
            sprite.put(x + ox, y + oy, scale_rgb(petal, 0.88 if edge else 1.0), 0.75 if edge else 1.0)
        sprite.put(x, y, middle)


def draw_kapradi(sprite: Sprite, rng: random.Random, index: int) -> None:
    """Kapradí: pět až osm listů z jednoho místa, na každém střídavé lístky ubývající ke špičce."""
    dark = hsv_to_rgb(rng.uniform(100, 112), 0.65, rng.uniform(0.32, 0.38))
    light = hsv_to_rgb(rng.uniform(86, 96), 0.55, rng.uniform(0.62, 0.72))
    fronds = []
    count = rng.randint(5, 8)
    for i in range(count):
        angle = (i + rng.uniform(0.2, 0.8)) / count * math.tau
        fronds.append((angle, rng.uniform(17, 26), rng.uniform(-0.04, 0.04)))
    for angle, length, bend in fronds:
        x, y = sprite.c, sprite.c
        a = angle
        for step in range(int(length)):
            t = step / length
            sprite.put(x, y, lerp_rgb(dark, light, t * 0.6))
            if step >= 2 and step % 2 == 0:
                side = 1 if (step // 2) % 2 else -1
                reach = max(1, int((1 - t) * 6))
                for r in range(1, reach + 1):
                    lx = x + math.cos(a + side * 1.3) * r
                    ly = y + math.sin(a + side * 1.3) * r
                    sprite.put(lx, ly, lerp_rgb(dark, light, 0.4 + 0.5 * t + 0.1 * r / reach))
            x += math.cos(a)
            y += math.sin(a)
            a += bend


def draw_houby(sprite: Sprite, rng: random.Random, index: int) -> None:
    """Jedna až tři houby: klobouk shora, uprostřed světlejší, muchomůrka s tečkami."""
    red = index % 2 == 1
    cap = (186, 44, 32) if red else hsv_to_rgb(rng.uniform(24, 32), rng.uniform(0.45, 0.6), rng.uniform(0.5, 0.62))
    caps = []
    for _ in range(rng.randint(1, 3)):
        caps.append((sprite.c + rng.uniform(-8, 8), sprite.c + rng.uniform(-8, 8), rng.uniform(3.6, 5.8)))
    for cx, cy, r in caps:
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                d = math.hypot(x - cx, y - cy) / r
                if d > 1:
                    continue
                color = scale_rgb(cap, 1.08 - 0.28 * d * d)
                if red and d < 0.8 and hash_unit(x, y, index * 7) > 0.8:
                    color = (240, 236, 226)
                sprite.put(x, y, color)


def draw_rakos(sprite: Sprite, rng: random.Random, index: int) -> None:
    """Rákos: dlouhé tuhé listy a jedna až dvě hnědé palice na stéblech."""
    dark = (66, 84, 36)
    tip = (168, 164, 96)
    tuft(sprite, rng, dark, tip, (11, 16), (14, 24), 3.0, width=2)
    for _ in range(rng.randint(1, 3)):
        angle = rng.uniform(0, math.tau)
        end = blade(sprite, sprite.c, sprite.c, angle, rng.uniform(12, 19), (90, 96, 50), (130, 124, 70), 0.0)
        for step in range(-3, 4):
            x = end[0] + math.cos(angle) * step
            y = end[1] + math.sin(angle) * step
            sprite.put(x, y, (98, 62, 34) if abs(step) < 3 else (120, 80, 44))
            sprite.put(x - math.sin(angle), y + math.cos(angle), (78, 48, 26))


HEATHER = ((62, 44, 40), (146, 72, 132), (186, 108, 170), (220, 156, 206))


def draw_vres(sprite: Sprite, rng: random.Random, index: int) -> None:
    """Keřík vřesu: hustě tečkovaný chomáč na tmavých stoncích."""
    radius = rng.uniform(9, 13)
    lobes = [rng.uniform(0.75, 1.2) for _ in range(7)]
    spots = []
    for y in range(CELL):
        for x in range(CELL):
            dx = x + 0.5 - sprite.c
            dy = y + 0.5 - sprite.c
            i = (math.atan2(dy, dx) % math.tau) / math.tau * 7
            lobe = lobes[int(i) % 7] + (lobes[(int(i) + 1) % 7] - lobes[int(i) % 7]) * (i - int(i))
            d = math.hypot(dx, dy) / (radius * lobe)
            if d <= 1:
                spots.append((x, y, d))
    for x, y, d in spots:
        roll = hash_unit(x, y, index * 13 + 5)
        if roll > 0.8 + (1 - d) * 0.15:
            continue
        pick = hash_unit(x, y, index * 13 + 9) + (0.2 if d < 0.55 else -0.1)
        color = HEATHER[0] if pick < 0.3 else HEATHER[1] if pick < 0.7 else HEATHER[2] if pick < 0.92 else HEATHER[3]
        sprite.put(x, y, color)


def draw_vyhonky(sprite: Sprite, rng: random.Random, index: int) -> None:
    """Svěží výhonky po požáru: pár krátkých jasně zelených lístků z jednoho nebo dvou míst."""
    for _ in range(rng.randint(1, 2)):
        ox = sprite.c + rng.uniform(-7, 7)
        oy = sprite.c + rng.uniform(-7, 7)
        leaves = [(rng.uniform(0, math.tau), rng.uniform(5, 9)) for _ in range(rng.randint(4, 7))]
        for angle, length in leaves:
            blade(sprite, ox, oy, angle, length, (60, 120, 40), (150, 210, 80), 0.0, width=2)


DRAW = {
    "trava": draw_trava,
    "trava_sucha": draw_trava_sucha,
    "ostrice": draw_ostrice,
    "kvetiny": draw_kvetiny,
    "kapradi": draw_kapradi,
    "houby": draw_houby,
    "rakos": draw_rakos,
    "vres": draw_vres,
    "vyhonky": draw_vyhonky,
}


def generate(seed: int = 1) -> Path:
    sprites: list[Image.Image] = []
    info = {}
    for name, preset in DECOR.items():
        cells = []
        for index in range(int(preset["variants"])):
            rng = random.Random(seed * 7919 + sum(ord(c) for c in name) * 131 + index)
            sprite = Sprite()
            DRAW[name](sprite, rng, index)
            cells.append(len(sprites))
            sprites.append(sprite.image)
        info[name] = {"cells": cells, "patch": float(preset["patch"]), "scale": list(preset["scale"])}
    rows = math.ceil(len(sprites) / COLUMNS)
    atlas = Image.new("RGBA", (COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    for index, image in enumerate(sprites):
        atlas.alpha_composite(image, ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_DIR / "decor.png")
    catalog = {"cell": CELL, "columns": COLUMNS, "rows": rows, "decor": info}
    (OUT_DIR / "decor.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    preview = Image.new("RGB", atlas.size, (0x4F, 0x9A, 0x3C))
    preview.paste(atlas, (0, 0), atlas)
    preview.resize((atlas.width * 3, atlas.height * 3), Image.Resampling.NEAREST).save(PREVIEW / "decor.png")
    print(f"{len(sprites)} spritů porostu -> {OUT_DIR / 'decor.png'}")
    return OUT_DIR


if __name__ == "__main__":
    generate()
