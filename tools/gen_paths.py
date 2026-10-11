#!/usr/bin/env python3
"""Vzory cest pro pohled shora. Zatím jen grafika, do Godotu se nezapojí.

Vzor je pás cesty. Šířka obrázku jde napříč cestou, výška po délce.
Po délce na sebe vzor navazuje, takže se dá klást dokola podél křivky
libovolně dlouhé cesty. Napříč je uprostřed plná cesta a k oběma krajům
se třepí do průhledna, tam prosvitne tráva pod ní.

Ve hře se pás natočí po směru křivky a zapeče do textury chunku.
Náhled to tak předvádí: cesta přes body A, B, C a D a druhá cesta,
která ji kříží, položené na trávu ze hry. V křížení vyhrává cesta,
ke které má pixel blíž, takže se pásy slijí a obruba nepřejede přes střed.

  pesina  ušlapaná hlína, bez směru
  sterk   drobné kamení, bez směru, kraj se rozsype do trávy
  dlazba  kameny v řadách napříč, obruba podél, jede se zatáčkou

64 px je 1 m.

  py tools/gen_paths.py
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from gen_houses import hash01, load_font, smoothstep

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "tools" / "out" / "paths"
PREVIEW = ROOT / "tools" / "preview"
GRASS_ATLAS = ROOT / "godot" / "graphics" / "terrain" / "grass" / "atlas.png"

PX = 64
SS = 4
# Napříč 2,5 m, z toho plná cesta 1,8 m a zbytek je roztřepený kraj.
# Po délce 4 m, pak se vzor opakuje. Měřítka šumu jsou dělitelé délky,
# jinak by vzor na konci nenavázal.
ACROSS = 160
ALONG = 256
CORE = 1.8


@dataclass(frozen=True)
class Pattern:
    name: str
    label: str
    directional: bool


PATTERNS = (
    Pattern("pesina", "pěšina", False),
    Pattern("sterk", "štěrk", False),
    Pattern("dlazba", "dlažba", True),
)


def grid() -> tuple[np.ndarray, np.ndarray]:
    """u napříč (0..ACROSS), v po délce (0..ALONG), v pixelech výsledku."""
    u = (np.arange(ACROSS * SS, dtype=np.float32) + 0.5) / SS
    v = (np.arange(ALONG * SS, dtype=np.float32) + 0.5) / SS
    return np.meshgrid(u, v)


def wrap_noise(u: np.ndarray, v: np.ndarray, scale: float, salt: int) -> np.ndarray:
    """Hladký šum 0..1, po délce navazuje s periodou ALONG."""
    period = int(round(ALONG / scale))
    gu, gv = u / scale, v / scale
    iu, iv = np.floor(gu), np.floor(gv)
    fu, fv = gu - iu, gv - iv
    fu = fu * fu * (3.0 - 2.0 * fu)
    fv = fv * fv * (3.0 - 2.0 * fv)
    v0 = np.mod(iv, period)
    v1 = np.mod(iv + 1, period)
    a = hash01(iu, v0, salt)
    b = hash01(iu + 1, v0, salt)
    c = hash01(iu, v1, salt)
    d = hash01(iu + 1, v1, salt)
    return (a + (b - a) * fu + (c - a) * fv + (a - b - c + d) * fu * fv).astype(np.float32)


def wrap_fbm(u: np.ndarray, v: np.ndarray, scale: float, salt: int, octaves: int = 3) -> np.ndarray:
    total = np.zeros(u.shape, np.float32)
    weight, norm = 1.0, 0.0
    for octave in range(octaves):
        total += weight * wrap_noise(u, v, scale, salt + octave * 31)
        norm += weight
        weight *= 0.5
        scale *= 0.5
    return total / norm


def wrap_voronoi(u: np.ndarray, v: np.ndarray, size: float, salt: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Kamínky, po délce navazují. Vrací šířku spáry, světlost kamene a jeho číslo."""
    period = int(round(ALONG / size))
    gu, gv = u / size, v / size
    iu, iv = np.floor(gu), np.floor(gv)
    d1 = np.full(u.shape, 9.0, np.float32)
    d2 = np.full(u.shape, 9.0, np.float32)
    tone = np.zeros(u.shape, np.float32)
    ident = np.zeros(u.shape, np.float32)
    for dv in (-1, 0, 1):
        for du in (-1, 0, 1):
            cu, cv = iu + du, iv + dv
            key = np.mod(cv, period)
            pu = cu + 0.1 + 0.8 * hash01(cu, key, salt)
            pv = cv + 0.1 + 0.8 * hash01(cu, key, salt + 7)
            dist = np.hypot(gu - pu, gv - pv)
            closer = dist < d1
            d2 = np.where(closer, d1, np.minimum(d2, dist))
            tone = np.where(closer, hash01(cu, key, salt + 13), tone)
            ident = np.where(closer, hash01(cu, key, salt + 19), ident)
            d1 = np.where(closer, dist, d1)
    return d2 - d1, tone, ident


