#!/usr/bin/env python3
"""Domky z pohledu shora. Vidět je střecha, stěna jen u kraje obrazovky.

64 px je 1 m, stejně jako u postavy, skal a stromů. Kreslí se ve čtyřnásobném
rozlišení. Sedlo a trám mají dvě velikosti, menší ve dvou délkách.
Jurta má tři velikosti. Každý dům má dvě vrstvy:

  sedlo  obdélník rozpůlený hřebenem, hřeben je nejvýš
  tram   nejvyšší bod uprostřed, trámy ze středu do rohů
  jurta  kruh, střecha s věncem a tyčemi

Krytina je došková. Snopy jdou po spádu, od hřebene dolů k okapu,
ne v řadách napříč. Snopy se mírně stáčejí, okap je roztřepený a hřeben
je přeložený došek svázaný provázkem. Stěna je z lomového kamene.
Půdorys je o pár stupňů zkosený a hrany se vlní, dům je stavěný ručně.

Vrstva nese váhy materiálu, ne hotovou barvu. Alfa je krytí.
Střecha (výška domu): R krytina, G dřevo, B otvor (kouřová díra jurty).
Stěna (0 m, stojí jako pařez): R stěna, G dřevo, B sklo.
Součet vah děleno krytím nese světlost, stejně jako u postavy:
  součet / krytí = shade_floor + (1 - shade_floor) * světlost
Barvy skládá godot/shaders/house_layer.gdshader. Průhledné pixely mají váhy 0,
import proto nesmí opravovat okraje průhlednosti.

Stěna je celá pod střechou. U obdélníku jdou rohy pod 45 stupni a uříznou
stěnu; dlouhá stěna je lichoběžník, krátká trojúhelník. Čára rohu je jen
slabý předěl. Okno a dveře jedou s tím úhlem, u obvodu jsou širší. U jurty
jdou čáry z obvodu do středu. Uprostřed obrazovky střecha stěnu zakryje.
U kraje střecha ujede a vykoukne jen pás stěny, který zrovna míří ke kameře.

Náhled „u kraje“ je dům v rohu okna 1280×720. Posun je stejný jako
ObjectLayers.PARALLAX.

  py tools/gen_houses.py
  py tools/gen_houses.py --name jurta_stredni
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from gen_trees import on_grass

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "houses"
PREVIEW = ROOT / "tools" / "preview"
SHADER = "res://shaders/house_layer.gdshader"

PX = 64
SS = 4
PARALLAX = 0.016
# Roh okna 1280×720. Střecha ujede od středu záběru.
EDGE = (640.0 * PARALLAX, 360.0 * PARALLAX)

SHADE = (0.42, 1.1)
SHADE_FLOOR = 0.2
SHEEN = (0.16, 0.7)
LUMA = np.array((0.299, 0.587, 0.114), np.float32)

ROOF, WOOD, OPENING = 0, 1, 2
WALL, GLASS = 0, 2

OVERHANG = 0.2
# Zkosení půdorysu (pár stupňů) a zvlnění hran v metrech. Dům je ručně stavěný.
SHEAR = 0.04
WOBBLE = 0.05
DOOR_W = 0.92
WINDOW_W = 0.72


@dataclass(frozen=True)
class House:
    name: str
    label: str
    kind: str
    width: float
    depth: float
    height: float

    @property
    def folder(self) -> str:
        return self.name


# width a depth jsou metry půdorysu stěny. height je výška střechy v metrech.
# Menší sedlo i trám mají stejnou hloubku a výšku, liší se jen délkou.
LAYER_PREVIEW = ("sedlo_dlouhe", "tram_dlouhy", "jurta_stredni")
HOUSES: tuple[House, ...] = (
    House("sedlo_kratke", "sedlo krátké", "sedlo", 5.8, 4.6, 4.0),
    House("sedlo_dlouhe", "sedlo dlouhé", "sedlo", 8.4, 4.6, 4.0),
    House("sedlo_velke", "sedlo velké", "sedlo", 9.4, 5.4, 4.6),
    House("tram_kratky", "trám krátký", "tram", 5.2, 4.8, 4.0),
    House("tram_dlouhy", "trám dlouhý", "tram", 7.8, 4.8, 4.0),
    House("tram_velky", "trám velký", "tram", 8.6, 6.0, 4.6),
    House("jurta_mala", "jurta malá", "jurta", 3.8, 3.8, 3.2),
    House("jurta_stredni", "jurta střední", "jurta", 5.4, 5.4, 3.8),
    House("jurta_velka", "jurta velká", "jurta", 7.2, 7.2, 4.6),
)

# Náhledové barvy. Ve hře je nastaví shader každému domu zvlášť.
PALETTES = {
    "sláma": {
        "roof": (196, 148, 72),
        "wall": (196, 184, 162),
        "wood": (108, 72, 40),
        "glass": (150, 196, 206),
        "opening": (36, 30, 26),
    },
    "taška": {
        "roof": (168, 54, 46),
        "wall": (214, 210, 200),
        "wood": (92, 62, 44),
        "glass": (120, 176, 194),
        "opening": (32, 26, 24),
    },
    "dřevo": {
        "roof": (112, 74, 46),
        "wall": (150, 138, 120),
        "wood": (62, 40, 26),
        "glass": (132, 180, 190),
        "opening": (28, 22, 18),
    },
}
DEFAULT_PALETTE = "sláma"


class Mask:
    """Váhy jedné vrstvy ve čtyřnásobném rozlišení."""

    def __init__(self, cell: int) -> None:
        n = cell * SS
        self.cell = cell
        self.ch = np.zeros((3, n, n), np.float32)
        self.shade = np.ones((n, n), np.float32)
        self.cover = np.zeros((n, n), np.float32)

    def fill(self, where: np.ndarray, channel: int, shade: np.ndarray | float) -> None:
        self.ch[:, where] = 0.0
        self.ch[channel, where] = 1.0
        self.shade[where] = shade if np.isscalar(shade) else shade[where]
        self.cover[where] = 1.0


def m(meters: float) -> float:
    return meters * PX


def hash01(ix: np.ndarray, iy: np.ndarray, salt: int) -> np.ndarray:
    x = ix.astype(np.int64)
    y = iy.astype(np.int64)
    n = (x * 374761393 + y * 668265263 + salt * 1442695041) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n & 255) / 255.0).astype(np.float32)


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(x: np.ndarray, y: np.ndarray, scale: float, salt: int) -> np.ndarray:
    gx, gy = x / scale, y / scale
    ix, iy = np.floor(gx), np.floor(gy)
    fx, fy = gx - ix, gy - iy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    a = hash01(ix, iy, salt)
    b = hash01(ix + 1, iy, salt)
    c = hash01(ix, iy + 1, salt)
    d = hash01(ix + 1, iy + 1, salt)
    return (a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy).astype(np.float32)


def fbm(x: np.ndarray, y: np.ndarray, scale: float, salt: int, octaves: int = 3) -> np.ndarray:
    """Šum 0..1, hrubé vlny s jemnějšími navrch."""
    total = np.zeros(x.shape, np.float32)
    weight, norm = 1.0, 0.0
    for octave in range(octaves):
        total += weight * value_noise(x, y, scale, salt + octave * 31)
        norm += weight
        weight *= 0.5
        scale *= 0.5
    return total / norm


def voronoi(
    x: np.ndarray, y: np.ndarray, size: float, salt: int, stretch: tuple[float, float] = (1.0, 1.0)
) -> tuple[np.ndarray, np.ndarray]:
    """Kameny. Vrací šířku spáry (d2 - d1, v buňkách) a náhodnou světlost kamene."""
    gx = x / (size * stretch[0])
    gy = y / (size * stretch[1])
    ix, iy = np.floor(gx), np.floor(gy)
    d1 = np.full(x.shape, 9.0, np.float32)
    d2 = np.full(x.shape, 9.0, np.float32)
    tone = np.zeros(x.shape, np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = ix + dx, iy + dy
            px = cx + 0.1 + 0.8 * hash01(cx, cy, salt)
            py = cy + 0.1 + 0.8 * hash01(cx, cy, salt + 7)
            dist = np.hypot(gx - px, gy - py)
            closer = dist < d1
            d2 = np.where(closer, d1, np.minimum(d2, dist))
            tone = np.where(closer, hash01(cx, cy, salt + 13), tone)
            d1 = np.where(closer, dist, d1)
    return d2 - d1, tone


def stone_shade(
    x: np.ndarray, y: np.ndarray, size: float, salt: int, stretch: tuple[float, float] = (1.0, 1.0)
) -> np.ndarray:
    """Lomový kámen se spárou. Kraj kamene je tmavší, střed vyboulený."""
    gap, tone = voronoi(x, y, size, salt, stretch)
    bulge = smoothstep(0.0, 0.42, gap)
    speck = hash01(np.floor(x / 2.0), np.floor(y / 2.0), salt + 3)
    shade = (0.6 + 0.36 * tone) * (0.78 + 0.22 * bulge) * (0.93 + 0.07 * speck)
    shade = shade * (0.88 + 0.22 * fbm(x, y, size * 3.0, salt + 5, 2))
    return np.where(gap < 0.06, 0.34 + 0.08 * speck, shade).astype(np.float32)


def organic(x: np.ndarray, y: np.ndarray, salt: int, shear: float, amp: float) -> tuple[np.ndarray, np.ndarray]:
    """Lehce zkosený a zvlněný půdorys. Rohy nejsou pravé a hrany nejsou pravítko."""
    rng = np.random.default_rng(salt)
    a, b = rng.uniform(-shear, shear, 2)
    wx = x + a * y
    wy = y + b * x
    nx = fbm(x, y, m(1.6), salt + 41, 2) - 0.5
    ny = fbm(x, y, m(1.6), salt + 59, 2) - 0.5
    return (wx + 2.0 * amp * nx).astype(np.float32), (wy + 2.0 * amp * ny).astype(np.float32)


def downscale(values: np.ndarray, cell: int) -> np.ndarray:
    return values.reshape(cell, SS, cell, SS).mean(axis=(1, 3))


def pack_mask(mask: Mask) -> Image.Image:
    stored = SHADE_FLOOR + (1.0 - SHADE_FLOOR) * np.clip(mask.shade, 0.0, 1.0)
    channels = [downscale(channel * stored, mask.cell) for channel in mask.ch]
    cover = downscale(mask.cover, mask.cell)
    rgba = np.stack(channels + [cover], axis=-1)
    return Image.fromarray(np.round(np.clip(rgba, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")


def colorize(mask: Image.Image, tints: tuple[tuple[int, int, int], ...]) -> Image.Image:
    """Stejný výpočet jako house_layer.gdshader."""
    data = np.asarray(mask, np.float32) / 255.0
    weights, alpha = data[..., :3], data[..., 3]
    total = weights.sum(axis=-1)
    base = (weights @ (np.array(tints, np.float32) / 255.0)) / np.maximum(total, 1e-3)[..., None]
    light = np.clip((total / np.maximum(alpha, 1e-3) - SHADE_FLOOR) / (1.0 - SHADE_FLOOR), 0.0, 1.0)
    rgb = base * (SHADE[0] + (SHADE[1] - SHADE[0]) * light)[..., None]
    rgb += (SHEEN[0] * (1.0 - base @ LUMA) * smoothstep(SHEEN[1], 1.0, light))[..., None]
    out = np.dstack([np.clip(rgb, 0.0, 1.0), alpha])
    return Image.fromarray(np.round(out * 255.0).astype(np.uint8), "RGBA")


def roof_tints(palette: dict) -> tuple[tuple[int, int, int], ...]:
    return (palette["roof"], palette["wood"], palette["opening"])


def wall_tints(palette: dict) -> tuple[tuple[int, int, int], ...]:
    return (palette["wall"], palette["wood"], palette["glass"])


def grids(cell: int) -> tuple[np.ndarray, np.ndarray]:
    axis = (np.arange(cell * SS, dtype=np.float32) + 0.5) / SS - cell / 2
    return np.meshgrid(axis, axis)


def cell_for(hx: float, hy: float) -> int:
    reach = max(hx, hy) * (1.0 + SHEAR) + m(OVERHANG + WOBBLE) + 3.0
    cell = int(math.ceil(reach * 2.0))
    if cell % 2:
        cell += 1
    return cell


def rect_sides(x: np.ndarray, y: np.ndarray, hx: float, hy: float) -> dict[str, np.ndarray]:
    """Čtyři trojúhelníky: úhlopříčky z rohů do středu."""
    ax = np.abs(x) / hx
    ay = np.abs(y) / hy
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    return {
        "south": inside & (y > 0) & (ay >= ax),
        "north": inside & (y < 0) & (ay >= ax),
        "east": inside & (x > 0) & (ax > ay),
        "west": inside & (x < 0) & (ax > ay),
    }


def quad(mask: np.ndarray, s: np.ndarray, t: np.ndarray, s0: float, s1: float, t0: float, t1: float) -> np.ndarray:
    return mask & (s >= s0) & (s <= s1) & (t >= t0) & (t <= t1)


def edge_distances(x: np.ndarray, y: np.ndarray, hx: float, hy: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    return hy + y, hx - x, hy - y, hx + x


def miter_sides(x: np.ndarray, y: np.ndarray, hx: float, hy: float) -> dict[str, np.ndarray]:
    """Stěny podle nejbližší hrany. Předěl sousedů je 45 stupňů, ne cesta do středu."""
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    north_d, east_d, south_d, west_d = edge_distances(x, y, hx, hy)
    return {
        "south": inside & (south_d <= north_d) & (south_d <= east_d) & (south_d <= west_d),
        "north": inside & (north_d < south_d) & (north_d <= east_d) & (north_d <= west_d),
        "east": inside & (east_d < south_d) & (east_d < north_d) & (east_d <= west_d),
        "west": inside & (west_d < south_d) & (west_d < north_d) & (west_d < east_d),
    }


def miter_ud(x: np.ndarray, y: np.ndarray, hx: float, hy: float, side: str) -> tuple[np.ndarray, np.ndarray]:
    """u je 0..1 podél stěny, depth je vzdálenost od obvodu v px. Bok se zužuje pod 45°."""
    if side == "south":
        depth = hy - y
        left = -hx + depth
        span = hx - depth
    elif side == "north":
        depth = hy + y
        left = -hx + depth
        span = hx - depth
        return (x - left) / np.maximum(2.0 * span, 1e-3), depth
    elif side == "east":
        depth = hx - x
        left = -hy + depth
        span = hy - depth
        return (y - left) / np.maximum(2.0 * span, 1e-3), depth
    else:
        depth = hx + x
        left = -hy + depth
        span = hy - depth
        return (y - left) / np.maximum(2.0 * span, 1e-3), depth
    return (x - left) / np.maximum(2.0 * span, 1e-3), depth


def miter_seams(x: np.ndarray, y: np.ndarray, hx: float, hy: float, width: float) -> np.ndarray:
    """Jen předěl sousedních stěn. Protější stěny uprostřed čáru nemají."""
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    north_d, east_d, south_d, west_d = edge_distances(x, y, hx, hy)

    def crease(a: np.ndarray, b: np.ndarray, *farther: np.ndarray) -> np.ndarray:
        on_line = np.abs(a - b) <= width
        closest = on_line
        for other in farther:
            closest = closest & (a <= other + width)
        return closest

    return inside & (
        crease(north_d, east_d, south_d, west_d)
        | crease(north_d, west_d, south_d, east_d)
        | crease(south_d, east_d, north_d, west_d)
        | crease(south_d, west_d, north_d, east_d)
    )


def wall_lengths(house: House) -> dict[str, float]:
    if house.kind == "jurta":
        return {}
    return {"north": house.width, "south": house.width, "east": house.depth, "west": house.depth}


def window_centers(length: float, door: bool) -> list[float]:
    """Poloha oken v metrech od středu stěny. Dveře sedí uprostřed západní stěny."""
    if door:
        return []
    if length >= 7.2:
        return [-1.7, 0.0, 1.7]
    if length >= 4.6:
        return [-1.05, 1.05]
    return [0.0]


def paint_opening(
    mask: Mask,
    where: np.ndarray,
    s: np.ndarray,
    t: np.ndarray,
    s0: float,
    s1: float,
    t0: float,
    t1: float,
    channel: int,
    shade: float,
    frame: float = 0.0,
    depth_pad: float = 0.02,
) -> None:
    if frame > 0.0:
        mask.fill(quad(where, s, t, s0 - frame, s1 + frame, max(0.0, t0 - depth_pad), t1 + depth_pad), WOOD, 0.72)
    mask.fill(quad(where, s, t, s0, s1, t0, t1), channel, shade)


def salt_of(house: House) -> int:
    return sum(ord(char) * (index + 1) for index, char in enumerate(house.name))


def paint_door(mask: Mask, where: np.ndarray, u: np.ndarray, t: np.ndarray, half: float, length: float) -> None:
    """Dveře z prken. Prkna jdou s úhlem stěny, rám je tmavší."""
    paint_opening(mask, where, u, t, 0.5 - half, 0.5 + half, 0.0, 0.46, WOOD, 0.62, frame=0.06 / length)
    door = quad(where, u, t, 0.5 - half, 0.5 + half, 0.0, 0.46)
    plank = np.mod((u - 0.5 + half) / (2.0 * half) * 4.0, 1.0)
    mask.shade[door & (plank < 0.12)] = 0.42
    pane = half * 0.42
    paint_opening(mask, where, u, t, 0.5 - pane, 0.5 + pane, 0.24, 0.40, GLASS, 0.95)


def paint_rect_wall(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    hx, hy = m(house.width) / 2.0, m(house.depth) / 2.0
    sides = miter_sides(x, y, hx, hy)
    depth_limit = min(hx, hy)
    salt = salt_of(house)
    rng = np.random.default_rng(salt)
    # Kameny jsou podél stěny delší, ať leží jako zdivo a ne jako dlažba.
    lying = stone_shade(x, y, m(0.4), salt, (1.45, 0.75))
    standing = stone_shade(x, y, m(0.4), salt + 1, (0.75, 1.45))
    for side, where in sides.items():
        _u, depth = miter_ud(x, y, hx, hy, side)
        t = np.clip(depth / depth_limit, 0.0, 1.0)
        stone = lying if side in ("north", "south") else standing
        mask.fill(where, WALL, (0.56 + 0.44 * (1.0 - t)) * stone)

    seam = miter_seams(x, y, hx, hy, m(0.03)) & (mask.cover > 0.0)
    mask.shade[seam] *= 0.82

    for side, where in sides.items():
        u, depth = miter_ud(x, y, hx, hy, side)
        t = depth / depth_limit
        length = wall_lengths(house)[side]
        door = side == "west"
        if door:
            paint_door(mask, where, u, t, (DOOR_W / 2.0) / length, length)
        for center in window_centers(length, door):
            mid = 0.5 + (center + rng.uniform(-0.14, 0.14)) / length
            half = (WINDOW_W * rng.uniform(0.86, 1.08) / 2.0) / length
            sill = rng.uniform(0.0, 0.04)
            paint_opening(
                mask,
                where,
                u,
                t,
                mid - half,
                mid + half,
                0.02 + sill,
                0.53 + sill,
                GLASS,
                0.95,
                frame=0.08 / length,
            )
            # Příčka okna, ať sklo není jedna plocha.
            cross = quad(where, u, t, mid - 0.012 / length * 3.0, mid + 0.012 / length * 3.0, 0.02 + sill, 0.53 + sill)
            mask.fill(cross, WOOD, 0.66)


def paint_yurt_wall(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    radius = m(house.width) / 2.0
    dist = np.hypot(x, y)
    inside = dist <= radius
    t = 1.0 - dist / radius
    angle = np.arctan2(y, x)
    salt = salt_of(house)
    stone = stone_shade(x, y, m(0.36), salt)
    # Obvod je světlejší: ten pás vykoukne, když střecha ujede.
    shade = (0.56 + 0.44 * (1.0 - np.clip(t, 0.0, 1.0))) * stone
    mask.fill(inside, WALL, shade)

    door_a = math.pi
    door_half = (DOOR_W / 2.0) / (house.width / 2.0)
    win_half = (WINDOW_W / 2.0) / (house.width / 2.0)
    gap = np.abs(np.mod(angle - door_a + math.pi, math.tau) - math.pi)

    posts = 10 if house.width < 4.5 else 14 if house.width < 6.5 else 18
    rng = np.random.default_rng(salt)
    hub = radius * 0.1
    for index in range(posts):
        turn = (index + 0.5 + rng.uniform(-0.18, 0.18)) * math.tau / posts - math.pi
        local = np.abs(np.mod(angle - turn + math.pi, math.tau) - math.pi)
        arc = local * np.maximum(dist, 1.0)
        width = m(0.06) * rng.uniform(0.8, 1.2)
        mask.fill(inside & (dist >= hub) & (arc <= width) & (gap > door_half), WOOD, rng.uniform(0.66, 0.84))

    def wedge(half: float, t0: float, t1: float, channel: int, tone: float, frame: float = 0.0) -> None:
        if frame > 0.0:
            mask.fill(inside & (gap <= half + frame) & (t >= max(0.0, t0 - 0.03)) & (t <= t1 + 0.03), WOOD, 0.7)
        mask.fill(inside & (gap <= half) & (t >= t0) & (t <= t1), channel, tone)

    wedge(door_half, 0.0, 0.5, WOOD, 0.62, frame=0.05)
    wedge(door_half * 0.38, 0.22, 0.4, GLASS, 0.95)
    # Okna na severu, jihu a východě. Západ drží dveře. Lichoběžník míří do středu.
    for turn in (math.pi / 2.0, -math.pi / 2.0, 0.0):
        local = np.abs(np.mod(angle - turn + math.pi, math.tau) - math.pi)
        mask.fill(inside & (local <= win_half + win_half * 0.28) & (t >= 0.0) & (t <= 0.48), WOOD, 0.7)
        mask.fill(inside & (local <= win_half) & (t >= 0.04) & (t <= 0.44), GLASS, 0.95)


def thatch_curve(x: np.ndarray, y: np.ndarray, salt: int) -> np.ndarray:
    """Snopy nejdou jako po pravítku, sem tam se stočí."""
    return m(0.14) * (fbm(x, y, m(1.3), salt + 71, 2) - 0.5) * 2.0


def thatch_shade(
    down: np.ndarray, across: np.ndarray, salt: int, bias: np.ndarray, x: np.ndarray, y: np.ndarray
) -> np.ndarray:
    """Došek. down je 0 na hřebeni a 1 u okapu, snop běží po spádu."""
    bundle_w = m(0.2)
    phase = across / bundle_w + 0.06 * np.sin(down * 14.0 + np.floor(across / bundle_w) * 1.7)
    bundle = np.floor(phase)
    local = phase - bundle
    fiber = hash01(np.floor(across / m(0.028)), np.floor(down * 7.0), salt)
    fine = hash01(np.floor(across / m(0.012)), np.floor(down * 18.0), salt + 1)
    seam = np.minimum(local, 1.0 - local) < 0.06 + 0.05 * fiber
    tone = hash01(bundle, np.zeros(bundle.shape, np.float32), salt + 4)
    down_c = np.clip(down, 0.0, 1.0)
    # Skvrny od deště a slunce, ať střecha není stejná od rohu do rohu.
    weather = 0.80 + 0.30 * fbm(x, y, m(1.4), salt + 9)
    shade = (1.0 - 0.34 * down_c) * bias * (0.76 + 0.24 * tone) * (0.86 + 0.10 * fiber + 0.04 * fine) * weather
    shade = np.where(seam, shade * 0.6, shade)
    end = 0.8 + 0.14 * hash01(bundle, np.ones(bundle.shape, np.float32), salt + 8)
    shade = np.where(down_c > end, shade * (0.6 + 0.12 * fine), shade)
    return np.clip(shade, 0.0, 1.0)


def ragged(across: np.ndarray, eave: np.ndarray, salt: int) -> np.ndarray:
    """Okap: konce snopů nejsou v jedné řadě. eave je vzdálenost k okraji střechy."""
    tuft = hash01(np.floor(across / m(0.06)), np.zeros(across.shape, np.float32), salt + 17)
    return eave >= m(0.1) * tuft


def ridge_cap(
    mask: Mask, band: np.ndarray, along: np.ndarray, off: np.ndarray, half: np.ndarray, salt: int
) -> None:
    """Hřeben z došku přeloženého přes vrchol, svázaný provázkem."""
    streak = hash01(np.floor(along / m(0.3)), np.floor(off / m(0.016)), salt)
    edge = smoothstep(0.45, 1.0, np.abs(off) / np.maximum(half, 1.0))
    mask.fill(band, ROOF, (0.66 + 0.1 * streak) * (1.0 - 0.38 * edge))
    ties = band & (np.mod(along, m(1.1)) < m(0.06))
    mask.fill(ties, WOOD, 0.5)


def paint_gable(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    hx = m(house.width) / 2.0 + m(OVERHANG)
    hy = m(house.depth) / 2.0 + m(OVERHANG)
    salt = salt_of(house)
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    curve = thatch_curve(x, y, salt)
    down = np.abs(y) / hy
    across = np.where(y < 0.0, x + m(0.1), x) + curve
    # Obě strany štítu stejně světlé, dům se ve hře otáčí.
    bias = np.full_like(x, 0.87, dtype=np.float32)
    roof = inside & ragged(across, hy - np.abs(y), salt)
    mask.fill(roof, ROOF, thatch_shade(down, across, salt + 11, bias, x, y))
    # Štítové hrany drží dřevo. Okap je střapatý konec došku, ne prkno.
    mask.fill(roof & (hx - np.abs(x) <= m(0.05)), WOOD, 0.55)
    half = m(0.13) * (0.85 + 0.3 * fbm(x, y, m(0.8), salt + 3, 2))
    ridge_cap(mask, roof & (np.abs(y) <= half), x + curve, y, half, salt + 5)


def paint_hip(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    hx = m(house.width) / 2.0 + m(OVERHANG)
    hy = m(house.depth) / 2.0 + m(OVERHANG)
    salt = salt_of(house)
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    sides = rect_sides(x, y, hx, hy)
    slope = np.maximum(np.abs(x) / hx, np.abs(y) / hy)
    # Všechny strany stejně světlé, dům se ve hře otáčí. Plochy dělí nároží a okap.
    bias = np.full_like(slope, 0.84)
    # Od vrcholu dolů k okapu. Na bocích by rovnoběžné řady zase vypadaly jako stěna.
    bundles = max(28, int(math.tau * max(hx, hy) / m(0.22)))
    ang = np.mod(np.arctan2(y, x) + math.pi, math.tau)
    across = ang / (math.tau / bundles) * m(0.2) + thatch_curve(x, y, salt)
    eave = np.minimum(hx - np.abs(x), hy - np.abs(y))
    roof = inside & ragged(across, eave, salt)
    mask.fill(roof, ROOF, thatch_shade(slope, across, salt + 23, bias, x, y))
    norm = math.hypot(hx, hy)
    half = m(0.11) * (0.85 + 0.3 * fbm(x, y, m(0.8), salt + 3, 2))
    for sign in (1.0, -1.0):
        off = (x * hy - sign * y * hx) / norm
        along = np.abs(x * hx + sign * y * hy) / norm
        ridge_cap(mask, roof & (np.abs(off) <= half), along, off, half, salt + 5)
    knot = np.hypot(x, y)
    mask.fill(roof & (knot <= m(0.26)), ROOF, 0.96)
    mask.fill(roof & (knot > m(0.2)) & (knot <= m(0.26)), WOOD, 0.62)


def rope(mask: Mask, where: np.ndarray, dist: np.ndarray, angle: np.ndarray, radius: float, salt: int) -> None:
    """Provaz kolem jurty. Lehce se vlní a je kroucený."""
    wobble = m(0.02) * np.sin(angle * 3.0 + salt) + m(0.012) * np.sin(angle * 7.0 + salt * 0.7)
    band = where & (np.abs(dist - radius - wobble) <= m(0.03))
    twist = np.mod(angle * radius / m(0.05) + (dist - radius) / m(0.03), 1.0) < 0.5
    mask.fill(band, WOOD, np.where(twist, 0.7, 0.5))


def paint_yurt_roof(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    radius = m(house.width) / 2.0 + m(OVERHANG)
    dist = np.hypot(x, y)
    inside = dist <= radius
    slope = dist / radius
    angle = np.arctan2(y, x)
    salt = salt_of(house)
    hole = radius * 0.16
    crown_out = hole + m(0.16)
    bundles = max(18, int(math.tau * radius / m(0.22)))
    ang = np.mod(angle + math.pi, math.tau)
    across = ang / (math.tau / bundles) * m(0.2) + thatch_curve(x, y, salt) * 0.6
    roof = inside & ragged(across, radius - dist, salt)
    bias = np.ones(x.shape, np.float32)
    shade = thatch_shade(slope, across, salt + 2, bias, x, y)
    mask.fill(roof, ROOF, shade)

    poles = 8 if house.width < 4.5 else 10 if house.width < 6.5 else 12
    rng = np.random.default_rng(salt + 1)
    for index in range(poles):
        turn = (index + rng.uniform(-0.15, 0.15)) * math.tau / poles - math.pi
        local = np.abs(np.mod(angle - turn + math.pi, math.tau) - math.pi)
        arc = local * np.maximum(dist, 1.0)
        reach = radius - m(rng.uniform(0.18, 0.4))
        pole = roof & (dist >= crown_out) & (dist <= reach) & (arc <= m(0.04))
        mask.fill(pole, WOOD, rng.uniform(0.72, 0.88))
    rope(mask, roof, dist, angle, radius * 0.56, salt)
    rope(mask, roof, dist, angle, radius * 0.8, salt + 3)
    ring = roof & (dist >= hole) & (dist <= crown_out)
    grain = hash01(np.floor(angle * 24.0), np.floor(dist / 3.0), salt + 4)
    mask.fill(ring, WOOD, 0.84 + 0.12 * grain)
    mask.fill(dist <= hole, OPENING, 0.35)


def render(house: House) -> tuple[Image.Image, Image.Image, int]:
    if house.kind == "jurta":
        hx = hy = m(house.width) / 2.0
    else:
        hx, hy = m(house.width) / 2.0, m(house.depth) / 2.0
    cell = cell_for(hx, hy)
    x, y = grids(cell)
    # Stěna i střecha mají stejné zkosení, takže střecha zeď dál přikryje.
    shear = 0.0 if house.kind == "jurta" else SHEAR
    x, y = organic(x, y, salt_of(house), shear, m(WOBBLE))
    wall, roof = Mask(cell), Mask(cell)
    if house.kind == "jurta":
        paint_yurt_wall(wall, x, y, house)
        paint_yurt_roof(roof, x, y, house)
    elif house.kind == "sedlo":
        paint_rect_wall(wall, x, y, house)
        paint_gable(roof, x, y, house)
    elif house.kind == "tram":
        paint_rect_wall(wall, x, y, house)
        paint_hip(roof, x, y, house)
    else:
        raise SystemExit(f"neznámý typ {house.kind}")
    return pack_mask(wall), pack_mask(roof), cell


def crop_square(image: Image.Image, pad: int = 2) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image
    width, height = image.size
    left, top, right, bottom = bbox
    cx, cy = width / 2, height / 2
    half = max(cx - left, right - cx, cy - top, bottom - cy)
    new_half = int(math.ceil(half - 1e-6)) + pad
    new_size = max(2, new_half * 2)
    if new_size >= width:
        return image
    left = (width - new_size) // 2
    top = (height - new_size) // 2
    return image.crop((left, top, left + new_size, top + new_size))


def paste_center(canvas: Image.Image, sprite: Image.Image, offset: tuple[int, int] = (0, 0)) -> None:
    x = (canvas.width - sprite.width) // 2 + offset[0]
    y = (canvas.height - sprite.height) // 2 + offset[1]
    canvas.alpha_composite(sprite, (x, y))


def ground_shadow(cell: int, house: House) -> Image.Image:
    hx = m(house.width) / 2.0 + m(OVERHANG) * 0.35
    hy = m(house.depth) / 2.0 + m(OVERHANG) * 0.35
    alpha = Image.new("L", (cell, cell), 0)
    draw = ImageDraw.Draw(alpha)
    cx = cy = cell / 2
    draw.ellipse((cx - hx, cy - hy * 0.96, cx + hx, cy + hy * 0.96), fill=90)
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=5))
    image = Image.new("RGBA", (cell, cell), (0, 0, 0, 255))
    image.putalpha(alpha)
    return image


def compose(wall: Image.Image, roof: Image.Image, shadow: Image.Image, shift: tuple[int, int]) -> Image.Image:
    pad = max(abs(shift[0]), abs(shift[1])) + 4
    side = max(wall.width, roof.width, shadow.width) + pad * 2
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    paste_center(image, shadow)
    paste_center(image, wall)
    paste_center(image, roof, shift)
    return image


def trim(image: Image.Image, pad: int = 10) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image
    left, top, right, bottom = bbox
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(image.width, right + pad)
    bottom = min(image.height, bottom + pad)
    return image.crop((left, top, right, bottom))


def check_cover(house: House, wall: Image.Image, roof: Image.Image) -> None:
    wall_a = np.asarray(wall.getchannel("A"))
    roof_a = np.asarray(roof.getchannel("A"))
    hidden = (wall_a > 200) & (roof_a < 200)
    if int(hidden.sum()) > 0:
        raise SystemExit(f"{house.name}: střecha nezakrývá {int(hidden.sum())} px stěny")
    shift = (round(EDGE[0] * house.height), round(EDGE[1] * house.height))
    moved = np.zeros_like(roof_a)
    ox, oy = shift
    src = roof_a
    x0, y0 = max(ox, 0), max(oy, 0)
    x1, y1 = min(src.shape[1] + ox, src.shape[1]), min(src.shape[0] + oy, src.shape[0])
    moved[y0:y1, x0:x1] = src[y0 - oy : y1 - oy, x0 - ox : x1 - ox]
    shown = (wall_a > 200) & (moved < 128)
    if int(shown.sum()) < 20:
        raise SystemExit(f"{house.name}: u kraje není vidět stěna")
    glass = np.asarray(wall)[..., 2]
    if int((glass > 20).sum()) < 10:
        raise SystemExit(f"{house.name}: chybí okno")


def load_font(size: int) -> ImageFont.ImageFont:
    for name in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "arial.ttf",
        "segoeui.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def save_grid(items: list[tuple[Image.Image, str]], columns: int, path: Path, scale: int) -> None:
    if not items:
        return
    gap = 14
    caption = 26
    slot_w = max(image.width for image, _label in items)
    slot_h = max(image.height for image, _label in items)
    rows = math.ceil(len(items) / columns)
    sheet = Image.new("RGB", (columns * slot_w + (columns + 1) * gap, rows * (slot_h + caption) + (rows + 1) * gap), (0x4F, 0x9A, 0x3C))
    draw = ImageDraw.Draw(sheet)
    font = load_font(16)
    for index, (image, label) in enumerate(items):
        col, row = index % columns, index // columns
        x = gap + col * (slot_w + gap)
        y = gap + row * (slot_h + caption + gap)
        draw.text((x, y), label, fill=(24, 32, 18), font=font)
        ox = x + (slot_w - image.width) // 2
        oy = y + caption + (slot_h - image.height) // 2
        sheet.paste(on_grass(image), (ox, oy))
    if scale != 1:
        sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def on_checker(image: Image.Image, cell: int = 8) -> Image.Image:
    bg = Image.new("RGBA", image.size)
    draw = ImageDraw.Draw(bg)
    light, dark = (68, 68, 74, 255), (42, 42, 48, 255)
    width, height = image.size
    for top in range(0, height, cell):
        for left in range(0, width, cell):
            fill = light if (left // cell + top // cell) % 2 == 0 else dark
            draw.rectangle((left, top, left + cell, top + cell), fill=fill)
    bg.alpha_composite(image)
    return bg.convert("RGB")


def save_masks(path: Path) -> None:
    """Surové soubory vrstev. R, G a B jsou materiály, ne výsledná barva."""
    items: list[tuple[Image.Image, str]] = []
    for house in HOUSES:
        for filename in ("wall.png", "roof.png"):
            image = Image.open(OUT_DIR / house.name / filename).convert("RGBA")
            items.append((image, f"{house.name}/{filename}"))
    gap, caption = 14, 26
    columns = 6
    slot_w = max(image.width for image, _label in items)
    slot_h = max(image.height for image, _label in items)
    rows = math.ceil(len(items) / columns)
    sheet = Image.new("RGB", (columns * slot_w + (columns + 1) * gap, rows * (slot_h + caption) + (rows + 1) * gap), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    font = load_font(16)
    for index, (image, label) in enumerate(items):
        col, row = index % columns, index // columns
        x = gap + col * (slot_w + gap)
        y = gap + row * (slot_h + caption + gap)
        draw.text((x, y), label, fill=(230, 226, 214), font=font)
        ox = x + (slot_w - image.width) // 2
        oy = y + caption + (slot_h - image.height) // 2
        sheet.paste(on_checker(image), (ox, oy))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def colored(wall: Image.Image, roof: Image.Image, palette: str) -> tuple[Image.Image, Image.Image]:
    colors = PALETTES[palette]
    return colorize(wall, wall_tints(colors)), colorize(roof, roof_tints(colors))


def uid_for(res_path: str) -> str:
    alphabet = "abcdefghijklmnopqrstuvwxyz234567"
    digest = hashlib.sha256(res_path.encode()).digest()
    chars: list[str] = []
    acc = 0
    bits = 0
    for byte in digest:
        acc = (acc << 8) | byte
        bits += 8
        while bits >= 5 and len(chars) < 13:
            bits -= 5
            chars.append(alphabet[(acc >> bits) & 31])
    return "uid://" + "".join(chars)


def write_import(png: Path) -> None:
    res = "res://" + png.relative_to(ROOT / "godot").as_posix()
    digest = hashlib.md5(res.encode()).hexdigest()
    imported = f"res://.godot/imported/{png.name}-{digest}.ctex"
    text = f"""[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid_for(res)}"
