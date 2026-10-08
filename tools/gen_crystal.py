#!/usr/bin/env python3
"""Dva vzory shora, bez barvy. Godot je obarví podle materiálu.

Krystal je broušený kámen. Oblázek je měkčí hruda pro horniny.
R je světlost, G semínka odlesku (jas = fáze bliknutí), B okraj, A krytí.
Semínko je kolečko. Hvězdičku s paprsky kreslí shader krystalu.
Body 1 jsou nejběžnější, body 100 nejvzácnější. Počet jezírek se z nich počítá ve hře.

  py tools/gen_crystal.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "crystal"
PREVIEW = ROOT / "tools" / "preview"
SHADER = "res://shaders/crystal.gdshader"

CELL = 32
SS = 4
# Konečný poloměr před hrboly. Ústa jezírka mají 28 px, tři kameny se do nich vejdou.
RADIUS = 12.6 * SS

# Stěny odshora po směru hodin. Číslo je násobek poloměru a světlost.
CRYSTAL_FACETS = (
    (1.00, 210),
    (0.84, 118),
    (1.06, 232),
    (0.90, 96),
    (1.02, 186),
    (0.80, 142),
    (0.96, 168),
)
STONE_FACETS = (
    (1.00, 176),
    (0.94, 158),
    (1.06, 188),
    (0.90, 146),
    (1.02, 170),
    (0.88, 140),
    (1.08, 184),
    (0.92, 152),
    (0.98, 166),
)
# Jas semínek je fáze. Po sRGB převodu v shaderu pořád zůstanou nad prahem.
CRYSTAL_SPARKS = (255, 188, 128, 84)
STONE_SPARKS = (210, 150, 96)

# title je název pro hráče (nápis nad jezírkem, HUD). Body určují skóre, vzácnost jezírek
# jde podle pořadí materiálu.
# monster je druh příšery z gen_monsters.MONSTERS. Příšera má tělo v barvě color a kresbu
# v monster_accent, jinak v glint. monster_scale zvětší příšeru dražšího materiálu ve skupině.
# Skupiny jdou od nejméně po nejvíc nebezpečné: pavouk, vlk, tyranosaurus, ptakoještěr.
# Ptakoještěr letí přímo přes všechno, proto hlídá nejvzácnější materiály.
MATERIALS = {
    "piskovec": {"title": "Pískovec", "shape": "stone", "points": 1, "color": "C4A56A", "sparkle": 0.10, "glint": "F0E0B8",
                 "monster": "pavouk", "monster_scale": 1.0},
    "sira": {"title": "Síra", "shape": "stone", "points": 2, "color": "D6C43A", "sparkle": 0.18, "glint": "FFF3A8",
             "monster": "pavouk", "monster_accent": "4A3A18", "monster_scale": 1.05},
    "lavovy": {"title": "Lávový kámen", "shape": "stone", "points": 8, "color": "6A332C", "sparkle": 0.24, "glint": "FF7848",
               "monster": "pavouk", "monster_scale": 1.1},
    "grafit": {"title": "Grafit", "shape": "stone", "points": 10, "color": "1A1C1E", "sparkle": 0.0, "glint": "3A3A3A",
               "monster": "pavouk", "monster_accent": "6E767E", "monster_scale": 1.15},
    "magnetit": {"title": "Magnetit", "shape": "stone", "points": 12, "color": "4A5158", "sparkle": 0.38, "glint": "E4E8EE",
                 "monster": "vlk", "monster_scale": 1.0},
    "kremen": {"title": "Křemen", "shape": "stone", "points": 15, "color": "E6D6B8", "sparkle": 0.55, "glint": "FFFFFF",
               "monster": "vlk", "monster_accent": "8C7458", "monster_scale": 1.08},
    "stribro": {"title": "Stříbro", "shape": "crystal", "points": 21, "color": "A8B4C6", "sparkle": 1.0, "glint": "FFFFFF",
                "monster": "vlk", "monster_accent": "4E5A6C", "monster_scale": 1.15},
    "jantar": {"title": "Jantar", "shape": "crystal", "points": 30, "color": "B4621C", "sparkle": 0.62, "glint": "FFE1B0",
               "monster": "tyranosaurus", "monster_accent": "5A2410", "monster_scale": 1.0},
    "smaragd": {"title": "Smaragd", "shape": "crystal", "points": 42, "color": "1E8A45", "sparkle": 0.80, "glint": "E7FFE8",
                "monster": "tyranosaurus", "monster_accent": "E2B33A", "monster_scale": 1.08},
    "zlato": {"title": "Zlato", "shape": "crystal", "points": 62, "color": "ECC420", "sparkle": 0.80, "glint": "FFF0A8",
              "monster": "tyranosaurus", "monster_accent": "B8302A", "monster_scale": 1.15},
    "rubin": {"title": "Rubín", "shape": "crystal", "points": 78, "color": "C42030", "sparkle": 0.92, "glint": "FFE8E0",
              "monster": "ptakojester", "monster_scale": 1.0},
    "safir": {"title": "Safír", "shape": "crystal", "points": 90, "color": "2A5BD7", "sparkle": 1.15, "glint": "E4EEFF",
              "monster": "ptakojester", "monster_scale": 1.08},
    "diamant": {"title": "Diamant", "shape": "crystal", "points": 100, "color": "D7E7F6", "sparkle": 1.40, "glint": "FFFFFF",
                "monster": "ptakojester", "monster_accent": "8098B4", "monster_scale": 1.15},
}


def parse_hex(text: str) -> tuple[int, int, int]:
    value = int(text, 16)
    return (value >> 16) & 255, (value >> 8) & 255, value & 255


def outline(facets: tuple[tuple[float, int], ...]) -> list[tuple[float, float]]:
    center = CELL * SS / 2
    points = []
    for index, (mul, _shade) in enumerate(facets):
        angle = -math.pi / 2 + index / len(facets) * math.tau
        points.append(
            (
                center + math.cos(angle) * RADIUS * mul,
                center + math.sin(angle) * RADIUS * mul,
            )
        )
    return points


def blend(a: tuple[float, float], b: tuple[float, float], t: float) -> tuple[float, float]:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def snap_pixel(value: float) -> float:
    pixel = round(value / SS - 0.5)
    return (pixel + 0.5) * SS


def draw_mask(
    facets: tuple[tuple[float, int], ...],
    sparks: tuple[int, ...],
    cap: int,
) -> Image.Image:
    size = CELL * SS
    red = Image.new("L", (size, size), 0)
    green = Image.new("L", (size, size), 0)
    blue = Image.new("L", (size, size), 0)
    alpha = Image.new("L", (size, size), 0)
    points = outline(facets)
    center = (size / 2 + 1.5 * SS, size / 2 - 2.2 * SS)
    ImageDraw.Draw(alpha).polygon(points, fill=255)
    red_draw = ImageDraw.Draw(red)
    for index, (_mul, shade) in enumerate(facets):
        nxt = points[(index + 1) % len(points)]
        red_draw.polygon((center, points[index], nxt), fill=shade)
    inner = [blend(center, point, 0.40) for point in points]
    red_draw.polygon(inner, fill=min(cap, 250))
    crown = [blend(center, point, 0.16) for point in points]
    red_draw.polygon(crown, fill=cap)
    rim = ImageDraw.Draw(blue)
    rim.line(points + [points[0]], fill=210, width=SS + 2, joint="curve")
    inner_rim = [blend((size / 2, size / 2), point, 0.78) for point in points]
    rim.line(inner_rim + [inner_rim[0]], fill=120, width=max(SS - 1, 1), joint="curve")
    spark_draw = ImageDraw.Draw(green)
    for index, value in enumerate(sparks):
        point = blend(points[index], points[(index + 2) % len(points)], 0.42)
        x, y = snap_pixel(point[0]), snap_pixel(point[1])
        radius = SS * 1.35
        # Střed pro shader. Vidět je hvězdička, ne tohle kolečko.
        spark_draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=value)
    return downsample(red, green, blue, alpha)


def downsample(red: Image.Image, green: Image.Image, blue: Image.Image, alpha: Image.Image) -> Image.Image:
    src_r, src_g, src_b, src_a = red.load(), green.load(), blue.load(), alpha.load()
    out = Image.new("RGBA", (CELL, CELL))
    dst = out.load()
    for y in range(CELL):
        for x in range(CELL):
            sum_r = sum_g = sum_b = sum_a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px, py = x * SS + sx, y * SS + sy
                    cover = src_a[px, py]
                    sum_a += cover
                    sum_r += src_r[px, py] * cover
                    sum_g += src_g[px, py] * cover
                    sum_b += src_b[px, py] * cover
            if sum_a <= 0.0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            dst[x, y] = (
                round(sum_r / sum_a),
                round(sum_g / sum_a),
                round(sum_b / sum_a),
                round(sum_a / (SS * SS)),
            )
    return out


def opaque_radius(image: Image.Image) -> float:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    cx = image.width / 2
    cy = image.height / 2
    best = 0.0
    for y in range(image.height):
        for x in range(image.width):
            if pixels[x, y] < 128:
                continue
            best = max(best, math.hypot(x + 0.5 - cx, y + 0.5 - cy))
    return round(best, 2)


def colorize(mask: Image.Image, hex_color: str) -> Image.Image:
    color = parse_hex(hex_color)
    source = mask.load()
    out = Image.new("RGBA", mask.size)
    target = out.load()
    for y in range(mask.height):
        for x in range(mask.width):
            red, _green, blue, cover = source[x, y]
            shade = 0.32 + (1.18 - 0.32) * (red / 255.0)
            rgb = [0, 0, 0]
            for channel in range(3):
                value = color[channel] * shade + color[channel] * (blue / 255.0) * 0.22
                rgb[channel] = max(0, min(255, round(value)))
            target[x, y] = (rgb[0], rgb[1], rgb[2], cover)
    return out


def write_preview(masks: dict[str, Image.Image]) -> None:
    scale = 5
    pad = 8
    cell = CELL * scale
    sheet = Image.new("RGBA", (pad + (cell + pad) * len(MATERIALS), pad * 2 + cell), (28, 32, 30, 255))
    for index, info in enumerate(MATERIALS.values()):
        swatch = colorize(masks[info["shape"]], info["color"]).resize((cell, cell), Image.Resampling.NEAREST)
        sheet.alpha_composite(swatch, (pad + index * (cell + pad), pad))
    PREVIEW.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW / "crystal.png")


def main() -> None:
    masks = {
        "crystal": draw_mask(CRYSTAL_FACETS, CRYSTAL_SPARKS, 255),
        "stone": draw_mask(STONE_FACETS, STONE_SPARKS, 214),
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    shapes = {}
    for name, mask in masks.items():
        mask.save(OUT_DIR / f"{name}.png")
        shapes[name] = {"file": f"{name}.png", "radius": opaque_radius(mask)}
    catalog = {"shader": SHADER, "shapes": shapes, "materials": MATERIALS}
    text = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    (OUT_DIR / "crystal.json").write_text(text, encoding="utf-8")
    write_preview(masks)
    for name, shape in shapes.items():
        print(f"{name} {CELL} px, poloměr {shape['radius']}")


if __name__ == "__main__":
    main()
