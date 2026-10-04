#!/usr/bin/env python3
"""Vygeneruje veškerou grafiku ze seznamu terénů.

Jediný seznam parametrů je TERRAINS. Čisté dlaždice i přechody se počítají z něj.
Později sem přibudou objekty a postavy.

Příklad:
  py tools/generate.py
"""

from __future__ import annotations

TERRAINS = {
    "grass": {"name": "grass", "base": "4F9A3C", "hue": 5.0, "contrast": 28.0, "coarseness": 1.0},
    "dirt": {"name": "dirt", "base": "7A5A3A", "hue": 3.0, "contrast": 22.0, "coarseness": 1.4},
}


def main() -> None:
    from gen_terrain_tiles import generate_surface, parse_hex
    from gen_transitions import generate_transitions

    for kind, preset in TERRAINS.items():
        generate_surface(
            kind,
            name=preset["name"],
            base=parse_hex(preset["base"]),
            hue=preset["hue"],
            contrast=preset["contrast"],
            coarseness=preset["coarseness"],
        )
    generate_transitions()


if __name__ == "__main__":
    main()
