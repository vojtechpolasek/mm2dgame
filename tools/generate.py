#!/usr/bin/env python3
"""Vygeneruje veškerou grafiku ze seznamu terénů a stromů.

Seznamy parametrů jsou TERRAINS a TREES. Čistý terén se skládá do atlasu.
Přechody se nepečou, v Godotu je míchá shader. Pro Godot se zapíše
graphics/terrain/surfaces.json a graphics/objects/trees/trees.json.

Příklad:
  py tools/generate.py
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SURFACES_PATH = ROOT / "godot" / "graphics" / "terrain" / "surfaces.json"

# forest a rocks jsou počet pokusů na dlaždici. Vyšší číslo = víc jedinců.
# Druh, který v mapě chybí, v terénu neroste. Sníh a voda jsou bez lesa i skal.
# Poušť má jen suché stromy a těch je málo. Velké skály tu jsou, ale řídce.
# Na trávě je jen pár malých balvanů.
TERRAINS = {
    "grass": {
        "name": "grass",
        "base": "4F9A3C",
        "hue": 5.0,
        "contrast": 28.0,
        "coarseness": 1.0,
        "shore": "sand",
        "forest": {"strom1": 0.07, "strom2": 0.04, "ker1": 1.2, "strom_suchy": 0.05},
        "rocks": {"balvan1": 0.03},
    },
    "dirt": {
        "name": "dirt",
        "base": "7A5A3A",
        "hue": 3.0,
        "contrast": 22.0,
        "coarseness": 1.4,
        "shore": "sand",
        "forest": {"strom1": 1.15, "strom2": 1.0, "ker1": 0.03, "strom_suchy": 0.55},
    },
    "desert": {
        "name": "desert",
        "base": "E2C48A",
        "hue": 3.0,
        "contrast": 16.0,
        "coarseness": 2.0,
        "shore": "sand",
        "forest": {"strom_suchy": 0.02},
        "rocks": {"skala1": 0.002, "skala2": 0.0015, "skala10": 0.001, "skala15": 0.0008, "balvan1": 0.0006},
    },
    "snow": {"name": "snow", "base": "E8EEF2", "hue": 2.0, "contrast": 12.0, "coarseness": 1.8, "shore": "ice"},
    "water": {
        "name": "water",
        "base": "2C6E8A",
        "hue": 4.0,
        "contrast": 16.0,
        "coarseness": 1.7,
        "walkable": False,
        "max_distance": 10,
        "wave": {
            "speed": 0.5,
            "scale": 14,
            "swell": 0.03,
            "tint": 0.18,
            "angle": 30,
            "highlight": "4A8EAA",
            "deep": "245E78",
            "mask_start": 0.7,
        },
    },
}

# Vyšší číslo = užší přechod. Dvojice mimo BLEND_PAIRS použije BLEND_POWER.
# Terén z BLEND_SHARP se do dlaždice řízne až nakonec, svou ostrostí.
# Ostatní povrchy se předtím smíchají mezi sebou.
BLEND_POWER = 2
BLEND_PAIRS = {
    frozenset({"grass", "dirt"}): 1,
}
BLEND_SHARP = {
    "water": 2,
}

# Písek kryje přechod od souše. U hlíny se dlouze rozpouští, oba kraje jsou členité.
SHORE = {
    "sand": "C4A460",
    "sand_wet": "A68448",
    "shallow": "7EBFDA",
    "ice": "E7F6FA",
    "shallow_from": 0.5,
    "shallow_to": 1.0,
    "shallow_strength": 0.5,
    "sand_solid": 0.34,
    "sand_solid_wobble": 0.05,
    "sand_land_fade": 0.40,
    "sand_land_fray": 0.24,
    "sand_water": 0.58,
    "sand_water_shift": 0.36,
    "sand_strength": 1.0,
    "ice_from": 0.02,
    "ice_to": 0.30,
    "ice_strength": 0.48,
}

# Vrstva 1 je nejširší spodek koruny, nejvyšší číslo je špička z listů.
# widths je průměr vrstvy v pixelech, density její zarostlost.
# leaves je počet listů na jedné větvičce. Když chybí, je jich 5 až 8. Nula znamená skoro holé větve.
# height je výška vrstvy v metrech. Pařez je na zemi (0) a při posunu obrazovky stojí.
# Vyšší vrstva se posouvá víc a víc se zvětší. spacing je v metrech: blíž už jiný strom nesmí stát.
# spacing_from přepíše spacing vůči jednomu druhu. Mezi dvojicí platí větší z obou stran.
TREES = {
    "strom1": {
        "leaf": "leaf1.png",
        "layers": 4,
        "density": {4: 0.85, 3: 0.7, 2: 0.55, 1: 0.4},
        "widths": {4: 50, 3: 90, 2: 120, 1: 200},
        "height": {4: 8.0, 3: 6.0, 2: 4.0, 1: 2.2},
        "variants": 9,
        "branch": "6A4328",
        "spacing": 4.5,
        "spacing_from": {"ker1": 2.5},
        "stump": {"color": "6B4A2A", "radius": 14, "root_length": 48},
    },
    "strom2": {
        "leaf": "leaf2.png",
        "layers": 4,
        "density": {4: 1.35, 3: 1.2, 2: 1.05, 1: 0.9},
        "widths": {4: 64, 3: 115, 2: 150, 1: 250},
        "height": {4: 12.0, 3: 9.0, 2: 6.0, 1: 3.4},
        "variants": 9,
        "branch": "6A4328",
        "spacing": 6,
        "spacing_from": {"ker1": 3},
        "stump": {"color": "6B4A2A", "radius": 14, "root_length": 48},
    },
    "ker1": {
        "leaf": "leaf1.png",
        "layers": 2,
        "density": {2: 1.3, 1: 1.2},
        "widths": {2: 40, 1: 68},
        "height": {2: 1.2, 1: 0.55},
        "leaves": 12,
        "variants": 9,
        "branch": "6A4328",
        "spacing": 2,
        "spacing_from": {"strom1": 2.5, "strom2": 3, "strom_suchy": 2.5},
        "stump": {"color": "6B4A2A", "radius": 7, "root_length": 16},
    },
    "strom_suchy": {
        "leaf": "leaf1.png",
        "layers": 4,
        "density": {4: 0.7, 3: 0.6, 2: 0.48, 1: 0.36},
        "widths": {4: 42, 3: 80, 2: 120, 1: 190},
        "height": {4: 7.5, 3: 5.5, 2: 3.6, 1: 2.0},
        "leaves": 0,
        "variants": 9,
        "branch": "8C7E6C",
        "spacing": 4.5,
        "spacing_from": {"ker1": 2.5},
        "stump": {"color": "7A6E5E", "radius": 13, "root_length": 40},
    },
}


def blend_power(corners: tuple[str, ...]) -> float:
    unique = list(set(corners))
    if len(unique) < 2:
        return float(BLEND_POWER)
    best = 0.0
    for index, left in enumerate(unique):
        for right in unique[index + 1 :]:
            pair = frozenset((left, right))
            if pair in BLEND_PAIRS:
                power = float(BLEND_PAIRS[pair])
            else:
                power = float(max(BLEND_SHARP.get(left, 0), BLEND_SHARP.get(right, 0), BLEND_POWER))
            best = max(best, power)
    return best


def surface_info() -> dict:
    surfaces = {}
    for name, preset in TERRAINS.items():
        entry = {"base": preset["base"], "walkable": preset.get("walkable", True)}
        if "max_distance" in preset:
            entry["max_distance"] = preset["max_distance"]
        if "wave" in preset:
            entry["wave"] = preset["wave"]
        if preset.get("shore"):
            entry["shore"] = preset["shore"]
        forest = preset.get("forest") or {}
        for tree, amount in forest.items():
            if tree not in TREES:
                raise SystemExit(f"{name}: les obsahuje neznámý strom {tree}")
            if float(amount) <= 0:
                raise SystemExit(f"{name}: zalesnění {tree} musí být větší než 0")
        if forest:
            entry["forest"] = {tree: float(amount) for tree, amount in forest.items()}
        from gen_rocks import ROCKS

        rocks = preset.get("rocks") or {}
        for rock, amount in rocks.items():
            if rock not in ROCKS:
                raise SystemExit(f"{name}: skály obsahují neznámou skálu {rock}")
            if float(amount) <= 0:
                raise SystemExit(f"{name}: výskyt {rock} musí být větší než 0")
        if rocks:
            entry["rocks"] = {rock: float(amount) for rock, amount in rocks.items()}
        surfaces[name] = entry
    return {"tile_size": 64, "atlas_columns": 4, "variants": 16, "shore": SHORE, "surfaces": surfaces}


def write_surface_info(path: Path = SURFACES_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(surface_info(), indent=2) + "\n", encoding="utf-8")
    return path


def main() -> None:
    from gen_terrain_tiles import generate_surface, parse_hex

    for kind, preset in TERRAINS.items():
        generate_surface(
            kind,
            name=preset["name"],
            base=parse_hex(preset["base"]),
            hue=preset["hue"],
            contrast=preset["contrast"],
            coarseness=preset["coarseness"],
        )
    print(write_surface_info())

    from gen_trees import generate_trees, write_tree_info

    for name, preset in TREES.items():
        generate_trees(name, preset)
    print(write_tree_info(TREES))


if __name__ == "__main__":
    main()
