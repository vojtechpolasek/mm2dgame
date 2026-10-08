#!/usr/bin/env python3
"""Složí stromy pro pohled kolmo shora.

Každá vrstva je průhledný atlas 3×3. Jedno políčko je jedna varianta.
Kreslí se na společné plátno, uložená buňka je ořezaná na obsah vrstvy
a střed zůstává, ať se patra při vystředění v Godotu nerozjedou.
Nejvyšší vrstva je hromada listů, hustší uprostřed. Každá nižší je vějíř
větví: silnější konec míří ke středu a na větvích sedí díly z vrstev nad ní.
Pařez je vlastní atlas a při skládání zůstává uprostřed.

Příklad:
  py tools/gen_trees.py
  py tools/gen_trees.py --name strom1
"""

from __future__ import annotations

import argparse
import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from gen_terrain_tiles import hsv_to_rgb, parse_hex, rgb_to_hsv

ROOT = Path(__file__).resolve().parent.parent
LEAVES = ROOT / "tools" / "assets" / "leaves"
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "trees"
TREES_PATH = OUT_DIR / "trees.json"
PREVIEW = ROOT / "tools" / "preview"
GRASS = (0x4F, 0x9A, 0x3C)
ATLAS_COLUMNS = 3

WIDTH_JITTER = 0.10
DENSITY_JITTER = 0.12
LEAF_HUE = 14.0
LEAF_VALUE = (0.78, 1.14)
LEAF_BEND = 3.5


def shade(rgb: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(round(channel * factor)))) for channel in rgb)


def mix_rgb(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vary_color(
    rgb: tuple[int, int, int],
    rng: random.Random,
    hue: float,
    value: float,
) -> tuple[int, int, int]:
    base_h, base_s, base_v = rgb_to_hsv(*rgb)
    return hsv_to_rgb(
        base_h + rng.uniform(-hue, hue),
        min(1.0, max(0.0, base_s * rng.uniform(0.94, 1.05))),
        min(1.0, max(0.0, base_v * rng.uniform(1 - value, 1 + value))),
    )


def hash01(x: int, y: int, salt: int = 0) -> float:
    n = (x * 374761393 + y * 668265263 + salt * 1442695041) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return (n & 255) / 255.0


def jitter(rng: random.Random, value: float, amount: float) -> float:
    return value * rng.uniform(1 - amount, 1 + amount)


def blit_at(canvas: Image.Image, sprite: Image.Image, x: float, y: float) -> None:
    if sprite.width == 0 or sprite.height == 0:
        return
    left = int(round(x))
    top = int(round(y))
    crop_l = max(0, -left)
    crop_t = max(0, -top)
    crop_r = min(sprite.width, canvas.width - left)
    crop_b = min(sprite.height, canvas.height - top)
    if crop_l >= crop_r or crop_t >= crop_b:
        return
    piece = sprite.crop((crop_l, crop_t, crop_r, crop_b))
    canvas.alpha_composite(piece, (left + crop_l, top + crop_t))


def blit_anchor(
    canvas: Image.Image,
    sprite: Image.Image,
    anchor: tuple[float, float],
    dest: tuple[float, float],
) -> None:
    blit_at(canvas, sprite, dest[0] - anchor[0], dest[1] - anchor[1])


def blit_center(canvas: Image.Image, sprite: Image.Image, dest: tuple[float, float]) -> None:
    blit_at(canvas, sprite, dest[0] - sprite.width / 2, dest[1] - sprite.height / 2)


def bend_leaf(src: Image.Image, bend: float) -> Image.Image:
    if abs(bend) < 0.25:
        return src.copy()
    width, height = src.size
    margin = int(math.ceil(abs(bend))) + 1
    out = Image.new("RGBA", (width + margin * 2, height), (0, 0, 0, 0))
    src_px = src.load()
    out_px = out.load()
    cx = (width - 1) / 2
    cx_out = margin + cx
    for y in range(height):
        t = y / (height - 1) if height > 1 else 0.0
        offset = bend * (1 - t) ** 2
        for x in range(out.width):
            ix = int(round(x - cx_out - offset + cx))
            if 0 <= ix < width:
                out_px[x, y] = src_px[ix, y]
    return out


def tint_leaf(src: Image.Image, hue_shift: float, sat_scale: float, value_scale: float) -> Image.Image:
    out = src.copy()
    pixels = out.load()
    for y in range(out.height):
        for x in range(out.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            hue, sat, value = rgb_to_hsv(red, green, blue)
            red, green, blue = hsv_to_rgb(
                hue + hue_shift,
                min(1.0, max(0.0, sat * sat_scale)),
                min(1.0, max(0.0, value * value_scale)),
            )
            pixels[x, y] = (red, green, blue, alpha)
    return out


def scale_nearest(src: Image.Image, scale: float) -> Image.Image:
    width = max(1, int(round(src.width * scale)))
    height = max(1, int(round(src.height * scale)))
    if (width, height) == src.size:
        return src
    return src.resize((width, height), Image.Resampling.NEAREST)


def stem_point(src: Image.Image) -> tuple[float, float]:
    pixels = src.load()
    for y in range(src.height - 1, -1, -1):
        cols = [x for x in range(src.width) if pixels[x, y][3]]
        if cols:
            return (sum(cols) / len(cols), float(y))
    return ((src.width - 1) / 2, (src.height - 1) / 2)


def rotation_for_heading(heading: float) -> float:
    """Stupně proti směru hodin, aby špička listu mířila podél heading (y dolů, 0 = +x)."""
    return -math.degrees(heading + math.pi / 2)


def _rotate_raw(
    src: Image.Image,
    degrees_ccw: float,
    anchor: tuple[float, float],
) -> tuple[Image.Image, tuple[float, float]]:
    rad = math.radians(degrees_ccw)
    cos = math.cos(rad)
    sin = math.sin(rad)
    cx = (src.width - 1) / 2
    cy = (src.height - 1) / 2
    vx = anchor[0] - cx
    vy = anchor[1] - cy
    rx = vx * cos + vy * sin
    ry = -vx * sin + vy * cos
    rotated = src.rotate(degrees_ccw, resample=Image.Resampling.NEAREST, expand=True)
    ncx = (rotated.width - 1) / 2
    ncy = (rotated.height - 1) / 2
    return rotated, (ncx + rx, ncy + ry)


def _majority(colors: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    counts: dict[tuple[int, int, int], int] = {}
    best = colors[0]
    best_count = 0
    for color in colors:
        count = counts.get(color, 0) + 1
        counts[color] = count
        if count > best_count:
            best = color
            best_count = count
    return best


def _downscale_crisp(
    src: Image.Image,
    scale: int,
    anchor: tuple[float, float],
) -> tuple[Image.Image, tuple[float, float]]:
    width = max(1, math.ceil(src.width / scale))
    height = max(1, math.ceil(src.height / scale))
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    src_px = src.load()
    out_px = out.load()
    for y in range(height):
        for x in range(width):
            colors: list[tuple[int, int, int]] = []
            for oy in range(scale):
                sy = y * scale + oy
                if sy >= src.height:
                    continue
                for ox in range(scale):
                    sx = x * scale + ox
                    if sx >= src.width:
                        continue
                    pixel = src_px[sx, sy]
                    if pixel[3] > 128:
                        colors.append((pixel[0], pixel[1], pixel[2]))
            if len(colors) >= 2:
                out_px[x, y] = (*_majority(colors), 255)
    small = (
        (anchor[0] - (scale - 1) / 2) / scale,
        (anchor[1] - (scale - 1) / 2) / scale,
    )
    return out, small


def rotate_about(
    src: Image.Image,
    degrees_ccw: float,
    anchor: tuple[float, float],
) -> tuple[Image.Image, tuple[float, float]]:
    # Větší obrázek se otočí a složí zpátky, aby v listu nezůstaly díry.
    scale = 3
    big = src.resize((src.width * scale, src.height * scale), Image.Resampling.NEAREST)
    big_anchor = (anchor[0] * scale + (scale - 1) / 2, anchor[1] * scale + (scale - 1) / 2)
    rotated, rotated_anchor = _rotate_raw(big, degrees_ccw, big_anchor)
    return _downscale_crisp(rotated, scale, rotated_anchor)


def fit_length(
    origin: tuple[float, float],
    heading: float,
    length: float,
    cx: float,
    cy: float,
    max_radius: float,
) -> float:
    dx = math.cos(heading)
    dy = math.sin(heading)
    ox = origin[0] - cx
    oy = origin[1] - cy
    along = ox * dx + oy * dy
    disc = along * along - (ox * ox + oy * oy - max_radius * max_radius)
    if disc < 0:
        return length
    reach = -along + math.sqrt(disc)
    if reach <= 0:
        return 0.0
    return min(length, reach)


def bezier(p0: tuple[float, float], p1: tuple[float, float], p2: tuple[float, float], t: float) -> tuple[float, float]:
    u = 1 - t
    return (
        u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
        u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
    )


def bezier_tangent(p0: tuple[float, float], p1: tuple[float, float], p2: tuple[float, float], t: float) -> tuple[float, float]:
    u = 1 - t
    return (
        2 * u * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0]),
        2 * u * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1]),
    )