path="{imported}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{res}"
dest_files=["{imported}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""
    png.with_suffix(".png.import").write_text(text, encoding="utf-8")


def write_info(built: dict[str, dict]) -> Path:
    catalog = {
        "px_per_meter": PX,
        "height_unit": "m",
        "filter": "linear",
        "shader": SHADER,
        "shade": list(SHADE),
        "shade_floor": SHADE_FLOOR,
        "sheen": list(SHEEN),
        "parallax_preview": {"x": EDGE[0], "y": EDGE[1]},
        "colors": {
            name: {key: "".join(f"{channel:02X}" for channel in rgb) for key, rgb in palette.items()}
            for name, palette in PALETTES.items()
        },
        "houses": built,
    }
    path = OUT_DIR / "houses.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def build(selected: list[House]) -> dict[str, dict]:
    overview: list[tuple[Image.Image, str]] = []
    edge_view: list[tuple[Image.Image, str]] = []
    layers: list[tuple[Image.Image, str]] = []
    colors: list[tuple[Image.Image, str]] = []
    catalog: dict[str, dict] = {}

    for house in HOUSES:
        wall, roof, _cell = render(house)
        check_cover(house, wall, roof)
        wall, roof = crop_square(wall), crop_square(roof)
        if house in selected:
            out = OUT_DIR / house.name
            out.mkdir(parents=True, exist_ok=True)
            wall_path, roof_path = out / "wall.png", out / "roof.png"
            wall.save(wall_path)
            roof.save(roof_path)
            write_import(wall_path)
            write_import(roof_path)
        painted_wall, painted_roof = colored(wall, roof, DEFAULT_PALETTE)
        shadow = ground_shadow(max(wall.width, roof.width), house)
        shift = (round(EDGE[0] * house.height), round(EDGE[1] * house.height))
        center = trim(compose(painted_wall, painted_roof, shadow, (0, 0)))
        edge = trim(compose(painted_wall, painted_roof, shadow, shift))
        overview.append((center, house.label))
        edge_view.append((edge, house.label))
        if house.name in LAYER_PREVIEW:
            layers.extend(
                (
                    (trim(painted_wall), f"{house.label} · stěna"),
                    (trim(painted_roof), f"{house.label} · střecha"),
                    (center, f"{house.label} · spolu"),
                    (edge, f"{house.label} · u kraje"),
                )
            )
            for name in PALETTES:
                tinted_wall, tinted_roof = colored(wall, roof, name)
                tinted = trim(compose(tinted_wall, tinted_roof, shadow, shift))
                colors.append((tinted, f"{house.label} · {name}"))
        catalog[house.name] = {
            "label": house.label,
            "kind": house.kind,
            "width_m": house.width,
            "depth_m": house.depth,
            "layers": {
                "wall": {
                    "file": "wall.png",
                    "height": 0.0,
                    "slot": 1.0,
                    "channels": ["wall", "wood", "glass"],
                    "cell": wall.width,
                    "center": wall.width // 2,
                },
                "roof": {
                    "file": "roof.png",
                    "height": house.height,
                    "slot": 0.0,
                    "channels": ["roof", "wood", "opening"],
                    "cell": roof.width,
                    "center": roof.width // 2,
                },
            },
        }
        print(f"{house.name}: stěna {wall.width} px, střecha {roof.width} px, výška {house.height} m")

    return {
        "catalog": catalog,
        "overview": overview,
        "edge": edge_view,
        "layers": layers,
        "colors": colors,
    }


def remove_stale() -> None:
    if not OUT_DIR.exists():
        return
    keep = {house.name for house in HOUSES}
    for child in OUT_DIR.iterdir():
        if child.is_dir() and child.name not in keep:
            for item in child.iterdir():
                item.unlink()
            child.rmdir()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    names = tuple(house.name for house in HOUSES)
    parser.add_argument("--name", choices=names, help="jen jeden dům, jinak všech devět")
    args = parser.parse_args()
    selected = [house for house in HOUSES if args.name in (None, house.name)]
    if args.name is None:
        remove_stale()
    built = build(selected)
    if args.name is None:
        save_grid(built["overview"], 3, PREVIEW / "houses.png", 2)
        save_grid(built["edge"], 3, PREVIEW / "houses_kraj.png", 2)
        save_grid(built["layers"], 4, PREVIEW / "houses_vrstvy.png", 2)
        save_grid(built["colors"], 3, PREVIEW / "houses_barvy.png", 2)
        save_masks(PREVIEW / "houses_masky.png")
        info = write_info(built["catalog"])
        print(PREVIEW / "houses.png")
        print(PREVIEW / "houses_vrstvy.png")
        print(PREVIEW / "houses_kraj.png")
        print(PREVIEW / "houses_barvy.png")
        print(PREVIEW / "houses_masky.png")
        print(info)


if __name__ == "__main__":
    main()
