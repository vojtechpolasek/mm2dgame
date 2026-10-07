#!/usr/bin/env python3
"""Složí pro každý povrch vlastní náhled 3x3 z náhodných dlaždic atlasu.

Výstup jsou kontrolní obrázky mimo grafiku Godotu.
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TERRAIN = ROOT / "godot" / "graphics" / "terrain"
PREVIEW = ROOT / "tools" / "preview"
TILE = 64


def collect_surfaces() -> dict[str, list[Image.Image]]:
    surfaces: dict[str, list[Image.Image]] = {}
    for atlas in sorted(TERRAIN.glob("*/atlas.png")):
        image = Image.open(atlas).convert("RGB")
        columns = image.width // TILE
        rows = image.height // TILE
        tiles = []
        for index in range(columns * rows):
            column = index % columns
            row = index // columns
            tiles.append(image.crop((column * TILE, row * TILE, (column + 1) * TILE, (row + 1) * TILE)))
        image.close()
        surfaces[atlas.parent.name] = tiles
    return surfaces


def compose(tiles: list[Image.Image], size: int, rng: random.Random) -> tuple[Image.Image, list[int]]:
    chosen = [rng.randrange(len(tiles)) for _ in range(size * size)]
    sheet = Image.new("RGB", (TILE * size, TILE * size))
    for index, tile_index in enumerate(chosen):
        sheet.paste(tiles[tile_index], ((index % size) * TILE, (index // size) * TILE))
    return sheet, chosen


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, default=3, help="strana náhledu v dlaždicích")
    parser.add_argument("--seed", type=int, help="seed výběru, jinak náhodný")
    args = parser.parse_args()
    if args.size < 1:
        raise SystemExit("size musí být aspoň 1")

    surfaces = collect_surfaces()
    if not surfaces:
        raise SystemExit(f"v {TERRAIN} nejsou žádné atlasy")

    seed = args.seed if args.seed is not None else random.SystemRandom().randrange(1_000_000)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    print(f"seed {seed}")

    for name, tiles in surfaces.items():
        sheet, chosen = compose(tiles, args.size, random.Random(seed + hash(name) % 10007))
        out = PREVIEW / f"{name}_3x3.png"
        sheet.save(out)
        print(name)
        for index, tile_index in enumerate(chosen):
            row, col = divmod(index, args.size)
            print(f"  {row},{col}  {tile_index:02d}")
        print(f"  {out}")


if __name__ == "__main__":
    main()