def curve_points(
    origin: tuple[float, float],
    heading: float,
    length: float,
    bend: float,
) -> tuple[tuple[float, float], tuple[float, float], tuple[float, float]]:
    dx = math.cos(heading)
    dy = math.sin(heading)
    p0 = origin
    p2 = (origin[0] + dx * length, origin[1] + dy * length)
    p1 = ((p0[0] + p2[0]) / 2 - dy * bend, (p0[1] + p2[1]) / 2 + dx * bend)
    return p0, p1, p2


def width_at(t: float, base_w: float, tip_w: float) -> float:
    return tip_w + (base_w - tip_w) * (1 - t) ** 0.82


@dataclass
class LeafStamp:
    image: Image.Image
    anchor: tuple[float, float]
    x: float
    y: float
    centered: bool = False


@dataclass
class Branch:
    p0: tuple[float, float]
    p1: tuple[float, float]
    p2: tuple[float, float]
    base_w: float
    tip_w: float
    color: tuple[int, int, int]
    salt: int
    sort_y: float
    snow: tuple[int, int, int] | None = None
    leaves: list[LeafStamp] = field(default_factory=list)
    children: list[Branch] = field(default_factory=list)


@dataclass
class Grow:
    rng: random.Random
    cx: float
    cy: float
    radii: dict[int, float]
    densities: dict[int, float]
    branch_levels: int
    wood: tuple[int, int, int]
    leaf: Image.Image
    hue_bias: float
    value_bias: float
    leaves_on_branch: int | None = None
    snow: tuple[int, int, int] | None = None
    salt: int = 1