def off_center(u: np.ndarray) -> np.ndarray:
    """Vzdálenost od osy cesty v pixelech."""
    return np.abs(u - ACROSS / 2.0)


def side_wave(u: np.ndarray, v: np.ndarray, salt: int) -> np.ndarray:
    """Vlna -1..1 po délce, každý kraj cesty jiná."""
    side = np.where(u > ACROSS / 2.0, 40.0, -40.0).astype(np.float32)
    return (wrap_fbm(side, v, 64.0, salt, 3) - 0.5) * 2.0


def frayed_edge(u: np.ndarray, v: np.ndarray, salt: int, reach: float, feather: float) -> np.ndarray:
    """Krytí 0..1. Kraj se vlní po délce a na samé hraně je zrnitý."""
    half = CORE * PX / 2.0
    edge = half + reach * side_wave(u, v, salt)
    grain = hash01(np.floor(u * 2.0), np.floor(v * 2.0), salt + 3)
    soft = 1.0 - smoothstep(edge - feather, edge + feather, off_center(u))
    return np.clip(soft * 1.25 - 0.25 * grain, 0.0, 1.0)


def mix(*pairs: tuple[np.ndarray, tuple[int, int, int]]) -> np.ndarray:
    """Barva z vah. Váhy nemusí dát dohromady 1, normalizují se."""
    total = sum(weight for weight, _rgb in pairs)
    out = sum(weight[..., None] * np.array(rgb, np.float32) for weight, rgb in pairs)
    return out / np.maximum(total, 1e-4)[..., None] / 255.0


