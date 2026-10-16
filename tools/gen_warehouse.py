#!/usr/bin/env python3
"""Sklad materiálu z pohledu shora. Ve hře budou tři v rozích trojúhelníku kolem továrny,
zhruba v půli cesty k nejvzdálenějším dolům.

64 px je 1 m. Kreslí se ve čtyřnásobném rozlišení a skládá do masky stejně jako továrna,
barvy i kanály jsou stejné, aby sklad patřil k ní. Tvar je ale kříž, ne osmiúhelník,
a střecha je jehlan z vlnitého plechu, ne otočné mezikruží.

Spodek (0 m):
  kamenná dlažba ve tvaru kříže se zvlněnou zídkou, železné úhelníky na vnějších rozích
  ramen a kulaté pláty ve vnitřních rozích. Na konci každého ramene je skladová plocha:
  štěrkové lože v železném rámu se sloupky v rozích (stejný kanál jako sklad v továrně).
  Kdo se plochy dotkne, odloží tam materiál, jako do jezírka; dalším dotykem ho zase vezme.
  Mezi plochou a střechou jsou kolejnice, po kterých se vozí ke středu.

Střecha (výška ROOF_H): samostatná vrstva nad středovým čtvercem, o přesah větší.
  Jehlan ze čtyř ploch vlnitého plechu, nárožní lišty s nýty, tmavý okap,
  rez v různé míře. Na vrcholu osmiboký mosazný světlík s žaluziemi, ozvěna továrny.

Vrstva nese váhy materiálu, ne hotovou barvu. Alfa je krytí.
Spodek: R podlaha, G kov, B sklad (štěrk).
Střecha: R plech, G mosaz, B temný lem.
Součet vah děleno krytím nese světlost, stejně jako u továrny.

Ve hře je kreslí factory_layer.gdshader bez pásů, stejně jako továrnu. Import nesmí mít
fix_alpha_border.

  py tools/gen_warehouse.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from gen_factory import (
    EDGE,
    PREVIEW,
    SS,
    TINTS_BASE as FACTORY_BASE,
    TINTS_RING as FACTORY_RING,
    Mask,
    blend,
    compose,
    crop_square,
    disc,
    fit,
    hex_of,
    on_checker,
    pack_mask,
    paste_center,
    save_sheet,
    trim,
)
from gen_houses import SHADE, SHADE_FLOOR, SHEEN, colorize, fbm, hash01, load_font, organic, smoothstep, stone_shade

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "warehouse"
FACTORY_DIR = ROOT / "godot" / "graphics" / "objects" / "factory"
CRYSTAL_DIR = ROOT / "godot" / "graphics" / "objects" / "crystal"

PX = 64

# Míry v metrech. Kříž je přes ramena REACH * 2 široký, továrna má přes plochy 6 m
# a s výstupkem skoro 7,5 m, sklad má tedy zhruba polovinu.
CORE = 0.78  # poloviční strana středového čtverce
ARM = 0.62  # poloviční šířka ramene
REACH = 1.92  # od středu ke konci ramene
CURB = 0.13  # zídka
# Skladová plocha v rameni: od BAY_IN do BAY_OUT od středu, poloviční šířka BAY_HALF.
# Ústa jezírka mají 1 m, plocha je podobně velká, aby se tam vešly tři kameny a víc menších.
BAY_IN = 0.98
BAY_OUT = REACH - CURB - 0.05
BAY_HALF = 0.44
BAY_FRAME = 0.07
# Střecha
ROOF_HALF = CORE + 0.1
ROOF_H = 1.5
LANTERN = 0.27  # apotéma světlíku
RIB_PITCH = 0.085  # vlny plechu
PANEL = 0.46  # šířka tabule plechu

FLOOR, METAL, YARD_CH = 0, 1, 2
PLATE, BRASS, LIP = 0, 1, 2

# Stejné barvy jako továrna. Plech střechy je o kus šedší než pláty mezikruží,
# aby sklad nebyl zmenšená továrna.
TINTS_BASE = FACTORY_BASE
TINTS_ROOF = (
    (138, 132, 120),  # vlnitý plech
    FACTORY_RING[1],  # mosaz
    FACTORY_RING[2],  # lem a spáry
)

# Směry ramen: východ, jih, západ, sever (jih je +y). Světlo jako u domečků.
DIRS = ((1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0))
# Jehlan potřebuje větší rozdíl ploch než došek domečků, jinak splývá v jednu desku.
FACE_LIGHT = {"south": 1.0, "east": 0.8, "west": 0.7, "north": 0.56}


def m(meters: float) -> float:
    return meters * PX


def cell_for() -> int:
    cell = int(math.ceil(m(REACH + 0.25) * 2.0))
    return cell + cell % 2


def grids(cell: int) -> tuple[np.ndarray, np.ndarray]:
    axis = (np.arange(cell * SS, dtype=np.float32) + 0.5) / SS - cell / 2.0
    return np.meshgrid(axis, axis)


def rect_dist(x: np.ndarray, y: np.ndarray, hx: float, hy: float) -> np.ndarray:
    """Vzdálenost od hrany obdélníku, uvnitř kladná."""
    return np.minimum(hx - np.abs(x), hy - np.abs(y))


def cross(x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    edge = np.maximum.reduce(
        [
            rect_dist(x, y, m(CORE), m(CORE)),
            rect_dist(x, y, m(REACH), m(ARM)),
            rect_dist(x, y, m(ARM), m(REACH)),
        ]
    )
    return edge >= 0.0, edge


def local(x: np.ndarray, y: np.ndarray, d: tuple[float, float]) -> tuple[np.ndarray, np.ndarray]:
    """Souřadnice ramene: along ven od středu, side napříč."""
    nx, ny = d
    return x * nx + y * ny, -x * ny + y * nx


def paint_base(x0: np.ndarray, y0: np.ndarray, salt: int = 0) -> Mask:
    cell = int(round(x0.shape[1] / SS))
    mask = Mask(cell)
    # Zděný obvod se vlní jako u továrny, kování a plochy drží rovné souřadnice.
    x, y = organic(x0, y0, 601 + salt, 0.0, m(0.05))
    inside, edge = cross(x, y)
    flags = stone_shade(x, y, m(0.5), 603 + salt)
    weather = 0.84 + 0.24 * fbm(x, y, m(1.8), 605 + salt)
    mask.fill(inside, FLOOR, flags * weather * (1.0 - 0.18 * smoothstep(m(0.5), 0.0, edge)))
    # Pod střechou je dlažba ošlapaná do hladka, ve hře ji uvidí jen u kraje obrazovky.
    core = rect_dist(x0, y0, m(CORE), m(CORE)) >= 0.0
    mask.fill(core, FLOOR, stone_shade(x0, y0, m(0.3), 607 + salt, (1.6, 1.0)) * 0.86)

    curb = inside & (edge < m(CURB))
    blocks = stone_shade(x, y, m(0.3), 609 + salt, (1.3, 1.3))
    mask.fill(curb, FLOOR, blocks * (0.72 + 0.3 * smoothstep(0.0, m(0.18), edge)))

    for d in DIRS:
        paint_rails(mask, x0, y0, d)
        paint_bay(mask, x0, y0, d, salt)
    paint_corners(mask, x0, y0, inside, edge)
    return mask


def paint_rails(mask: Mask, x: np.ndarray, y: np.ndarray, d: tuple[float, float]) -> None:
    """Dvě kolejnice s pražci od plochy pod střechu. Úzké, ať plochu nepřekryjí."""
    along, side = local(x, y, d)
    span = (along >= m(CORE - 0.3)) & (along <= m(BAY_IN))
    sleeper = span & (np.abs(side) <= m(0.3)) & (np.mod(along, m(0.16)) < m(0.05))
    mask.fill(sleeper, METAL, 0.42)
    for gauge in (-0.2, 0.2):
        rail = span & (np.abs(side - m(gauge)) <= m(0.03))
        mask.fill(rail, METAL, 0.62 + 0.34 * smoothstep(m(0.03), 0.0, np.abs(side - m(gauge))))


def paint_bay(mask: Mask, x: np.ndarray, y: np.ndarray, d: tuple[float, float], salt: int) -> None:
    """Skladová plocha: železný rám, uvnitř štěrk. Sem se kameny odkládají."""
    along, side = local(x, y, d)
    mid = m((BAY_IN + BAY_OUT) * 0.5)
    half_a = m((BAY_OUT - BAY_IN) * 0.5)
    half_s = m(BAY_HALF)
    a = along - mid
    frame = (np.abs(a) <= half_a) & (np.abs(side) <= half_s)
    bed = (np.abs(a) <= half_a - m(BAY_FRAME)) & (np.abs(side) <= half_s - m(BAY_FRAME))
    rim_in = np.minimum(half_a - np.abs(a), half_s - np.abs(side))
    mask.fill(frame, METAL, 0.5 + 0.34 * np.sin(np.clip(rim_in / m(BAY_FRAME), 0.0, 1.0) * math.pi))
    gravel = stone_shade(x, y, m(0.11), 611 + salt)
    earth = 0.6 + 0.28 * fbm(x, y, m(0.7), 613 + salt)
    # Lože je zapuštěné: u rámu stín, uprostřed světlejší.
    sink = 0.78 + 0.22 * smoothstep(0.0, m(0.18), rim_in - m(BAY_FRAME))
    mask.fill(bed, YARD_CH, (0.5 * earth + 0.5 * gravel) * sink)
    # Vyšlapaný pruh od kolejí: štěrk tam je ujetý a světlejší.
    worn = bed & (np.abs(side) <= m(0.26)) & (a < 0.0)
    blend(mask, worn, FLOOR, 0.22 * smoothstep(0.0, -half_a, a))
    # Sloupky v rozích rámu, oblé.
    for sa in (-1.0, 1.0):
        for ss in (-1.0, 1.0):
            pa, ps = sa * (half_a - m(0.035)), ss * (half_s - m(0.035))
            dist = np.hypot(a - pa, side - ps)
            post = dist <= m(0.075)
            mask.fill(post, METAL, 0.55 + 0.42 * smoothstep(m(0.075), 0.0, dist))
    # Nýty v půlce dlouhých stran rámu.
    for ss in (-1.0, 1.0):
        bolt = (np.hypot(a, side - ss * (half_s - m(BAY_FRAME * 0.5))) <= m(0.025))
        mask.fill(bolt, METAL, 0.96)
    for sa in (-1.0, 1.0):
        bolt = (np.hypot(a - sa * (half_a - m(BAY_FRAME * 0.5)), side) <= m(0.025))
        mask.fill(bolt, METAL, 0.96)


def paint_corners(mask: Mask, x: np.ndarray, y: np.ndarray, inside: np.ndarray, edge: np.ndarray) -> None:
    """Úhelníky na vnějších rozích ramen, kulaté pláty ve vnitřních rozích kříže."""
    for d in DIRS:
        along, side = local(x, y, d)
        for ss in (-1.0, 1.0):
            ca, cs = m(REACH), ss * m(ARM)
            near = (np.abs(along - ca) <= m(0.3)) & (np.abs(side - cs) <= m(0.3))
            leg = near & inside & (edge < m(0.12))
            mask.fill(leg, METAL, 0.62)
            for ba, bs in ((0.2, 0.06), (0.06, 0.2)):
                bolt = np.hypot(along - (ca - m(ba)), side - (cs - ss * m(bs))) <= m(0.035)
                mask.fill(bolt & inside, METAL, 0.95)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx, cy = sx * m(CORE), sy * m(CORE)
            plate = inside & disc(x, y, cx, cy, m(0.2))
            mask.fill(plate, METAL, 0.56)
            mask.fill(plate & ~disc(x, y, cx, cy, m(0.15)), METAL, 0.76)
            mask.fill(inside & disc(x, y, cx, cy, m(0.05)), METAL, 0.92)


def paint_roof(x0: np.ndarray, y0: np.ndarray, salt: int = 0) -> Mask:
    cell = int(round(x0.shape[1] / SS))
    mask = Mask(cell)
    x, y = organic(x0, y0, 621 + salt, 0.0, m(0.015))
    ax, ay = np.abs(x), np.abs(y)
    big = np.maximum(ax, ay)
    rh = m(ROOF_HALF)
    roof = big <= rh
    down = big / rh  # 0 na vrcholu, 1 u okapu
    ns = ay >= ax
    sides = {
        "south": ns & (y > 0),
        "north": ns & (y <= 0),
        "east": ~ns & (x > 0),
        "west": ~ns & (x <= 0),
    }
    bias = np.ones_like(x)
    for name, where in sides.items():
        bias = np.where(where, FACE_LIGHT[name], bias)
    across = np.where(ns, x, y)
    rib = 0.5 + 0.5 * np.sin(across / m(RIB_PITCH) * math.tau)
    weather = 0.9 + 0.16 * fbm(x, y, m(0.9), 623 + salt)
    shade = bias * (0.58 + 0.24 * rib) * weather * (0.92 + 0.1 * down)
    mask.fill(roof, PLATE, shade)

    # Rez stéká po spádu, víc u okapu.
    rust = smoothstep(0.52, 0.82, fbm(x * 0.7, y * 0.7 + down * m(0.6), m(0.5), 625 + salt)) * (0.25 + 0.45 * down)
    blend(mask, roof, LIP, rust * 0.7)

    # Spáry tabulí po spádu.
    panel = np.abs(np.mod(across + m(PANEL) * 0.5, m(PANEL)) - m(PANEL) * 0.5)
    seam = roof & (panel < m(0.018)) & (big > m(LANTERN + 0.05))
    mask.fill(seam, LIP, 0.34)

    # Nárožní lišty: oblé, světlé uprostřed, s nýty.
    hip = np.abs(ax - ay) / math.sqrt(2.0)
    cap = roof & (hip <= m(0.055))
    mask.fill(cap, PLATE, (0.6 + 0.4 * smoothstep(m(0.055), 0.0, hip)) * np.minimum(1.1, bias + 0.15))
    mask.fill(roof & (hip > m(0.055)) & (hip <= m(0.07)), LIP, 0.3)
    stud = roof & (hip <= m(0.022)) & (np.mod(big, m(0.17)) < m(0.04)) & (big > m(LANTERN + 0.08))
    mask.fill(stud, LIP, 0.82)

    # Okap: tmavý lem a řada nýtů nad ním.
    eave = rh - big
    mask.fill(roof & (eave <= m(0.05)), LIP, 0.34 + 0.4 * np.sin(np.clip(eave / m(0.05), 0.0, 1.0) * math.pi))
    along_eave = np.where(ns, x, y)
    rivet = roof & (np.abs(eave - m(0.1)) <= m(0.022)) & (np.abs(np.mod(along_eave, m(0.2)) - m(0.1)) <= m(0.022))
    rivet &= hip > m(0.09)
    mask.fill(rivet, LIP, 0.8)

    # Okapové koule v rozích, mosazné.
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx, cy = sx * (rh - m(0.05)), sy * (rh - m(0.05))
            dist = np.hypot(x - cx, y - cy)
            mask.fill(dist <= m(0.07), BRASS, 0.6 + 0.38 * smoothstep(m(0.07), 0.0, dist))

    paint_lantern(mask, x0, y0)
    return mask


def paint_lantern(mask: Mask, x: np.ndarray, y: np.ndarray) -> None:
    """Osmiboký světlík s žaluziemi. Mosaz, jako poklop na mezikruží."""
    ax, ay = np.abs(x), np.abs(y)
    ap = m(LANTERN)
    oct_d = np.minimum(np.minimum(ap - ax, ap - ay), (ap * math.sqrt(2.0) - (ax + ay)) / math.sqrt(2.0))
    body = oct_d >= 0.0
    # Stín pod světlíkem na plechu.
    mask.fill((oct_d >= -m(0.04)) & ~body, LIP, 0.3)
    # Žaluzie: proužky souběžné s nejbližší stěnou osmiúhelníku.
    ang = np.arctan2(y, x)
    face = np.round(ang / (math.pi / 4.0)) * (math.pi / 4.0)
    radial = x * np.cos(face) + y * np.sin(face)
    slat = np.mod(radial / m(0.045), 1.0)
    mask.fill(body, BRASS, 0.5 + 0.36 * slat)
    mask.fill(body & (oct_d <= m(0.03)), LIP, 0.46)
    # Hrany mezi stěnami.
    edge_ang = np.abs(np.mod(ang + math.pi / 8.0, math.pi / 4.0) - math.pi / 8.0) * np.hypot(x, y)
    mask.fill(body & (edge_ang <= m(0.012)), LIP, 0.4)
    dist = np.hypot(x, y)
    hat = dist <= m(0.11)
    mask.fill(hat, BRASS, 0.62 + 0.36 * smoothstep(m(0.11), 0.0, dist))
    mask.fill(hat & (dist >= m(0.09)), LIP, 0.5)


def bays_px() -> list[dict]:
    """Středy a poloviny skladových ploch v px od středu, jih je +y."""
    mid = m((BAY_IN + BAY_OUT) * 0.5)
    half_a = m((BAY_OUT - BAY_IN) * 0.5)
    half_s = m(BAY_HALF)
    names = ("east", "south", "west", "north")
    out = []
    for name, (nx, ny) in zip(names, DIRS):
        hx = half_a if nx else half_s
        hy = half_s if nx else half_a
        out.append(
            {
                "side": name,
                "center": [round(nx * mid, 2), round(ny * mid, 2)],
                "half": [round(hx, 2), round(hy, 2)],
            }
        )
    return out


# --- náhled se zásobou -------------------------------------------------------

MATERIAL_SAMPLE = ("piskovec", "sira", "magnetit", "lavovy", "grafit")


def gem_sprites() -> dict[str, Image.Image]:
    """Kameny obarvené zhruba jako crystal.gdshader. Jen pro náhled."""
    info = json.loads((CRYSTAL_DIR / "crystal.json").read_text(encoding="utf-8"))
    shapes = {name: Image.open(CRYSTAL_DIR / shape["file"]).convert("RGBA") for name, shape in info["shapes"].items()}
    sprites = {}
    for key, mat in info["materials"].items():
        data = np.asarray(shapes[mat["shape"]], np.float32) / 255.0
        color = np.array([int(mat["color"][i : i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0
        light = data[..., 0] / np.maximum(data[..., 3], 1e-3)
        rim = data[..., 2] / np.maximum(data[..., 3], 1e-3)
        rgb = color[None, None, :] * (0.4 + 0.9 * light)[..., None]
        rgb = rgb * (1.0 - 0.55 * rim)[..., None] + 0.12 * light[..., None] ** 4
        out = np.dstack([np.clip(rgb, 0.0, 1.0), data[..., 3]])
        sprites[key] = Image.fromarray(np.round(out * 255.0).astype(np.uint8), "RGBA")
    return sprites


def stock(base: Image.Image, fills: list[list[str]]) -> Image.Image:
    """Spodek s kameny na plochách. Pořadí ploch jako DIRS."""
    image = base.copy()
    sprites = gem_sprites()
    cx, cy = image.width / 2.0, image.height / 2.0
    spots = ((-0.36, -0.3), (0.34, -0.22), (0.0, 0.32), (-0.3, 0.34), (0.36, 0.36), (0.02, -0.02))
    rng = np.random.default_rng(7)
    for bay, mats in zip(bays_px(), fills):
        bx, by = bay["center"]
        hx, hy = bay["half"]
        scale = 1.0 if len(mats) <= 3 else 0.78
        for index, key in enumerate(mats):
            sprite = sprites[key]
            if scale != 1.0:
                side = round(sprite.width * scale)
                sprite = sprite.resize((side, side), Image.Resampling.LANCZOS)
            sprite = sprite.rotate(float(rng.uniform(0, 360)), resample=Image.Resampling.BICUBIC)
            ox, oy = spots[index % len(spots)]
            px = cx + bx + ox * hx * 1.1 - sprite.width / 2.0
            py = cy + by + oy * hy * 1.1 - sprite.height / 2.0
            image.alpha_composite(sprite, (round(px), round(py)))
    return image


def factory_preview() -> Image.Image | None:
    base_path, ring_path = FACTORY_DIR / "base.png", FACTORY_DIR / "ring.png"
    if not base_path.exists() or not ring_path.exists():
        return None
    base = colorize(Image.open(base_path).convert("RGBA"), FACTORY_BASE)
    ring = colorize(Image.open(ring_path).convert("RGBA"), FACTORY_RING)
    return compose(base, ring, (0, 0))


def side_by_side(left: Image.Image, right: Image.Image, gap: int = 40) -> Image.Image:
    height = max(left.height, right.height)
    image = Image.new("RGBA", (left.width + gap + right.width, height), (0, 0, 0, 0))
    image.alpha_composite(left, (0, (height - left.height) // 2))
    image.alpha_composite(right, (left.width + gap, (height - right.height) // 2))
    return image


def save_masks(base: Image.Image, roof: Image.Image, path: Path) -> None:
    items = ((base, "base.png  R podlaha  G kov  B štěrk"), (roof, "roof.png  R plech  G mosaz  B lem"))
    gap, caption = 16, 28
    slot = max(base.width, roof.width) * 2
    sheet = Image.new("RGB", (2 * slot + 3 * gap, slot + caption + 2 * gap), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)
    for index, (image, label) in enumerate(items):
        x = gap + index * (slot + gap)
        draw.text((x, gap), label, fill=(230, 226, 214), font=font)
        big = image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST)
        sheet.paste(on_checker(big), (x + (slot - big.width) // 2, gap + caption + (slot - big.height) // 2))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def check(base: Image.Image, roof: Image.Image) -> None:
    base_px = np.asarray(base)
    roof_px = np.asarray(roof)
    if base_px.shape != roof_px.shape:
        raise SystemExit("spodek a střecha nemají stejný rozměr")
    h, w = base_px.shape[:2]
    cy, cx = h // 2, w // 2
    if roof_px[cy, cx, 3] < 200 or base_px[cy, cx, 3] < 200:
        raise SystemExit("uprostřed chybí střecha nebo podlaha")
    # Kříž: rohy čtverce kolem ramen jsou prázdné.
    corner = int(m(REACH - 0.15))
    if base_px[cy - corner, cx - corner, 3] > 8:
        raise SystemExit("spodek není kříž, roh je zastavěný")
    for bay in bays_px():
        bx, by = (int(round(v)) for v in bay["center"])
        hx, hy = (int(v) - 6 for v in bay["half"])
        patch = base_px[cy + by - hy : cy + by + hy, cx + bx - hx : cx + bx + hx]
        if int((patch[..., 2] > 60).sum()) < patch.shape[0] * patch.shape[1] * 0.5:
            raise SystemExit(f"plocha {bay['side']} není ve vlastním kanálu")
        if int((roof_px[cy + by - hy : cy + by + hy, cx + bx - hx : cx + bx + hx, 3] > 16).sum()) > 0:
            raise SystemExit(f"střecha zakrývá plochu {bay['side']}")


def write_info(base: Image.Image, roof: Image.Image) -> Path:
    """Míry v px od středu obrázku, jih je +y. Hra z nich postaví neprůchodný střed
    a čtyři plochy, které se chovají jako jezírka."""
    catalog = {
        "px_per_meter": PX,
        "height_unit": "m",
        "shader": "res://shaders/factory_layer.gdshader",
        "span_m": round(REACH * 2.0, 3),
        "core_px": round(m(CORE), 2),
        "arm_half_px": round(m(ARM), 2),
        "reach_px": round(m(REACH), 2),
        "bays": bays_px(),
        "shade": list(SHADE),
        "shade_floor": SHADE_FLOOR,
        "sheen": list(SHEEN),
        "layers": {
            "base": {
                "file": "base.png",
                "height": 0.0,
                "channels": ["floor", "metal", "yard"],
                "colors": [hex_of(tint) for tint in TINTS_BASE],
                "cell": base.width,
            },
            "roof": {
                "file": "roof.png",
                "height": ROOF_H,
                "channels": ["plate", "brass", "lip"],
                "colors": [hex_of(tint) for tint in TINTS_ROOF],
                "half_px": round(m(ROOF_HALF), 2),
                "cell": roof.width,
            },
        },
    }
    path = OUT_DIR / "sklad.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def main() -> None:
    x, y = grids(cell_for())
    base = pack_mask(paint_base(x, y))
    roof = pack_mask(paint_roof(x, y))
    side = crop_square(base).width
    canvas = lambda img: (lambda c: (paste_center(c, img), c)[1])(Image.new("RGBA", (side, side)))
    base = canvas(crop_square(base))
    roof = canvas(crop_square(roof))
    check(base, roof)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    base.save(OUT_DIR / "base.png")
    roof.save(OUT_DIR / "roof.png")

    painted_base = colorize(base, TINTS_BASE)
    painted_roof = colorize(roof, TINTS_ROOF)
    shift = (round(EDGE[0] * ROOF_H), round(EDGE[1] * ROOF_H))
    together = compose(painted_base, painted_roof, (0, 0))
    edge = compose(painted_base, painted_roof, shift)
    full = compose(
        stock(painted_base, [["sira", "sira", "sira"], ["magnetit"], [], ["piskovec", "lavovy", "grafit", "sira", "magnetit"]]),
        painted_roof,
        (0, 0),
    )
    tile = 420
    save_sheet(
        [
            (fit(trim(painted_base), tile), "spodek"),
            (fit(trim(painted_roof), tile), "střecha"),
            (fit(trim(together), tile), f"spolu · {REACH * 2:.1f} m"),
            (fit(trim(edge), tile), "u kraje"),
            (fit(trim(full), tile), "se zásobou"),
        ],
        3,
        PREVIEW / "sklad.png",
    )
    save_masks(base, roof, PREVIEW / "sklad_masky.png")
    factory = factory_preview()
    if factory is not None:
        pair = side_by_side(trim(factory), trim(together))
        save_sheet([(pair, "továrna a sklad ve stejném měřítku")], 1, PREVIEW / "sklad_vedle_tovarny.png")
    info = write_info(base, roof)
    print(f"sklad {base.width} px, přes ramena {REACH * 2:.2f} m, střecha {ROOF_H:.1f} m")
    print(PREVIEW / "sklad.png")
    print(PREVIEW / "sklad_masky.png")
    print(PREVIEW / "sklad_vedle_tovarny.png")
    print(info)


if __name__ == "__main__":
    main()