def branch_metrics(radius: float, depth: int, branch_levels: int) -> tuple[float, float, float]:
    if branch_levels <= 1 or depth <= 1:
        t = 0.0
    else:
        t = (depth - 1) / (branch_levels - 1)
    length = radius * (0.42 + 0.28 * t)
    base_w = 2.2 + 3.8 * t + radius * 0.008
    tip_w = max(1.5, base_w * (0.32 - 0.05 * t))
    return length, base_w, tip_w


def radial_heading(ctx: Grow, origin: tuple[float, float], fallback: float) -> float:
    dx = origin[0] - ctx.cx
    dy = origin[1] - ctx.cy
    base = fallback if math.hypot(dx, dy) < 2.5 else math.atan2(dy, dx)
    heading = base + ctx.rng.choice((-1.0, 1.0)) * ctx.rng.uniform(0.05, 0.95)
    if math.cos(heading - base) < 0.3:
        heading = base + ctx.rng.uniform(-0.4, 0.4)
    return heading


def make_leaf_sprite(
    ctx: Grow,
    heading: float | None,
    parent_w: float,
    value_mul: float = 1.0,
    scale_mul: float = 1.0,
) -> tuple[Image.Image, tuple[float, float], bool]:
    scale = ctx.rng.uniform(0.68, 1.22) * scale_mul
    if parent_w > 0:
        scale *= min(1.05, 0.52 + parent_w / 7.5)
    bent = bend_leaf(ctx.leaf, ctx.rng.uniform(-LEAF_BEND, LEAF_BEND))
    tinted = tint_leaf(
        bent,
        ctx.hue_bias + ctx.rng.uniform(-LEAF_HUE, LEAF_HUE),
        ctx.rng.uniform(0.88, 1.12),
        min(1.25, ctx.value_bias * ctx.rng.uniform(*LEAF_VALUE) * value_mul),
    )
    scaled = scale_nearest(tinted, scale)
    if heading is None:
        turned, _anchor = rotate_about(scaled, ctx.rng.uniform(0, 360), ((scaled.width - 1) / 2, (scaled.height - 1) / 2))
        return turned, (turned.width / 2, turned.height / 2), True
    turned, anchor = rotate_about(scaled, rotation_for_heading(heading), stem_point(scaled))
    return turned, anchor, False


def sample_frame(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    base_w: float,
    tip_w: float,
    t: float,
) -> tuple[tuple[float, float], tuple[float, float], tuple[float, float], float]:
    pos = bezier(p0, p1, p2, t)
    tx, ty = bezier_tangent(p0, p1, p2, t)
    norm = math.hypot(tx, ty)
    if norm < 1e-4:
        tx, ty = 1.0, 0.0
    else:
        tx, ty = tx / norm, ty / norm
    return pos, (tx, ty), (-ty, tx), width_at(t, base_w, tip_w)


def outward_child_count(ctx: Grow, density: float) -> int:
    count = 1
    if ctx.rng.random() < density:
        count += 1
    if ctx.rng.random() < density * 0.75:
        count += 1
    return count


def make_branch(
    ctx: Grow,
    depth: int,
    origin: tuple[float, float],
    heading: float,
    length_override: float | None = None,
    max_radius: float | None = None,
) -> Branch | None:
    radius = ctx.radii[depth]
    length, base_w, tip_w = branch_metrics(radius, depth, ctx.branch_levels)
    if length_override is None:
        length *= ctx.rng.uniform(0.86, 1.14)
    else:
        base_w *= max(0.68, min(1.0, length_override / max(length, 1)))
        tip_w *= max(0.68, min(1.0, length_override / max(length, 1)))
        length = length_override
    if max_radius is not None:
        length = fit_length(origin, heading, length, ctx.cx, ctx.cy, max_radius)
    if length < 6:
        return None
    base_w *= ctx.rng.uniform(0.9, 1.1)
    tip_w = max(1.5, min(base_w * 0.62, tip_w * ctx.rng.uniform(0.9, 1.08)))
    bend = length * ctx.rng.choice((-1.0, 1.0)) * ctx.rng.uniform(0.18, 0.48)
    p0, p1, p2 = curve_points(origin, heading, length, bend)
    mid = bezier(p0, p1, p2, 0.5)
    t = 0.0 if ctx.branch_levels <= 1 else (depth - 1) / (ctx.branch_levels - 1)
    color = vary_color(ctx.wood, ctx.rng, hue=5, value=0.05)
    color = shade(color, 1.08 - 0.22 * t)
    ctx.salt += 1
    branch = Branch(
        p0=p0,
        p1=p1,
        p2=p2,
        base_w=base_w,
        tip_w=tip_w,
        color=color,
        salt=ctx.salt,
        sort_y=max(p0[1], p2[1], mid[1]),
        snow=ctx.snow,
    )
    if depth <= 1:
        branch.leaves = twig_leaves(ctx, branch)
    else:
        attach_children(ctx, branch, depth, max_radius)
    return branch


def place_on_branch(
    ctx: Grow,
    branch: Branch,
    t: float,
    side: int,
) -> tuple[tuple[float, float], float, float]:
    pos, tangent, normal, width = sample_frame(branch.p0, branch.p1, branch.p2, branch.base_w, branch.tip_w, t)
    if side == 0:
        heading = math.atan2(tangent[1], tangent[0]) + ctx.rng.uniform(-0.35, 0.35)
        origin = (pos[0] + tangent[0] * width * 0.15, pos[1] + tangent[1] * width * 0.15)
    else:
        heading = math.atan2(normal[1] * side, normal[0] * side) + ctx.rng.uniform(-0.4, 0.4)
        origin = (
            pos[0] + normal[0] * side * width * 0.42,
            pos[1] + normal[1] * side * width * 0.42,
        )
    return origin, heading, width


