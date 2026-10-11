#!/usr/bin/env python3
"""Továrna z pohledu shora. Zatím jen grafika, do Godotu se nezapojí.

64 px je 1 m. Kreslí se ve čtyřnásobném rozlišení a složí se do masky,
stejně jako domečky. Osmiúhelník je přes plochy široký jako kotlina,
tedy 6 m. Výstupek z jižní hrany přesahuje.

Spodek (0 m):
  podlaha osmiúhelníku, sedm dopravníků od hran ke středu,
  čtvercový výstupek na jižní hraně (tam ve hře vyjedou krabičky)
  a kruhová plocha na materiál uprostřed.
  Dopravníky jsou jeden snímek. Pohyb pásu by potom byl posun
  toho vzoru, ne další obrázky.

Mezikruží (výška RING_H): samostatná vrstva, střed je průhledný,
takže sklad pod ním zůstane vidět. Obrázek je vystředěný na osu,
kolem které se vrstva ve hře otočí. Jeden díl má mosazný poklop,
aby otočení bylo poznat.

Vrstva nese váhy materiálu, ne hotovou barvu. Alfa je krytí.
Spodek: R podlaha, G kov, B sklad.
Mezikruží: R pláty, G mosaz, B temný lem.
Součet vah děleno krytím nese světlost, stejně jako u domečků.

  py tools/gen_factory.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from gen_houses import SHADE_FLOOR, colorize, hash01, load_font, smoothstep
from gen_trees import on_grass

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "tools" / "out" / "factory"
PREVIEW = ROOT / "tools" / "preview"

PX = 64
SS = 4
PARALLAX = 0.016
EDGE = (640.0 * PARALLAX, 360.0 * PARALLAX)

# Návrhové metry jsou z větší kresby. SCALE je srovná s kotlinou:
# pata kotliny má 384 px, tedy 6 m v průměru. Přes plochy je osmiúhelník
# stejně široký. Výstupek sedí na jižní ploše a nepřesahuje její konce.
FLAT = 5.6
DOCK = 2.7
RING_OUT = 3.55
RING_IN = 2.02
YARD = 2.18
RING_H = 3.0
BELT_HALF = 0.56
SCALE = 6.0 / (FLAT * 2.0)

FLOOR, METAL, YARD_CH = 0, 1, 2
PLATE, BRASS, LIP = 0, 1, 2

# Jižní hrana je ta s výstupkem. Normály ploch jdou po 45°, jih je π/2.
SOUTH = 2

TINTS_BASE = (
    (176, 164, 140),  # podlaha
    (102, 106, 112),  # kov
    (214, 186, 120),  # sklad
)
TINTS_RING = (
    (150, 134, 108),  # pláty
    (198, 156, 78),  # mosaz
    (64, 56, 48),  # lem a spáry
)


class Mask:
    def __init__(self, cell: int) -> None:
        n = cell * SS
        self.cell = cell
        self.ch = np.zeros((3, n, n), np.float32)
        self.shade = np.ones((n, n), np.float32)
        self.cover = np.zeros((n, n), np.float32)

    def fill(self, where: np.ndarray, channel: int, shade: np.ndarray | float) -> None:
        self.ch[:, where] = 0.0
        self.ch[channel, where] = 1.0
        self.shade[where] = shade if np.isscalar(shade) else shade[where]
        self.cover[where] = 1.0


def real(meters: float) -> float:
    return meters * SCALE


def m(meters: float) -> float:
    return real(meters) * PX


def cell_for() -> int:
    reach = max(real(FLAT + DOCK + 0.35), real(FLAT) / math.cos(math.pi / 8) + real(0.35))
    cell = int(math.ceil(reach * PX * 2.0 + 8.0))
    if cell % 2:
        cell += 1
    return cell


def grids(cell: int) -> tuple[np.ndarray, np.ndarray]:
    axis = (np.arange(cell * SS, dtype=np.float32) + 0.5) / SS - cell / 2.0
    return np.meshgrid(axis, axis)


def downscale(values: np.ndarray, cell: int) -> np.ndarray:
    return values.reshape(cell, SS, cell, SS).mean(axis=(1, 3))


def pack_mask(mask: Mask) -> Image.Image:
    stored = SHADE_FLOOR + (1.0 - SHADE_FLOOR) * np.clip(mask.shade, 0.0, 1.0)
    channels = [downscale(channel * stored, mask.cell) for channel in mask.ch]
    cover = downscale(mask.cover, mask.cell)
    rgba = np.stack(channels + [cover], axis=-1)
    return Image.fromarray(np.round(np.clip(rgba, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")


def noise(n: int, salt: int, step: int = 8) -> np.ndarray:
    iy, ix = np.indices((n, n))
    return hash01(ix // step, iy // step, salt)


def octagon(x: np.ndarray, y: np.ndarray, apothem: float) -> tuple[np.ndarray, np.ndarray]:
    ax = np.abs(x)
    ay = np.abs(y)
    limit = apothem * math.sqrt(2.0)
    inside = (ax <= apothem) & (ay <= apothem) & (ax + ay <= limit)
    dist = np.minimum(apothem - ax, apothem - ay)
    dist = np.minimum(dist, (limit - (ax + ay)) / math.sqrt(2.0))
    return inside, dist


def paint_base(x: np.ndarray, y: np.ndarray) -> Mask:
    cell = int(round((x.shape[1] / SS)))
    mask = Mask(cell)
    n = x.shape[0]
    ap = m(FLAT)
    inside, edge = octagon(x, y, ap)
    grain = noise(n, 11)
    rim = smoothstep(m(0.42), 0.0, edge)
    floor_shade = (0.56 + 0.18 * grain) * (1.0 - 0.30 * rim)
    mask.fill(inside, FLOOR, floor_shade)

    curb = inside & (edge < m(0.16)) & (edge >= 0.0)
    mask.fill(curb, METAL, 0.62 + 0.08 * grain)

    dist = np.hypot(x, y)
    yard = dist <= m(YARD)
    yard_shade = 0.74 + 0.10 * noise(n, 19, 6)
    yard_shade = yard_shade * (1.0 - 0.22 * smoothstep(m(YARD - 0.16), m(YARD), dist))
    mask.fill(yard, YARD_CH, yard_shade)
    # Kříž na ploše, ať je vidět, že se sklad s mezikružím netočí.
    arm = m(0.07)
    cross = yard & (((np.abs(x) <= arm) & (np.abs(y) <= m(0.85))) | ((np.abs(y) <= arm) & (np.abs(x) <= m(0.85))))
    mask.fill(cross, METAL, 0.46)

    paint_belts(mask, x, y, inside)
    paint_dock(mask, x, y, grain)
    return mask


def paint_belts(mask: Mask, x: np.ndarray, y: np.ndarray, inside: np.ndarray) -> None:
    """Sedm pásů od ploché hrany ke kolu. Jižní hrana má místo pásu výstupek."""
    half = m(BELT_HALF)
    rail = m(0.09)
    outer = m(FLAT) - m(0.18)
    inner = m(RING_OUT) - m(0.18)
    pitch = m(0.36)
    slat_w = m(0.07)
    for k in range(8):
        if k == SOUTH:
            continue
        ang = k * math.pi / 4.0
        nx, ny = math.cos(ang), math.sin(ang)
        along = x * nx + y * ny
        side = -x * ny + y * nx
        span = inside & (along >= inner) & (along <= outer)
        belt = span & (np.abs(side) <= half)
        center = span & (np.abs(side) <= half - rail)
        rails = belt & ~center
        mask.fill(belt, METAL, 0.40)
        mask.fill(rails, METAL, 0.78)
        slats = center & (np.mod(along, pitch) < slat_w)
        mask.fill(slats, METAL, 0.90)


def paint_dock(mask: Mask, x: np.ndarray, y: np.ndarray, grain: np.ndarray) -> None:
    ap = m(FLAT)
    side = m(DOCK)
    overlap = m(0.06)
    dock = (np.abs(x) <= side / 2.0) & (y >= ap - overlap) & (y <= ap + side)
    mask.fill(dock, FLOOR, 0.64 + 0.12 * grain)
    rim = m(0.14)
    border = dock & (
        (np.abs(x) >= side / 2.0 - rim)
        | (y <= ap - overlap + rim)
        | (y >= ap + side - rim)
    )
    mask.fill(border, METAL, 0.70)
    plate = (
        (np.abs(x) <= side / 2.0 - m(0.42))
        & (y >= ap + m(0.42))
        & (y <= ap + side - m(0.42))
    )
    mask.fill(plate, YARD_CH, 0.86)
    # Válečky u vnější hrany, kudy krabička vyjede ven.
    roller = plate & (np.mod(y, m(0.34)) < m(0.05)) & (y > ap + side - m(1.15))
    mask.fill(roller, METAL, 0.55)


def paint_ring(x: np.ndarray, y: np.ndarray) -> Mask:
    cell = int(round(x.shape[1] / SS))
    mask = Mask(cell)
    n = x.shape[0]
    dist = np.hypot(x, y)
    outer, inner = m(RING_OUT), m(RING_IN)
    ring = (dist <= outer) & (dist >= inner)
    grain = noise(n, 29, 5)
    t = np.clip((dist - inner) / (outer - inner), 0.0, 1.0)
    ang = np.arctan2(y, x)
    # Spáry míří do rohů osmiúhelníku, díly sedí nad plochými stranami.
    # Severní poklop je pak uprostřed dílu a spára jím nevede.
    sector = math.pi / 4.0
    aligned = ang - math.pi / 8.0
    sector_i = np.floor(np.mod(aligned + math.pi, math.tau) / sector)
    alt = np.where(np.mod(sector_i, 2) == 0, 0.05, -0.03).astype(np.float32)
    shade = np.clip(0.50 + 0.30 * t + 0.08 * grain + alt, 0.0, 1.0)
    mask.fill(ring, PLATE, shade)

    seam_ang = np.minimum(np.mod(aligned, sector), sector - np.mod(aligned, sector))
    seams = ring & (seam_ang * np.maximum(dist, 1.0) < m(0.055))
    mask.fill(seams, LIP, 0.34)

    lip_w = m(0.12)
    mask.fill(ring & (dist <= inner + lip_w), LIP, 0.40)
    mask.fill(ring & (dist >= outer - lip_w), LIP, 0.48)

    # Poklop na severu. Jediný takový díl, proto je otočení vidět.
    north = np.abs(np.arctan2(np.sin(ang + math.pi / 2.0), np.cos(ang + math.pi / 2.0)))
    hatch = ring & (north < 0.30) & (dist > inner + m(0.38)) & (dist < outer - m(0.38))
    mask.fill(hatch, BRASS, 0.78 + 0.10 * grain)
    hatch_rim = hatch & (
        (north > 0.24)
        | (dist < inner + m(0.50))
        | (dist > outer - m(0.50))
    )
    mask.fill(hatch_rim, LIP, 0.42)
    knob = (x * x + (y + m((RING_IN + RING_OUT) * 0.5)) ** 2) < m(0.16) ** 2
    mask.fill(ring & knob, BRASS, 0.96)

    paint_rivets(mask, x, y, ring)
    return mask


def paint_rivets(mask: Mask, x: np.ndarray, y: np.ndarray, ring: np.ndarray) -> None:
    rivet = np.zeros(x.shape, dtype=bool)
    radius = m((RING_IN + RING_OUT) * 0.5)
    # Severní díl má poklop, nýty tam nepřekrývají mosaz.
    for i in range(16):
        ang = (i + 0.5) * math.pi / 8.0
        north = (ang + math.pi / 2.0 + math.pi) % math.tau - math.pi
        if abs(north) < 0.42:
            continue
        px = math.cos(ang) * radius
        py = math.sin(ang) * radius
        rivet |= (x - px) ** 2 + (y - py) ** 2 < m(0.065) ** 2
    mask.fill(ring & rivet, LIP, 0.72)


def crop_square(image: Image.Image, pad: int = 4) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image
    width, height = image.size
    left, top, right, bottom = bbox
    cx, cy = width / 2.0, height / 2.0
    half = max(cx - left, right - cx, cy - top, bottom - cy)
    new_half = int(math.ceil(half - 1e-6)) + pad
    new_size = max(2, new_half * 2)
    if new_size >= width:
        return image
    left = (width - new_size) // 2
    top = (height - new_size) // 2
    return image.crop((left, top, left + new_size, top + new_size))


def paste_center(canvas: Image.Image, sprite: Image.Image, offset: tuple[int, int] = (0, 0)) -> None:
    x = (canvas.width - sprite.width) // 2 + offset[0]
    y = (canvas.height - sprite.height) // 2 + offset[1]
    canvas.alpha_composite(sprite, (x, y))


def ground_shadow(base: Image.Image) -> Image.Image:
    alpha = base.getchannel("A").point(lambda value: 78 if value > 16 else 0)
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=7))
    image = Image.new("RGBA", base.size, (0, 0, 0, 255))
    image.putalpha(alpha)
    return image


def compose(base: Image.Image, ring: Image.Image, shift: tuple[int, int]) -> Image.Image:
    pad = max(abs(shift[0]), abs(shift[1])) + 4
    side = max(base.width, ring.width) + pad * 2
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    paste_center(image, ground_shadow(base))
    paste_center(image, base)
    paste_center(image, ring, shift)
    return image


def trim(image: Image.Image, pad: int = 12) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image
    left, top, right, bottom = bbox
    return image.crop(
        (
            max(0, left - pad),
            max(0, top - pad),
            min(image.width, right + pad),
            min(image.height, bottom + pad),
        )
    )


def fit(image: Image.Image, side: int) -> Image.Image:
    scale = side / max(image.size)
    resized = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    return resized


def save_sheet(items: list[tuple[Image.Image, str]], columns: int, path: Path) -> None:
    gap, caption = 16, 28
    slot_w = max(image.width for image, _label in items)
    slot_h = max(image.height for image, _label in items)
    rows = math.ceil(len(items) / columns)
    sheet = Image.new(
        "RGB",
        (columns * slot_w + (columns + 1) * gap, rows * (slot_h + caption) + (rows + 1) * gap),
        (0x4F, 0x9A, 0x3C),
    )
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)
    for index, (image, label) in enumerate(items):
        col, row = index % columns, index // columns
        x = gap + col * (slot_w + gap)
        y = gap + row * (slot_h + caption + gap)
        draw.text((x, y), label, fill=(24, 32, 18), font=font)
        ox = x + (slot_w - image.width) // 2
        oy = y + caption + (slot_h - image.height) // 2
        sheet.paste(on_grass(image), (ox, oy))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def on_checker(image: Image.Image, cell: int = 12) -> Image.Image:
    bg = Image.new("RGBA", image.size)
    draw = ImageDraw.Draw(bg)
    light, dark = (68, 68, 74, 255), (42, 42, 48, 255)
    width, height = image.size
    for top in range(0, height, cell):
        for left in range(0, width, cell):
            fill = light if (left // cell + top // cell) % 2 == 0 else dark
            draw.rectangle((left, top, left + cell, top + cell), fill=fill)
    bg.alpha_composite(image)
    return bg.convert("RGB")


def save_masks(base: Image.Image, ring: Image.Image, path: Path) -> None:
    items = ((base, "base.png  R podlaha  G kov  B sklad"), (ring, "ring.png  R pláty  G mosaz  B lem"))
    gap, caption = 16, 28
    slot = max(base.width, ring.width)
    sheet = Image.new("RGB", (2 * slot + 3 * gap, slot + caption + 2 * gap), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)
    for index, (image, label) in enumerate(items):
        x = gap + index * (slot + gap)
        draw.text((x, gap), label, fill=(230, 226, 214), font=font)
        ox = x + (slot - image.width) // 2
        oy = gap + caption + (slot - image.height) // 2
        sheet.paste(on_checker(image), (ox, oy))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def check(base: Image.Image, ring: Image.Image) -> None:
    base_px = np.asarray(base)
    ring_px = np.asarray(ring)
    if base_px.shape != ring_px.shape:
        raise SystemExit("spodek a mezikruží nemají stejný rozměr")
    h, w = base_px.shape[:2]
    cy, cx = h // 2, w // 2
    if ring_px[cy, cx, 3] > 8:
        raise SystemExit("střed mezikruží není průhledný")
    if base_px[cy, cx, 3] < 200:
        raise SystemExit("uprostřed chybí sklad")
    # Jižní koridor mezi kolem a hranou je volná podlaha. Pásy jsou na ostatních sedmi.
    y0 = cy + int(m(RING_OUT)) + 6
    y1 = cy + int(m(FLAT)) - int(m(0.45))
    south = base_px[y0:y1, cx - 8 : cx + 8]
    if south.size == 0 or int((south[..., 1] > 40).sum()) > 12:
        raise SystemExit("na jižní hraně je dopravník, má tam být volná podlaha")
    x0 = cx + int(m(RING_OUT)) + 6
    x1 = cx + int(m(FLAT)) - int(m(0.45))
    east = base_px[cy - 8 : cy + 8, x0:x1]
    if int((east[..., 1] > 40).sum()) < 40:
        raise SystemExit("chybí východní dopravník")
    yard = base_px[cy - 20 : cy - 10, cx + 10 : cx + 20]
    if int((yard[..., 2] > 80).sum()) < 20:
        raise SystemExit("sklad není ve vlastním kanálu")
    # Poklop (mosaz) leží nad středem a po otočení se pohne.
    brass = np.argwhere((ring_px[..., 1] > 40) & (ring_px[..., 3] > 180))
    if len(brass) < 30:
        raise SystemExit("chybí poklop, podle kterého bude vidět otočení")
    hatch_y = float(brass[:, 0].mean())
    if hatch_y >= cy:
        raise SystemExit("poklop není na severní straně")
    turned = ring.rotate(28, resample=Image.Resampling.BICUBIC)
    turned_px = np.asarray(turned)
    if turned_px[cy, cx, 3] > 12:
        raise SystemExit("po otočení se střed mezikruží zavřel")
    moved = np.argwhere((turned_px[..., 1] > 40) & (turned_px[..., 3] > 180))
    if len(moved) < 30 or float(moved[:, 0].mean()) <= hatch_y + 4:
        raise SystemExit("poklop se s vrstvou neotáčí")
    # Díra zůstane nad skladem i když je záběr uprostřed.
    hidden_yard = (base_px[..., 3] > 200) & (base_px[..., 2] > 80) & (ring_px[..., 3] > 200)
    open_yard = (base_px[..., 3] > 200) & (base_px[..., 2] > 80) & (ring_px[..., 3] < 16)
    if int(open_yard.sum()) < 400:
        raise SystemExit("sklad není vidět skrz díru")
    if int(hidden_yard.sum()) > int(open_yard.sum()):
        raise SystemExit("mezikruží zakrývá většinu skladu")


def write_info(base: Image.Image, ring: Image.Image) -> Path:
    catalog = {
        "px_per_meter": PX,
        "height_unit": "m",
        "wired_into_godot": False,
        "flat_to_flat_m": round(real(FLAT) * 2.0, 3),
        "vertex_to_vertex_m": round(real(FLAT) * 2.0 / math.cos(math.pi / 8), 3),
        "dock_edge": "south",
        "dock_m": round(real(DOCK), 3),
        "conveyors": {"count": 7, "animated": False},
        "layers": {
            "base": {
                "file": "base.png",
                "height": 0.0,
                "channels": ["floor", "metal", "yard"],
                "cell": base.width,
                "center": base.width // 2,
            },
            "ring": {
                "file": "ring.png",
                "height": round(real(RING_H), 3),
                "channels": ["plate", "brass", "lip"],
                "center_clear": True,
                "cell": ring.width,
                "center": ring.width // 2,
            },
        },
    }
    path = OUT_DIR / "tovarna.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def main() -> None:
    x, y = grids(cell_for())
    base = crop_square(pack_mask(paint_base(x, y)))
    ring = crop_square(pack_mask(paint_ring(x, y)))
    # Oba snímky musí sdílet střed otáčení. Ořez bere vzdálenost od středu,
    # takže osmiúhelník i díra zůstanou uprostřed i s výstupkem na jihu.
    side = max(base.width, ring.width)
    if base.size != (side, side):
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        paste_center(canvas, base)
        base = canvas
    if ring.size != (side, side):
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        paste_center(canvas, ring)
        ring = canvas
    check(base, ring)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    base_path, ring_path = OUT_DIR / "base.png", OUT_DIR / "ring.png"
    base.save(base_path)
    ring.save(ring_path)

    painted_base = colorize(base, TINTS_BASE)
    painted_ring = colorize(ring, TINTS_RING)
    turned = colorize(ring.rotate(28, resample=Image.Resampling.BICUBIC), TINTS_RING)
    shift = (round(EDGE[0] * real(RING_H)), round(EDGE[1] * real(RING_H)))
    together = trim(compose(painted_base, painted_ring, (0, 0)))
    rotated = trim(compose(painted_base, turned, (0, 0)))
    edge = trim(compose(painted_base, painted_ring, shift))
    tile = 460
    save_sheet(
        [
            (fit(trim(painted_base), tile), "spodek"),
            (fit(trim(painted_ring), tile), "mezikruží"),
            (fit(together, tile), "spolu · 6 m"),
            (fit(rotated, tile), "otočené o 28°"),
            (fit(edge, tile), "u kraje"),
        ],
        3,
        PREVIEW / "tovarna.png",
    )
    save_masks(base, ring, PREVIEW / "tovarna_masky.png")
    info = write_info(base, ring)
    print(f"spodek {base.width} px, mezikruží {ring.width} px, výška {real(RING_H):.2f} m")
    print(f"přes plochy {real(FLAT) * 2:.1f} m, výstupek {real(DOCK):.2f} m na jih")
    print(PREVIEW / "tovarna.png")
    print(PREVIEW / "tovarna_masky.png")
    print(info)


if __name__ == "__main__":
    main()
