#!/usr/bin/env python3
"""Domky z pohledu shora. Vidět je střecha, stěna jen u kraje obrazovky.

64 px je 1 m, stejně jako u postavy, skal a stromů. Kreslí se ve čtyřnásobném
rozlišení. Sedlo a trám mají dvě velikosti, menší ve dvou délkách.
Jurta má tři velikosti. Každý dům má dvě vrstvy:

  sedlo  obdélník rozpůlený hřebenem, hřeben je nejvýš
  tram   nejvyšší bod uprostřed, trámy ze středu do rohů
  jurta  kruh, střecha s věncem a tyčemi

Krytina je došková. Snopy jdou po spádu, od hřebene dolů k okapu,
ne v řadách napříč.

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
    House("sedlo_kratke", "sedlo krátké", "sedlo", 4.2, 3.2, 3.4),
    House("sedlo_dlouhe", "sedlo dlouhé", "sedlo", 7.6, 3.2, 3.4),
    House("sedlo_velke", "sedlo velké", "sedlo", 9.2, 5.4, 5.0),
    House("tram_kratky", "trám krátký", "tram", 4.0, 3.6, 3.4),
    House("tram_dlouhy", "trám dlouhý", "tram", 7.2, 3.6, 3.4),
    House("tram_velky", "trám velký", "tram", 8.0, 6.4, 5.0),
    House("jurta_mala", "jurta malá", "jurta", 3.8, 3.8, 3.2),
    House("jurta_stredni", "jurta střední", "jurta", 5.4, 5.4, 3.8),
    House("jurta_velka", "jurta velká", "jurta", 7.2, 7.2, 4.6),
)

# Náhledové barvy. Ve hře je nastaví shader každému domu zvlášť.
PALETTES = {
    "sláma": {
        "roof": (196, 148, 72),
        "wall": (232, 216, 188),
        "wood": (108, 72, 40),
        "glass": (150, 196, 206),
        "opening": (36, 30, 26),
    },
    "taška": {
        "roof": (168, 54, 46),
        "wall": (244, 240, 232),
        "wood": (92, 62, 44),
        "glass": (120, 176, 194),
        "opening": (32, 26, 24),
    },
    "dřevo": {
        "roof": (112, 74, 46),
        "wall": (186, 154, 112),
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
    reach = max(hx, hy) + m(OVERHANG) + 3.0
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


def paint_rect_wall(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    hx, hy = m(house.width) / 2.0, m(house.depth) / 2.0
    sides = miter_sides(x, y, hx, hy)
    depth_limit = min(hx, hy)
    salt = sum(ord(char) for char in house.name)
    course = m(0.32)
    for side, where in sides.items():
        u, depth = miter_ud(x, y, hx, hy, side)
        t = np.clip(depth / depth_limit, 0.0, 1.0)
        groove = (np.mod(depth, course) < m(0.035)) & (depth > 1.0)
        grain = hash01(np.floor(u * 32.0), np.floor(depth / 4.0), salt + len(side))
        shade = (0.58 + 0.42 * (1.0 - t)) * np.where(groove, 0.88, 1.0)
        shade = shade * (0.92 + 0.08 * grain)
        mask.fill(where, WALL, shade)

    seam = miter_seams(x, y, hx, hy, m(0.035)) & (mask.cover > 0.0)
    mask.shade[seam] *= 0.78

    for side, where in sides.items():
        u, depth = miter_ud(x, y, hx, hy, side)
        t = depth / depth_limit
        length = wall_lengths(house)[side]
        door = side == "west"
        if door:
            half = (DOOR_W / 2.0) / length
            paint_opening(mask, where, u, t, 0.5 - half, 0.5 + half, 0.0, 0.46, WOOD, 0.62, frame=0.06 / length)
            pane = half * 0.42
            paint_opening(mask, where, u, t, 0.5 - pane, 0.5 + pane, 0.24, 0.40, GLASS, 0.95)
        half = (WINDOW_W / 2.0) / length
        for center in window_centers(length, door):
            mid = 0.5 + center / length
            paint_opening(
                mask,
                where,
                u,
                t,
                mid - half,
                mid + half,
                0.02,
                0.55,
                GLASS,
                0.95,
                frame=0.08 / length,
            )


def paint_yurt_wall(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    radius = m(house.width) / 2.0
    dist = np.hypot(x, y)
    inside = dist <= radius
    t = 1.0 - dist / radius
    angle = np.arctan2(y, x)
    salt = sum(ord(char) for char in house.name)
    grain = hash01(np.floor(angle * 8.0), np.floor(dist / 6.0), salt)
    # Obvod je světlejší: ten pás vykoukne, když střecha ujede.
    shade = (0.58 + 0.42 * (1.0 - np.clip(t, 0.0, 1.0))) * (0.9 + 0.1 * grain)
    mask.fill(inside, WALL, shade)

    door_a = math.pi
    door_half = (DOOR_W / 2.0) / (house.width / 2.0)
    win_half = (WINDOW_W / 2.0) / (house.width / 2.0)
    gap = np.abs(np.mod(angle - door_a + math.pi, math.tau) - math.pi)

    posts = 10 if house.width < 4.5 else 14 if house.width < 6.5 else 18
    sector = math.tau / posts
    delta = np.mod(angle + math.pi, sector)
    delta = np.minimum(delta, sector - delta)
    arc = delta * np.maximum(dist, 1.0)
    hub = radius * 0.1
    mask.fill(inside & (dist >= hub) & (arc <= m(0.07)) & (gap > door_half), WOOD, 0.78)

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


def thatch_shade(down: np.ndarray, across: np.ndarray, salt: int, bias: np.ndarray) -> np.ndarray:
    """Došek. down je 0 na hřebeni a 1 u okapu, snop běží po spádu."""
    bundle_w = m(0.2)
    wiggle = 0.05 * np.sin(down * 16.0 + np.floor(across / bundle_w))
    phase = across / bundle_w + wiggle
    bundle = np.floor(phase)
    local = phase - bundle
    seam = np.minimum(local, 1.0 - local) < 0.1
    fiber = hash01(np.floor(across / m(0.04)), np.floor(down * 5.0), salt)
    tone = hash01(bundle, np.zeros(bundle.shape, np.float32), salt + 4)
    down_c = np.clip(down, 0.0, 1.0)
    shade = (1.0 - 0.36 * down_c) * bias * (0.78 + 0.22 * tone) * (0.9 + 0.1 * fiber)
    shade = np.where(seam, shade * 0.62, shade)
    end = 0.76 + 0.2 * hash01(bundle, np.ones(bundle.shape, np.float32), salt + 8)
    shade = np.where(down_c > end, shade * 0.55, shade)
    return np.clip(shade, 0.0, 1.0)


def paint_gable(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    hx = m(house.width) / 2.0 + m(OVERHANG)
    hy = m(house.depth) / 2.0 + m(OVERHANG)
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    down = np.abs(y) / hy
    across = np.where(y < 0.0, x + m(0.1), x)
    bias = np.where(y < 0.0, 0.74, 1.0).astype(np.float32)
    mask.fill(inside, ROOF, thatch_shade(down, across, 11, bias))
    # Štítové hrany drží dřevo. Okap je střapatý konec došku, ne prkno.
    mask.fill(inside & (hx - np.abs(x) <= m(0.05)), WOOD, 0.55)
    mask.fill(inside & (np.abs(y) <= m(0.06)), WOOD, 0.9)


def paint_hip(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    hx = m(house.width) / 2.0 + m(OVERHANG)
    hy = m(house.depth) / 2.0 + m(OVERHANG)
    inside = (np.abs(x) <= hx) & (np.abs(y) <= hy)
    sides = rect_sides(x, y, hx, hy)
    slope = np.maximum(np.abs(x) / hx, np.abs(y) / hy)
    bias = np.ones_like(slope)
    bias = np.where(sides["south"], 1.0, bias)
    bias = np.where(sides["east"], 0.86, bias)
    bias = np.where(sides["west"], 0.8, bias)
    bias = np.where(sides["north"], 0.7, bias)
    # Od vrcholu dolů k okapu. Na bocích by rovnoběžné řady zase vypadaly jako stěna.
    bundles = max(28, int(math.tau * max(hx, hy) / m(0.22)))
    ang = np.mod(np.arctan2(y, x) + math.pi, math.tau)
    across = ang / (math.tau / bundles) * m(0.2)
    mask.fill(inside, ROOF, thatch_shade(slope, across, 23, bias))
    d1 = np.abs(x * hy - y * hx) / math.hypot(hx, hy)
    d2 = np.abs(x * hy + y * hx) / math.hypot(hx, hy)
    mask.fill(inside & ((d1 <= m(0.1)) | (d2 <= m(0.1))), WOOD, 0.9)


def paint_yurt_roof(mask: Mask, x: np.ndarray, y: np.ndarray, house: House) -> None:
    radius = m(house.width) / 2.0 + m(OVERHANG)
    dist = np.hypot(x, y)
    inside = dist <= radius
    slope = dist / radius
    angle = np.arctan2(y, x)
    salt = sum(ord(char) for char in house.name)
    hole = radius * 0.16
    crown_out = hole + m(0.16)
    bundles = max(18, int(math.tau * radius / m(0.22)))
    sector = math.tau / bundles
    ang = np.mod(angle + math.pi, math.tau)
    bundle = np.floor(ang / sector)
    local = ang / sector - bundle
    seam = np.minimum(local, 1.0 - local) < 0.09
    tone = hash01(bundle, np.zeros(bundle.shape, np.float32), salt)
    fiber = hash01(np.floor(ang / (sector * 0.28)), np.floor(slope * 4.0), salt + 2)
    shade = (1.0 - 0.34 * slope) * (0.78 + 0.22 * tone) * (0.9 + 0.1 * fiber)
    shade = np.where(seam & (dist > crown_out), shade * 0.64, shade)
    end = 0.78 + 0.18 * hash01(bundle, np.ones(bundle.shape, np.float32), salt + 6)
    shade = np.where(slope > end, shade * 0.55, shade)
    mask.fill(inside, ROOF, np.clip(shade, 0.0, 1.0))

    poles = 8 if house.width < 4.5 else 10 if house.width < 6.5 else 12
    pole_sector = math.tau / poles
    delta = np.mod(angle + math.pi / poles, pole_sector)
    delta = np.minimum(delta, pole_sector - delta)
    arc = delta * np.maximum(dist, 1.0)
    pole = inside & (dist >= crown_out) & (dist <= radius - m(0.06)) & (arc <= m(0.04))
    mask.fill(pole, WOOD, 0.82)
    mask.fill(inside & (dist >= hole) & (dist <= crown_out), WOOD, 0.94)
    mask.fill(dist <= hole, OPENING, 0.35)


def render(house: House) -> tuple[Image.Image, Image.Image, int]:
    if house.kind == "jurta":
        hx = hy = m(house.width) / 2.0
    else:
        hx, hy = m(house.width) / 2.0, m(house.depth) / 2.0
    cell = cell_for(hx, hy)
    x, y = grids(cell)
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
        info = write_info(built["catalog"])
        print(PREVIEW / "houses.png")
        print(PREVIEW / "houses_vrstvy.png")
        print(PREVIEW / "houses_kraj.png")
        print(PREVIEW / "houses_barvy.png")
        print(info)


if __name__ == "__main__":
    main()