def leaf_dest(origin: tuple[float, float], heading: float) -> tuple[float, float]:
    return (origin[0] - math.cos(heading) * 1.4, origin[1] - math.sin(heading) * 1.4)


def add_leaf(ctx: Grow, branch: Branch, origin: tuple[float, float], heading: float, parent_w: float, value_mul: float) -> None:
    image, anchor, _centered = make_leaf_sprite(ctx, heading, parent_w, value_mul=value_mul)
    dest = leaf_dest(origin, heading)
    branch.leaves.append(LeafStamp(image, anchor, dest[0], dest[1]))


def add_clump(ctx: Grow, branch: Branch, origin: tuple[float, float], parent_w: float) -> None:
    count = ctx.rng.randint(3, 5)
    for _ in range(count):
        ang = ctx.rng.random() * math.tau
        dist = ctx.rng.uniform(0.4, 4.2)
        pos = (origin[0] + math.cos(ang) * dist, origin[1] + math.sin(ang) * dist)
        add_leaf(ctx, branch, pos, ang + ctx.rng.uniform(-0.3, 0.3), parent_w, ctx.rng.uniform(0.86, 1.05))


def branch_leaf_count(ctx: Grow) -> int:
    if ctx.snow is not None:
        return 0
    if ctx.leaves_on_branch is None:
        return ctx.rng.randint(5, 8)
    if ctx.leaves_on_branch <= 0:
        return 1 if ctx.rng.random() < 0.04 else 0
    return ctx.rng.randint(max(0, ctx.leaves_on_branch - 2), ctx.leaves_on_branch + 2)


def twig_leaves(ctx: Grow, branch: Branch) -> list[LeafStamp]:
    count = branch_leaf_count(ctx)
    if count <= 0:
        return branch.leaves
    times = [0.12 + 0.8 * (ctx.rng.random() ** 0.72) for _ in range(max(0, count - 1))]
    times.append(ctx.rng.uniform(0.86, 0.98))
    side = ctx.rng.choice((-1, 1))
    for index, t in enumerate(times):
        use_side = 0 if index == len(times) - 1 or ctx.rng.random() < 0.36 else side
        origin, heading, width = place_on_branch(ctx, branch, min(0.98, t), use_side)
        light = 1.06 if use_side <= 0 else 0.9
        add_leaf(ctx, branch, origin, heading, width, light)
        if use_side != 0:
            side = -side
    return branch.leaves


def attach_child(
    ctx: Grow,
    branch: Branch,
    depth: int,
    origin: tuple[float, float],
    heading: float,
    length: float,
    max_radius: float | None,
) -> None:
    child = make_branch(ctx, depth, origin, heading, length, max_radius)
    if child is not None:
        branch.children.append(child)


def attach_children(ctx: Grow, branch: Branch, depth: int, max_radius: float | None) -> None:
    child_depth = depth - 1
    density = ctx.densities.get(child_depth, 0.5)
    times = [0.16 + 0.72 * (ctx.rng.random() ** 0.75) for _ in range(outward_child_count(ctx, density))]
    times.append(ctx.rng.uniform(0.82, 0.97))
    side = ctx.rng.choice((-1, 1))
    parent_len = math.hypot(branch.p2[0] - branch.p0[0], branch.p2[1] - branch.p0[1])
    for t in times:
        use_side = side if ctx.rng.random() < 0.78 else 0
        origin, side_heading, _width = place_on_branch(ctx, branch, t, use_side)
        natural, _, _ = branch_metrics(ctx.radii[child_depth], child_depth, ctx.branch_levels)
        length = max(7.0, min(natural * 0.9, parent_len * ctx.rng.uniform(0.34, 0.58)))
        attach_child(ctx, branch, child_depth, origin, radial_heading(ctx, origin, side_heading), length, max_radius)
        side = -side
    if depth >= 3 and ctx.rng.random() < ctx.densities.get(depth - 2, 0.4) * 0.85:
        t = ctx.rng.uniform(0.35, 0.9)
        side = ctx.rng.choice((-1, 1))
        origin, side_heading, _width = place_on_branch(ctx, branch, t, side)
        skip = depth - 2
        natural, _, _ = branch_metrics(ctx.radii[skip], skip, ctx.branch_levels)
        length = max(7.0, min(natural * 0.85, parent_len * ctx.rng.uniform(0.22, 0.42)))
        attach_child(ctx, branch, skip, origin, radial_heading(ctx, origin, side_heading), length, max_radius)
    if ctx.snow is not None or ctx.leaves_on_branch == 0:
        extras = 0
        if ctx.snow is None and ctx.rng.random() < 0.12:
            extras = 1
    else:
        extras = 1 if ctx.rng.random() < 0.45 else 2
    for _ in range(extras):
        t = ctx.rng.uniform(0.25, 0.96)
        side = ctx.rng.choice((-1, 1))
        origin, heading, width = place_on_branch(ctx, branch, t, side)
        if ctx.rng.random() < 0.45:
            add_clump(ctx, branch, origin, width)
        else:
            add_leaf(ctx, branch, origin, heading, max(width, 3.0), ctx.rng.uniform(0.88, 1.06))


