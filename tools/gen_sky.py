#!/usr/bin/env python3
"""Slunce a fáze měsíce pro ukazatel na obloze v HUD (Hud.SkyDial).

Jeden pruh buněk CELL x CELL: slunce, pak měsíc v pořadí fází noci (DayNight.MOON_PHASES):
úplněk, ubývající 3/4, 1/2, 1/4, nov, přibývající 1/4, 1/2, 3/4. Ubývající svítí vlevo,
přibývající vpravo (jako z severní polokoule).

Měsíc je koule osvětlená z boku podle fáze, s měkkým rozhraním světla a stínu, moři a krátery.
Neosvícená část je tmavá a neprůhledná (popelavý svit), nov je tmavý kotouč s jemným okrajem.
Slunce je zlatý kotouč se září a krátkými paprsky. Ve hře se kreslí v polovině velikosti.

  py tools/gen_sky.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot" / "graphics" / "hud" / "sky.png"
PREVIEW = ROOT / "tools" / "preview" / "sky.png"

CELL = 48
SS = 4
MOON_RADIUS = 16.0
SUN_RADIUS = 11.0
# Osvětlený podíl a strana světla (1 vpravo, -1 vlevo) v pořadí buněk po slunci.
PHASES = (
    (1.0, -1),
    (0.75, -1),
    (0.5, -1),
    (0.25, -1),
    (0.0, 1),
    (0.25, 1),
    (0.5, 1),
    (0.75, 1),
)

LIT = np.array([236, 233, 220], float)
MARE = np.array([168, 172, 178], float)
DARK = np.array([38, 44, 60], float)
DARK_MARE = np.array([30, 35, 50], float)
RIM = np.array([120, 132, 160], float)
SUN_CORE = np.array([255, 246, 200], float)
SUN_EDGE = np.array([250, 176, 52], float)
SUN_GLOW = np.array([255, 196, 80], float)


def _grid(radius: float) -> tuple[np.ndarray, np.ndarray]:
    side = CELL * SS
    coords = (np.arange(side) + 0.5) / SS - CELL * 0.5
    x, y = np.meshgrid(coords, coords)
    return x / radius, y / radius


def _surface(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """0 vysočina, 1 moře. Moře jsou měkké skvrny, krátery malé světlé kroužky s tmavým dnem."""
    rng = random.Random(7)
    mare = np.zeros_like(x)
    for cx, cy, r in ((-0.3, -0.25, 0.42), (0.18, -0.38, 0.3), (0.28, 0.08, 0.34), (-0.12, 0.32, 0.26), (0.5, -0.1, 0.18)):
        d = np.hypot(x - cx, y - cy) / r
        mare = np.maximum(mare, np.clip(1.2 - d, 0.0, 1.0) * 0.85)
    craters = np.zeros_like(x)
    for _ in range(14):
        cx, cy = rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8)
        r = rng.uniform(0.05, 0.13)
        d = np.hypot(x - cx, y - cy) / r
        craters += np.where(d < 1.0, 0.35 * (1.0 - d), 0.0)
        craters -= np.where((d >= 1.0) & (d < 1.35), 0.25 * (1.35 - d) / 0.35, 0.0)
    return np.clip(mare + craters, -0.3, 1.0)


def moon(lit: float, side: int) -> Image.Image:
    x, y = _grid(MOON_RADIUS)
    rr = x * x + y * y
    inside = rr <= 1.0
    z = np.sqrt(np.clip(1.0 - rr, 0.0, 1.0))
    # Úhel Slunce-Měsíc-Země: osvětlený podíl (1 - cos a) / 2. Úplněk svítí ze směru pozorovatele.
    elong = math.acos(1.0 - 2.0 * lit)
    light = np.array([side * math.sin(elong), 0.0, -math.cos(elong)])
    dot = x * light[0] + y * light[1] + z * light[2]
    day = np.clip(dot / 0.12 + 0.5, 0.0, 1.0)
    # Okraj kotouče trochu tmavší, koule pak nevypadá placatě.
    limb = 0.78 + 0.22 * z
    surface = _surface(x, y)
    mare_part = np.clip(surface, 0.0, 1.0)[..., None]
    lit_rgb = (LIT * (1 - mare_part) + MARE * mare_part) * limb[..., None] * (1.0 + np.clip(-surface, 0.0, 1.0)[..., None] * 0.3)
    dark_rgb = DARK * (1 - mare_part) + DARK_MARE * mare_part
    rgb = dark_rgb * (1 - day[..., None]) + lit_rgb * day[..., None]
    # Tenký okraj, ať je tmavá část vidět i na tmavém pozadí.
    rim = np.clip((np.sqrt(rr) - 0.9) / 0.1, 0.0, 1.0)[..., None] * (1 - day[..., None]) * 0.6
    rgb = rgb * (1 - rim) + RIM * rim
    alpha = np.where(inside, 255.0, 0.0)
    return _image(rgb, alpha)


def sun() -> Image.Image:
    x, y = _grid(SUN_RADIUS)
    d = np.hypot(x, y)
    angle = np.arctan2(y, x)
    t = np.clip(d, 0.0, 1.0)[..., None]
    disc = SUN_CORE * (1 - t**2) + SUN_EDGE * t**2
    # Paprsky: dvanáct měkkých klínů nad září, slábnou do dálky.
    rays = np.clip(np.cos(angle * 12.0) * 2.2 - 1.2, 0.0, 1.0) * np.clip((2.0 - d) / 0.8, 0.0, 1.0)
    glow = np.clip(1.0 - (d - 1.0) / 1.0, 0.0, 1.0) ** 2 * 0.55
    outer = np.where(d > 1.0, np.maximum(glow, rays * 0.9), 0.0)
    edge = np.clip((1.0 - d) * SUN_RADIUS * 1.0 + 0.5, 0.0, 1.0)
    rgb = disc * edge[..., None] + SUN_GLOW * (1 - edge[..., None])
    alpha = np.clip(edge + outer * (1 - edge), 0.0, 1.0) * 255.0
    return _image(rgb, alpha)


def _image(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    data = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 255)]).astype(np.uint8)
    big = Image.fromarray(data, "RGBA")
    # Zmenšení z nadvzorkování s předem vynásobeným krytím, ať okraj nezesvětlí ani nezčerná.
    premult = np.array(big, float)
    premult[..., :3] *= premult[..., 3:4] / 255.0
    small = Image.fromarray(premult.astype(np.uint8), "RGBA").resize((CELL, CELL), Image.LANCZOS)
    out = np.array(small, float)
    a = out[..., 3:4]
    out[..., :3] = np.where(a > 0, out[..., :3] * 255.0 / np.maximum(a, 1.0), 0.0)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def main() -> None:
    cells = [sun()] + [moon(lit, side) for lit, side in PHASES]
    strip = Image.new("RGBA", (CELL * len(cells), CELL), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        strip.paste(cell, (i * CELL, 0))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    strip.save(OUT)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    preview = Image.new("RGBA", strip.size, (24, 30, 46, 255))
    preview.alpha_composite(strip)
    preview.resize((strip.width * 3, strip.height * 3), Image.NEAREST).save(PREVIEW)
    print(f"{OUT} ({len(cells)} buněk)")


if __name__ == "__main__":
    main()
