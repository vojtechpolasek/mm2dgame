#!/usr/bin/env python3
"""Složí pro každý povrch vlastní náhled 3x3 z náhodných dlaždic.

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


def collect_surfaces() -> dict[str, list[Path]]:
    surfaces: dict[str, list[Path]] = {}
    for path in sorted(TERRAIN.glob("*/*.png")):
        if path.is_file() and path.parent.name != "transitions":
            surfaces.setdefault(path.parent.name, []).append(path)
    return surfaces


def compose(tiles: list[Path], size: int, rng: random.Random) -> tuple[Image.Image, list[Path]]:
    chosen = [rng.choice(tiles) for _ in range(size * size)]
    first = Image.open(chosen[0]).convert("RGB")
    tile_size = first.width
    if first.height != tile_size:
        raise SystemExit(f"{chosen[0]} není čtverec")
    sheet = Image.new("RGB", (tile_size * size, tile_size * size))
    sheet.paste(first, (0, 0))
    first.close()
    for index, path in enumerate(chosen[1:], start=1):
        image = Image.open(path).convert("RGB")
        if image.size != (tile_size, tile_size):
            raise SystemExit(f"{path.name} má jiný rozměr než {tile_size}")
        sheet.paste(image, ((index % size) * tile_size, (index // size) * tile_size))
        image.close()
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
        raise SystemExit(f"v {TERRAIN} nejsou žádné dlaždice")

    seed = args.seed if args.seed is not None else random.SystemRandom().randrange(1_000_000)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    print(f"seed {seed}")

    for name, tiles in surfaces.items():
        sheet, chosen = compose(tiles, args.size, random.Random(seed + hash(name) % 10007))
        out = PREVIEW / f"{name}_3x3.png"
        sheet.save(out)
        print(name)
        for index, path in enumerate(chosen):
            row, col = divmod(index, args.size)
            print(f"  {row},{col}  {path.name}")
        print(f"  {out}")


if __name__ == "__main__":
    main()