def stroke(canvas: Image.Image, branch: Branch) -> None:
    pixels = canvas.load()
    span = math.hypot(branch.p1[0] - branch.p0[0], branch.p1[1] - branch.p0[1])
    span += math.hypot(branch.p2[0] - branch.p1[0], branch.p2[1] - branch.p1[1])
    steps = max(2, int(span / 0.65))
    for index in range(steps + 1):
        t = index / steps
        pos = bezier(branch.p0, branch.p1, branch.p2, t)
        radius = width_at(t, branch.base_w, branch.tip_w) / 2
        radius *= 1 + 0.08 * math.sin(t * 10 + branch.salt)
        reach = radius + 1.6
        x0 = max(0, int(pos[0] - reach))
        y0 = max(0, int(pos[1] - reach))
        x1 = min(canvas.width - 1, int(pos[0] + reach))
        y1 = min(canvas.height - 1, int(pos[1] + reach))
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                dx = x - pos[0]
                dy = y - pos[1]
                dist = math.hypot(dx, dy)
                edge = (hash01(x, y, branch.salt) - 0.5) * 1.15
                if dist > radius + edge:
                    continue
                light = -(dx * 0.45 + dy * 0.9) / max(radius, 0.8)
                rim = dist / max(radius, 0.8)
                grain = hash01(x, y, branch.salt + 17)
                value = 1.0 + 0.16 * light - 0.24 * rim
                if grain > 0.94:
                    value *= 0.7
                wood = shade(branch.color, value)
                if branch.snow is not None:
                    up = -dy / max(radius, 0.8)
                    cap = max(0.0, min(1.0, (up + 0.2) / 0.65))
                    cap = cap ** 0.55
                    cap *= 0.88 + 0.12 * hash01(x, y, branch.salt + 41)
                    cap *= 0.9 + 0.15 * t
                    if hash01(x, y, branch.salt + 43) > 0.92:
                        cap = max(cap, 0.55)
                    if cap > 0.04:
                        snow = shade(branch.snow, 0.92 + 0.12 * max(0.0, min(1.0, up)))
                        wood = mix_rgb(wood, snow, min(1.0, cap))
                pixels[x, y] = (*wood, 255)


def paint_branch(canvas: Image.Image, branch: Branch) -> None:
    stroke(canvas, branch)
    order: list[tuple[float, int, LeafStamp | Branch]] = [(leaf.y, 1, leaf) for leaf in branch.leaves]
    order.extend((child.sort_y, 0, child) for child in branch.children)
    order.sort(key=lambda item: (item[0], item[1]))
    for _y, kind, obj in order:
        if kind == 0:
            paint_branch(canvas, obj)  # type: ignore[arg-type]
        else:
            leaf = obj
            assert isinstance(leaf, LeafStamp)
            if leaf.centered:
                blit_center(canvas, leaf.image, (leaf.x, leaf.y))
            else:
                blit_anchor(canvas, leaf.image, leaf.anchor, (leaf.x, leaf.y))


def primary_count(radius: float, density: float, rng: random.Random, leaves: bool) -> int:
    if leaves:
        return max(12, round(density * (radius / 3.05) ** 2 * rng.uniform(0.92, 1.08)))
    spacing = max(9.0, radius * 0.18 / max(density, 0.12))
    raw = (2 * math.pi * radius * 0.5) / spacing
    return max(4, round(raw * rng.uniform(0.88, 1.12)))


