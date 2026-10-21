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
# Druh, který v mapě chybí, v terénu neroste. Voda je bez lesa i skal.
# Poušť má jen suché stromy a těch je málo. Velké skály tu jsou, ale řídce.
# Na trávě je jen pár malých balvanů.
# Sníh má víc stromů než tráva a míň než hlína. Skal je málo, malých kamenů víc.
# Padlé stromy (padly_strom mezi skálami) leží hlavně na trávě, v lese na hlíně a v močálu.
# decor je průchozí porost z gen_decor.py, počet trsů na dlaždici. Shlukuje se podle druhu.
# springs jsou prameniště řeky (gen_spring.py), ze kterých si pramen na tom terénu vybere.
# Čtverec světa si vybere jen pár terénů. avoid jsou terény, se kterými se nevybere
# společně (platí oběma směry), třeba "avoid": ["desert"] u sněhu. Teď ho nemá žádný terén.
TERRAINS = {
    "grass": {
        "name": "grass",
        "springs": ["pramen_tun", "pramen_kamen"],
        "base": "4F9A3C",
        "hue": 5.0,
        "contrast": 28.0,
        "coarseness": 1.0,
        "shore": "sand",
        "forest": {"strom1": 0.073, "strom2": 0.042, "strom3": 0.0235, "ker1": 0.088, "strom_suchy": 0.052, "smrk": 0.012, "borovice": 0.01},
        "rocks": {"balvan1": 0.008, "balvan_mech": 0.0024, "padly_strom": 0.002},
        "decor": {"trava": 1.1, "kvetiny": 0.35},
    },
    "dirt": {
        "name": "dirt",
        "springs": ["pramen_mokrad", "pramen_tun"],
        "base": "7A5A3A",
        "hue": 3.0,
        "contrast": 14.0,
        "coarseness": 1.4,
        "shore": "sand",
        "forest": {"strom1": 1.15, "strom2": 1.0, "strom3": 0.045, "ker1": 0.042, "strom_suchy": 0.55, "smrk": 0.16, "borovice": 0.08},
        # Stromy smějí stát blíž sebe (forest.gd DENSE_TREE_GAP).
        "dense_forest": True,
        "rocks": {"padly_strom": 0.002},
        "decor": {"kapradi": 0.25, "trava": 0.15, "houby": 0.05},
    },
    "desert": {
        "name": "desert",
        "springs": ["pramen_tun"],
        "base": "E2C48A",
        "hue": 2.0,
        "contrast": 9.0,
        "coarseness": 2.0,
        "shore": "sand",
        "forest": {"strom_suchy": 0.02},
        "rocks": {"skala1": 0.01, "skala2": 0.0075, "skala10": 0.005, "skala15": 0.004, "balvan1": 0.0015},
        "decor": {"trava_sucha": 0.06},
    },
    "snow": {
        "name": "snow",
        "springs": ["pramen_kamen"],
        "base": "E8EEF2",
        "hue": 2.0,
        "contrast": 6.0,
        "coarseness": 1.8,
        "shore": "ice",
        "forest": {"smrk_snih": 0.5, "borovice_snih": 0.2, "strom_snih": 0.12, "strom2_snih": 0.08, "ker_snih": 0.1},
        "rocks": {"balvan_snih": 0.017, "skala_snih": 0.0017, "skala2_snih": 0.00083},
        "decor": {"trava_sucha": 0.04},
        # Nad sněhem padají vločky.
        "snowfall": 1.0,
    },
    # Kamenná suť: drobné i větší ostrohranné kameny, hodně skal, skoro žádné stromy.
    "scree": {
        "name": "scree",
        "springs": ["pramen_kamen"],
        "base": "7E7A73",
        "hue": 2.0,
        "contrast": 12.0,
        "coarseness": 1.0,
        "shore": "sand",
        "forest": {"strom_suchy": 0.012, "ker1": 0.01},
        "rocks": {"balvan1": 0.03, "skala1": 0.006, "skala2": 0.005, "skala10": 0.004},
        "decor": {"trava_sucha": 0.1, "kvetiny": 0.04},
    },
    # Černý popel po požáru: závěje popela, uhlíky, jen ohořelé suché stromy a lávové pukliny.
    "ash": {
        "name": "ash",
        "springs": ["pramen_kamen"],
        "base": "3B3937",
        "hue": 1.5,
        "contrast": 18.0,
        "coarseness": 1.6,
        "forest": {"strom_ohoreny": 0.09, "strom_suchy": 0.012},
        "rocks": {"cedic_maly": 0.01, "cedic": 0.004, "puklina": 0.008},
        "decor": {"vyhonky": 0.15},
    },
    # Močál: bahno, louže a trsy ostřice, keře a pár stromů. Břeh nemá, bahno přejde rovnou do vody.
    "swamp": {
        "name": "swamp",
        "springs": ["pramen_mokrad"],
        "base": "4E4A2F",
        "hue": 3.0,
        "contrast": 14.0,
        "coarseness": 1.5,
        "forest": {"vrba": 1.0, "strom1": 1.0, "strom2": 0.5, "ker_bazina": 0.12, "strom_suchy": 0.4},
        "dense_forest": True,
        "rocks": {"balvan_mech": 0.012, "padly_strom": 0.0027},
        "decor": {"ostrice": 0.6, "rakos": 0.35},
        # Nad močálem se válí mlha.
        "fog": 1.0,
        # V bahně se chodí pomaleji: postavy, vesničané i příšery, které nelétají.
        "speed": 0.75,
    },
    # Vřesoviště: fialový vřes, borůvčí a olivová tráva. Keře, řídké stromy a balvany.
    "heath": {
        "name": "heath",
        "springs": ["pramen_mokrad", "pramen_kamen"],
        "base": "5E5040",
        "hue": 3.0,
        "contrast": 14.0,
        "coarseness": 1.2,
        "shore": "sand",
        "forest": {"ker1": 0.07, "strom1": 0.012, "strom_suchy": 0.02},
        "rocks": {"balvan_mech": 0.01, "balvan1": 0.008, "skala_mech": 0.0015, "padly_strom": 0.0007},
        "decor": {"vres": 0.5, "trava_sucha": 0.25},
    },
    "water": {
        "name": "water",
        "base": "2C6E8A",
        "hue": 4.0,
        "contrast": 16.0,
        "coarseness": 1.7,
        "walkable": False,
        "max_distance": 30,
        # Nejvýš 20 % plochy mapy. Generátor přebytek sloupne od břehu.
        "max_share": 0.2,
        "wave": {
            "speed": 0.5,
            "scale": 48,
            "swell": 0.04,
            "tint": 0.26,
            "glint_scale": 36,
            "glint": 0.6,
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
# snow je barva čepice na hřbetu větví a na pařezu. Takový strom je bez listí.
# height je výška vrstvy v metrech. Pařez je na zemi (0) a při posunu obrazovky stojí.
# Vyšší vrstva se posouvá víc a víc se zvětší. spacing je v metrech: blíž už jiný strom nesmí stát.
# spacing_from přepíše spacing vůči jednomu druhu. Mezi dvojicí platí větší z obou stran.
# leaf_hue posune odstín listí ve stupních (záporný ke žluté), leaf_sat a leaf_value násobí
# sytost a jas listí. bare je úplně holý strom bez občasných lístků.
# conifer je jehličnan: list je jehličí (gen_needles.py), větve rovné v pravidelném přeslenu.
# twig_gap je rozestup bočních větviček vůči jejich délce, needles_along po kolika px sedí
# jehličí i na silné větvi (smrk). Bez něj má jehličí jen větvička (borovice).
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
    "strom3": {
        "leaf": "leaf2.png",
        "layers": 4,
        "density": {4: 1.35, 3: 1.2, 2: 1.05, 1: 0.9},
        "widths": {4: 128, 3: 230, 2: 300, 1: 500},
        "height": {4: 12.0, 3: 9.0, 2: 6.0, 1: 3.4},
        "variants": 9,
        "branch": "6A4328",
        "spacing": 6.5,
        "spacing_from": {"ker1": 4.5},
        "stump": {"color": "6B4A2A", "radius": 28, "root_length": 96},
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
        "spacing_from": {"strom1": 2.5, "strom2": 3, "strom3": 4.5, "strom_suchy": 2.5},
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
    # Ohořelý strom na popelu: holé černé větve, uhelný pařez.
    "strom_ohoreny": {
        "leaf": "leaf1.png",
        "layers": 4,
        "density": {4: 0.6, 3: 0.52, 2: 0.42, 1: 0.32},
        "widths": {4: 40, 3: 76, 2: 112, 1: 176},
        "height": {4: 7.0, 3: 5.2, 2: 3.4, 1: 1.9},
        "leaves": 0,
        "bare": True,
        "variants": 9,
        "branch": "2E2925",
        "spacing": 4.0,
        "stump": {"color": "2A2521", "radius": 13, "root_length": 38},
    },
    # Vrba do močálu: široká, hustá, šedozelená koruna.
    "vrba": {
        "leaf": "leaf2.png",
        "layers": 4,
        "density": {4: 1.2, 3: 1.15, 2: 1.05, 1: 0.95},
        "widths": {4: 70, 3: 140, 2: 200, 1: 270},
        "height": {4: 7.5, 3: 5.6, 2: 3.8, 1: 2.2},
        "leaf_hue": -12,
        "leaf_sat": 0.72,
        "leaf_value": 0.84,
        "variants": 9,
        "branch": "5A4A36",
        "spacing": 5.5,
        "spacing_from": {"ker_bazina": 3.2},
        "stump": {"color": "5C4B37", "radius": 16, "root_length": 56},
    },
    # Bažinný keř: olivový, tmavší než keř na trávě.
    "ker_bazina": {
        "leaf": "leaf2.png",
        "layers": 2,
        "density": {2: 1.3, 1: 1.2},
        "widths": {2: 44, 1: 76},
        "height": {2: 1.2, 1: 0.55},
        "leaves": 12,
        "leaf_hue": -26,
        "leaf_sat": 0.7,
        "leaf_value": 0.82,
        "variants": 9,
        "branch": "4E3E2C",
        "spacing": 2,
        "spacing_from": {"vrba": 3.2},
        "stump": {"color": "4E3E2C", "radius": 7, "root_length": 16},
    },
    # Smrk: hustý, pravidelný, tmavé jehličí ve větvičkách.
    "smrk": {
        "leaf": "needle1.png",
        "conifer": True,
        "twig_gap": 0.3,
        "needles_along": 9,
        "layers": 4,
        "density": {4: 1.05, 3: 0.85, 2: 0.72, 1: 0.62},
        "widths": {4: 46, 3: 104, 2: 156, 1: 216},
        "height": {4: 11.0, 3: 8.0, 2: 5.2, 1: 2.6},
        "leaves": 7,
        "variants": 9,
        "branch": "4E3626",
        "spacing": 3.6,
        "spacing_from": {"ker1": 2.5, "ker_snih": 2.5},
        "stump": {"color": "5A4030", "radius": 13, "root_length": 44},
    },
    "smrk_snih": {
        "leaf": "needle1.png",
        "conifer": True,
        "twig_gap": 0.3,
        "needles_along": 9,
        "layers": 4,
        "density": {4: 1.05, 3: 0.85, 2: 0.72, 1: 0.62},
        "widths": {4: 46, 3: 104, 2: 156, 1: 216},
        "height": {4: 11.0, 3: 8.0, 2: 5.2, 1: 2.6},
        "leaves": 7,
        "variants": 9,
        "branch": "4E3626",
        "spacing": 3.6,
        "spacing_from": {"ker1": 2.5, "ker_snih": 2.5},
        "stump": {"color": "5A4030", "radius": 13, "root_length": 44},
        "snow": "F4F7FA",
    },
    # Borovice: řidší, svazky dlouhých světlejších jehlic, rezavá kůra.
    "borovice": {
        "leaf": "needle2.png",
        "conifer": True,
        "layers": 4,
        "density": {4: 1.1, 3: 0.9, 2: 0.75, 1: 0.62},
        "widths": {4: 70, 3: 130, 2: 180, 1: 224},
        "height": {4: 12.0, 3: 9.5, 2: 6.5, 1: 3.5},
        "leaves": 6,
        "variants": 9,
        "branch": "7A4A2E",
        "spacing": 4.5,
        "spacing_from": {"ker1": 2.5, "ker_snih": 2.5},
        "stump": {"color": "7A4A30", "radius": 13, "root_length": 44},
    },
    "borovice_snih": {
        "leaf": "needle2.png",
        "conifer": True,
        "layers": 4,
        "density": {4: 1.1, 3: 0.9, 2: 0.75, 1: 0.62},
        "widths": {4: 70, 3: 130, 2: 180, 1: 224},
        "height": {4: 12.0, 3: 9.5, 2: 6.5, 1: 3.5},
        "leaves": 6,
        "variants": 9,
        "branch": "7A4A2E",
        "spacing": 4.5,
        "spacing_from": {"ker1": 2.5, "ker_snih": 2.5},
        "stump": {"color": "7A4A30", "radius": 13, "root_length": 44},
        "snow": "F4F7FA",
    },
    "strom_snih": {
        "leaf": "leaf1.png",
        "layers": 4,
        "density": {4: 0.85, 3: 0.7, 2: 0.55, 1: 0.4},
        "widths": {4: 50, 3: 90, 2: 120, 1: 200},
        "height": {4: 8.0, 3: 6.0, 2: 4.0, 1: 2.2},
        "leaves": 0,
        "snow": "F4F7FA",
        "variants": 9,
        "branch": "6A4328",
        "spacing": 3.2,
        "spacing_from": {"ker_snih": 2.5},
        "stump": {"color": "6B4A2A", "radius": 14, "root_length": 48},
    },
    "strom2_snih": {
        "leaf": "leaf2.png",
        "layers": 4,
        "density": {4: 1.35, 3: 1.2, 2: 1.05, 1: 0.9},
        "widths": {4: 64, 3: 115, 2: 150, 1: 250},
        "height": {4: 12.0, 3: 9.0, 2: 6.0, 1: 3.4},
        "leaves": 0,
        "snow": "F4F7FA",
        "variants": 9,
        "branch": "6A4328",
        "spacing": 4.2,
        "spacing_from": {"ker_snih": 3},
        "stump": {"color": "6B4A2A", "radius": 14, "root_length": 48},
    },
    "ker_snih": {
        "leaf": "leaf1.png",
        "layers": 2,
        "density": {2: 1.3, 1: 1.2},
        "widths": {2: 40, 1: 68},
        "height": {2: 1.2, 1: 0.55},
        "leaves": 0,
        "snow": "F4F7FA",
        "variants": 9,
        "branch": "6A4328",
        "spacing": 2,
        "spacing_from": {"strom_snih": 2.5, "strom2_snih": 3},
        "stump": {"color": "6B4A2A", "radius": 7, "root_length": 16},
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
        if "max_share" in preset:
            entry["max_share"] = preset["max_share"]
        if "wave" in preset:
            entry["wave"] = preset["wave"]
        if preset.get("shore"):
            entry["shore"] = preset["shore"]
        for key in ("fog", "snowfall"):
            if key in preset:
                if not 0 < float(preset[key]) <= 1:
                    raise SystemExit(f"{name}: {key} má být mezi 0 a 1")
                entry[key] = float(preset[key])
        if preset.get("dense_forest"):
            entry["dense_forest"] = True
        if "speed" in preset:
            if not 0 < float(preset["speed"]) <= 2:
                raise SystemExit(f"{name}: speed má být mezi 0 a 2")
            entry["speed"] = float(preset["speed"])
        from gen_decor import DECOR

        decor = preset.get("decor") or {}
        for kind, amount in decor.items():
            if kind not in DECOR:
                raise SystemExit(f"{name}: porost obsahuje neznámý druh {kind}")
            if float(amount) <= 0:
                raise SystemExit(f"{name}: hustota porostu {kind} musí být větší než 0")
        if decor:
            entry["decor"] = {kind: float(amount) for kind, amount in decor.items()}
        avoid = preset.get("avoid") or []
        for other in avoid:
            if other not in TERRAINS:
                raise SystemExit(f"{name}: avoid obsahuje neznámý terén {other}")
        if avoid:
            entry["avoid"] = list(avoid)
        springs = preset.get("springs") or []
        if springs:
            from gen_rocks import ROCKS as SPRING_ROCKS

            for spring in springs:
                if not SPRING_ROCKS.get(spring, {}).get("spring"):
                    raise SystemExit(f"{name}: springs obsahuje {spring}, to není prameniště")
            entry["springs"] = list(springs)
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
