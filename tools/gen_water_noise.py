#!/usr/bin/env python3
"""Předpočítaný šum odlesků a pěny vody (terrain_common.gdshaderinc).

Voda jezer i řek dřív v každém pixelu počítala dva hodnotové šumy pro odlesky a dva pro pěnu.
Tady se spočítají jednou do opakovatelných textur a shader z nich jen čte:

  glints.png  odlesky, value_noise(at) * 0.6 + value_noise(at * (2.25, 1.75) + 11) * 0.4,
              GLINT_CELLS buněk prvního šumu na stranu, čte se s lineárním filtrem
  foam.png    krajka pěny, value_noise(p * 0.11) * 0.6 + value_noise(p * 0.35) * 0.4,
              texel na pixel světa, FOAM_SIDE px na stranu, čte se bez filtru

Šum je stejný jako value_noise v shaderu (mřížka náhodných hodnot, hladká interpolace), jen
mřížka se opakuje po periodě textury, ať textura navazuje. Druhá oktáva odlesků má měřítko
2,25 × 1,75 místo 2,3 × 1,7, ať je perioda celá.

  py tools/gen_water_noise.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot" / "graphics" / "terrain" / "water"

## Stejná čísla mají GLINT_CELLS a FOAM_SIDE v terrain_common.gdshaderinc.
GLINT_SIDE = 256
GLINT_CELLS = 32
FOAM_SIDE = 400


def value_noise(x: np.ndarray, y: np.ndarray, period: tuple[int, int], seed: int) -> np.ndarray:
    """Hodnotový šum v bodech x, y (v buňkách mřížky), mřížka se opakuje po period buňkách."""
    lattice = np.random.default_rng(seed).random((period[1], period[0]))
    cx = np.floor(x).astype(np.int64)
    cy = np.floor(y).astype(np.int64)
    fx = x - cx
    fy = y - cy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    x0 = cx % period[0]
    y0 = cy % period[1]
    x1 = (cx + 1) % period[0]
    y1 = (cy + 1) % period[1]
    a = lattice[y0, x0]
    b = lattice[y0, x1]
    c = lattice[y1, x0]
    d = lattice[y1, x1]
    return (a + (b - a) * fx) * (1.0 - fy) + (c + (d - c) * fx) * fy


def save(values: np.ndarray, name: str) -> None:
    image = Image.fromarray(np.clip(np.round(values * 255.0), 0, 255).astype(np.uint8), "L")
    image.save(OUT / name)
    print(f"{name}: {values.shape[1]} x {values.shape[0]}, průměr {values.mean():.3f}")


def main() -> None:
    # Odlesky: texel uprostřed své plochy, souřadnice v buňkách prvního šumu.
    pos = (np.arange(GLINT_SIDE) + 0.5) / GLINT_SIDE * GLINT_CELLS
    x, y = np.meshgrid(pos, pos)
    first = value_noise(x, y, (GLINT_CELLS, GLINT_CELLS), 1)
    second = value_noise(x * 2.25 + 11.0, y * 1.75 + 11.0, (GLINT_CELLS * 9 // 4, GLINT_CELLS * 7 // 4), 2)
    save(first * 0.6 + second * 0.4, "glints.png")
    # Pěna: texel je celý pixel světa (shader bere floor polohy).
    pos = np.arange(FOAM_SIDE, dtype=np.float64)
    x, y = np.meshgrid(pos, pos)
    patches = value_noise(x * 0.11, y * 0.11, (44, 44), 3)
    grains = value_noise(x * 0.35, y * 0.35, (140, 140), 4)
    save(patches * 0.6 + grains * 0.4, "foam.png")


if __name__ == "__main__":
    main()
