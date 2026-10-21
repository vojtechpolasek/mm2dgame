#!/usr/bin/env python3
"""Prameniště řeky pro pohled kolmo shora. Řeka začíná uprostřed tůňky (střed buňky).

Tři typy (kind v presetu):
  kamen   mechová skála kreslená jako skály v gen_rocks.py (preset rock), u její paty
          tůňka, ze které voda vyvěrá. Skála leží v záporném x, řeka ve hře teče do kladného x
          (river.gd natočí uzel podle směru řeky). Vrstvy nad 1 jsou vyšší patra skály.
  mokrad  bahnité místo s několika loužemi a trsy rákosu a ostřice.
  tun     malá tůňka obložená oblázky, na hladině kroužky.
Vrstva 1 je zem s vodou (height 0), další vrstvy jsou, co vyčnívá: patra skály, rákos, oblázky.
Kolem je tmavší mokrá zem, slabě průhledná, do kolize se nepočítá (obrys bere pixely
od OUTLINE_ALPHA v gen_rocks.py). Prameniště překáží jako skála.

Generuje je gen_rocks.py (druh s "spring": True), sám se spustí jen pro náhled:
  py tools/gen_spring.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image

from gen_crack import vnoise
from gen_terrain_tiles import parse_hex
from gen_trees import blank, contact_sheet, crop_square, hash01, mix_rgb, pack_atlas, shade, vary_color

# Voda jako řeka a jezera (river.gdshader, surfaces.json).
DEEP = (36, 94, 120)
WATER = (44, 110, 138)
SHALLOW = (126, 191, 218)
HIGHLIGHT = (190, 226, 238)
WET_EDGE = (66, 58, 44)
# Mokrá zem kolem: průhlednost a jak daleko za vodou (px).
WET_ALPHA = 110
WET_REACH = 16.0
REED = [(104, 128, 58), (128, 140, 66), (86, 108, 50), (150, 146, 84)]
PEBBLE = (150, 144, 134)
# Kamenný pramen: největší poloměr tůňky a jak daleko za ní stojí střed skály (podíl poloměru paty).
POOL_MAX = 42.0
ROCK_OFFSET = 0.62


def canvas_size(preset: dict) -> int:
    reach = float(preset["widths"][1]) / 2 + WET_REACH + 6
    if preset.get("rock"):
        # Skála stojí vedle tůňky, celé její plátno se musí vejít.
        from gen_rocks import canvas_size as rock_canvas

        rock = preset["rock"]
        reach = max(reach, POOL_MAX + float(rock["widths"][1]) * 0.5 * ROCK_OFFSET + rock_canvas(rock) / 2 + 12)
    size = int(math.ceil(reach * 2))
    return size + size % 2


def _blob(rng: random.Random, radius: float, rough: float, lobes: int = 7) -> list[tuple[float, float, float]]:
    """Nepravidelný obrys: součet sinusovek kolem kruhu. Vrací (amplituda, frekvence, fáze)."""
    return [(radius * rough * rng.uniform(0.3, 1.0) / (k + 1), k + 2, rng.uniform(0, math.tau)) for k in range(lobes)]


def _reach(blob: list[tuple[float, float, float]], radius: float, angle: float) -> float:
    return radius + sum(a * math.sin(f * angle + p) for a, f, p in blob)


def _inside(cx: float, cy: float, x: float, y: float, radius: float, blob) -> float:
    """O kolik px je bod uvnitř obrysu (záporné venku)."""
    dx, dy = x - cx, y - cy
    return _reach(blob, radius, math.atan2(dy, dx)) - math.hypot(dx, dy)


def _water(x: float, y: float, depth: float, radius: float, salt: int, rings: bool) -> tuple[int, int, int]:
    """Voda tůňky: depth 0 u břehu, 1 uprostřed."""
    color = mix_rgb(SHALLOW, WATER, min(1.0, depth * 4.0))
    color = mix_rgb(color, DEEP, max(0.0, depth - 0.35) * 1.3)
    ripple = vnoise(x, y, 6.0, salt)
    if ripple > 0.75:
        color = mix_rgb(color, HIGHLIGHT, (ripple - 0.75) * 1.2)
    if rings:
        # Slabé kroužky od vyvěrající vody.
        wave = math.sin(depth * radius * 0.6)
        if wave > 0.9:
            color = mix_rgb(color, HIGHLIGHT, (wave - 0.9) * 2.0)
    return color


def _pool(img: Image.Image, cx: float, cy: float, radius: float, blob, salt: int, rings: bool) -> None:
    """Tůňka s mokrým okrajem a kolem mokrá zem."""
    px = img.load()
    span = int(radius * 1.6 + WET_REACH) + 2
    for y in range(max(0, int(cy - span)), min(img.height, int(cy + span))):
        for x in range(max(0, int(cx - span)), min(img.width, int(cx + span))):
            m = _inside(cx, cy, x + 0.5, y + 0.5, radius, blob)
            m += (vnoise(x, y, 4.0, salt + 1) - 0.5) * 2.0
            if m > 2.0:
                depth = min(1.0, (m - 2.0) / max(radius * 0.8, 1.0))
                px[x, y] = (*_water(x, y, depth, radius, salt, rings), 255)
            elif m > 0.0:
                px[x, y] = (*mix_rgb(WET_EDGE, SHALLOW, 0.25 * m / 2.0), 255)
            elif m > -WET_REACH:
                fade = 1.0 + m / WET_REACH
                old = px[x, y]
                alpha = int(WET_ALPHA * fade * fade)
                if alpha > old[3]:
                    px[x, y] = (*shade(WET_EDGE, 0.8 + 0.3 * hash01(x, y, salt)), alpha)


def _tuft(img: Image.Image, cx: float, cy: float, rng: random.Random, height: float) -> None:
    """Trs rákosu: tenké stébla od středu ven, na konci světlejší."""
    px = img.load()
    for _ in range(rng.randint(7, 13)):
        angle = rng.uniform(0, math.tau)
        length = height * rng.uniform(0.6, 1.0)
        color = rng.choice(REED)
        steps = int(length * 2)
        for s in range(steps):
            t = s / max(steps - 1, 1)
            x = cx + math.cos(angle) * length * t
            y = cy + math.sin(angle) * length * t
            ix, iy = int(x), int(y)
            if 0 <= ix < img.width and 0 <= iy < img.height:
                px[ix, iy] = (*shade(color, 0.75 + 0.45 * t), 255)
                if t < 0.4 and ix + 1 < img.width:
                    px[ix + 1, iy] = (*shade(color, 0.7), 255)


def _pebble(img: Image.Image, cx: float, cy: float, radius: float, color, salt: int) -> None:
    px = img.load()
    for y in range(int(cy - radius) - 1, int(cy + radius) + 2):
        for x in range(int(cx - radius) - 1, int(cx + radius) + 2):
            if not (0 <= x < img.width and 0 <= y < img.height):
                continue
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 1.15)
            if d > radius:
                continue
            lit = 1.05 - 0.35 * ((x + 0.5 - cx) + (y + 0.5 - cy)) / max(radius, 1.0) * 0.5
            c = shade(color, lit * (0.9 + 0.2 * hash01(x, y, salt)))
            if d > radius - 1.2:
                c = shade(c, 0.65)
            px[x, y] = (*c, 255)


def _rock_layers(rock: dict, rng: random.Random, salt: int) -> tuple[dict[int, Image.Image], float, float, float]:
    """Skála stejně jako v gen_rocks.py: patra, plošky, praskliny, hrboly a mech.
    Vrací vrstvy na vlastním plátně, střed paty (x, y) a její poloměr."""
    from gen_rocks import (
        build_shapes,
        bump_count,
        canvas_size as rock_canvas,
        crack_count,
        draw_layer,
        facet_count,
        make_bumps,
        make_facets,
        raster_cracks,
    )

    size = rock_canvas(rock)
    layers = int(rock["layers"])
    shapes = build_shapes(rock, rng, size)
    stone = vary_color(parse_hex(rock["color"]), rng, hue=7, value=0.05)
    moss = vary_color(parse_hex(rock["moss"]), rng, hue=8, value=0.06) if rock.get("moss") else None
    facets = make_facets(rng, shapes[1], facet_count(rng, shapes[1].rx * 2))
    frames = {}
    for layer in range(1, layers + 1):
        shape = shapes[layer]
        cracks = raster_cracks(rng, shape, crack_count(rng, shape.rx * 2))
        bumps = make_bumps(rng, shape, bump_count(rng, shape.rx * 2))
        frames[layer] = draw_layer(
            size,
            shape,
            stone,
            facets,
            cracks,
            bumps,
            0.0,
            rng,
            salt=salt + layer * 17,
            parent=None if layer == 1 else shapes[layer - 1],
            above=None if layer == layers else shapes[layer + 1],
            moss=moss,
        )
    return frames, shapes[1].cx, shapes[1].cy, shapes[1].rx


def draw_spring(preset: dict, rng: random.Random, salt: int) -> dict[int, Image.Image]:
    size = canvas_size(preset)
    c = size / 2
    ground, top = blank(size), blank(size)
    kind = preset["kind"]
    stone = parse_hex(preset.get("color", "8A8172"))
    if kind == "kamen":
        pool_r = rng.uniform(POOL_MAX - 8, POOL_MAX)
        _pool(ground, c, c, pool_r, _blob(rng, pool_r, 0.25), salt, True)
        # Skála za tůňkou (záporné x), pata přesahuje přes její okraj, voda vytéká zpod ní.
        frames, rx, ry, radius = _rock_layers(preset["rock"], rng, salt)
        left = int(round(c - pool_r - radius * ROCK_OFFSET - rx))
        top_y = int(round(c + rng.uniform(-8, 8) - ry))
        out = {1: ground}
        for layer, frame in frames.items():
            if layer == 1:
                ground.alpha_composite(frame, (max(left, 0), max(top_y, 0)), (max(-left, 0), max(-top_y, 0)))
            else:
                image = blank(size)
                image.alpha_composite(frame, (max(left, 0), max(top_y, 0)), (max(-left, 0), max(-top_y, 0)))
                out[layer] = image
        return out
    elif kind == "mokrad":
        reach = float(preset["widths"][1]) * 0.42
        mud = parse_hex(preset.get("mud", "4E4430"))
        blob = _blob(rng, reach, 0.3)
        px = ground.load()
        for y in range(size):
            for x in range(size):
                m = _inside(c, c, x + 0.5, y + 0.5, reach, blob) + (vnoise(x, y, 5.0, salt) - 0.5) * 8
                if m > 0:
                    px[x, y] = (*shade(mud, 0.8 + 0.35 * vnoise(x, y, 3.0, salt + 2)), 255 if m > 3 else int(255 * m / 3))
                elif m > -WET_REACH:
                    fade = 1.0 + m / WET_REACH
                    px[x, y] = (*shade(mud, 0.7), int(WET_ALPHA * fade * fade))
        # Hlavní louže uprostřed (tam začíná řeka) a pár menších okolo.
        pool_r = rng.uniform(15, 19)
        _pool(ground, c, c, pool_r, _blob(rng, pool_r, 0.3), salt, True)
        spots = []
        for _ in range(rng.randint(2, 3)):
            angle = rng.uniform(math.pi * 0.4, math.pi * 1.6)
            dist = rng.uniform(pool_r + 10, reach * 0.75)
            r = rng.uniform(6, 10)
            spots.append((c + math.cos(angle) * dist, c + math.sin(angle) * dist, r))
            _pool(ground, spots[-1][0], spots[-1][1], r, _blob(rng, r, 0.3), salt + 7, False)
        # Rákos kolem, ne do vody a ne ve směru řeky (kladné x).
        for _ in range(rng.randint(6, 9)):
            for _try in range(20):
                angle = rng.uniform(math.pi * 0.35, math.pi * 1.65)
                dist = rng.uniform(pool_r + 4, reach * 0.95)
                x, y = c + math.cos(angle) * dist, c + math.sin(angle) * dist
                if all(math.hypot(x - sx, y - sy) > sr + 3 for sx, sy, sr in spots):
                    _tuft(top, x, y, rng, rng.uniform(10, 17))
                    break
    elif kind == "tun":
        pool_r = rng.uniform(18, 23)
        blob = _blob(rng, pool_r, 0.18)
        _pool(ground, c, c, pool_r, blob, salt, True)
        count = rng.randint(7, 11)
        for i in range(count):
            angle = (i + rng.uniform(-0.3, 0.3)) / count * math.tau
            # Ve směru řeky (kladné x) mezera, voda tam odtéká.
            if abs(math.atan2(math.sin(angle), math.cos(angle))) < 0.55:
                continue
            dist = _reach(blob, pool_r, angle) + rng.uniform(1, 4)
            r = rng.uniform(4, 7)
            color = shade(stone, rng.uniform(0.85, 1.15))
            _pebble(ground, c + math.cos(angle) * dist, c + math.sin(angle) * dist, r + 1, shade(color, 0.6), salt + i)
            _pebble(top, c + math.cos(angle) * dist, c + math.sin(angle) * dist, r, color, salt + i)
    else:
        raise SystemExit(f"neznámý typ prameniště {kind}")
    return {1: ground, 2: top}


def generate_spring(name: str, preset: dict, out_dir: Path, preview_dir: Path, seed: int, count: int) -> list[int]:
    """Vrstvy všech variant do atlasů v out_dir. Vrací šířky uložených buněk."""
    salt = sum(ord(char) for char in name)
    variants = []
    for index in range(count):
        rng = random.Random(seed + salt + index * 7919)
        variants.append(draw_spring(preset, rng, salt + index * 101))
    saved = []
    for layer in range(1, int(preset["layers"]) + 1):
        fitted = crop_square([frames[layer] for frames in variants])
        saved.append(fitted[0].width)
        pack_atlas(fitted).save(out_dir / f"layer_{layer}.png")
    labels = [f"{index:02d}" for index in range(count)]
    ground = parse_hex(preset.get("preview_ground", "5E7A3C"))

    def on_ground(image: Image.Image) -> Image.Image:
        back = Image.new("RGBA", image.size, (*ground, 255))
        back.alpha_composite(image)
        return back

    flat = []
    for frames in variants:
        image = blank(frames[1].width)
        for layer in sorted(frames):
            image.alpha_composite(frames[layer])
        flat.append(on_ground(image))
    contact_sheet(flat, labels, preview_dir / f"{name}.png", 2)
    return saved


if __name__ == "__main__":
    from gen_rocks import ROCKS, generate_rocks, write_rock_info

    for spring in [name for name, preset in ROCKS.items() if preset.get("spring")]:
        generate_rocks(spring, ROCKS[spring])
    print(write_rock_info(ROCKS))
