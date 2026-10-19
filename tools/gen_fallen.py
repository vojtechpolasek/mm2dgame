#!/usr/bin/env python3
"""Padlý strom pro pohled kolmo shora: kmen zlomený u země leží vedle pařezu.

Vrstva 1 je na zemi (výška 0): pařez s třískami po zlomu a stín ležícího kmene.
Vrstva 2 je ležící kmen se silnými větvemi, vrstva 3 koruna s pár listy. Kmen je
o pětinu užší než pařez. Překáží jen kmen s pařezem: kapsle (úsečka od pařezu ke
konci kmene, poloměr se zužuje) jde do capsule.json vedle atlasů a odtud do rocks.json.
Koruna v chůzi nepřekáží.

Kmen leží v obrázku vodorovně, pařez vlevo, koruna vpravo. Ve hře se strom otočí
náhodně jako skála. Střed obrázku je uprostřed celého stromu, leží vždycky na kmeni,
obrys paty z něj proto jde po paprscích.

Generuje ho gen_rocks.py (druh s "fallen": True), sám se spustí jen pro náhled:
  py tools/gen_fallen.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

from PIL import Image

from gen_terrain_tiles import parse_hex
from gen_trees import (
    LEAVES,
    Branch,
    Grow,
    blank,
    blit_anchor,
    blit_at,
    contact_sheet,
    crop_square,
    curve_points,
    draw_stump,
    hash01,
    make_leaf_sprite,
    mix_rgb,
    pack_atlas,
    paint_branch,
    shade,
    stroke,
    vary_color,
)

# Světlé dřevo na lomu a třískách.
WOOD = (204, 170, 118)
# Posun vrstev v náhledu „u kraje“, stejný jako u skal: px na metr výšky.
EDGE_SHIFT = (480.0 * 0.0052, 260.0 * 0.0052)


def canvas_size(preset: dict) -> int:
    """Plátno pojme nejdelší kmen, pařez s kořeny i korunu, střed je uprostřed stromu."""
    span = float(preset["length"][1]) + float(preset["crown"][1]) + float(preset["stump"]["radius"]) * 1.6 + 30
    half = max(span / 2, float(preset["crown"][1])) + 24
    size = int(math.ceil(half * 2))
    return size + size % 2


class Plan:
    """Rozměry jedné varianty. u je vzdálenost podél kmene od lomu, v kolmo na něj."""

    def __init__(self, preset: dict, rng: random.Random, size: int) -> None:
        self.length = rng.uniform(*preset["length"])
        self.crown = rng.uniform(*preset["crown"])
        self.stump_r = float(preset["stump"]["radius"]) * rng.uniform(0.9, 1.1)
        # Kmen je zlomený kus nad zemí, kde už je užší než pařez s náběhem kořenů.
        self.base_w = self.stump_r * 2 * rng.uniform(0.67, 0.74)
        self.tip_w = self.base_w * rng.uniform(0.55, 0.65)
        # Pařez stojí kousek za lomem, kmen padl od něj.
        self.stump_u = -self.stump_r * 1.05
        low = self.stump_u - self.stump_r - 12
        high = self.length + self.crown * 0.85
        self.offset = (low + high) / 2
        self.cx = size / 2
        self.cy = size / 2
        # Lehký ohyb osy kmene, ať všechny neleží jako pravítko.
        self.sag = rng.uniform(-3.0, 3.0)

    def at(self, u: float, v: float = 0.0) -> tuple[float, float]:
        t = u / max(self.length, 1.0)
        return (self.cx + u - self.offset, self.cy + v + self.sag * 4 * t * (1 - t))

    def width(self, u: float) -> float:
        t = min(1.0, max(0.0, u / self.length))
        return self.base_w + (self.tip_w - self.base_w) * t

    def local(self, x: float, y: float) -> tuple[float, float]:
        u = x - self.cx + self.offset
        t = u / max(self.length, 1.0)
        return u, y - self.cy - self.sag * 4 * t * (1 - t)


def capsule(plan: Plan) -> list[float]:
    """Kapsle kmene od středu obrázku: pařez, konec kmene a poloměry v nich. Ohyb osy se přičte k poloměru."""
    ax, ay = plan.at(plan.stump_u)
    bx, by = plan.at(plan.length)
    ra = max(plan.stump_r * 0.8, plan.base_w / 2) + abs(plan.sag)
    rb = plan.tip_w / 2 + abs(plan.sag) * 0.5
    return [round(value, 1) for value in (ax - plan.cx, ay - plan.cy, bx - plan.cx, by - plan.cy, ra, rb)]


def broken_end(plan: Plan, v: float, salt: int) -> float:
    """Kde kmen začíná: zubatý lom, třísky vyčnívají až o 12 px."""
    half = plan.base_w / 2
    t = (v + half) / max(plan.base_w, 1.0)
    teeth = abs(math.sin(t * math.pi * 3.0 + salt)) * 7 + hash01(int(v + 50), 0, salt) * 5
    return -teeth * (1.0 - abs(t - 0.5))


def draw_ground(plan: Plan, size: int, rng: random.Random, bark: tuple[int, int, int], salt: int) -> Image.Image:
    image = blank(size)
    pixels = image.load()
    # Stín kmene: plný pod kmenem (obrys paty), měkký okraj.
    x0 = int(plan.at(-4)[0]) - 6
    x1 = int(plan.at(plan.length)[0]) + 6
    reach = int(plan.base_w / 2 + 10)
    for x in range(max(0, x0), min(size, x1)):
        for y in range(max(0, int(plan.cy) - reach - 8), min(size, int(plan.cy) + reach + 8)):
            u, v = plan.local(x + 0.5 - 2, y + 0.5 - 3)
            if u < broken_end(plan, v, salt) or u > plan.length:
                continue
            half = plan.width(u) / 2
            out = abs(v) - half
            if out > 4:
                continue
            alpha = 170 if out <= 0 else int(170 * (1 - out / 4) * 0.6)
            pixels[x, y] = (22, 20, 14, alpha)
    # Řídký stín koruny, slabší než obrys paty, aby korunou šlo projít.
    end = plan.at(plan.length)
    for _ in range(26):
        angle = rng.uniform(-1.4, 1.4)
        dist = rng.uniform(10, plan.crown * 0.85)
        cx = end[0] + math.cos(angle) * dist + 3
        cy = end[1] + math.sin(angle) * dist * 1.1 + 4
        radius = rng.uniform(6, 14)
        for y in range(int(cy - radius), int(cy + radius) + 1):
            for x in range(int(cx - radius), int(cx + radius) + 1):
                if not (0 <= x < size and 0 <= y < size):
                    continue
                d = math.hypot(x - cx, y - cy) / radius
                if d > 1:
                    continue
                alpha = int(60 * (1 - d))
                old = pixels[x, y]
                if old[3] < alpha:
                    pixels[x, y] = (22, 20, 14, alpha)
    # Pařez s kořeny a třískami na straně, kam strom padl.
    sx, sy = plan.at(plan.stump_u)
    draw_stump(image, rng, sx, sy, shade(bark, 1.15), plan.stump_r, plan.stump_r * 1.4)
    for _ in range(rng.randint(4, 7)):
        angle = rng.uniform(-0.9, 0.9)
        start = (sx + math.cos(angle) * plan.stump_r * 0.6, sy + math.sin(angle) * plan.stump_r * 0.6)
        length = rng.uniform(5, 11)
        width = rng.uniform(1.6, 3.0)
        tip = (start[0] + math.cos(angle) * length, start[1] + math.sin(angle) * length)
        splinter = Branch(p0=start, p1=((start[0] + tip[0]) / 2, (start[1] + tip[1]) / 2), p2=tip, base_w=width, tip_w=0.8,
                          color=shade(WOOD, rng.uniform(0.85, 1.05)), salt=rng.randrange(1, 100000), sort_y=0)
        stroke(image, splinter)
    # Světlý lom na pařezu.
    for y in range(int(sy - plan.stump_r), int(sy + plan.stump_r) + 1):
        for x in range(int(sx - plan.stump_r), int(sx + plan.stump_r) + 1):
            d = math.hypot(x - sx, y - sy) / (plan.stump_r * 0.72)
            if d <= 1 and hash01(x, y, salt + 5) < 0.85:
                pixels[x, y] = (*shade(WOOD, 0.8 + 0.25 * hash01(x // 2, y, salt)), 255)
    return image


def limb(plan: Plan, rng: random.Random, origin: tuple[float, float], heading: float, length: float,
         base_w: float, tip_w: float, bark: tuple[int, int, int]) -> Branch:
    bend = length * rng.choice((-1.0, 1.0)) * rng.uniform(0.1, 0.3)
    p0, p1, p2 = curve_points(origin, heading, length, bend)
    return Branch(p0=p0, p1=p1, p2=p2, base_w=base_w, tip_w=tip_w, color=shade(bark, rng.uniform(0.9, 1.08)),
                  salt=rng.randrange(1, 100000), sort_y=p0[1])


def draw_trunk(plan: Plan, size: int, rng: random.Random, bark: tuple[int, int, int], moss: tuple[int, int, int] | None,
               salt: int) -> tuple[Image.Image, list[Branch]]:
    """Ležící kmen: válec s podélnou kůrou, zubatý lom, pahýly a silné větve koruny."""
    image = blank(size)
    # Pahýly větví podél kmene, kreslí se pod kmen.
    for _ in range(rng.randint(3, 5)):
        u = rng.uniform(0.3, 0.88) * plan.length
        side = rng.choice((-1.0, 1.0))
        edge = plan.at(u, side * plan.width(u) * 0.35)
        heading = (math.pi / 2 if side > 0 else -math.pi / 2) + rng.uniform(-0.6, 0.6)
        stroke(image, limb(plan, rng, edge, heading, rng.uniform(10, 24), rng.uniform(4.0, 6.5), 2.5, bark))
    pixels = image.load()
    x0 = int(plan.at(-14)[0])
    x1 = int(plan.at(plan.length + 2)[0])
    reach = int(plan.base_w / 2 + 8)
    patch_salt = salt + 31
    for x in range(max(0, x0), min(size, x1)):
        for y in range(max(0, int(plan.cy) - reach - 8), min(size, int(plan.cy) + reach + 8)):
            u, v = plan.local(x + 0.5, y + 0.5)
            start = broken_end(plan, v, salt)
            if u < start or u > plan.length:
                continue
            half = plan.width(u) / 2
            if abs(v) > half:
                continue
            across = v / half
            # Válec: světlo shora zleva, kraje tmavší.
            value = 0.92 - 0.2 * across - 0.22 * across * across
            groove = hash01(int(u / 7), int((v + 40) / 2.2), salt)
            if groove > 0.78:
                value *= 0.72
            value *= 0.92 + 0.14 * hash01(x, y, salt + 3)
            color = shade(bark, value)
            if moss is not None and across < 0.2:
                patch = hash01(int(u / 18), int((v + 40) / 9), patch_salt) * 0.7 + hash01(x // 3, y // 3, patch_salt + 1) * 0.3
                if patch > 0.66:
                    color = mix_rgb(color, shade(moss, 0.8 + 0.3 * hash01(x, y, patch_salt + 2)), 0.85)
            # Lom: světlé vlákno dřeva kousek za zubatým koncem.
            if u - start < 3.5:
                color = shade(WOOD, 0.75 + 0.3 * hash01(int(u), int(v + 40), salt + 7))
            pixels[x, y] = (*color, 255)
    # Silné větve koruny vyrůstají z konce kmene a rozbíhají se dopředu a do stran.
    end = plan.at(plan.length)
    limbs = []
    count = rng.randint(4, 6)
    for index in range(count):
        heading = -1.25 + 2.5 * (index + rng.uniform(0.2, 0.8)) / count
        length = plan.crown * rng.uniform(0.5, 0.78)
        # Silná větev může vyrůst i kus před koncem kmene.
        at = plan.length - rng.uniform(0, 0.18) * plan.length
        start = plan.at(at, rng.uniform(-0.3, 0.3) * plan.width(at))
        branch = limb(plan, rng, start, heading, length, plan.width(at) * rng.uniform(0.55, 0.85), 3.0, bark)
        limbs.append(branch)
        stroke(image, branch)
    return image, limbs


def draw_crown(plan: Plan, size: int, rng: random.Random, bark: tuple[int, int, int], limbs: list[Branch],
               leaf: Image.Image, leaf_share: float) -> Image.Image:
    """Koruna: tenčí větve z konců silných a jen pár listů, zčásti zavadlých."""
    from gen_trees import bezier

    image = blank(size)
    ctx = Grow(rng=rng, cx=plan.cx, cy=plan.cy, radii={}, densities={}, branch_levels=1, wood=bark, leaf=leaf,
               hue_bias=rng.uniform(-6, 6), value_bias=rng.uniform(0.92, 1.0))
    twigs: list[Branch] = []
    for parent in limbs:
        for _ in range(rng.randint(5, 8)):
            t = rng.uniform(0.35, 1.0)
            origin = bezier(parent.p0, parent.p1, parent.p2, t)
            direction = math.atan2(parent.p2[1] - parent.p0[1], parent.p2[0] - parent.p0[0])
            heading = direction + rng.uniform(-0.9, 0.9)
            twig = limb(plan, rng, origin, heading, plan.crown * rng.uniform(0.2, 0.42), 3.0, 1.4, bark)
            for _ in range(rng.randint(1, 3)):
                sub_t = rng.uniform(0.4, 0.95)
                sub_origin = bezier(twig.p0, twig.p1, twig.p2, sub_t)
                twig.children.append(limb(plan, rng, sub_origin, heading + rng.uniform(-1.0, 1.0),
                                          plan.crown * rng.uniform(0.08, 0.18), 1.8, 1.0, bark))
            twigs.append(twig)
    for twig in sorted(twigs, key=lambda item: item.sort_y):
        paint_branch(image, twig)
    # Málo listí: jen na koncích některých větviček. Část listů zvadlá do žluta a hněda.
    for twig in twigs:
        if rng.random() > leaf_share:
            continue
        for _ in range(rng.randint(1, 3)):
            t = rng.uniform(0.6, 1.0)
            pos = bezier(twig.p0, twig.p1, twig.p2, t)
            heading = rng.uniform(0, math.tau)
            wilted = rng.random() < 0.4
            ctx.hue_bias = rng.uniform(-40, -25) if wilted else rng.uniform(-6, 6)
            sprite, anchor, _centered = make_leaf_sprite(ctx, heading, 2.0, value_mul=0.8 if wilted else 1.0)
            blit_anchor(image, sprite, anchor, pos)
    return image


def draw_fallen(preset: dict, rng: random.Random, salt: int, leaf: Image.Image) -> tuple[dict[int, Image.Image], list[float]]:
    size = canvas_size(preset)
    plan = Plan(preset, rng, size)
    bark = vary_color(parse_hex(preset["color"]), rng, hue=5, value=0.06)
    moss = parse_hex(preset["moss"]) if preset.get("moss") and rng.random() < 0.6 else None
    ground = draw_ground(plan, size, rng, bark, salt)
    trunk, limbs = draw_trunk(plan, size, rng, bark, moss, salt)
    crown = draw_crown(plan, size, rng, bark, limbs, leaf, float(preset.get("leaf_share", 0.3)))
    return {1: ground, 2: trunk, 3: crown}, capsule(plan)


def stack(frames: dict[int, Image.Image], heights: dict[int, float], shift: tuple[float, float]) -> Image.Image:
    image = blank(frames[1].width)
    for layer in sorted(frames):
        blit_at(image, frames[layer], shift[0] * heights[layer], shift[1] * heights[layer])
    return image


def generate_fallen(name: str, preset: dict, out_dir: Path, preview_dir: Path, seed: int, count: int) -> list[int]:
    """Vrstvy všech variant do atlasů v out_dir. Vrací šířky uložených buněk."""
    leaf = Image.open(LEAVES / preset.get("leaf", "leaf1.png")).convert("RGBA")
    salt = sum(ord(char) for char in name)
    heights = {layer: float(preset["height"][layer]) for layer in (1, 2, 3)}
    variants = []
    capsules = []
    for index in range(count):
        rng = random.Random(seed + salt + index * 7919)
        frames, shape = draw_fallen(preset, rng, salt + index * 101, leaf)
        variants.append(frames)
        capsules.append(shape)
    (out_dir / "capsule.json").write_text(json.dumps(capsules) + "\n", encoding="utf-8")
    saved = []
    for layer in (1, 2, 3):
        fitted = crop_square([frames[layer] for frames in variants])
        saved.append(fitted[0].width)
        pack_atlas(fitted).save(out_dir / f"layer_{layer}.png")
    labels = [f"{index:02d}" for index in range(count)]
    contact_sheet([stack(frames, heights, (0.0, 0.0)) for frames in variants], labels, preview_dir / f"{name}.png", 1)
    contact_sheet([stack(frames, heights, EDGE_SHIFT) for frames in variants], labels, preview_dir / f"{name}_kraj.png", 1)
    first = variants[0]
    panels = [first[1], first[2], first[3], stack(first, heights, (0.0, 0.0))]
    contact_sheet(panels, [f"vrstva {layer} · {heights[layer]:g} m" for layer in (1, 2, 3)] + ["strom"], preview_dir / f"{name}_layers.png", 1)
    return saved


if __name__ == "__main__":
    from gen_rocks import ROCKS, generate_rocks, write_rock_info

    generate_rocks("padly_strom", ROCKS["padly_strom"])
    print(write_rock_info(ROCKS))
