#!/usr/bin/env python3
"""Generuje přechodové dlaždice pro všechny kombinace rohů známých povrchů.

Pořadí rohů v názvu souboru je levý horní, pravý horní, levý dolní, pravý dolní.
Čisté dlaždice, kde jsou všechny rohy stejné, se negenerují.

Nový povrch se přidá do TERRAINS v generate.py a spustí se py tools/generate.py.

Příklad:
  py tools/generate.py
"""

from __future__ import annotations

import argparse
import itertools
import random
from pathlib import Path

from PIL import Image

from generate import TERRAINS
from gen_terrain_tiles import (
    GRAPHICS,
    Field,
    lerp_rgb,
    master_weight,
    paint_field,
    paint_marks,
    parse_hex,
)

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = GRAPHICS / "terrain" / "transitions"
PREVIEW = ROOT / "tools" / "preview" / "transitions.png"
CORNER_ORDER = ("tl", "tr", "bl", "br")
POWER = 4


def preset_args(kind: str) -> tuple[tuple[int, int, int], float, float, float]:
    preset = TERRAINS[kind]
    return (
        parse_hex(preset["base"]),
        preset["hue"] / 100 * 360,
        preset["contrast"] / 100,
        preset["coarseness"],
    )


def render_field(kind: str, seed: int, size: int) -> Field:
    base, hue_span, contrast, coarseness = preset_args(kind)
    return paint_field(size, random.Random(seed), seed, base, hue_span, contrast, coarseness, kind)


def corner_weights(x: int, y: int, size: int, corners: tuple[str, str, str, str]) -> dict[str, float]:
    u = 0.0 if size == 1 else x / (size - 1)
    v = 0.0 if size == 1 else y / (size - 1)
    weights: dict[str, float] = {}
    for name, weight in (
        (corners[0], (1 - u) * (1 - v)),
        (corners[1], u * (1 - v)),
        (corners[2], (1 - u) * v),
        (corners[3], u * v),
    ):
        weights[name] = weights.get(name, 0.0) + weight
    return weights


def powered(weights: dict[str, float]) -> dict[str, float]:
    raised = {name: weight**POWER for name, weight in weights.items() if weight > 0}
    total = sum(raised.values()) or 1.0
    return {name: weight / total for name, weight in raised.items()}


def mix_pixel(fields: dict[str, Field], x: int, y: int, weights: dict[str, float]) -> tuple[int, int, int]:
    red = green = blue = 0.0
    for name, weight in weights.items():
        if weight <= 0:
            continue
        color = fields[name].get(x, y)
        red += color[0] * weight
        green += color[1] * weight
        blue += color[2] * weight
    return (int(round(red)), int(round(green)), int(round(blue)))


def uniform_edge(x: int, y: int, size: int, reach: int, corners: tuple[str, str, str, str]) -> str | None:
    top_left, top_right, bottom_left, bottom_right = corners
    if x < reach and top_left == bottom_left:
        return top_left
    if x >= size - reach and top_right == bottom_right:
        return top_right
    if y < reach and top_left == top_right:
        return top_left
    if y >= size - reach and bottom_left == bottom_right:
        return bottom_left
    return None


def compose(
    corners: tuple[str, str, str, str],
    masters: dict[str, Field],
    variants: dict[str, Field],
    border: int,
) -> Field:
    size = next(iter(masters.values())).size
    blend = max(4, border)
    reach = border + blend
    out = Field(size)
    for y in range(size):
        for x in range(size):
            weights = powered(corner_weights(x, y, size, corners))
            inner = mix_pixel(variants, x, y, weights)
            owner = uniform_edge(x, y, size, reach, corners)
            edge = masters[owner].get(x, y) if owner is not None else mix_pixel(masters, x, y, weights)
            weight = master_weight(x, y, size, border, blend)
            if weight >= 1:
                color = edge
            elif weight <= 0:
                color = inner
            else:
                color = lerp_rgb(inner, edge, weight)
            out.set(x, y, color)
    return out


def allow_pixel(kind: str, x: int, y: int, size: int, border: int, corners: tuple[str, str, str, str]):
    weights = powered(corner_weights(x, y, size, corners))
    return weights.get(kind, 0.0) >= 0.62


def pattern_name(corners: tuple[str, str, str, str]) -> str:
    return "-".join(corners)


def combinations(kinds: list[str]) -> list[tuple[str, str, str, str]]:
    found = []
    for corners in itertools.product(kinds, repeat=4):
        if len(set(corners)) == 1:
            continue
        found.append(corners)
    return found


def cell_corners(terrain: dict[tuple[int, int], str], x: int, y: int, base: str) -> tuple[str, str, str, str]:
    def vertex(vx: int, vy: int) -> str:
        # Vrchol patří buňce, která ho při malování nastavila. Jinak zůstává podklad.
        names = []
        for cx, cy in ((vx - 1, vy - 1), (vx, vy - 1), (vx - 1, vy), (vx, vy)):
            name = terrain.get((cx, cy))
            if name is not None and name != base:
                names.append(name)
        return names[-1] if names else base

    return (vertex(x, y), vertex(x + 1, y), vertex(x, y + 1), vertex(x + 1, y + 1))


