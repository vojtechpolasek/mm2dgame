#!/usr/bin/env python3
"""Lávová puklina pro pohled kolmo shora: klikatá prasklina s odbočkami, na dně žhavá láva.

Vrstvy jdou pod zem jako u dolu (gen_mine.py), posouvají se opačně než skály a puklina
vypadá hluboká:
  1 (0 m)    kůra kolem pukliny se slabou září, uprostřed díra,
  2 (-0,5 m) tmavé stěny prosvícené lávou, uprostřed širší části díra,
  3 (-0,9 m) žhavá láva s kousky ztuhlé kůry.
Kůra okraje je široká, ať hlubší vrstvy posunuté u kraje obrazovky nevykouknou vedle.
Pulzování žáru dělá ve hře shader crack_layer.gdshader.

Překáží jen hrubě: hlavní prasklina jsou tři kapsle, delší odbočka jedna. Kapsle jdou
do capsule.json vedle atlasů a odtud do rocks.json. Ve hře se puklina otočí náhodně.

Generuje ji gen_rocks.py (druh s "crack": True), sám se spustí jen pro náhled:
  py tools/gen_crack.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image

from gen_terrain_tiles import parse_hex
from gen_trees import blank, blit_at, contact_sheet, crop_square, hash01, mix_rgb, pack_atlas, shade

# Posun vrstev v náhledu „u kraje“, stejný jako u skal: px na metr výšky. Puklina je
# mělká, v náhledu je posun třikrát větší, ať je hloubka vidět.
EDGE_SHIFT = (480.0 * 0.0052 * 3, 260.0 * 0.0052 * 3)
# Šířka kůry kolem díry a záře za ní v px. Kůra je širší než největší posun vrstvy -0,9 m
# u kraje obrazovky (asi 5 px), ať láva nevykoukne vedle pukliny.
RIM = 8.0
HALO = 8.0
# Vrstvy pod okrajem sahají o tolik px za díru, ať při posunu nevznikne mezera.
UNDER = 1.0
# Díra ve stěnách je vnitřní podíl šířky. Užší místa díru nemají, láva tam jen prosvítá.
WALL_HOLE = 0.45
WALL_HOLE_MIN = 2.5
LAVA_HOT = (255, 214, 110)
LAVA_DEEP = (176, 38, 12)
WALL = (58, 32, 26)


def vnoise(x: float, y: float, scale: float, salt: int) -> float:
    """Hladký šum 0..1 s buňkou scale px."""
    gx, gy = x / scale, y / scale
    ix, iy = math.floor(gx), math.floor(gy)
    fx, fy = gx - ix, gy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = hash01(ix, iy, salt) + (hash01(ix + 1, iy, salt) - hash01(ix, iy, salt)) * fx
    b = hash01(ix, iy + 1, salt) + (hash01(ix + 1, iy + 1, salt) - hash01(ix, iy + 1, salt)) * fx
    return a + (b - a) * fy


def canvas_size(preset: dict) -> int:
    half = float(preset["length"][1]) / 2 + 110 + RIM + HALO
    size = int(math.ceil(half * 2))
    return size + size % 2


def _jagged(rng: random.Random, start: tuple[float, float], heading: float, length: float, step: float,
            kink: float) -> list[tuple[float, float]]:
    """Lomená čára: rovné kousky, směr se po každém trochu zlomí a táhne zpátky."""
    points = [start]
    x, y = start
    drift = 0.0
    walked = 0.0
    while walked < length:
        part = min(step * rng.uniform(0.7, 1.3), length - walked)
        drift = drift * 0.6 + rng.uniform(-kink, kink)
        x += math.cos(heading + drift) * part
        y += math.sin(heading + drift) * part
        walked += part
        points.append((x, y))
    return points


def _resample(points: list[tuple[float, float]], spacing: float = 1.0) -> list[tuple[float, float, float]]:
    """Body po spacing px s podílem délky t od 0 do 1."""
    total = sum(math.dist(points[i], points[i + 1]) for i in range(len(points) - 1))
    out = []
    walked = 0.0
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        seg = math.dist(a, b)
        n = max(1, int(seg / spacing))
        for k in range(n):
            f = k / n
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, (walked + seg * f) / max(total, 1.0)))
        walked += seg
    out.append((points[-1][0], points[-1][1], 1.0))
    return out


class Plan:
    """Osy hlavní praskliny a odboček, poloviční šířka v každém bodě. Souřadnice od středu."""

    def __init__(self, preset: dict, rng: random.Random) -> None:
        length = rng.uniform(*preset["length"])
        half_max = rng.uniform(*preset["width"]) / 2
        main = _jagged(rng, (-length / 2, 0.0), 0.0, length, 13.0, 0.75)
        # Střed čáry do nuly, ať se kreslí uprostřed plátna.
        mx = sum(p[0] for p in main) / len(main)
        my = sum(p[1] for p in main) / len(main)
        self.main = [(x - mx, y - my) for x, y in main]
        salt = rng.randrange(1, 10000)
        # Šířka se podél praskliny nepravidelně dme a zužuje.
        self.main_half = lambda t: max(0.7, half_max * math.sin(math.pi * t) ** 0.6 * (0.55 + 0.75 * vnoise(t * 7.0, 0.5, 1.0, salt)))
        self.branches: list[tuple[list[tuple[float, float]], float]] = []
        samples = _resample(self.main, 4.0)
        for _ in range(rng.randint(*preset["branches"])):
            at = int(rng.uniform(0.2, 0.8) * (len(samples) - 1))
            x, y, t = samples[at]
            nx, ny, _ = samples[min(len(samples) - 1, at + 2)]
            along = math.atan2(ny - y, nx - x)
            heading = along + rng.choice((-1.0, 1.0)) * rng.uniform(0.5, 1.1)
            line = _jagged(rng, (x, y), heading, rng.uniform(38, 105), 10.0, 0.7)
            self.branches.append((line, self.main_half(t) * rng.uniform(0.45, 0.65)))

    def strokes(self) -> list[tuple[float, float, float]]:
        """Body všech os po 1 px s poloviční šířkou."""
        out = [(x, y, self.main_half(t)) for x, y, t in _resample(self.main)]
        for line, base in self.branches:
            out.extend((x, y, max(0.5, base * (1 - t) ** 0.8)) for x, y, t in _resample(line))
        return out


def _capsule(points: list[tuple[float, float]], half: float) -> list[float]:
    """Kapsle přes úsek čáry: od prvního k poslednímu bodu, poloměr pojme i vybočení."""
    a, b = points[0], points[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    seg = max(math.hypot(dx, dy), 0.001)
    off = max(abs((p[0] - a[0]) * dy - (p[1] - a[1]) * dx) / seg for p in points)
    return [round(v, 1) for v in (a[0], a[1], b[0], b[1], half + off, half + off)]


def capsules(plan: Plan) -> list[list[float]]:
    out = []
    main = plan.main
    thirds = [0, len(main) // 3, 2 * len(main) // 3, len(main) - 1]
    for k in range(3):
        part = main[thirds[k]:thirds[k + 1] + 1]
        t_mid = (thirds[k] + thirds[k + 1]) / 2 / max(len(main) - 1, 1)
        out.append(_capsule(part, plan.main_half(t_mid) * 0.9))
    for line, base in plan.branches:
        length = sum(math.dist(line[i], line[i + 1]) for i in range(len(line) - 1))
        if length >= 60:
            # Jen silnější půlka odbočky, tenká špička nepřekáží.
            out.append(_capsule(line[: max(2, len(line) // 2 + 1)], base * 0.8))
    return out


def _field(plan: Plan, size: int) -> tuple[list[float], list[float]]:
    """Pro každý pixel: o kolik px je uvnitř praskliny (záporné venku) a poloviční šířka tam."""
    margin = [-99.0] * (size * size)
    width = [0.0] * (size * size)
    c = size / 2
    reach = RIM + HALO + 1
    for x, y, half in plan.strokes():
        px, py = x + c, y + c
        r = half + reach
        for iy in range(max(0, int(py - r)), min(size, int(py + r) + 2)):
            for ix in range(max(0, int(px - r)), min(size, int(px + r) + 2)):
                m = half - math.hypot(ix + 0.5 - px, iy + 0.5 - py)
                at = iy * size + ix
                if m > margin[at]:
                    margin[at] = m
                    width[at] = half
    return margin, width


def draw_crack(preset: dict, rng: random.Random, salt: int) -> tuple[dict[int, Image.Image], list[list[float]]]:
    size = canvas_size(preset)
    plan = Plan(preset, rng)
    margin, width = _field(plan, size)
    crust = parse_hex(preset["color"])
    glow = parse_hex(preset["lava"])
    rim, walls, lava = blank(size), blank(size), blank(size)
    rp, wp, lp = rim.load(), walls.load(), lava.load()
    for y in range(size):
        for x in range(size):
            m = margin[y * size + x]
            if m < -(RIM + HALO):
                continue
            half = width[y * size + x]
            # Roztřepená hrana: díra je podle šumu o kus širší nebo užší.
            m += (vnoise(x, y, 3.5, salt + 2) - 0.5) * 2.4 * min(1.0, half / 2.5)
            rim_w = RIM * (0.8 + 0.5 * vnoise(x, y, 7.0, salt + 3))
            grain = hash01(x, y, salt)
            blotch = vnoise(x, y, 5.0, salt + 1)
            # Okraj: kůra kolem díry, za ní slabá záře do popela.
            if m <= 0:
                if m > -rim_w:
                    color = shade(crust, 0.75 + 0.5 * grain * blotch)
                    # Hrana díry je rozžhavená.
                    color = mix_rgb(color, glow, max(0.0, 1 + m / 1.6) * 0.75)
                    rp[x, y] = (*color, 255)
                else:
                    fade = max(0.0, 1 - (-m - rim_w) / HALO)
                    rp[x, y] = (*mix_rgb(crust, glow, 0.55), int(95 * fade * fade))
            if m <= -UNDER:
                continue
            # Stěny: tmavá hornina, k lávě rudne.
            hole = half >= WALL_HOLE_MIN and m > half * (1 - WALL_HOLE)
            if not hole:
                deep = max(0.0, min(1.0, (m + UNDER) / max(half * (1 - WALL_HOLE) + UNDER, 0.1)))
                color = mix_rgb(shade(WALL, 0.7 + 0.45 * grain), glow, deep ** 2 * 0.45)
                wp[x, y] = (*color, 255)
            # Láva: žhavý střed, rudé okraje, kousky tmavé kůry plavou.
            core = max(0.0, min(1.0, m / max(half, 0.5)))
            color = mix_rgb(LAVA_DEEP, glow, min(1.0, core * 1.8))
            color = mix_rgb(color, LAVA_HOT, max(0.0, core - 0.55) * 2.0)
            # Kry ztuhlé kůry na hladině.
            plate = vnoise(x, y, 4.0, salt + 4)
            if plate > 0.72:
                color = mix_rgb(color, (62, 26, 16), min(1.0, (plate - 0.72) * 9) * 0.85)
            lp[x, y] = (*shade(color, 0.92 + 0.12 * grain), 255)
    return {1: rim, 2: walls, 3: lava}, capsules(plan)


def stack(frames: dict[int, Image.Image], heights: dict[int, float], shift: tuple[float, float]) -> Image.Image:
    """Nejhlubší vrstva první, okraj přes ni."""
    image = blank(frames[1].width)
    for layer in sorted(frames, reverse=True):
        blit_at(image, frames[layer], shift[0] * heights[layer], shift[1] * heights[layer])
    return image


def generate_crack(name: str, preset: dict, out_dir: Path, preview_dir: Path, seed: int, count: int) -> list[int]:
    """Vrstvy všech variant do atlasů v out_dir. Vrací šířky uložených buněk."""
    salt = sum(ord(char) for char in name)
    heights = {layer: float(preset["height"][layer]) for layer in (1, 2, 3)}
    variants = []
    shapes = []
    for index in range(count):
        rng = random.Random(seed + salt + index * 7919)
        frames, shape = draw_crack(preset, rng, salt + index * 101)
        variants.append(frames)
        shapes.append(shape)
    (out_dir / "capsule.json").write_text(json.dumps(shapes) + "\n", encoding="utf-8")
    saved = []
    for layer in (1, 2, 3):
        fitted = crop_square([frames[layer] for frames in variants])
        saved.append(fitted[0].width)
        pack_atlas(fitted).save(out_dir / f"layer_{layer}.png")
    labels = [f"{index:02d}" for index in range(count)]
    # Náhled na popelu, ať je vidět záře.
    ground = parse_hex("3B3937")

    def on_ground(image: Image.Image) -> Image.Image:
        back = Image.new("RGBA", image.size, (*ground, 255))
        back.alpha_composite(image)
        return back

    contact_sheet([on_ground(stack(frames, heights, (0.0, 0.0))) for frames in variants], labels, preview_dir / f"{name}.png", 1)
    contact_sheet([on_ground(stack(frames, heights, EDGE_SHIFT)) for frames in variants], labels, preview_dir / f"{name}_kraj.png", 2)
    first = variants[0]
    panels = [on_ground(first[layer]) for layer in (1, 2, 3)] + [on_ground(stack(first, heights, EDGE_SHIFT))]
    contact_sheet(panels, [f"vrstva {layer} · {heights[layer]:g} m" for layer in (1, 2, 3)] + ["u kraje"], preview_dir / f"{name}_layers.png", 2)
    return saved


if __name__ == "__main__":
    from gen_rocks import ROCKS, generate_rocks, write_rock_info

    generate_rocks("puklina", ROCKS["puklina"])
    print(write_rock_info(ROCKS))
