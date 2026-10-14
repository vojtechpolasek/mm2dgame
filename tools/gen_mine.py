#!/usr/bin/env python3
"""Důl pro bezedné jezírko: díra do země se stěnami plnými kamenů, kolmo shora.

Vrstva 1 je okraj na zemi (výška 0) s dírou uprostřed. Další vrstvy jsou pod zemí
(záporná výška), každá menší a hlubší: dvě stěny a dno. Při posunu kamery jde hlubší
vrstva opačně než střecha, takže díra vypadá hluboká. Vrstva pod okrajem sahá
o PRESAH px pod ústí té nad ní, ať při posunu nevykoukne její kraj.

Obrázek nenese barvy, ale masky pro shader mine_layer.gdshader:
  R  světlost (hornina i kámen materiálu), skutečná světlost je R * VALUE_SCALE
  G  maska kamene materiálu: tam shader dá barvu materiálu dolu
  B  u kamene materiálu semínko odlesku, jinde plamen lucerny
Jeden důl tak poslouží všem materiálům.

Generuje ho gen_rocks.py (druh "dul" s "mine": True), sám se spustí jen pro náhled:
  py tools/gen_mine.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image

from gen_terrain_tiles import parse_hex
from gen_trees import blank, blit_at, contact_sheet, crop_square, hash01, mix_rgb, pack_atlas, shade

ROOT = Path(__file__).resolve().parent.parent
CRYSTAL_INFO = ROOT / "godot" / "graphics" / "objects" / "crystal" / "crystal.json"

VALUE_SCALE = 1.5
# O kolik px sahá vrstva pod ústí té nad ní. Posun mezi sousedními vrstvami je u kraje
# velkého okna kolem 11 px, hrboly ústí berou další kus.
PRESAH = 13.0
# Posun vrstvy v px na metr výšky kousek od rohu okna 1920 × 1080 při zoomu 1 (PARALLAX 0.016 ve hře).
SHIFT_PER_M = 14.0
# Ústí každé hlubší vrstvy vůči ústí té nad ní.
MOUTH_SHRINK = 0.7
# Podíl buněk stěny, které jsou kámen materiálu, po vrstvách od okraje.
ORE_SHARE = {1: 0.0, 2: 0.3, 3: 0.36, 4: 0.3}
# Světlo jde zleva shora, stejně jako u skal.
LIGHT = (-0.63, -0.77)


class Blob:
    """Nerovný kruh: poloměr se mění podle úhlu plynulou křivkou z několika sinů."""

    def __init__(self, cx: float, cy: float, radius: float, rng: random.Random, rough: float) -> None:
        self.cx = cx
        self.cy = cy
        self.radius = radius
        self.waves = []
        for freq in (2, 3, 4, 5, 7, 9):
            amp = rough * rng.uniform(0.3, 1.0) / math.sqrt(freq)
            self.waves.append((freq, amp, rng.uniform(0, math.tau)))
        # Pár výrazných hrbolů, ať díra není jen zvlněný kruh.
        self.bumps = [
            (rng.uniform(-math.pi, math.pi), rng.uniform(0.25, 0.5), rough * rng.uniform(-1.1, 1.3))
            for _ in range(rng.randint(2, 4))
        ]

    def mul(self, angle: float) -> float:
        value = 1.0
        for freq, amp, phase in self.waves:
            value += amp * math.sin(freq * angle + phase)
        for at, width, amp in self.bumps:
            diff = (angle - at + math.pi) % math.tau - math.pi
            value += amp * math.exp(-(diff / width) ** 2)
        return value

    def reach_max(self) -> float:
        return self.radius * max(self.mul(-math.pi + index / 128 * math.tau) for index in range(128))

    def reach_min(self) -> float:
        return self.radius * min(self.mul(-math.pi + index / 128 * math.tau) for index in range(128))

    def norm(self, x: float, y: float) -> float:
        """0 ve středu, 1 na okraji, víc venku."""
        dx = x - self.cx
        dy = y - self.cy
        dist = math.hypot(dx, dy)
        if dist == 0:
            return 0.0
        return dist / (self.radius * self.mul(math.atan2(dy, dx)))

    def edge(self, x: float, y: float) -> float:
        """Vzdálenost od okraje v px, kladná uvnitř."""
        dx = x - self.cx
        dy = y - self.cy
        return self.radius * self.mul(math.atan2(dy, dx)) - math.hypot(dx, dy)


class Grown(Blob):
    """Obrys o extra px dál než base v každém směru, s malou vlastní vlnou wobble."""

    def __init__(self, base: Blob, extra: float, wobble: Blob) -> None:
        self.cx = base.cx
        self.cy = base.cy
        self.radius = 1.0
        self.base = base
        self.extra = extra
        self.wobble = wobble

    def mul(self, angle: float) -> float:
        return self.base.radius * self.base.mul(angle) + self.extra + self.wobble.radius * (self.wobble.mul(angle) - 1.0)


def _hidden(pit: Pit, layer: int, shift: float) -> bool:
    """Zůstane obrys vrstvy pod okrajem, i když ji posun odsune o shift px ven?"""
    shape = pit.outer[layer]
    rim = pit.outer[1]
    for index in range(96):
        angle = -math.pi + index / 96 * math.tau
        reach = shape.radius * shape.mul(angle) + shift
        if rim.norm(shape.cx + math.cos(angle) * reach, shape.cy + math.sin(angle) * reach) > 0.97:
            return False
    return True


def make_pit(preset: dict, size: int, rng: random.Random) -> Pit:
    """Varianta, ve které žádná hlubší vrstva ani při posunu nevyjede zpod okraje."""
    heights = preset["height"]
    for _ in range(40):
        pit = Pit(preset, size, rng)
        if all(_hidden(pit, layer, SHIFT_PER_M * abs(float(heights[layer]))) for layer in range(2, pit.layers + 1)):
            return pit
    raise SystemExit("důl: hlubší vrstva se nevejde pod okraj, zmenši pond_ratio nebo PRESAH")


class Pit:
    """Jedna varianta dolu: obrysy vrstev od okraje k dnu."""

    def __init__(self, preset: dict, size: int, rng: random.Random) -> None:
        center = size / 2
        layers = int(preset["layers"])
        rough = float(preset.get("rough", 0.12))
        outer_r = float(preset["widths"][1]) * 0.5 * rng.uniform(0.97, 1.03)
        self.outer: dict[int, Blob] = {1: Blob(center, center, outer_r, rng, rough * 0.7)}
        self.mouth: dict[int, Blob] = {}
        mouth_r = outer_r * float(preset["pond_ratio"])
        mouth = Blob(
            center + rng.uniform(-3, 3),
            center + rng.uniform(-3, 3),
            mouth_r,
            rng,
            rough,
        )
        self.mouth[1] = mouth
        for layer in range(2, layers + 1):
            above = self.mouth[layer - 1]
            # Obrys pod ústím je skoro kruh, jen o PRESAH dál než nejdelší hrbol ústí nad ním.
            self.outer[layer] = Grown(above, PRESAH, Blob(above.cx, above.cy, PRESAH * 0.25, rng, 1.0))
            if layer < layers:
                self.mouth[layer] = Blob(
                    above.cx + rng.uniform(-2.5, 2.5),
                    above.cy + rng.uniform(-2.5, 2.5),
                    above.radius * MOUTH_SHRINK,
                    rng,
                    rough * 0.9,
                )
        self.layers = layers


def _cells(rng: random.Random, shape: Blob, cell: float) -> list[tuple[float, float, float, float]]:
    """Body Voroného buněk: kameny ve stěně. [x, y, jas, kámen materiálu?]."""
    reach = shape.reach_max()
    count = max(12, int(math.pi * reach * reach / (cell * cell)))
    cells = []
    for _ in range(count):
        angle = rng.uniform(-math.pi, math.pi)
        dist = math.sqrt(rng.random()) * reach
        cells.append((shape.cx + math.cos(angle) * dist, shape.cy + math.sin(angle) * dist, rng.uniform(0.78, 1.18), rng.random()))
    return cells


def _nearest(cells, x: float, y: float) -> tuple[int, float, float]:
    best = 1e9
    second = 1e9
    found = 0
    for index, (cx, cy, _bias, _ore) in enumerate(cells):
        dist = (x - cx) ** 2 + (y - cy) ** 2
        if dist < best:
            second = best
            best = dist
            found = index
        elif dist < second:
            second = dist
    return found, math.sqrt(best), math.sqrt(second)


def _put(pixels, x: int, y: int, value: float, ore: float, blue: float) -> None:
    r = int(round(max(0.0, min(1.0, value / VALUE_SCALE)) * 255))
    pixels[x, y] = (r, int(round(ore * 255)), int(round(max(0.0, min(1.0, blue)) * 255)), 255)


def draw_rim(size: int, pit: Pit, rng: random.Random, salt: int) -> Image.Image:
    """Okraj: val hlíny a sutě kolem ústí, u ústí pár vysypaných kamenů materiálu."""
    image = blank(size)
    pixels = image.load()
    outer = pit.outer[1]
    mouth = pit.mouth[1]
    stones = []
    for _ in range(rng.randint(22, 32)):
        angle = rng.uniform(-math.pi, math.pi)
        along = rng.uniform(0.05, 0.95)
        inner = mouth.radius * mouth.mul(angle)
        out = outer.radius * outer.mul(angle)
        dist = inner + (out - inner) * along
        ore = 1.0 if along < 0.45 and rng.random() < 0.3 else 0.0
        stones.append((
            mouth.cx + math.cos(angle) * dist,
            mouth.cy + math.sin(angle) * dist,
            rng.uniform(1.6, 3.6) if ore else rng.uniform(1.8, 4.6),
            rng.uniform(0.85, 1.2),
            ore,
            rng.uniform(-math.pi, math.pi),
        ))
    reach = outer.reach_max() + 2
    lo = max(0, int(outer.cx - reach))
    hi = min(size - 1, int(outer.cx + reach))
    for y in range(lo, hi + 1):
        for x in range(lo, hi + 1):
            px = x + 0.5
            py = y + 0.5
            if outer.norm(px, py) > 1.0:
                continue
            in_lip = -mouth.edge(px, py)
            if in_lip < 0:
                continue
            to_out = outer.edge(px, py)
            across = in_lip + to_out
            u = in_lip / max(across, 1.0)
            dx = px - mouth.cx
            dy = py - mouth.cy
            dist = math.hypot(dx, dy) or 1.0
            ndx = dx / dist
            ndy = dy / dist
            # Val: hřbet je ve třetině od ústí. Vnitřní svah padá do díry, vnější ven.
            crest = 0.35
            if u < crest:
                slope = (crest - u) / crest
                nx, ny = -ndx, -ndy
            else:
                slope = (u - crest) / (1 - crest)
                nx, ny = ndx, ndy
            lit = nx * LIGHT[0] + ny * LIGHT[1]
            value = 0.82 + 0.3 * lit * slope
            value *= 0.9 + 0.16 * hash01(x, y, salt)
            value *= 0.92 + 0.14 * hash01(x // 3, y // 3, salt + 7)
            # Hrana ústí tmavne do díry.
            if in_lip < 4.0:
                value *= 0.55 + 0.45 * in_lip / 4.0
            if to_out < 2.0:
                value *= 0.82 + 0.09 * to_out
            ore = 0.0
            blue = 0.0
            for sx, sy, sr, bias, sore, tilt in stones:
                ddx = px - sx
                ddy = py - sy
                if ddx * ddx + ddy * ddy > sr * sr * 1.4:
                    continue
                rx = ddx * math.cos(tilt) + ddy * math.sin(tilt)
                ry = (-ddx * math.sin(tilt) + ddy * math.cos(tilt)) * 1.3
                if rx * rx + ry * ry > sr * sr:
                    continue
                side = (ddx * LIGHT[0] + ddy * LIGHT[1]) / sr
                value = (0.9 + 0.32 * max(-1.0, min(1.0, side))) * bias
                ore = sore
                if sore and hash01(x, y, salt + 13) > 0.8:
                    blue = 0.1 + 0.9 * hash01(x, y, salt + 17)
                break
            _put(pixels, x, y, value, ore, blue)
    return image


def draw_wall(size: int, pit: Pit, layer: int, rng: random.Random, salt: int) -> Image.Image:
    """Stěna nebo dno: kameny jako Voroného buňky, část z nich je materiál dolu.
    Hlubší vrstva je tmavší. Stěna svítí, kde se obrací ke světlu, tedy na protější straně."""
    image = blank(size)
    pixels = image.load()
    outer = pit.outer[layer]
    mouth = pit.mouth.get(layer)
    above = pit.mouth[layer - 1]
    floor = mouth is None
    depth = (layer - 1) / max(pit.layers - 1, 1)
    cells = _cells(rng, outer, 5.2 if not floor else 4.6)
    share = ORE_SHARE.get(layer, 0.3)
    lamp = None
    if floor:
        angle = rng.uniform(-math.pi, math.pi)
        reach = rng.uniform(0.0, 0.25) * outer.radius
        lamp = (outer.cx + math.cos(angle) * reach, outer.cy + math.sin(angle) * reach)
    reach = outer.reach_max() + 2
    lo = max(0, int(outer.cx - reach))
    hi = min(size - 1, int(outer.cx + reach))
    for y in range(lo, hi + 1):
        for x in range(lo, hi + 1):
            px = x + 0.5
            py = y + 0.5
            if outer.norm(px, py) > 1.0:
                continue
            lip = 99.0
            if mouth is not None:
                lip = -mouth.edge(px, py)
                if lip < 0:
                    continue
            dx = px - outer.cx
            dy = py - outer.cy
            dist = math.hypot(dx, dy) or 1.0
            # Stěna nálevky se dívá do středu: na pravé dolní straně ke světlu.
            lit = -(dx / dist) * LIGHT[0] - (dy / dist) * LIGHT[1]
            if floor:
                lit *= 0.2
            index, near, second = _nearest(cells, px, py)
            cx, cy, bias, roll = cells[index]
            is_ore = roll < share
            border = second - near < 1.1
            value = (0.62 - 0.2 * depth) * (0.86 + 0.3 * lit)
            # Kámen je vypouklý: strana ke světlu světlejší.
            bulge = ((px - cx) * LIGHT[0] + (py - cy) * LIGHT[1]) / 4.0
            value *= bias * (1.0 + 0.16 * max(-1.0, min(1.0, bulge)))
            value *= 0.92 + 0.14 * hash01(x, y, salt)
            # Pod hranou vrstvy nad ní je stín.
            under = above.edge(px, py)
            if 0 <= under < 5.0:
                value *= 0.62 + 0.38 * under / 5.0
            if lip < 3.0:
                value *= 1.0 + 0.18 * (1.0 - lip / 3.0) * max(0.0, lit)
            ore = 0.0
            blue = 0.0
            if border:
                value *= 0.55
            elif is_ore:
                ore = 1.0
                value = (0.62 + 0.5 * max(-1.0, min(1.0, bulge))) * bias
                if hash01(x, y, salt + 23) > 0.86:
                    blue = 0.1 + 0.9 * hash01(index, layer, salt + 29)
            if lamp is not None:
                ldx = px - lamp[0]
                ldy = py - lamp[1]
                if abs(ldx) <= 2.0 and -3.0 <= ldy <= 2.5:
                    # Lucerna: tmavý rámeček, uprostřed plamen.
                    ore = 0.0
                    value = 0.25
                    blue = 0.0
                    if abs(ldx) <= 1.0 and -2.0 <= ldy <= 1.5:
                        value = 1.3
                        blue = 1.0 - 0.3 * abs(ldy + 0.25) / 1.75
            _put(pixels, x, y, value, ore, blue)
    return image


def canvas_size(preset: dict) -> int:
    half = float(preset["widths"][1]) * 0.5 * (1.0 + float(preset.get("rough", 0.12)) * 2.2) + 6
    size = int(math.ceil(half * 2))
    return size + size % 2


def draw_pit(preset: dict, rng: random.Random, salt: int) -> dict[int, Image.Image]:
    size = canvas_size(preset)
    pit = make_pit(preset, size, rng)
    frames = {1: draw_rim(size, pit, rng, salt + 1)}
    for layer in range(2, pit.layers + 1):
        frames[layer] = draw_wall(size, pit, layer, rng, salt + layer * 17)
    return frames


# --- Náhled: obarví masky jako shader při plném světle lucerny ---

LAMP = (255, 178, 92)


def colorize(frame: Image.Image, rock: tuple[int, int, int], ore: tuple[int, int, int], depth: float) -> Image.Image:
    out = blank(frame.width)
    src = frame.load()
    dst = out.load()
    center = frame.width / 2
    for y in range(frame.height):
        for x in range(frame.width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            value = r / 255 * VALUE_SCALE
            mask = g / 255
            body = mix_rgb(shade(rock, value), shade(ore, value * 1.1), mask)
            dist = math.hypot(x + 0.5 - center, y + 0.5 - center)
            reach = 70 - 36 * depth
            glow = (0.12 + 0.75 * depth) * math.exp(-(dist / reach) ** 2)
            body = tuple(min(255, int(body[i] * (1 + glow * LAMP[i] / 255 * 1.4))) for i in range(3))
            if mask < 0.5 and b > 0:
                body = mix_rgb(body, (255, 236, 170), b / 255)
            dst[x, y] = (*body, a)
    return out


def preview(name: str, preset: dict, variants: list[dict[int, Image.Image]], out: Path) -> None:
    ores = [(196, 165, 106), (200, 40, 50), (60, 120, 210), (40, 170, 90)]
    try:
        info = json.loads(CRYSTAL_INFO.read_text(encoding="utf-8"))
        ores = [parse_hex(item["color"]) for item in info["materials"].values()] or ores
    except (OSError, KeyError, ValueError):
        pass
    rim = parse_hex(preset["color"])
    wall = parse_hex(preset["wall"])
    heights = {layer: float(preset["height"][layer]) for layer in preset["height"]}
    deepest = min(heights.values()) or -1.0
    sheets = []
    shifted = []
    for index, frames in enumerate(variants):
        ore = ores[(index * 3 + 2) % len(ores)]
        for shift, bucket in (((0.0, 0.0), sheets), ((8.0, 5.0), shifted)):
            image = blank(frames[1].width)
            for layer in sorted(frames, key=lambda key: heights[key]):
                depth = heights[layer] / deepest
                painted = colorize(frames[layer], rim if layer == 1 else wall, ore, depth)
                blit_at(image, painted, shift[0] * heights[layer], shift[1] * heights[layer])
            bucket.append(image)
    labels = [f"{index:02d}" for index in range(len(variants))]
    contact_sheet(sheets, labels, out / f"{name}.png", 3)
    contact_sheet(shifted, labels, out / f"{name}_kraj.png", 3)


def generate_mine(name: str, preset: dict, out_dir: Path, preview_dir: Path, seed: int, count: int) -> list[int]:
    """Vrstvy všech variant do atlasů v out_dir. Vrací šířky uložených buněk."""
    layers = int(preset["layers"])
    salt = sum(ord(char) for char in name)
    variants = []
    for index in range(count):
        rng = random.Random(seed + salt + index * 7919)
        variants.append(draw_pit(preset, rng, salt + index * 101))
    saved = []
    for layer in range(1, layers + 1):
        fitted = crop_square([frames[layer] for frames in variants])
        saved.append(fitted[0].width)
        pack_atlas(fitted).save(out_dir / f"layer_{layer}.png")
    preview(name, preset, variants, preview_dir)
    return saved


if __name__ == "__main__":
    from gen_rocks import ROCKS, generate_rocks, write_rock_info

    generate_rocks("dul", ROCKS["dul"])
    print(write_rock_info(ROCKS))