def save_preview(tiles: dict[tuple[str, str, str, str], list[Image.Image]], path: Path, seed: int) -> None:
    base = next(iter(TERRAINS))
    others = [name for name in TERRAINS if name != base]
    feature = others[0]
    rows = [
        [base, base, base, base, base, base, base],
        [base, feature, feature, base, base, base, base],
        [base, feature, feature, feature, base, base, base],
        [base, base, feature, feature, base, base, base],
        [base, base, base, base, base, base, base],
    ]
    terrain = {
        (x, y): rows[y][x]
        for y in range(len(rows))
        for x in range(len(rows[0]))
    }
    rng = random.Random(seed)
    tile_size = 64
    sheet = Image.new("RGB", (len(rows[0]) * tile_size, len(rows) * tile_size))
    pure_cache: dict[str, list[Image.Image]] = {}
    for y, row in enumerate(rows):
        for x, _name in enumerate(row):
            corners = cell_corners(terrain, x, y, base)
            if len(set(corners)) == 1:
                kind = corners[0]
                if kind not in pure_cache:
                    folder = GRAPHICS / "terrain" / kind
                    pure_cache[kind] = [Image.open(path).convert("RGB") for path in sorted(folder.glob(f"{kind}_*.png"))]
                image = rng.choice(pure_cache[kind])
            else:
                image = rng.choice(tiles[corners])
            sheet.paste(image, (x * tile_size, y * tile_size))
    scale = 3
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def generate_transitions(
    *,
    variants: int = 4,
    tile_size: int = 64,
    border: int = 4,
    seed: int = 1,
    preview: Path | None = PREVIEW,
) -> Path:
    if variants < 1:
        raise SystemExit("variants musí být aspoň 1")

    kinds = list(TERRAINS)
    patterns = combinations(kinds)
    masters = {kind: render_field(kind, seed, tile_size) for kind in kinds}
    variant_fields = []
    for index in range(variants):
        variant_seed = seed + 1000 * (index + 1)
        variant_fields.append({kind: render_field(kind, variant_seed, tile_size) for kind in kinds})

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.png"):
        old.unlink()

    saved: dict[tuple[str, str, str, str], list[Image.Image]] = {}
    for corners in patterns:
        images: list[Image.Image] = []
        for index, variant_set in enumerate(variant_fields):
            field = compose(corners, masters, variant_set, border)
            for kind in set(corners):
                mark_seed = seed + 1000 * (index + 1) + 50 + sum(ord(char) for char in kind)
                allow = lambda px, py, kind=kind, corners=corners: allow_pixel(
                    kind, px, py, tile_size, border, corners
                )
                owned = sum(
                    1
                    for y in range(0, tile_size, 2)
                    for x in range(0, tile_size, 2)
                    if allow(x, y)
                )
                samples = (tile_size // 2) ** 2
                density = max(0.12, owned / samples)
                paint_marks(
                    field,
                    random.Random(mark_seed + index * 17),
                    kind,
                    TERRAINS[kind]["coarseness"],
                    allow,
                    density,
                )
            image = field.image()
            image.save(OUT_DIR / f"{pattern_name(corners)}_{index:02d}.png")
            images.append(image)
        saved[corners] = images

    # Čistá hlína vpravo musí navazovat na přechod, který má vpravo hlínu.
    edge_kind = next((name for name in kinds if name != kinds[0]), kinds[0])
    edge_right = next(corners for corners in patterns if corners[1] == corners[3] == edge_kind)
    seam = 0
    master = masters[edge_kind]
    sample = saved[edge_right][0]
    for y in range(tile_size):
        left = master.get(tile_size - 1, y)
        right = sample.getpixel((tile_size - 1, y))
        seam += abs(left[0] - right[0]) + abs(left[1] - right[1]) + abs(left[2] - right[2])
    if preview is not None:
        save_preview(saved, preview, seed)
    print(f"{len(patterns)} tvarů × {variants} variant -> {OUT_DIR}")
    print(f"shoda pravého okraje s předlohou, průměrný rozdíl {seam / tile_size:.2f}")
    if preview is not None:
        print(preview)
    return OUT_DIR


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--variants", type=int, default=4, help="počet variant každého tvaru")
    parser.add_argument("--tile-size", type=int, default=64)
    parser.add_argument("--border", type=int, default=4)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--preview", type=Path, default=PREVIEW)
    args = parser.parse_args()
    generate_transitions(
        variants=args.variants,
        tile_size=args.tile_size,
        border=args.border,
        seed=args.seed,
        preview=args.preview,
    )


if __name__ == "__main__":
    main()