def branch_angles(count: int, rng: random.Random, density: float) -> list[float]:
    angles = [((index + rng.uniform(0.2, 0.8)) / count) * math.tau for index in range(count)]
    for _ in range(max(1, count // 3)):
        index = rng.randrange(count)
        angles[index] += rng.uniform(-0.35, 0.35)
    gap = rng.uniform(0.2, 0.45) * (1.35 - min(density, 1.0))
    gap_at = rng.random() * math.tau
    opened: list[float] = []
    for angle in angles:
        delta = (angle - gap_at + math.pi) % math.tau - math.pi
        if abs(delta) < gap * 0.5:
            push = gap * 0.55
            angle = gap_at + (push if delta >= 0 else -push)
        opened.append((angle + rng.uniform(-0.12, 0.12)) % math.tau)
    return opened


def scatter_leaves(ctx: Grow, canvas: Image.Image, depth: int) -> None:
    radius = ctx.radii[depth]
    count = primary_count(radius, ctx.densities[depth], ctx.rng, True)
    stamps: list[LeafStamp] = []
    for _ in range(count):
        roll = ctx.rng.random()
        if roll < 0.68:
            dist = radius * (ctx.rng.random() ** 1.65) * 0.58
        elif roll < 0.88:
            dist = radius * ctx.rng.uniform(0.28, 0.7)
        else:
            dist = radius * ctx.rng.uniform(0.62, 1.02)
        angle = ctx.rng.random() * math.tau
        pos = (ctx.cx + math.cos(angle) * dist, ctx.cy + math.sin(angle) * dist)
        edge = min(1.0, dist / max(radius, 1))
        image, _anchor, _centered = make_leaf_sprite(ctx, None, 0, scale_mul=1.08 - 0.3 * edge)
        stamps.append(LeafStamp(image, (0, 0), pos[0], pos[1], True))
    stamps.sort(key=lambda item: item.y)
    for stamp in stamps:
        blit_center(canvas, stamp.image, (stamp.x, stamp.y))


def scatter_branches(ctx: Grow, canvas: Image.Image, depth: int) -> None:
    radius = ctx.radii[depth]
    count = primary_count(radius, ctx.densities[depth], ctx.rng, False)
    branches: list[Branch] = []
    for angle in branch_angles(count, ctx.rng, ctx.densities[depth]):
        if ctx.rng.random() < 0.42:
            base_r = radius * ctx.rng.uniform(0.0, 0.14)
        else:
            base_r = radius * ctx.rng.uniform(0.06, 0.4)
        side = ctx.rng.uniform(-radius * 0.06, radius * 0.06)
        origin = (
            ctx.cx + math.cos(angle) * base_r - math.sin(angle) * side,
            ctx.cy + math.sin(angle) * base_r + math.cos(angle) * side,
        )
        reach = radius * ctx.rng.uniform(0.92, 1.18)
        if ctx.rng.random() < 0.18:
            reach *= ctx.rng.uniform(0.5, 0.72)
        length = max(8.0, reach)
        branch = make_branch(ctx, depth, origin, radial_heading(ctx, origin, angle), length, radius)
        if branch is not None:
            branches.append(branch)
    branches.sort(key=lambda item: item.sort_y)
    for branch in branches:
        paint_branch(canvas, branch)


def draw_stump(
    canvas: Image.Image,
    rng: random.Random,
    cx: float,
    cy: float,
    color: tuple[int, int, int],
    radius: float,
    root_length: float,
    snow: tuple[int, int, int] | None = None,
) -> None:
    color = vary_color(color, rng, hue=4, value=0.04)
    radius *= rng.uniform(0.92, 1.1)
    root_length *= rng.uniform(0.92, 1.12)
    rx = radius * rng.uniform(0.9, 1.08)
    ry = rx * rng.uniform(0.82, 1.08)
    phase = rng.uniform(0, math.tau)
    phase_b = rng.uniform(0, math.tau)
    count = rng.randint(8, 11)
    for index in range(count):
        angle = (index + rng.uniform(0.08, 0.92)) / count * math.tau
        start_r = rx * rng.uniform(0.18, 0.48)
        origin = (cx + math.cos(angle) * start_r, cy + math.sin(angle) * start_r * (ry / rx))
        visible = root_length * rng.uniform(0.62, 0.9)
        length = max(10.0, rx * 0.28 + visible)
        heading = angle + rng.uniform(-0.32, 0.32)
        bend = length * rng.choice((-1.0, 1.0)) * rng.uniform(0.14, 0.36)
        p0, p1, p2 = curve_points(origin, heading, length, bend)
        root = Branch(
            p0=p0,
            p1=p1,
            p2=p2,
            base_w=rng.uniform(3.6, 5.6),
            tip_w=rng.uniform(1.8, 2.8),
            color=shade(color, rng.uniform(0.48, 0.7)),
            salt=rng.randrange(1, 100000),
            sort_y=0,
        )
        stroke(canvas, root)

    pixels = canvas.load()
    pad = int(max(rx, ry) + 3)
    x0 = max(0, int(cx - pad))
    y0 = max(0, int(cy - pad))
    x1 = min(canvas.width - 1, int(cx + pad))
    y1 = min(canvas.height - 1, int(cy + pad))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            dist = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            edge = 0.9 + 0.1 * math.sin(ang * 2 + phase) + 0.07 * math.sin(ang * 5 + phase_b)
            if dist > edge:
                continue
            grain = hash01(x, y, 3)
            value = 0.5 + 0.16 * grain - 0.05 * dx - 0.04 * dy
            if grain > 0.93:
                value *= 0.78
            wood = shade(color, value)
            if snow is not None:
                up = max(0.0, -dy)
                cap = 0.7 + 0.3 * up
                cap *= 0.92 + 0.08 * grain
                if dist > edge * 0.72:
                    cap *= 0.35
                wood = mix_rgb(wood, shade(snow, 0.94 + 0.1 * up), min(1.0, cap))
            pixels[x, y] = (*wood, 255)


def blank(size: int) -> Image.Image:
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def canvas_size(preset: dict) -> int:
    layers = int(preset["layers"])
    crown = max(float(preset["widths"][layer]) for layer in range(1, layers + 1))
    stump = preset["stump"]
    half = max(
        crown * 0.5 * (1 + WIDTH_JITTER) + 48,
        float(stump["radius"]) * 1.5 + float(stump["root_length"]) * 2.0 + 12,
    )
    size = int(math.ceil(half * 2))
    if size % 2:
        size += 1
    return size


def build_grow(preset: dict, rng: random.Random, size: int, leaf: Image.Image, wood: tuple[int, int, int]) -> Grow:
    layers = int(preset["layers"])
    radii: dict[int, float] = {}
    densities: dict[int, float] = {}
    for layer in range(1, layers + 1):
        depth = layers - layer
        radii[depth] = jitter(rng, float(preset["widths"][layer]), WIDTH_JITTER) / 2
        densities[depth] = min(1.4, max(0.0, jitter(rng, float(preset["density"][layer]), DENSITY_JITTER)))
    return Grow(
        rng=rng,
        cx=size / 2,
        cy=size / 2,
        radii=radii,
        densities=densities,
        branch_levels=layers - 1,
        wood=wood,
        leaf=leaf,
        hue_bias=rng.uniform(-8, 8),
        value_bias=rng.uniform(0.94, 1.06),
        leaves_on_branch=None if preset.get("leaves") is None else int(preset["leaves"]),
        snow=parse_hex(preset["snow"]) if preset.get("snow") else None,
    )


def render_layers(ctx: Grow, size: int) -> dict[int, Image.Image]:
    layers = ctx.branch_levels + 1
    images: dict[int, Image.Image] = {}
    for depth in range(layers):
        layer = layers - depth
        image = blank(size)
        if depth == 0 and ctx.leaves_on_branch != 0:
            scatter_leaves(ctx, image, depth)
        else:
            scatter_branches(ctx, image, depth)
        images[layer] = image
    return images


def stack_tree(stump: Image.Image, layers: dict[int, Image.Image]) -> Image.Image:
    image = blank(stump.width)
    image.alpha_composite(stump)
    for layer in sorted(layers):
        image.alpha_composite(layers[layer])
    return image


def on_grass(image: Image.Image) -> Image.Image:
    background = Image.new("RGBA", image.size, GRASS + (255,))
    background.alpha_composite(image)
    return background.convert("RGB")


def load_font(size: int) -> ImageFont.ImageFont:
    for name in ("arial.ttf", "segoeui.ttf", "calibri.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def contact_sheet(images: list[Image.Image], labels: list[str], path: Path, scale: int) -> None:
    if not images:
        return
    tile = images[0].width
    columns = max(1, math.ceil(math.sqrt(len(images))))
    rows = math.ceil(len(images) / columns)
    gap = 8
    caption = 18
    sheet = Image.new("RGB", (columns * tile + (columns + 1) * gap, rows * (tile + caption) + (rows + 1) * gap), GRASS)
    draw = ImageDraw.Draw(sheet)
    font = load_font(14)
    for index, image in enumerate(images):
        col = index % columns
        row = index // columns
        x = gap + col * (tile + gap)
        y = gap + row * (tile + caption + gap)
        sheet.paste(on_grass(image), (x, y + caption))
        draw.text((x + 2, y), labels[index], fill=(24, 32, 18), font=font)
    if scale != 1:
        sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def crop_square(images: list[Image.Image], pad: int = 2) -> list[Image.Image]:
    """Čtverec kolem středu, který pojme obsah všech snímků a nechá okraj pro filtr."""
    if not images:
        return images
    width, height = images[0].size
    half = 0.0
    for image in images:
        if image.size != (width, height):
            raise ValueError("snímky v atlasu nemají stejnou velikost")
        bbox = image.getchannel("A").getbbox()
        if bbox is None:
            continue
        left, top, right, bottom = bbox
        cx = width / 2
        cy = height / 2
        half = max(half, cx - left, right - cx, cy - top, bottom - cy)
    new_half = int(math.ceil(half - 1e-6)) + pad
    new_size = max(2, new_half * 2)
    if new_size >= width or new_size >= height:
        return images
    left = (width - new_size) // 2
    top = (height - new_size) // 2
    box = (left, top, left + new_size, top + new_size)
    return [image.crop(box) for image in images]


def atlas_cell(path: Path, columns: int) -> int | None:
    if not path.is_file() or columns <= 0:
        return None
    with Image.open(path) as image:
        if image.width % columns:
            return None
        return image.width // columns


def pack_atlas(images: list[Image.Image], columns: int = ATLAS_COLUMNS) -> Image.Image:
    cell = images[0].width
    rows = math.ceil(len(images) / columns)
    sheet = Image.new("RGBA", (columns * cell, rows * cell), (0, 0, 0, 0))
    for index, image in enumerate(images):
        sheet.alpha_composite(image, ((index % columns) * cell, (index // columns) * cell))
    return sheet


def clean_output(path: Path) -> None:
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_dir():
            for item in child.iterdir():
                if item.is_file():
                    item.unlink()
            child.rmdir()
        elif child.suffix == ".png" or child.name.endswith(".png.import"):
            child.unlink()


def check_preset(name: str, preset: dict) -> int:
    layers = int(preset["layers"])
    if not 1 <= layers <= 4:
        raise SystemExit(f"{name}: vrstvy mají být 1 až 4")
    for key in ("density", "widths", "height"):
        values = preset.get(key)
        if not values:
            raise SystemExit(f"{name}: chybí {key}")
        for layer in range(1, layers + 1):
            if layer not in values:
                raise SystemExit(f"{name}: {key} nemá vrstvu {layer}")
            if float(values[layer]) <= 0:
                raise SystemExit(f"{name}: {key} vrstvy {layer} musí být větší než 0")
    if float(preset.get("spacing", 0)) <= 0:
        raise SystemExit(f"{name}: spacing musí být větší než 0")
    if preset.get("leaves") is not None and int(preset["leaves"]) < 0:
        raise SystemExit(f"{name}: leaves musí být aspoň 0")
    if preset.get("snow"):
        parse_hex(preset["snow"])
    for other, gap in preset.get("spacing_from", {}).items():
        if float(gap) <= 0:
            raise SystemExit(f"{name}: spacing vůči {other} musí být větší než 0")
    if int(preset.get("variants", 9)) < 1:
        raise SystemExit(f"{name}: variants musí být aspoň 1")
    return layers


def spacing_between(trees: dict, left: str, right: str) -> float:
    left_gap = float(trees[left].get("spacing_from", {}).get(right, trees[left]["spacing"]))
    right_gap = float(trees[right].get("spacing_from", {}).get(left, trees[right]["spacing"]))
    return max(left_gap, right_gap)


def tree_info(trees: dict) -> dict:
    catalog = {}
    for name, preset in trees.items():
        check_preset(name, preset)
        for other in preset.get("spacing_from", {}):
            if other not in trees:
                raise SystemExit(f"{name}: spacing_from obsahuje neznámý strom {other}")
        drawn = canvas_size(preset)
        layers = int(preset["layers"])
        stump_cell = atlas_cell(OUT_DIR / name / "stump.png", ATLAS_COLUMNS) or drawn
        layer_cells = {
            layer: atlas_cell(OUT_DIR / name / f"layer_{layer}.png", ATLAS_COLUMNS) or drawn
            for layer in range(1, layers + 1)
        }
        size = max([stump_cell, *layer_cells.values()])
        catalog[name] = {
            "leaf": preset["leaf"],
            "variants": int(preset.get("variants", 9)),
            "canvas": size,
            "center": size // 2,
            "stump": {
                "height": 0,
                "color": preset["stump"]["color"],
                "radius": preset["stump"]["radius"],
                "root_length": preset["stump"]["root_length"],
                "canvas": stump_cell,
            },
            "layers": {
                str(layer): {
                    "height": float(preset["height"][layer]),
                    "width": float(preset["widths"][layer]),
                    "density": float(preset["density"][layer]),
                    "canvas": layer_cells[layer],
                }
                for layer in range(1, layers + 1)
            },
            "spacing": float(preset["spacing"]),
        }
        if preset.get("leaves") is not None:
            catalog[name]["leaves"] = int(preset["leaves"])
        if preset.get("spacing_from"):
            catalog[name]["spacing_from"] = {other: float(gap) for other, gap in preset["spacing_from"].items()}
    names = list(trees)
    return {
        "height_unit": "m",
        "spacing_unit": "m",
        "atlas_columns": ATLAS_COLUMNS,
        "trees": catalog,
        "spacing": {left: {right: spacing_between(trees, left, right) for right in names} for left in names},
    }


def write_tree_info(trees: dict, path: Path = TREES_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(tree_info(trees), indent=2) + "\n", encoding="utf-8")
    return path


def generate_trees(name: str, preset: dict, seed: int = 1, variants: int | None = None) -> Path:
    check_preset(name, preset)
    count = int(preset.get("variants", 9) if variants is None else variants)
    leaf_path = LEAVES / preset["leaf"]
    if not leaf_path.is_file():
        raise SystemExit(f"chybí list {leaf_path}")
    leaf = Image.open(leaf_path).convert("RGBA")
    wood = parse_hex(preset.get("branch", "6A4328"))
    stump_color = parse_hex(preset["stump"]["color"])
    size = canvas_size(preset)
    out = OUT_DIR / name
    clean_output(out)
    out.mkdir(parents=True, exist_ok=True)

    composites: list[Image.Image] = []
    layer_frames: dict[int, list[Image.Image]] = {layer: [] for layer in range(1, int(preset["layers"]) + 1)}
    stumps: list[Image.Image] = []
    first_layers: dict[int, Image.Image] | None = None
    first_stump: Image.Image | None = None
    name_salt = sum(ord(char) for char in name)
    for index in range(count):
        rng = random.Random(seed + name_salt + index * 7919)
        ctx = build_grow(preset, rng, size, leaf, wood)
        layers = render_layers(ctx, size)
        stump = blank(size)
        draw_stump(
            stump,
            rng,
            ctx.cx,
            ctx.cy,
            stump_color,
            float(preset["stump"]["radius"]),
            float(preset["stump"]["root_length"]),
            ctx.snow,
        )
        for layer, image in layers.items():
            layer_frames[layer].append(image)
        stumps.append(stump)
        composites.append(stack_tree(stump, layers))
        if index == 0:
            first_layers = layers
            first_stump = stump

    saved: list[int] = []
    for layer, frames in layer_frames.items():
        fitted = crop_square(frames)
        saved.append(fitted[0].width)
        pack_atlas(fitted).save(out / f"layer_{layer}.png")
    stumps = crop_square(stumps)
    saved.append(stumps[0].width)
    pack_atlas(stumps).save(out / "stump.png")

    labels = [f"{index:02d}" for index in range(count)]
    contact_sheet(composites, labels, PREVIEW / f"{name}.png", 2)
    if first_layers is not None and first_stump is not None:
        panels = [first_stump]
        panel_labels = ["pařez"]
        for layer in range(1, int(preset["layers"]) + 1):
            panels.append(first_layers[layer])
            panel_labels.append(f"vrstva {layer}")
        panels.append(composites[0])
        panel_labels.append("strom")
        contact_sheet(panels, panel_labels, PREVIEW / f"{name}_layers.png", 2)
    print(f"{count} variant, plátno {size}, buňky {min(saved)}–{max(saved)} -> {out}")
    print(PREVIEW / f"{name}.png")
    return out


def main() -> None:
    from generate import TREES, write_surface_info

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--name", choices=tuple(TREES), help="jen jeden strom, jinak všechny z generate.py")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--variants", type=int, help="přepíše počet variant z definice")
    args = parser.parse_args()
    names = [args.name] if args.name else list(TREES)
    for name in names:
        generate_trees(name, TREES[name], seed=args.seed, variants=args.variants)
    print(write_tree_info(TREES))
    print(write_surface_info())


if __name__ == "__main__":
    main()