def paint_pesina(u: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Ušlapaná hlína. Uprostřed světlejší a hladší, ke kraji tmavší a hrubší."""
    rel = off_center(u) / (CORE * PX / 2.0)
    worn = 1.0 - smoothstep(0.15, 0.95, rel)
    blotch = wrap_fbm(u, v, 32.0, 101)
    crumb = wrap_fbm(u, v, 8.0, 103, 2)
    rgb = mix(
        (0.6 + 0.8 * worn, (150, 118, 80)),
        (0.7 + 0.6 * (1.0 - worn), (110, 82, 54)),
        (0.4 * blotch, (124, 96, 62)),
    )
    rgb *= (0.86 + 0.18 * blotch + 0.08 * crumb)[..., None]
    # Pár kamínků a vyschlé praskliny, aby hlína nebyla jedna barva.
    gap, tone, ident = wrap_voronoi(u, v, 8.0, 105)
    pebble = (ident > 0.95) & (gap > 0.34)
    pebble_rgb = (0.42 + 0.2 * tone)[..., None] * np.array((1.0, 0.95, 0.88)) * (0.8 + 0.3 * smoothstep(0.34, 0.6, gap))[..., None]
    rgb = np.where(pebble[..., None], pebble_rgb, rgb)
    # Vyschlé praskliny jen sem tam, ne síť přes celou cestu.
    crack_gap, _t, crack_id = wrap_voronoi(u, v, 32.0, 107)
    crack = (crack_gap < 0.022) & (crack_id > 0.72) & (worn > 0.45)
    rgb = np.where(crack[..., None], rgb * 0.8, rgb)
    alpha = frayed_edge(u, v, 109, 11.0, 5.0)
    return rgb, alpha


def paint_sterk(u: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Drobné kamení na hlíně. Kraj se rozsype: kameny řídnou, hlína mizí dřív."""
    gap, tone, ident = wrap_voronoi(u, v, 4.0, 201)
    big_gap, big_tone, big_id = wrap_voronoi(u, v, 8.0, 203)
    stone = gap > 0.12
    warm = wrap_fbm(u, v, 32.0, 205)
    stone_rgb = mix(
        (1.0 - tone * 0.6, (146, 142, 134)),
        (0.4 + tone, (178, 166, 142)),
        (0.5 * warm, (120, 112, 100)),
    )
    bulge = smoothstep(0.1, 0.45, gap)
    stone_rgb *= (0.72 + 0.34 * bulge)[..., None]
    # Občas větší oblázek, ať štěrk není rovnoměrná zrnitost.
    cobble = (big_id > 0.88) & (big_gap > 0.16)
    cobble_rgb = (0.62 + 0.32 * big_tone)[..., None] * np.array((0.88, 0.85, 0.8)) * (0.8 + 0.26 * smoothstep(0.16, 0.5, big_gap))[..., None]
    under = np.array((98, 86, 70), np.float32) / 255.0 * (0.85 + 0.2 * warm)[..., None]
    rgb = np.where(stone[..., None], stone_rgb, under)
    rgb = np.where(cobble[..., None], cobble_rgb, rgb)

    rel = off_center(u) / (CORE * PX / 2.0)
    reach = rel + 0.12 * side_wave(u, v, 207)
    # Hlína pod štěrkem končí u kraje plné cesty, kameny přesahují dál a řídnou.
    dirt_alpha = 1.0 - smoothstep(0.88, 1.02, reach)
    keep = ident > smoothstep(0.92, 1.32, reach)
    stone_alpha = np.where(stone & keep, 1.0, 0.0)
    cobble_alpha = np.where(cobble & (big_id > smoothstep(0.95, 1.3, reach) * 0.12 + 0.88), 1.0, 0.0)
    alpha = np.maximum(np.maximum(dirt_alpha, stone_alpha), cobble_alpha)
    return rgb, alpha.astype(np.float32)


def paint_dlazba(u: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Kameny v řadách napříč, každá řada posunutá. Po krajích obruba z dlouhých kamenů."""
    half = CORE * PX / 2.0
    curb_w = 11.0
    course = 16.0
    row = np.floor(v / course)
    lv = v / course - row
    shift = hash01(row, np.zeros_like(row), 301) * 20.0
    # Šířky kamenů napříč kolísají kolem 0,3 m. Kladou se od osy, ať je řada souměrná.
    width = 18.0 + 6.0 * hash01(row, np.ones_like(row), 303)
    across = u - ACROSS / 2.0 + shift
    col = np.floor(across / width)
    lu = across / width - col
    edge_u = np.minimum(lu, 1.0 - lu) * width
    edge_v = np.minimum(lv, 1.0 - lv) * course
    # Zaoblené rohy: blízko obou hran naráz je spára širší.
    corner = np.hypot(np.maximum(3.0 - edge_u, 0.0), np.maximum(3.0 - edge_v, 0.0))
    # Kameny jsou otesané rukou: obrys se vlní a spáry nemají stejnou šířku.
    chip = wrap_fbm(u, v, 4.0, 317, 2) * 2.2
    inset = np.minimum(edge_u, edge_v) - corner * 0.6 - chip + 0.6
    tone = hash01(col, np.mod(row, ALONG / course), 305)
    tint = hash01(col, np.mod(row, ALONG / course), 307)
    bulge = smoothstep(0.8, 5.0, inset)
    stone_rgb = mix((1.0 - tint, (158, 152, 142)), (tint, (172, 160, 138)))
    stone_rgb *= ((0.74 + 0.22 * tone) * (0.8 + 0.26 * bulge))[..., None]
    wear = wrap_fbm(u, v, 32.0, 309)
    stone_rgb *= (0.9 + 0.16 * wear)[..., None]
    mortar_rgb = np.array((88, 76, 60), np.float32) / 255.0 * (0.9 + 0.2 * wear)[..., None]
    rgb = np.where((inset > 1.1)[..., None], stone_rgb, mortar_rgb)

    # Obruba: řada dlouhých kamenů podél obou krajů.
    side = off_center(u)
    curb_zone = (side > half - curb_w) & (side <= half + 1.0)
    curb_len = 32.0
    curb_idx = np.floor(v / curb_len)
    curb_lv = v / curb_len - curb_idx
    curb_edge = np.minimum(
        np.minimum(curb_lv, 1.0 - curb_lv) * curb_len,
        np.minimum(side - (half - curb_w), half + 1.0 - side),
    )
    curb_key = np.mod(curb_idx, ALONG / curb_len) + np.where(u > ACROSS / 2.0, 100.0, 0.0)
    curb_tone = hash01(curb_key, np.zeros_like(curb_key), 311)
    curb_rgb = np.array((146, 140, 130), np.float32) / 255.0 * ((0.72 + 0.2 * curb_tone) * (0.78 + 0.28 * smoothstep(0.5, 4.0, curb_edge)))[..., None]
    curb_rgb = np.where((curb_edge > 1.0)[..., None], curb_rgb, mortar_rgb)
    rgb = np.where(curb_zone[..., None], curb_rgb, rgb)

    # Za obrubou jen úzký pruh hlíny, kde dlažba dosedá do trávy.
    dirt = np.array((104, 84, 60), np.float32) / 255.0 * (0.85 + 0.2 * wear)[..., None]
    rgb = np.where((side > half + 1.0)[..., None], dirt, rgb)
    limit = half + 6.0 + 4.0 * side_wave(u, v, 313)
    grain = hash01(np.floor(u * 2.0), np.floor(v * 2.0), 315)
    fringe = np.clip((1.0 - smoothstep(limit - 4.0, limit + 2.0, side)) * 1.2 - 0.2 * grain, 0.0, 1.0)
    alpha = np.where(side <= half + 1.0, 1.0, fringe)
    return rgb, alpha.astype(np.float32)


PAINTERS = {"pesina": paint_pesina, "sterk": paint_sterk, "dlazba": paint_dlazba}


def render(pattern: Pattern) -> Image.Image:
    u, v = grid()
    rgb, alpha = PAINTERS[pattern.name](u, v)
    rgba = np.dstack([np.clip(rgb, 0.0, 1.0) * alpha[..., None], alpha])
    small = rgba.reshape(ALONG, SS, ACROSS, SS, 4).mean(axis=(1, 3))
    # Barva bez přednásobení, ať okraj při skládání neztmavne.
    cover = small[..., 3:4]
    small[..., :3] = small[..., :3] / np.maximum(cover, 1e-4)
    return Image.fromarray(np.round(np.clip(small, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")


def check(pattern: Pattern, image: Image.Image) -> None:
    data = np.asarray(image).astype(np.int32)
    if image.size != (ACROSS, ALONG):
        raise SystemExit(f"{pattern.name}: má {image.size}, čekám {(ACROSS, ALONG)}")
    middle = data[:, ACROSS // 2 - 20 : ACROSS // 2 + 20, 3]
    if int((middle < 250).sum()) > middle.size // 50:
        raise SystemExit(f"{pattern.name}: střed cesty není plný")
    if int(data[:, :3, 3].max()) > 8 or int(data[:, -3:, 3].max()) > 8:
        raise SystemExit(f"{pattern.name}: kraj obrázku není průhledný")
    # Navázání po délce: poslední řádek proti prvnímu má být podobný jako dva sousední uvnitř.
    seam = np.abs(data[-1, :, :3] - data[0, :, :3]).mean()
    inner = np.abs(data[ALONG // 2, :, :3] - data[ALONG // 2 - 1, :, :3]).mean()
    if seam > inner * 2.5 + 6.0:
        raise SystemExit(f"{pattern.name}: vzor po délce nenavazuje ({seam:.1f} proti {inner:.1f})")


def catmull_rom(points: list[tuple[float, float]], step: float) -> np.ndarray:
    """Plynulá křivka přes body. Konce se prodlouží zrcadlením, ať křivka začne i skončí v bodě."""
    pts = [np.array(p, np.float64) for p in points]
    pts = [2.0 * pts[0] - pts[1]] + pts + [2.0 * pts[-1] - pts[-2]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        count = max(2, int(np.linalg.norm(p2 - p1) / step))
        for t in np.linspace(0.0, 1.0, count, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(
                0.5
                * (
                    2.0 * p1
                    + (-p0 + p2) * t
                    + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                    + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
                )
            )
    out.append(pts[-2])
    return np.array(out, np.float32)


def lay_along(curves: list[np.ndarray], texture: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Položí vzor podél křivek, jak to udělá pečení chunku ve hře."""
    tex = np.asarray(texture).astype(np.float32) / 255.0
    width, height = size
    best = np.full((height, width), np.inf, np.float32)
    out = np.zeros((height, width, 4), np.float32)
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    xs += 0.5
    ys += 0.5
    for curve in curves:
        seg = np.diff(curve, axis=0)
        length = np.hypot(seg[:, 0], seg[:, 1])
        arc = np.concatenate([[0.0], np.cumsum(length)]).astype(np.float32)
        tangent = seg / np.maximum(length, 1e-6)[:, None]
        tangent = np.vstack([tangent, tangent[-1:]])
        normal = np.stack([-tangent[:, 1], tangent[:, 0]], axis=1)
        reach = ACROSS / 2.0 + 2.0
        lo = curve.min(axis=0) - reach
        hi = curve.max(axis=0) + reach
        for row in range(max(0, int(lo[1])), min(height, int(hi[1]) + 1)):
            px, py = xs[row], ys[row]
            dx = px[:, None] - curve[None, :, 0]
            dy = py[:, None] - curve[None, :, 1]
            d2 = dx * dx + dy * dy
            near = np.argmin(d2, axis=1)
            dist = np.sqrt(d2[np.arange(width), near])
            ok = dist <= reach
            if not ok.any():
                continue
            n = normal[near]
            t = tangent[near]
            off = dx[np.arange(width), near] * n[:, 0] + dy[np.arange(width), near] * n[:, 1]
            along = arc[near] + dx[np.arange(width), near] * t[:, 0] + dy[np.arange(width), near] * t[:, 1]
            take = ok & (np.abs(off) < best[row])
            if not take.any():
                continue
            tu = np.clip(off + ACROSS / 2.0, 0.0, ACROSS - 1.001)
            tv = np.mod(along, ALONG)
            sample = bilinear(tex, tu, tv)
            prev_alpha = out[row, :, 3].copy()
            out[row, take] = sample[take]
            out[row, take, 3] = np.maximum(sample[take, 3], prev_alpha[take])
            best[row, take] = np.abs(off[take])
    return Image.fromarray(np.round(np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")


def bilinear(tex: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    u0 = np.floor(u - 0.5)
    v0 = np.floor(v - 0.5)
    fu = (u - 0.5 - u0)[:, None]
    fv = (v - 0.5 - v0)[:, None]
    u0i = np.clip(u0.astype(int), 0, ACROSS - 1)
    u1i = np.clip(u0.astype(int) + 1, 0, ACROSS - 1)
    v0i = np.mod(v0.astype(int), ALONG)
    v1i = np.mod(v0.astype(int) + 1, ALONG)
    a, b = tex[v0i, u0i], tex[v0i, u1i]
    c, d = tex[v1i, u0i], tex[v1i, u1i]
    # Barvu váží krytím, ať průhledný soused nezabarví okraj.
    def pm(x: np.ndarray) -> np.ndarray:
        return np.concatenate([x[:, :3] * x[:, 3:4], x[:, 3:4]], axis=1)

    mixed = (pm(a) * (1 - fu) + pm(b) * fu) * (1 - fv) + (pm(c) * (1 - fu) + pm(d) * fu) * fv
    mixed[:, :3] /= np.maximum(mixed[:, 3:4], 1e-4)
    return mixed


def grass(size: tuple[int, int]) -> Image.Image:
    """Tráva z atlasu hry. Dlaždice na sebe navazují v libovolném pořadí."""
    atlas = Image.open(GRASS_ATLAS).convert("RGB")
    tile = 64
    tiles = [atlas.crop((x, y, x + tile, y + tile)) for y in range(0, atlas.height, tile) for x in range(0, atlas.width, tile)]
    rng = np.random.default_rng(7)
    canvas = Image.new("RGB", size)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            canvas.paste(tiles[int(rng.integers(len(tiles)))], (x, y))
    return canvas


SCENE = (1100, 700)
ABCD = [(110.0, 560.0), (360.0, 210.0), (720.0, 470.0), (990.0, 150.0)]
CROSS = [(140.0, 120.0), (560.0, 330.0), (980.0, 600.0)]


def scene(texture: Image.Image) -> Image.Image:
    curves = [catmull_rom(ABCD, 2.0), catmull_rom(CROSS, 2.0)]
    road = lay_along(curves, texture, SCENE)
    image = grass(SCENE).convert("RGBA")
    image.alpha_composite(road)
    draw = ImageDraw.Draw(image)
    font = load_font(22)
    for label, (x, y) in zip("ABCD", ABCD):
        draw.ellipse((x - 9, y - 9, x + 9, y + 9), fill=(250, 246, 236), outline=(30, 26, 22), width=2)
        draw.text((x + 12, y - 30), label, fill=(250, 246, 236), font=font, stroke_width=2, stroke_fill=(30, 26, 22))
    return image.convert("RGB")


def tile_sheet(images: list[tuple[Image.Image, str]], path: Path) -> None:
    """Surové vzory, každý dvakrát po délce pod sebou, ať je vidět navázání."""
    gap, caption, scale = 20, 30, 2
    slot_w = ACROSS * scale
    slot_h = ALONG * 2 * scale
    sheet = Image.new("RGB", (len(images) * slot_w + (len(images) + 1) * gap, slot_h + caption + 2 * gap), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)
    for index, (image, label) in enumerate(images):
        x = gap + index * (slot_w + gap)
        draw.text((x, gap), label, fill=(230, 226, 214), font=font)
        doubled = Image.new("RGBA", (ACROSS, ALONG * 2))
        doubled.paste(image, (0, 0))
        doubled.paste(image, (0, ALONG))
        doubled = doubled.resize((slot_w, slot_h), Image.Resampling.NEAREST)
        bg = Image.new("RGBA", doubled.size, (79, 154, 60, 255))
        bg.alpha_composite(doubled)
        sheet.paste(bg.convert("RGB"), (x, gap + caption))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def scene_sheet(images: list[tuple[Image.Image, str]], path: Path) -> None:
    gap, caption = 16, 30
    w, h = SCENE
    sheet = Image.new("RGB", (w + 2 * gap, len(images) * (h + caption + gap) + gap), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    font = load_font(20)
    for index, (image, label) in enumerate(images):
        y = gap + index * (h + caption + gap)
        draw.text((gap, y), label, fill=(230, 226, 214), font=font)
        sheet.paste(image, (gap, y + caption))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def write_info() -> Path:
    catalog = {
        "px_per_meter": PX,
        "wired_into_godot": False,
        "across_px": ACROSS,
        "along_px": ALONG,
        "core_m": CORE,
        "repeat": "along",
        "patterns": {
            pattern.name: {
                "label": pattern.label,
                "file": f"{pattern.name}.png",
                "directional": pattern.directional,
            }
            for pattern in PATTERNS
        },
    }
    path = OUT_DIR / "paths.json"
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tiles: list[tuple[Image.Image, str]] = []
    scenes: list[tuple[Image.Image, str]] = []
    for pattern in PATTERNS:
        texture = render(pattern)
        check(pattern, texture)
        texture.save(OUT_DIR / f"{pattern.name}.png")
        tiles.append((texture, f"{pattern.label}  {ACROSS}×{ALONG} px"))
        image = scene(texture)
        image.save(PREVIEW / f"cesta_{pattern.name}.png")
        scenes.append((image, f"{pattern.label} · A, B, C, D a křížení"))
        print(f"{pattern.name}: {ACROSS}×{ALONG} px")
    tile_sheet(tiles, PREVIEW / "cesty_vzory.png")
    scene_sheet(scenes, PREVIEW / "cesty.png")
    print(PREVIEW / "cesty.png")
    print(PREVIEW / "cesty_vzory.png")
    print(write_info())


if __name__ == "__main__":
    main()
