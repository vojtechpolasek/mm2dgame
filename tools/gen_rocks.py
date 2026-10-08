#!/usr/bin/env python3
"""Složí skály pro pohled kolmo shora.

Každá vrstva je průhledný atlas 3×3. Vrstva 1 je pata na zemi a je nejširší.
Vyšší vrstva má vlastní obrys a nesedí uprostřed, ale vždycky zůstane uvnitř té pod ní.
Uložená buňka je ořezaná na obsah té vrstvy, střed plátna zůstává.
Náhled vrstvy srovná na střed. „U kraje“ je tentýž posun, jaký ve hře dělá
shader stromu: vyšší vrstva ujede od středu obrazovky.

Atlasy jdou do godot/graphics/objects/rocks, náhledy do tools/preview.

Příklad:
  py tools/gen_rocks.py
  py tools/gen_rocks.py --name balvan1
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from gen_terrain_tiles import hsv_to_rgb, parse_hex, rgb_to_hsv
from gen_trees import atlas_cell, blank, blit_at, contact_sheet, crop_square, hash01, mix_rgb, pack_atlas, shade, vary_color

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "rocks"
INFO_PATH = OUT_DIR / "rocks.json"
PREVIEW = ROOT / "tools" / "preview"
ATLAS_COLUMNS = 3

WIDTH_JITTER = 0.08
ROUGH = 0.2
## Nejdelší výčnělek obrysu paty vůči průměru, před přepočtem na průměr 1.
SPIKE_MAX = 1.8
# Obrys paty pro chůzi: počet směrů kolem středu a od jaké průhlednosti je pixel skála.
# Úhel 0 míří doprava a roste po směru hodin, jako Vector2.angle() v Godotu.
OUTLINE_STEPS = 64
OUTLINE_ALPHA = 128
# Stejné číslo jako PARALLAX ve forest.gd. Náhled „u kraje“ počítá s kamenem
# 480 px vpravo a 260 px pod středem obrazovky.
PARALLAX = 0.0052
EDGE_SHIFT = (480.0 * PARALLAX, 260.0 * PARALLAX)

# Vrstva 1 je pata (height 0, nestojí při posunu kamery). Vyšší číslo je menší a výš.
# widths je průměr vrstvy v pixelech, 64 px je jeden metr. Nízká skála má patu a
# jeden vršek. Vysoká má čtyři vrstvy, ať vršek při posunu kamery neodletí.
# Vrchol je nejvýš 8 m. spacing je v metrech a je menší než pata, ať se skály
# mohou dotýkat. rough je členitost obrysu.
# round je kruh: obě vrstvy jsou soustředné, bez zploštění. pond je barva vody
# uprostřed paty, pond_ratio je její poloměr vůči poloměru vrchní vrstvy.
# Vršek má uprostřed díru, voda sedí na patě a při posunu kamery zůstane.
# dry je kotlina bez vody. Obrys je lehce hrbolatý. Dno je plný kámen,
# díra je jen v horní vrstvě, ať je vidět vyplněné dno.
# mouth v katalogu je poloměr té díry v px. U kotliny je ještě o desetinu
# menší, protože hrboly díru stáhnou dovnitř skály.
# snow je barva čepice. Leží na vrchní ploše a na římse, spodní obruba zůstane kámen.
# Vyšší vrstva má sněhu víc.
ROCKS = {
    "balvan1": {
        "layers": 2,
        "widths": {1: 68, 2: 40},
        "height": {1: 0.0, 2: 1.1},
        "color": "8A8172",
        "rough": 0.28,
        "variants": 9,
        "spacing": 0.8,
    },
    "balvan_snih": {
        "layers": 2,
        "widths": {1: 68, 2: 40},
        "height": {1: 0.0, 2: 1.1},
        "color": "8A8172",
        "snow": "F4F7FA",
        "rough": 0.28,
        "variants": 9,
        "spacing": 0.8,
    },
    "skala1": {
        "layers": 4,
        "widths": {1: 250, 2: 165, 3: 95, 4: 40},
        "height": {1: 0.0, 2: 2.4, 3: 4.4, 4: 6.0},
        "color": "6E675C",
        "rough": 0.3,
        "variants": 9,
        "spacing": 3.2,
    },
    "skala_snih": {
        "layers": 4,
        "widths": {1: 250, 2: 165, 3: 95, 4: 40},
        "height": {1: 0.0, 2: 2.4, 3: 4.4, 4: 6.0},
        "color": "6E675C",
        "snow": "F4F7FA",
        "rough": 0.3,
        "variants": 9,
        "spacing": 3.2,
    },
    "skala2": {
        "layers": 4,
        "widths": {1: 300, 2: 200, 3: 120, 4: 50},
        "height": {1: 0.0, 2: 2.8, 3: 5.2, 4: 7.2},
        "color": "5E6560",
        "rough": 0.26,
        "variants": 9,
        "spacing": 3.8,
    },
    "skala2_snih": {
        "layers": 4,
        "widths": {1: 300, 2: 200, 3: 120, 4: 50},
        "height": {1: 0.0, 2: 2.8, 3: 5.2, 4: 7.2},
        "color": "5E6560",
        "snow": "F4F7FA",
        "rough": 0.26,
        "variants": 9,
        "spacing": 3.8,
    },
    "skala10": {
        "layers": 4,
        "widths": {1: 340, 2: 230, 3: 140, 4: 58},
        "height": {1: 0.0, 2: 3.0, 3: 5.6, 4: 8.0},
        "color": "746C62",
        "rough": 0.28,
        "variants": 9,
        "spacing": 4.3,
    },
    "skala15": {
        "layers": 4,
        "widths": {1: 400, 2: 270, 3: 165, 4: 70},
        "height": {1: 0.0, 2: 3.0, 3: 5.6, 4: 8.0},
        "color": "5C635E",
        "rough": 0.26,
        "variants": 9,
        "spacing": 5.0,
    },
    "jezirko": {
        "layers": 2,
        "widths": {1: 128, 2: 112},
        "height": {1: 0.0, 2: 0.7},
        "color": "A8A092",
        "rough": 0.08,
        "round": True,
        "pond": "3DCFC6",
        "pond_ratio": 0.5,
        "variants": 9,
        "spacing": 1.7,
    },
    "kotlina": {
        "layers": 2,
        "widths": {1: 384, 2: 348},
        "height": {1: 0.0, 2: 1.6},
        "color": "3E3B36",
        "rough": 0.08,
        "round": True,
        "dry": True,
        "pond_ratio": 0.72,
        "variants": 1,
        "spacing": 4.6,
    },
}


@dataclass
class Shape:
    cx: float
    cy: float
    rx: float
    ry: float
    axis: float
    verts: list[tuple[float, float]]

    def radius_mul(self, angle: float) -> float:
        verts = self.verts
        count = len(verts)
        angle = (angle + math.pi) % math.tau - math.pi
        for index in range(count):
            start, start_mul = verts[index]
            end, end_mul = verts[(index + 1) % count]
            sample = angle
            if index == count - 1:
                end += math.tau
                if sample < start:
                    sample += math.tau
            if start <= sample <= end:
                span = end - start
                blend = 0.0 if span == 0 else (sample - start) / span
                return start_mul + (end_mul - start_mul) * blend
        return verts[0][1]

    def norm(self, x: float, y: float) -> tuple[float, float]:
        local_x, local_y = self._local(x, y)
        dist = math.hypot(local_x / self.rx, local_y / self.ry)
        if dist == 0:
            return 0.0, 0.0
        angle = math.atan2(local_y / self.ry, local_x / self.rx)
        return dist / self.radius_mul(angle), angle

    def at(self, angle: float, along: float) -> tuple[float, float]:
        mul = self.radius_mul(angle)
        local_x = math.cos(angle) * along * mul * self.rx
        local_y = math.sin(angle) * along * mul * self.ry
        cos = math.cos(self.axis)
        sin = math.sin(self.axis)
        return self.cx + local_x * cos - local_y * sin, self.cy + local_x * sin + local_y * cos

    def _local(self, x: float, y: float) -> tuple[float, float]:
        dx = x - self.cx
        dy = y - self.cy
        cos = math.cos(self.axis)
        sin = math.sin(self.axis)
        return dx * cos + dy * sin, -dx * sin + dy * cos


def _wrap_angle(angle: float) -> float:
    return (angle + math.pi) % math.tau - math.pi


def make_verts(rng: random.Random, rough: float) -> list[tuple[float, float]]:
    count = rng.randint(16, 22)
    amp = 0.08 + rough * 0.2
    verts: list[list[float]] = []
    for index in range(count):
        angle = _wrap_angle(-math.pi + (index + rng.uniform(0.15, 0.85)) / count * math.tau)
        verts.append([angle, 1.0 + rng.uniform(-amp, amp)])
    for _ in range(rng.randint(4, 7)):
        index = rng.randrange(count)
        verts[index][1] *= rng.uniform(1.16, 1.32)
        verts[(index - 1) % count][1] *= rng.uniform(1.05, 1.14)
        verts[(index + 1) % count][1] *= rng.uniform(1.05, 1.14)
    for _ in range(rng.randint(2, 4)):
        verts[rng.randrange(count)][1] *= rng.uniform(0.76, 0.9)
    # Výčnělky se násobí, když náhoda vybere tentýž vrchol víckrát. Strop drží obrys v rozumné
    # velikosti, jinak jedna varianta vystrčí ocas daleko za ostatní a zvětší kolize všech skal.
    return _normalize_verts([(angle, min(SPIKE_MAX, max(0.62, mul))) for angle, mul in verts])


def _normalize_verts(verts: list[tuple[float, float]]) -> list[tuple[float, float]]:
    verts.sort()
    mean = sum(mul for _, mul in verts) / len(verts)
    return [(angle, mul / mean) for angle, mul in verts]


def make_facets(rng: random.Random, shape: Shape, count: int) -> list[tuple[float, float, float]]:
    facets = []
    for _ in range(count):
        angle = rng.uniform(-math.pi, math.pi)
        reach = math.sqrt(rng.random()) * 0.78
        x, y = shape.at(angle, reach)
        brightness = rng.uniform(0.78, 1.22)
        facets.append((x, y, brightness))
    return facets


def make_bumps(rng: random.Random, shape: Shape, count: int) -> list[tuple[float, float, float, float]]:
    bumps = []
    span = max(shape.rx, shape.ry, 8.0)
    for _ in range(count):
        angle = rng.uniform(-math.pi, math.pi)
        x, y = shape.at(angle, math.sqrt(rng.random()) * 0.78)
        radius = span * rng.uniform(0.14, 0.34)
        strength = rng.uniform(0.7, 1.0)
        bumps.append((x, y, radius, strength))
    return bumps


def bump_count(rng: random.Random, width: float) -> int:
    if width < 90:
        return rng.randint(5, 8)
    return rng.randint(11, 18)


def _stamp(marks: set[tuple[int, int]], x: float, y: float, thick: bool) -> None:
    ix = int(round(x))
    iy = int(round(y))
    marks.add((ix, iy))
    if thick:
        marks.add((ix + 1, iy))
        marks.add((ix, iy + 1))


def raster_cracks(rng: random.Random, shape: Shape, count: int) -> set[tuple[int, int]]:
    marks: set[tuple[int, int]] = set()
    span = max(shape.rx, shape.ry)
    for _ in range(count):
        thick = span >= 90 and rng.random() < 0.18
        if rng.random() < 0.22:
            _crack_along(rng, shape, marks, thick)
        else:
            _crack_inward(rng, shape, marks, thick, span)
    return marks


def _crack_inward(
    rng: random.Random,
    shape: Shape,
    marks: set[tuple[int, int]],
    thick: bool,
    span: float,
) -> None:
    angle = rng.uniform(-math.pi, math.pi)
    start = rng.uniform(0.55, 1.02)
    end = rng.uniform(0.08, 0.72)
    if start < end:
        start, end = end, start
    bend = rng.uniform(-1.05, 1.05)
    wiggle = rng.uniform(1.0, 2.6)
    phase = rng.uniform(0, math.tau)
    steps = max(6, int(abs(start - end) * span * 1.45))
    points: list[tuple[float, float]] = []
    for step in range(steps + 1):
        blend = step / steps
        along = start + (end - start) * blend
        wobble = 0.22 * math.sin(blend * wiggle * math.tau + phase)
        x, y = shape.at(angle + bend * blend * blend + wobble, along)
        points.append((x, y))
        _stamp(marks, x, y, thick)
    if rng.random() < 0.28 and len(points) > 5:
        origin = points[len(points) // 2]
        heading = angle + math.pi / 2 + rng.uniform(-0.5, 0.5)
        length = rng.uniform(0.1, 0.28) * span
        forks = max(4, int(length))
        for step in range(1, forks + 1):
            dist = length * step / forks
            _stamp(marks, origin[0] + math.cos(heading) * dist, origin[1] + math.sin(heading) * dist, False)


def _crack_along(
    rng: random.Random,
    shape: Shape,
    marks: set[tuple[int, int]],
    thick: bool,
) -> None:
    angle = rng.uniform(-math.pi, math.pi)
    along = rng.uniform(0.28, 0.82)
    span = rng.uniform(0.18, 0.55) * rng.choice((-1.0, 1.0))
    drift = rng.uniform(-0.08, 0.08)
    steps = max(5, int(abs(span) * along * max(shape.rx, shape.ry) * 0.85))
    for step in range(steps + 1):
        blend = step / steps
        x, y = shape.at(angle + span * blend, max(0.08, min(0.98, along + drift * blend)))
        _stamp(marks, x, y, thick)


def canvas_size(preset: dict) -> int:
    layers = int(preset["layers"])
    rough = float(preset.get("rough", ROUGH))
    biggest = max(float(preset["widths"][layer]) for layer in range(1, layers + 1))
    tallest = max(float(preset["height"][layer]) for layer in range(1, layers + 1))
    if preset.get("round"):
        lump = 1.14 if preset.get("dry") else 1.0
        half = biggest * 0.5 * lump + tallest * max(EDGE_SHIFT) + 8
        size = int(math.ceil(half * 2))
        if size % 2:
            size += 1
        return size
    reach = (1 + rough * 1.35) / max(0.35, 1 - rough)
    half = biggest * 0.5 * (1 + WIDTH_JITTER) * reach * 1.25
    half += biggest * 0.32
    half += tallest * max(EDGE_SHIFT) + 8
    size = int(math.ceil(half * 2))
    if size % 2:
        size += 1
    return size


CIRCLE_VERTS = [(-math.pi, 1.0), (0.0, 1.0)]


@dataclass
class Pond:
    radius: float
    color: tuple[int, int, int]
    hole: bool
    dry: bool = False
    mouth: Shape | None = None


@dataclass
class LayerGeom:
    diameter: float
    squash: float
    axis: float
    ox: float
    oy: float
    verts: list[tuple[float, float]]


@dataclass
class RockPlan:
    layers: dict[int, LayerGeom]


def plan_rock(preset: dict, rng: random.Random) -> RockPlan:
    rough = float(preset.get("rough", ROUGH))
    base = jitter_width(rng, float(preset["widths"][1]))
    base_verts = make_verts(rng, rough)
    return RockPlan(
        layers={
            1: LayerGeom(
                diameter=base,
                squash=rng.uniform(0.72, 0.96),
                axis=rng.uniform(0, math.pi),
                ox=0.0,
                oy=0.0,
                verts=base_verts,
            )
        }
    )


def shape_for(plan: RockPlan, size: int, layer: int) -> Shape:
    geom = plan.layers[layer]
    radius = geom.diameter * 0.5
    return Shape(
        cx=size / 2 + geom.ox,
        cy=size / 2 + geom.oy,
        rx=radius,
        ry=radius * geom.squash,
        axis=geom.axis,
        verts=geom.verts,
    )


def ray_reach(parent: Shape, ox: float, oy: float, angle: float, margin: float = 0.96) -> float:
    if parent.norm(ox, oy)[0] > margin:
        return 0.0
    span = max(parent.rx, parent.ry) * max(mul for _, mul in parent.verts) * 2 + 8
    lo = 0.0
    hi = span
    for _ in range(18):
        mid = (lo + hi) * 0.5
        if parent.norm(ox + math.cos(angle) * mid, oy + math.sin(angle) * mid)[0] <= margin:
            lo = mid
        else:
            hi = mid
    return lo


def clamp_inside(parent: Shape, child: Shape, margin: float = 0.94) -> Shape:
    for _ in range(10):
        worst = _sticks_out(parent, child)
        if worst <= margin:
            return child
        factor = margin / worst if worst else 1.0
        child = Shape(
            cx=child.cx,
            cy=child.cy,
            rx=child.rx * factor,
            ry=child.ry * factor,
            axis=child.axis,
            verts=child.verts,
        )
    return child


def contained_shape(parent: Shape, rng: random.Random, target_diameter: float) -> Shape:
    """Vršek s vlastním obrysem, který nikde nevyjde z paty pod sebou."""
    angle = rng.uniform(-math.pi, math.pi)
    ox, oy = parent.at(angle, rng.uniform(0.04, 0.26))
    if parent.norm(ox, oy)[0] > 0.4:
        ox, oy = parent.cx, parent.cy
    span = max(parent.rx, parent.ry)
    count = min(48, max(24, int(span / 5)))
    angles: list[float] = []
    radii: list[float] = []
    for index in range(count):
        sample = _wrap_angle(-math.pi + (index + 0.5) / count * math.tau)
        reach = ray_reach(parent, ox, oy, sample)
        fraction = rng.uniform(0.55, 0.78)
        roll = rng.random()
        if roll < 0.22:
            fraction *= rng.uniform(0.78, 0.9)
        elif roll < 0.5:
            fraction = min(0.9, fraction * rng.uniform(1.1, 1.24))
        angles.append(sample)
        radii.append(reach * fraction)
    mean_radius = sum(radii) / count or 1.0
    target_radius = target_diameter * 0.5
    if mean_radius > target_radius:
        shrink = target_radius / mean_radius
        radii = [radius * shrink for radius in radii]
    mean = sum(radii) / count or 1.0
    child = Shape(
        cx=ox,
        cy=oy,
        rx=mean,
        ry=mean,
        axis=0.0,
        verts=_normalize_verts([(angles[index], radii[index] / mean) for index in range(count)]),
    )
    return clamp_inside(parent, child)


def gentle_verts(rng: random.Random, rough: float) -> list[tuple[float, float]]:
    """Kruh s malými hrboly. Bez dlouhých výběžků, jaké mají obyčejné skály."""
    count = rng.randint(12, 16)
    amp = 0.045 + rough * 0.2
    verts: list[tuple[float, float]] = []
    for index in range(count):
        angle = _wrap_angle(-math.pi + (index + rng.uniform(0.25, 0.75)) / count * math.tau)
        verts.append((angle, 1.0 + rng.uniform(-amp, amp)))
    return _normalize_verts(verts)


def circle_shapes(preset: dict, size: int, rng: random.Random) -> dict[int, Shape]:
    """Soustředné kružnice. Vršek sedí uprostřed paty, ne vedle něj.
    Kotlina má na všech vrstvách stejné lehké hrboly, ať vršek nevyjede z paty.
    """
    center = size / 2
    rough = float(preset.get("rough", ROUGH))
    verts = gentle_verts(rng, rough) if preset.get("dry") else CIRCLE_VERTS
    shapes = {}
    for layer in range(1, int(preset["layers"]) + 1):
        radius = float(preset["widths"][layer]) * 0.5
        shapes[layer] = Shape(
            cx=center,
            cy=center,
            rx=radius,
            ry=radius,
            axis=0.0,
            verts=verts,
        )
    return shapes


def build_shapes(preset: dict, rng: random.Random, size: int) -> dict[int, Shape]:
    if preset.get("round"):
        return circle_shapes(preset, size, rng)
    plan = plan_rock(preset, rng)
    shapes = {1: shape_for(plan, size, 1)}
    base = plan.layers[1].diameter
    layers = int(preset["layers"])
    for index in range(2, layers + 1):
        target = base * float(preset["widths"][index]) / float(preset["widths"][1])
        target *= rng.uniform(0.9, 1.0)
        shapes[index] = contained_shape(shapes[index - 1], rng, target)
        if _sticks_out(shapes[index - 1], shapes[index]) > 0.995:
            raise SystemExit(f"vrstva {index} přesahuje vrstvu {index - 1}")
    return shapes


def _sticks_out(parent: Shape, child: Shape) -> float:
    worst = 0.0
    for index in range(256):
        angle = -math.pi + index / 256 * math.tau
        x, y = child.at(angle, 1.0)
        worst = max(worst, parent.norm(x, y)[0])
    return worst


def jitter_width(rng: random.Random, width: float) -> float:
    return width * rng.uniform(1 - WIDTH_JITTER, 1 + WIDTH_JITTER)


def facet_count(rng: random.Random, width: float) -> int:
    if width < 100:
        return rng.randint(3, 4)
    return rng.randint(5, 7)


def crack_count(rng: random.Random, width: float) -> int:
    if width < 100:
        return rng.randint(5, 8)
    return rng.randint(max(7, int(width / 32)), max(10, int(width / 16)))


def pond_pixel(
    x: int,
    y: int,
    shape: Shape,
    radius: float,
    color: tuple[int, int, int],
    salt: int,
) -> tuple[int, int, int, int]:
    """Plocha vody. Ke středu tmavší, u kraje světlejší pruh, ať drží i bez shaderu."""
    dx = x + 0.5 - shape.cx
    dy = y + 0.5 - shape.cy
    dist = math.hypot(dx, dy) / max(radius, 1.0)
    light = max(-1.0, min(1.0, (-0.45 * dx - 0.35 * dy) / max(radius, 1.0)))
    value = 0.78 + 0.2 * dist * dist
    value *= 0.9 + 0.18 * (light * 0.5 + 0.5)
    value *= 0.97 + 0.06 * hash01(x, y, salt + 5)
    if dist > 0.78:
        value *= 1 + 0.16 * (dist - 0.78) / 0.22
    value = min(1.12, max(0.62, value))
    return (*shade(color, value), 255)


def snow_amount(wy: float, covered: float, above_t: float | None, strength: float) -> float:
    """Podíl sněhu na pixelu. covered 0 je střed vrstvy, wy > 0 míří dolů po obrazovce.

    Čepice kryje horní plochu a odhalenou římsu. Spodní obruba a tenký kraj obrysu
    zůstanou kámen, ať skála nesplyne se sněhem.
    """
    skirt = max(0.0, min(1.0, (wy - 0.02) / 0.85))
    rim = max(0.0, min(1.0, (covered - 0.82) / 0.18))
    if above_t is not None and above_t < 1.08:
        return 0.0
    if above_t is None:
        cap = 1.0
    else:
        cap = max(0.0, min(1.0, (above_t - 1.08) / 0.22))
    cap *= 1.0 - 0.88 * skirt
    cap *= 1.0 - 0.6 * rim
    return cap * strength


def draw_layer(
    size: int,
    shape: Shape,
    color: tuple[int, int, int],
    facets: list[tuple[float, float, float]],
    cracks: set[tuple[int, int]],
    bumps: list[tuple[float, float, float, float]],
    lichen: float,
    rng: random.Random,
    salt: int,
    parent: Shape | None = None,
    above: Shape | None = None,
    pond: Pond | None = None,
    snow: tuple[int, int, int] | None = None,
    snow_strength: float = 1.0,
) -> Image.Image:
    image = blank(size)
    pixels = image.load()
    lichen_rgb = None
    if lichen > 0:
        base_h, base_s, base_v = rgb_to_hsv(*color)
        lichen_rgb = hsv_to_rgb(
            rng.uniform(78, 108),
            min(0.45, max(0.18, base_s + 0.22)),
            base_v * 0.78,
        )
    max_mul = max(mul for _, mul in shape.verts)
    reach = max(shape.rx, shape.ry) * max_mul + 3
    x0 = max(0, int(shape.cx - reach))
    y0 = max(0, int(shape.cy - reach))
    x1 = min(size - 1, int(shape.cx + reach))
    y1 = min(size - 1, int(shape.cy + reach))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            covered, _angle = shape.norm(x + 0.5, y + 0.5)
            if covered > 1:
                continue
            if parent is not None and parent.norm(x + 0.5, y + 0.5)[0] > 1:
                continue

            inside_mouth = False
            mouth_out = 0.0
            if pond is not None:
                if pond.mouth is not None:
                    mouth_t = pond.mouth.norm(x + 0.5, y + 0.5)[0]
                    inside_mouth = mouth_t <= 1.0
                    mouth_out = mouth_t - 1.0
                else:
                    pond_dist = math.hypot(x + 0.5 - shape.cx, y + 0.5 - shape.cy)
                    inside_mouth = pond_dist <= pond.radius
                    mouth_out = (pond_dist - pond.radius) / max(pond.radius, 1.0)
                if inside_mouth and pond.hole:
                    continue
                if inside_mouth and not pond.dry:
                    pixels[x, y] = pond_pixel(x, y, shape, pond.radius, pond.color, salt)
                    continue

            wx = (x + 0.5 - shape.cx) / max(shape.rx, 1.0)
            wy = (y + 0.5 - shape.cy) / max(shape.ry, 1.0)
            light = max(-1.0, min(1.0, -0.7 * wx - 0.86 * wy))
            lit = light * 0.5 + 0.5
            grain = 0.9 + 0.16 * hash01(x, y, salt)
            grain *= 0.9 + 0.22 * hash01(x // 4, y // 4, salt + 9)
            if hash01(x, y, salt + 3) > 0.97:
                grain *= 0.72

            best = 1e9
            brightness = 1.0
            for fx, fy, bias in facets:
                dist = (x - fx) ** 2 + (y - fy) ** 2
                if dist < best:
                    best = dist
                    brightness = bias
            # Světlo jde zleva shora. Vršek je světlejší, odhalená stěna pod ním tmavší.
            value = (0.74 + 0.22 * lit) * brightness * grain
            relief = 0.0
            for bx, by, br, strength in bumps:
                dx = x + 0.5 - bx
                dy = y + 0.5 - by
                dist = math.hypot(dx, dy) / br
                if dist >= 1:
                    continue
                dome = (1 - dist * dist) * strength
                side = max(-1.0, min(1.0, -(dx + dy) / br))
                relief += dome * (0.28 + 0.8 * side)
            if relief:
                if pond is not None and pond.dry and not pond.hole and inside_mouth:
                    relief *= 0.35
                value *= 1 + max(-0.55, min(0.62, relief))
            if above is None:
                value *= 1.02 + 0.08 * lit
            else:
                above_t = above.norm(x + 0.5, y + 0.5)[0]
                if above_t > 1:
                    value *= 0.7 + 0.18 * lit
                    if above_t < 1.2:
                        band = (1.2 - above_t) / 0.2
                        value *= 1 - band * (0.06 + 0.16 * (1 - lit))
                else:
                    value *= 0.96
            if covered > 0.9:
                value *= 1 - 0.14 * (covered - 0.9) / 0.1
            if lichen_rgb is not None and hash01(x, y, salt + 11) > 1 - lichen:
                pixels[x, y] = (*lichen_rgb, 255)
                continue
            if (x, y) in cracks:
                value *= 0.62
            if pond is not None and pond.dry and not pond.hole and inside_mouth:
                value *= 0.9
            if pond is not None and mouth_out > 0.0 and not (pond.dry and not pond.hole):
                if pond.dry:
                    span = 0.16
                    floor = 0.48
                elif pond.hole:
                    span = 5.0 / max(pond.radius, 1.0)
                    floor = 0.72
                else:
                    span = 8.0 / max(pond.radius, 1.0)
                    floor = 0.8
                if mouth_out < span:
                    value *= floor + (1.0 - floor) * (mouth_out / span)

            value = min(1.15, max(0.4, value))
            rgb = shade(color, value)
            if snow is not None:
                cap = snow_amount(wy, covered, None if above is None else above_t, snow_strength)
                cap *= 0.78 + 0.22 * hash01(x, y, salt + 29)
                if hash01(x, y, salt + 31) > 0.93:
                    cap *= 0.4
                if (x, y) in cracks:
                    cap *= 0.22
                if cap > 0.03:
                    rgb = mix_rgb(rgb, shade(snow, min(1.12, 0.9 + 0.16 * value)), cap)
            pixels[x, y] = (*rgb, 255)
    return image


def stack_layers(
    frames: dict[int, Image.Image],
    heights: dict[int, float],
    shift: tuple[float, float],
) -> Image.Image:
    image = blank(frames[1].width)
    for layer in sorted(frames):
        height = heights[layer]
        blit_at(image, frames[layer], shift[0] * height, shift[1] * height)
    return image


def check_preset(name: str, preset: dict) -> int:
    layers = int(preset["layers"])
    if not 1 <= layers <= 4:
        raise SystemExit(f"{name}: vrstvy mají být 1 až 4")
    for key in ("widths", "height"):
        values = preset.get(key)
        if not values:
            raise SystemExit(f"{name}: chybí {key}")
        previous = None
        for layer in range(1, layers + 1):
            if layer not in values:
                raise SystemExit(f"{name}: {key} nemá vrstvu {layer}")
            value = float(values[layer])
            if key == "height" and layer == 1 and value < 0:
                raise SystemExit(f"{name}: pata nemá být pod zemí")
            if key == "height" and layer > 1 and previous is not None and value <= previous:
                raise SystemExit(f"{name}: výška má stoupat, vrstva {layer} nestoupá")
            if key == "widths" and value <= 0:
                raise SystemExit(f"{name}: šířka vrstvy {layer} musí být větší než 0")
            if key == "widths" and previous is not None and value >= previous:
                raise SystemExit(f"{name}: vyšší vrstva {layer} má být užší než ta pod ní")
            if key == "height" and layer > 1 and value <= 0:
                raise SystemExit(f"{name}: výška vrstvy {layer} musí být větší než 0")
            previous = value
    rough = float(preset.get("rough", ROUGH))
    if not 0.05 <= rough <= 0.4:
        raise SystemExit(f"{name}: rough má být mezi 0.05 a 0.4")
    if float(preset.get("spacing", 0)) <= 0:
        raise SystemExit(f"{name}: spacing musí být větší než 0")
    if int(preset.get("variants", 9)) < 1:
        raise SystemExit(f"{name}: variants musí být aspoň 1")
    parse_hex(preset["color"])
    if preset.get("snow"):
        parse_hex(preset["snow"])
    if preset.get("round"):
        if "pond_ratio" not in preset:
            raise SystemExit(f"{name}: kruhová skála potřebuje pond_ratio")
        ratio = float(preset["pond_ratio"])
        if not 0.2 <= ratio <= 0.8:
            raise SystemExit(f"{name}: pond_ratio má být mezi 0.2 a 0.8")
        if not preset.get("dry"):
            if "pond" not in preset:
                raise SystemExit(f"{name}: kruhová skála s vodou potřebuje pond")
            parse_hex(preset["pond"])
    return layers


def rock_info(rocks: dict) -> dict:
    catalog = {}
    for name, preset in rocks.items():
        check_preset(name, preset)
        layers = int(preset["layers"])
        drawn = canvas_size(preset)
        layer_cells = {
            layer: atlas_cell(OUT_DIR / name / f"layer_{layer}.png", ATLAS_COLUMNS) or drawn
            for layer in range(1, layers + 1)
        }
        size = max(layer_cells.values())
        variants = int(preset.get("variants", 9))
        outline = foot_outline(OUT_DIR / name / "layer_1.png", variants, ATLAS_COLUMNS)
        catalog[name] = {
            "variants": int(preset.get("variants", 9)),
            "canvas": size,
            "center": size // 2,
            "color": preset["color"],
            "rough": float(preset.get("rough", ROUGH)),
            "layers": {
                str(layer): {
                    "height": float(preset["height"][layer]),
                    "width": float(preset["widths"][layer]),
                    "canvas": layer_cells[layer],
                }
                for layer in range(1, layers + 1)
            },
            "spacing": float(preset["spacing"]),
        }
        if preset.get("round"):
            mouth = float(preset["widths"][layers]) * 0.5 * float(preset["pond_ratio"])
            if preset.get("dry"):
                mouth *= 0.9
            catalog[name]["mouth"] = round(mouth, 1)
        if outline:
            catalog[name]["outline"] = outline
    return {
        "height_unit": "m",
        "spacing_unit": "m",
        "width_unit": "px",
        "atlas_columns": ATLAS_COLUMNS,
        "rocks": catalog,
    }


def foot_outline(path: Path, variants: int, columns: int) -> list[list[float]]:
    """Pro každou variantu nejdelší dosah paty v OUTLINE_STEPS výsečích kolem středu buňky, v px.

    Bere celou výseč, ne jeden paprsek, ať se nevynechá úzký výčnělek mezi směry.
    Střed buňky je střed skály ve hře, sprite je centrovaný.
    """
    cell = atlas_cell(path, columns)
    if cell is None:
        return []
    with Image.open(path) as image:
        alpha = image.getchannel("A")
    pixels = alpha.load()
    half = cell / 2
    outlines: list[list[float]] = []
    for variant in range(variants):
        left = (variant % columns) * cell
        top = (variant // columns) * cell
        reach = [0.0] * OUTLINE_STEPS
        box = alpha.crop((left, top, left + cell, top + cell)).getbbox()
        if box is not None:
            for y in range(box[1], box[3]):
                dy = y + 0.5 - half
                for x in range(box[0], box[2]):
                    if pixels[left + x, top + y] < OUTLINE_ALPHA:
                        continue
                    dx = x + 0.5 - half
                    dist = math.hypot(dx, dy) + 0.5
                    step = int(math.atan2(dy, dx) % math.tau / math.tau * OUTLINE_STEPS + 0.5) % OUTLINE_STEPS
                    if dist > reach[step]:
                        reach[step] = dist
        outlines.append([round(value, 1) for value in reach])
    return outlines


def write_rock_info(rocks: dict, path: Path = INFO_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(rock_info(rocks), indent=2)
    # Obrys je dlouhá řada čísel. Jedna varianta na řádek, ne číslo na řádek.
    text = re.sub(r"\[\s+(-?[\d.]+(?:,\s+-?[\d.]+)*)\s+\]", lambda found: "[" + ", ".join(found.group(1).split()).replace(",,", ",") + "]", text)
    path.write_text(text + "\n", encoding="utf-8")
    return path


def clean_output(path: Path) -> None:
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_file() and child.suffix == ".png":
            child.unlink()


def generate_rocks(name: str, preset: dict, seed: int = 1, variants: int | None = None) -> Path:
    check_preset(name, preset)
    count = int(preset.get("variants", 9) if variants is None else variants)
    layers = int(preset["layers"])
    size = canvas_size(preset)
    color = parse_hex(preset["color"])
    out = OUT_DIR / name
    clean_output(out)
    out.mkdir(parents=True, exist_ok=True)

    heights = {layer: float(preset["height"][layer]) for layer in range(1, layers + 1)}
    composites: list[Image.Image] = []
    shifted: list[Image.Image] = []
    layer_frames: dict[int, list[Image.Image]] = {layer: [] for layer in range(1, layers + 1)}
    first: dict[int, Image.Image] | None = None
    name_salt = sum(ord(char) for char in name)

    for index in range(count):
        rng = random.Random(seed + name_salt + index * 7919)
        stone = vary_color(color, rng, hue=7, value=0.05)
        snow_rgb = vary_color(parse_hex(preset["snow"]), rng, hue=2, value=0.02) if preset.get("snow") else None
        shapes = build_shapes(preset, rng, size)
        base = shapes[1]
        dry = bool(preset.get("dry"))
        pond = None
        pond_radius = 0.0
        water = (0, 0, 0)
        mouth = None
        if preset.get("round"):
            if not dry:
                water = vary_color(parse_hex(preset["pond"]), rng, hue=6, value=0.04)
            top = shapes[layers]
            pond_radius = top.rx * float(preset["pond_ratio"])
            if dry:
                mouth = Shape(
                    top.cx,
                    top.cy,
                    pond_radius,
                    pond_radius,
                    0.0,
                    gentle_verts(rng, float(preset.get("rough", ROUGH)) * 0.65),
                )
                mouth = clamp_inside(top, mouth, 0.9)
                pond_radius = mouth.rx
        facets = make_facets(rng, base, facet_count(rng, base.rx * 2))
        frames: dict[int, Image.Image] = {}
        for layer in range(1, layers + 1):
            shape = shapes[layer]
            cracks_n = crack_count(rng, shape.rx * 2)
            if dry:
                cracks_n = int(cracks_n * 1.5)
            cracks = raster_cracks(rng, shape, cracks_n)
            bumps = make_bumps(rng, shape, bump_count(rng, shape.rx * 2))
            lichen = 0.0 if preset.get("round") or snow_rgb is not None else (0.012 if layer == layers and base.rx >= 50 else 0.0)
            if preset.get("round"):
                pond = Pond(pond_radius, water, layer == layers, dry, mouth)
            frames[layer] = draw_layer(
                size,
                shape,
                stone,
                facets,
                cracks,
                bumps,
                lichen,
                rng,
                salt=name_salt + layer * 17,
                parent=None if layer == 1 else shapes[layer - 1],
                above=None if layer == layers else shapes[layer + 1],
                pond=pond,
                snow=snow_rgb,
                snow_strength=0.78 + 0.22 * ((layer - 1) / max(layers - 1, 1)),
            )
            layer_frames[layer].append(frames[layer])
        composites.append(stack_layers(frames, heights, (0.0, 0.0)))
        shifted.append(stack_layers(frames, heights, EDGE_SHIFT))
        if index == 0:
            first = frames

    saved: list[int] = []
    for layer, frames in layer_frames.items():
        fitted = crop_square(frames)
        saved.append(fitted[0].width)
        pack_atlas(fitted).save(out / f"layer_{layer}.png")

    labels = [f"{index:02d}" for index in range(count)]
    contact_sheet(composites, labels, PREVIEW / f"{name}.png", 2)
    contact_sheet(shifted, labels, PREVIEW / f"{name}_kraj.png", 2)
    if first is not None:
        panels = []
        panel_labels = []
        for layer in range(1, layers + 1):
            panels.append(first[layer])
            panel_labels.append(f"vrstva {layer} · {heights[layer]:g} m")
        panels.append(composites[0])
        panel_labels.append("skála")
        panels.append(shifted[0])
        panel_labels.append("u kraje")
        contact_sheet(panels, panel_labels, PREVIEW / f"{name}_layers.png", 2)
    print(f"{count} variant, plátno {size}, buňky {min(saved)}–{max(saved)} -> {out}")
    print(PREVIEW / f"{name}.png")
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--name", choices=tuple(ROCKS), help="jen jedna skála, jinak všechny")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--variants", type=int, help="přepíše počet variant z definice")
    parser.add_argument("--info", action="store_true", help="jen přepíše rocks.json z uložených atlasů")
    args = parser.parse_args()
    names = [] if args.info else [args.name] if args.name else list(ROCKS)
    for name in names:
        generate_rocks(name, ROCKS[name], seed=args.seed, variants=args.variants)
    print(write_rock_info(ROCKS))


if __name__ == "__main__":
    main()
