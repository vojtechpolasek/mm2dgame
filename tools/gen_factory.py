#!/usr/bin/env python3
"""Továrna z pohledu shora. Ve hře stojí uprostřed mapy místo kotliny.

64 px je 1 m. Kreslí se ve čtyřnásobném rozlišení a složí se do masky,
stejně jako domečky. Osmiúhelník je přes plochy široký jako kotlina,
tedy 6 m. Výstupek z jižní hrany přesahuje.

Spodek (0 m):
  kamenná dlažba v osmiúhelníku se zvlněnou zídkou a železným kováním
  v rozích, sedm dopravníků od hran ke středu s hnacím válcem a patkami,
  poklopy mezi pásy, čtvercový výstupek na jižní hraně (tam ve hře
  vyjedou krabičky) a uprostřed štěrková plocha na materiál s litinovou
  mříží. Příčky pásů v masce pro hru nejsou, kreslí je factory_layer.gdshader
  a posouvá je, když po pásu jede kámen. Náhled je má namalované.

Pro typ hry Skafandry je druhý spodek, base_suits.png: místo jednoho pásu
na každé straně dva užší zásobníky vedle sebe a středem výstupku vede ke kolu
pás na skafandry. Zbytek je stejný.

Mezikruží (výška RING_H): samostatná vrstva, střed je průhledný,
takže sklad pod ním zůstane vidět. Obrázek je vystředěný na osu,
kolem které se vrstva ve hře otočí. Nýtované pláty s rzí, ozubený
věnec a větrací mřížky. Jeden díl má mosazný poklop, aby otočení
bylo poznat.

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

from gen_houses import SHADE, SHADE_FLOOR, SHEEN, colorize, fbm, hash01, load_font, organic, smoothstep, stone_shade
from gen_trees import on_grass

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "objects" / "factory"
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
BELT_RAIL = 0.09
BELT_PITCH = 0.36
BELT_SLAT = 0.07
BELT_SHADE = 0.36
SLAT_SHADE = 0.84
DRUM_IN = 0.62
DRUM_HALF = 0.13
# Spodek pro typ hry Skafandry: na každé straně dva užší zásobníky vedle sebe.
# LANE_OFFSET je vzdálenost osy zásobníku od osy strany, LANE_HALF jeho poloviční šířka.
LANE_OFFSET = 0.73
LANE_HALF = 0.44
# Výstupkem vede ke kolu pás na skafandry, stejně úzký jako zásobníky. Končí DOCK_BELT_END
# před koncem výstupku, tam má válec.
DOCK_BELT_END = 0.3
SCALE = 6.0 / (FLAT * 2.0)

FLOOR, METAL, YARD_CH = 0, 1, 2
PLATE, BRASS, LIP = 0, 1, 2

# Jižní hrana je ta s výstupkem. Normály ploch jdou po 45°, jih je π/2.
SOUTH = 2

TINTS_BASE = (
    (176, 164, 140),  # podlaha
    (102, 106, 112),  # kov
    (134, 116, 88),  # sklad, středně tmavý: prach světlých i tmavých materiálů je na něm vidět
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


def blend(mask: Mask, where: np.ndarray, channel: int, amount: np.ndarray) -> None:
    """Přimíchá druhý materiál, třeba rez do plechu. Krytí a světlost zůstanou."""
    amount = np.clip(amount, 0.0, 1.0)
    keep = 1.0 - amount
    mask.ch[:, where] *= keep[where]
    mask.ch[channel, where] += amount[where]


def disc(x: np.ndarray, y: np.ndarray, cx: float, cy: float, radius: float) -> np.ndarray:
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius


def paint_base(x0: np.ndarray, y0: np.ndarray, slats: bool, lanes: int = 1) -> Mask:
    cell = int(round((x0.shape[1] / SS)))
    mask = Mask(cell)
    ap = m(FLAT)
    # Zděný obvod se vlní, stroje uvnitř drží rovné souřadnice x0, y0.
    x, y = organic(x0, y0, 401, 0.0, m(0.07))
    inside, edge = octagon(x, y, ap)
    flags = stone_shade(x, y, m(0.62), 403)
    weather = 0.84 + 0.24 * fbm(x, y, m(2.2), 405)
    mask.fill(inside, FLOOR, flags * weather * (1.0 - 0.2 * smoothstep(m(0.6), 0.0, edge)))

    # Obvodová zídka z větších kamenů, nahoře světlejší.
    curb = inside & (edge < m(0.34))
    blocks = stone_shade(x, y, m(0.36), 407, (1.3, 1.3))
    mask.fill(curb, FLOOR, blocks * (0.72 + 0.3 * smoothstep(0.0, m(0.2), edge)))
    paint_brackets(mask, x0, y0, inside, edge)

    dist0 = np.hypot(x0, y0)
    yard = dist0 <= m(YARD)
    gravel = stone_shade(x0, y0, m(0.16), 409)
    earth = 0.62 + 0.26 * fbm(x0, y0, m(0.9), 411)
    mask.fill(yard, YARD_CH, (0.55 * earth + 0.45 * gravel) * (1.0 - 0.2 * smoothstep(m(YARD - 0.3), m(YARD), dist0)))
    edging = yard & (dist0 >= m(YARD - 0.16))
    mask.fill(edging, FLOOR, stone_shade(x0, y0, m(0.22), 413) * 0.82)
    paint_drain(mask, x0, y0)

    paint_manholes(mask, x0, y0, inside)
    paint_belts(mask, x0, y0, inside, slats, lanes)
    paint_dock(mask, x0, y0, x, y)
    if lanes == 2:
        paint_dock_belt(mask, x0, y0, slats)
    return mask


def paint_brackets(mask: Mask, x: np.ndarray, y: np.ndarray, inside: np.ndarray, edge: np.ndarray) -> None:
    """Železné kování v rozích zídky. Drží ji pohromadě a je to první technický znak."""
    reach = m(FLAT) / math.cos(math.pi / 8.0)
    for k in range(8):
        ang = (k + 0.5) * math.pi / 4.0
        vx, vy = math.cos(ang) * reach, math.sin(ang) * reach
        plate = inside & (edge < m(0.36)) & disc(x, y, vx, vy, m(0.5))
        mask.fill(plate, METAL, 0.6)
        for step in (0.2, 0.38):
            bx, by = math.cos(ang) * (reach - m(step) * 1.4), math.sin(ang) * (reach - m(step) * 1.4)
            for turn in (-1.0, 1.0):
                tx, ty = -math.sin(ang) * turn * m(0.16), math.cos(ang) * turn * m(0.16)
                mask.fill(plate & disc(x, y, bx + tx, by + ty, m(0.05)), METAL, 0.92)


def paint_drain(mask: Mask, x: np.ndarray, y: np.ndarray) -> None:
    """Litinová mříž uprostřed skladu. Ukazuje střed, který se neotáčí."""
    dist = np.hypot(x, y)
    cover = dist <= m(0.36)
    mask.fill(cover, METAL, 0.5)
    slot = cover & (dist > m(0.1)) & (dist < m(0.3)) & (np.mod(np.arctan2(y, x) * 8.0 / math.pi, 1.0) < 0.42)
    mask.fill(slot, METAL, 0.26)
    mask.fill(cover & (dist >= m(0.3)), METAL, 0.78)
    mask.fill(dist <= m(0.07), METAL, 0.86)


def paint_manholes(mask: Mask, x: np.ndarray, y: np.ndarray, inside: np.ndarray) -> None:
    """Poklopy mezi pásy, do podzemí továrny."""
    radius = m((RING_OUT + FLAT) * 0.5 + 0.1)
    for k in range(8):
        ang = (k + 0.5) * math.pi / 4.0
        cx, cy = math.cos(ang) * radius, math.sin(ang) * radius
        lid = inside & disc(x, y, cx, cy, m(0.34))
        mask.fill(lid, METAL, 0.54)
        mask.fill(lid & ~disc(x, y, cx, cy, m(0.27)), METAL, 0.76)
        groove = lid & disc(x, y, cx, cy, m(0.22)) & (
            (np.abs((x - cx) * math.cos(ang) + (y - cy) * math.sin(ang)) < m(0.025))
            | (np.abs(-(x - cx) * math.sin(ang) + (y - cy) * math.cos(ang)) < m(0.025))
        )
        mask.fill(groove, METAL, 0.3)


def belt_span() -> tuple[float, float]:
    """Pás od kola k hraně, vzdálenost od středu v px. Kolo pás zakryje."""
    return m(RING_OUT) - m(0.18), m(FLAT) + m(0.2)


def lane_offsets(lanes: int) -> list[float]:
    """Posuny os pásů od osy strany v px. Jeden pás jde středem, dva vedle sebe."""
    return [0.0] if lanes == 1 else [-m(LANE_OFFSET), m(LANE_OFFSET)]


def paint_belts(mask: Mask, x: np.ndarray, y: np.ndarray, inside: np.ndarray, slats: bool, lanes: int = 1) -> None:
    """Pásy od ploché hrany ke kolu, na každé straně jeden nebo dva. Jižní hrana má místo
    pásu výstupek."""
    for offset in lane_offsets(lanes):
        paint_lanes(mask, x, y, inside, slats, offset, m(BELT_HALF) if lanes == 1 else m(LANE_HALF))


def paint_lanes(mask: Mask, x: np.ndarray, y: np.ndarray, inside: np.ndarray, slats: bool, offset: float, half: float) -> None:
    """Pás posunutý o offset px od osy každé strany."""
    rail = m(BELT_RAIL)
    inner, outer = belt_span()
    pitch = m(BELT_PITCH)
    slat_w = m(BELT_SLAT)
    dirt = 0.82 + 0.26 * fbm(x, y, m(0.8), 421)
    for k in range(8):
        if k == SOUTH:
            continue
        ang = k * math.pi / 4.0
        nx, ny = math.cos(ang), math.sin(ang)
        along = x * nx + y * ny
        side = -x * ny + y * nx - offset
        span = inside & (along >= inner) & (along <= outer)
        # Patky stojanu vedle pásu, po délce v pravidelném kroku.
        foot = span & (np.abs(side) > half) & (np.abs(side) <= half + m(0.12)) & (np.mod(along, m(0.9)) < m(0.16))
        mask.fill(foot, METAL, 0.62)
        belt = span & (np.abs(side) <= half)
        center = span & (np.abs(side) <= half - rail)
        rails = belt & ~center
        mask.fill(belt, METAL, BELT_SHADE * dirt)
        rail_light = 0.62 + 0.3 * smoothstep(0.0, rail * 0.6, half - np.abs(side))
        mask.fill(rails, METAL, rail_light)
        if slats:
            slat = center & (np.mod(along, pitch) < slat_w)
            mask.fill(slat, METAL, SLAT_SHADE * dirt)
        # Hnací válec u vnějšího konce, oblý: uprostřed světlý.
        drum_at = m(FLAT) - m(DRUM_IN)
        drum = center & (np.abs(along - drum_at) <= m(DRUM_HALF))
        mask.fill(drum, METAL, 0.5 + 0.45 * (1.0 - np.abs(along - drum_at) / m(DRUM_HALF)))
        bolt = span & (np.abs(np.abs(side) - (half - rail * 0.5)) < m(0.04)) & (np.abs(along - drum_at) < m(0.04))
        mask.fill(bolt, METAL, 0.98)


def dock_belt_span() -> tuple[float, float, float]:
    """Pás výstupkem: od kola, konec a válec, vzdálenost od středu v px."""
    inner, _outer = belt_span()
    end = m(FLAT) + m(DOCK) - m(DOCK_BELT_END)
    return inner, end, end - m(DRUM_IN) * 0.6


def paint_dock_belt(mask: Mask, x: np.ndarray, y: np.ndarray, slats: bool) -> None:
    """Pás středem výstupku ke kolu, jih je +y. Po něm jedou kameny na skafandr."""
    half = m(LANE_HALF)
    rail = m(BELT_RAIL)
    inner, end, drum_at = dock_belt_span()
    dirt = 0.82 + 0.26 * fbm(x, y, m(0.8), 423)
    along = y
    side = x
    span = (along >= inner) & (along <= end)
    belt = span & (np.abs(side) <= half)
    center = span & (np.abs(side) <= half - rail)
    mask.fill(belt, METAL, BELT_SHADE * dirt)
    mask.fill(belt & ~center, METAL, 0.62 + 0.3 * smoothstep(0.0, rail * 0.6, half - np.abs(side)))
    if slats:
        mask.fill(center & (np.mod(along, m(BELT_PITCH)) < m(BELT_SLAT)), METAL, SLAT_SHADE * dirt)
    drum = center & (np.abs(along - drum_at) <= m(DRUM_HALF))
    mask.fill(drum, METAL, 0.5 + 0.45 * (1.0 - np.abs(along - drum_at) / m(DRUM_HALF)))
    # Čelo pásu na konci výstupku.
    mask.fill((np.abs(side) <= half) & (along > end) & (along <= end + m(0.08)), METAL, 0.7)


def paint_dock(mask: Mask, x: np.ndarray, y: np.ndarray, wx: np.ndarray, wy: np.ndarray) -> None:
    ap = m(FLAT)
    side = m(DOCK)
    overlap = m(0.3)
    dock = (np.abs(wx) <= side / 2.0) & (wy >= ap - overlap) & (wy <= ap + side)
    mask.fill(dock, FLOOR, stone_shade(wx, wy, m(0.4), 431, (1.2, 1.2)) * 0.92)
    plate = (np.abs(x) <= side / 2.0 - m(0.38)) & (y >= ap + m(0.3)) & (y <= ap + side - m(0.38))
    frame = (np.abs(x) <= side / 2.0 - m(0.26)) & (y >= ap + m(0.18)) & (y <= ap + side - m(0.26))
    mask.fill(frame, METAL, 0.66)
    # Výdejní deska z prken, kudy krabička vyjede.
    plank = np.mod(x / m(0.32), 1.0)
    grain = hash01(np.floor(x / m(0.32)), np.floor(y / m(0.08)), 433)
    mask.fill(plate, YARD_CH, (0.78 + 0.14 * grain) * np.where(plank < 0.08, 0.6, 1.0))
    roller_zone = plate & (y > ap + side - m(1.05))
    phase = np.mod(y / m(0.3), 1.0)
    roller = roller_zone & (phase < 0.45)
    mask.fill(roller, METAL, 0.45 + 0.5 * np.sin(phase / 0.45 * math.pi))
    for sx in (-1.0, 1.0):
        bolt = disc(x, y, sx * (side / 2.0 - m(0.32)), ap + m(0.24), m(0.05))
        bolt |= disc(x, y, sx * (side / 2.0 - m(0.32)), ap + side - m(0.32), m(0.05))
        mask.fill(bolt, METAL, 0.95)


def paint_ring(x: np.ndarray, y: np.ndarray) -> Mask:
    cell = int(round(x.shape[1] / SS))
    mask = Mask(cell)
    n = x.shape[0]
    dist = np.hypot(x, y)
    outer, inner = m(RING_OUT), m(RING_IN)
    ang = np.arctan2(y, x)
    teeth = 44
    tooth_phase = np.mod(ang * teeth / math.tau, 1.0)
    tooth_w = np.abs(tooth_phase - 0.5) * 2.0
    tooth_top = outer + m(0.17) * np.clip(1.6 - 1.6 * tooth_w, 0.0, 1.0)
    gear = (dist > outer) & (dist <= tooth_top) & (tooth_w < 0.82)
    ring = (dist <= outer) & (dist >= inner)
    grain = noise(n, 29, 5)
    t = np.clip((dist - inner) / (outer - inner), 0.0, 1.0)
    # Spáry míří do rohů osmiúhelníku, díly sedí nad plochými stranami.
    # Severní poklop je pak uprostřed dílu a spára jím nevede.
    sector = math.pi / 4.0
    aligned = ang - math.pi / 8.0
    sector_i = np.floor(np.mod(aligned + math.pi, math.tau) / sector)
    alt = (hash01(sector_i, np.zeros_like(sector_i), 31) - 0.5) * 0.12
    seam_ang = np.minimum(np.mod(aligned, sector), sector - np.mod(aligned, sector))
    seam_px = seam_ang * np.maximum(dist, 1.0)
    # Plát je vyboulený: u spár a lemů tmavší, uprostřed světlejší.
    bulge = smoothstep(0.0, m(0.4), np.minimum(seam_px, np.minimum(dist - inner, outer - dist)))
    shade = np.clip((0.46 + 0.26 * t + 0.06 * grain + alt) * (0.82 + 0.22 * bulge), 0.0, 1.0)
    mask.fill(ring, PLATE, shade)
    mask.fill(gear, LIP, 0.56 + 0.3 * (1.0 - tooth_w))
    # Rez a ošoupání, ne všude stejně.
    rust = smoothstep(0.55, 0.85, fbm(x, y, m(0.9), 33)) * 0.55
    blend(mask, ring, LIP, rust)

    mask.fill(ring & (seam_px < m(0.05)), LIP, 0.3)
    lip_w = m(0.14)
    inner_lip = ring & (dist <= inner + lip_w)
    mask.fill(inner_lip, LIP, 0.38 + 0.4 * np.sin(np.clip((dist - inner) / lip_w, 0.0, 1.0) * math.pi))
    outer_lip = ring & (dist >= outer - lip_w)
    mask.fill(outer_lip, LIP, 0.42 + 0.36 * np.sin(np.clip((outer - dist) / lip_w, 0.0, 1.0) * math.pi))

    north = np.abs(np.arctan2(np.sin(ang + math.pi / 2.0), np.cos(ang + math.pi / 2.0)))
    paint_vents(mask, x, y, ring, dist, ang)
    # Poklop na severu. Jediný takový díl, proto je otočení vidět.
    hatch = ring & (north < 0.30) & (dist > inner + m(0.38)) & (dist < outer - m(0.38))
    mask.fill(hatch, BRASS, 0.78 + 0.10 * grain)
    hatch_rim = hatch & (
        (north > 0.24)
        | (dist < inner + m(0.50))
        | (dist > outer - m(0.50))
    )
    mask.fill(hatch_rim, LIP, 0.42)
    mid = m((RING_IN + RING_OUT) * 0.5)
    hinge = ring & (np.abs(x) <= m(0.36)) & (np.abs(y + inner + m(0.33)) <= m(0.05))
    mask.fill(hinge, LIP, 0.7)
    knob = disc(x, y, 0.0, -mid - m(0.18), m(0.12))
    mask.fill(ring & knob, BRASS, 0.96)

    paint_rivets(mask, x, y, ring, dist, aligned)
    return mask


def paint_vents(mask: Mask, x: np.ndarray, y: np.ndarray, ring: np.ndarray, dist: np.ndarray, ang: np.ndarray) -> None:
    """Dvě mřížky větrání. Jsou na jih a na jihovýchod, poklop drží sever sám."""
    mid = m((RING_IN + RING_OUT) * 0.5)
    for turn in (math.pi / 2.0, math.pi / 4.0 - 0.1):
        local = np.arctan2(np.sin(ang - turn), np.cos(ang - turn))
        arc = local * dist
        box = ring & (np.abs(arc) <= m(0.42)) & (np.abs(dist - mid) <= m(0.26))
        mask.fill(box, LIP, 0.34)
        slat = box & (np.mod((dist - mid) / m(0.11), 1.0) < 0.45) & (np.abs(arc) <= m(0.36))
        mask.fill(slat, PLATE, 0.7)


def paint_rivets(
    mask: Mask, x: np.ndarray, y: np.ndarray, ring: np.ndarray, dist: np.ndarray, aligned: np.ndarray
) -> None:
    """Nýty v řadách podél spár a obou lemů."""
    inner, outer = m(RING_IN), m(RING_OUT)
    sector = math.pi / 4.0
    local = np.mod(aligned, sector)
    near = np.minimum(local, sector - local) * np.maximum(dist, 1.0)
    pitch = m(0.28)
    head = m(0.05)
    radial = np.mod(dist - inner, pitch) - pitch * 0.5
    seam_row = (np.abs(near - m(0.13)) <= head) & (np.abs(radial) <= head)
    seam_row &= (dist > inner + m(0.24)) & (dist < outer - m(0.24))
    circ_pitch = m(0.34) / np.maximum(dist, 1.0)
    around = np.mod(aligned, circ_pitch) - circ_pitch * 0.5
    arc_off = around * dist
    lip_row = np.zeros_like(ring)
    for at in (inner + m(0.25), outer - m(0.25)):
        lip_row |= (np.abs(dist - at) <= head) & (np.abs(arc_off) <= head)
    rivet = ring & (seam_row | lip_row) & (mask.ch[1] < 0.5)
    mask.fill(rivet, LIP, 0.8)


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


def hex_of(color: tuple[int, int, int]) -> str:
    return "%02X%02X%02X" % color


def write_info(base: Image.Image, ring: Image.Image, suits: Image.Image) -> Path:
    """Míry jsou v px od středu obrázku, jih (+y) je výstupek. Hra z nich staví
    neprůchodný půdorys, dráhu kamene po pásu a příčky pásů ve shaderu."""
    inner, outer = belt_span()
    catalog = {
        "px_per_meter": PX,
        "height_unit": "m",
        "shader": "res://shaders/factory_layer.gdshader",
        "flat_to_flat_m": round(real(FLAT) * 2.0, 3),
        "vertex_to_vertex_m": round(real(FLAT) * 2.0 / math.cos(math.pi / 8), 3),
        "dock_edge": "south",
        "dock_m": round(real(DOCK), 3),
        "apothem_px": round(m(FLAT), 2),
        "dock_px": {"half": round(m(DOCK) / 2.0, 2), "from": round(m(FLAT) - m(0.3), 2), "to": round(m(FLAT) + m(DOCK), 2)},
        "yard_px": round(m(YARD), 2),
        "ring_px": {"inner": round(m(RING_IN), 2), "outer": round(m(RING_OUT), 2), "teeth": round(m(RING_OUT + 0.17), 2)},
        "conveyors": {
            "count": 7,
            "angles": [k for k in range(8) if k != SOUTH],
            "step_deg": 45,
            "inner_px": round(inner, 2),
            "outer_px": round(outer, 2),
            "half_px": round(m(BELT_HALF), 2),
            "rail_px": round(m(BELT_RAIL), 2),
            "pitch_px": round(m(BELT_PITCH), 2),
            "slat_px": round(m(BELT_SLAT), 2),
            "slat_gain": round(SLAT_SHADE / BELT_SHADE, 4),
            "drum_px": round(m(FLAT) - m(DRUM_IN), 2),
            "drum_half_px": round(m(DRUM_HALF), 2),
        },
        "suits": {
            "file": "base_suits.png",
            "lane_offset_px": round(m(LANE_OFFSET), 2),
            "lane_half_px": round(m(LANE_HALF), 2),
            "dock_belt": {
                "outer_px": round(dock_belt_span()[1], 2),
                "drum_px": round(dock_belt_span()[2], 2),
            },
            "cell": suits.width,
        },
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
                "center": base.width // 2,
            },
            "ring": {
                "file": "ring.png",
                "height": round(real(RING_H), 3),
                "channels": ["plate", "brass", "lip"],
                "colors": [hex_of(tint) for tint in TINTS_RING],
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
    base = crop_square(pack_mask(paint_base(x, y, slats=False)))
    shown = crop_square(pack_mask(paint_base(x, y, slats=True)))
    suits = crop_square(pack_mask(paint_base(x, y, slats=False, lanes=2)))
    suits_shown = crop_square(pack_mask(paint_base(x, y, slats=True, lanes=2)))
    ring = crop_square(pack_mask(paint_ring(x, y)))
    # Oba snímky musí sdílet střed otáčení. Ořez bere vzdálenost od středu,
    # takže osmiúhelník i díra zůstanou uprostřed i s výstupkem na jihu.
    side = max(base.width, ring.width)

    def padded(image: Image.Image) -> Image.Image:
        if image.size == (side, side):
            return image
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        paste_center(canvas, image)
        return canvas

    base, shown, ring = padded(base), padded(shown), padded(ring)
    suits, suits_shown = padded(suits), padded(suits_shown)
    check(base, ring)
    if suits.size != base.size:
        raise SystemExit("spodek se zásobníky nemá stejný rozměr jako spodek")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    base_path, ring_path = OUT_DIR / "base.png", OUT_DIR / "ring.png"
    base.save(base_path)
    ring.save(ring_path)
    suits.save(OUT_DIR / "base_suits.png")

    painted_base = colorize(shown, TINTS_BASE)
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
    painted_suits = colorize(suits_shown, TINTS_BASE)
    save_sheet(
        [
            (fit(trim(painted_suits), tile), "spodek se zásobníky"),
            (fit(trim(compose(painted_suits, painted_ring, (0, 0))), tile), "Skafandry · spolu"),
        ],
        2,
        PREVIEW / "tovarna_skafandry.png",
    )
    info = write_info(base, ring, suits)
    print(f"spodek {base.width} px, mezikruží {ring.width} px, výška {real(RING_H):.2f} m")
    print(f"přes plochy {real(FLAT) * 2:.1f} m, výstupek {real(DOCK):.2f} m na jih")
    print(PREVIEW / "tovarna.png")
    print(PREVIEW / "tovarna_masky.png")
    print(info)


if __name__ == "__main__":
    main()
