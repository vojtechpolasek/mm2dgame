#!/usr/bin/env python3
"""Logo hry. Písmena nejsou z písma: každé má kostru z tahů a podél ní jsou navlečené
kameny ze hry. Drahokam je broušený sedmiúhelník, hornina hrudka o devíti ploškách,
stínování a lem jsou stejné jako v gen_crystal.py a crystal.gdshader. Kamenná písmena
porůstají mechem a trávou, drahokamy se třpytí. „O“ je kamenná koule s obličejem,
jako příšera koule2 z gen_monsters.py.

splash.png je celá obrazovka 1920 × 1080 na barvě BACKGROUND. Godot ho ukáže při startu
a stejný obrázek pak drží opona v menu_stage.gd, dokud se nesloží mapa.
logo.png je stejný nápis na průhledném pozadí pro hlavní menu.
logo_mm.png je malé logo „MM“ na průhledném pozadí, ve hře je to tlačítko menu.

  py tools/gen_logo.py
  py tools/gen_logo.py --seed 3
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

from gen_crystal import CRYSTAL_FACETS, MATERIALS, STONE_FACETS, parse_hex

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot" / "graphics" / "menu" / "splash.png"
OUT_MINI = ROOT / "godot" / "graphics" / "menu" / "logo_mm.png"
OUT_LOGO = ROOT / "godot" / "graphics" / "menu" / "logo.png"
# Šířka loga v hlavním menu. Menu ho zmenší, víc je jen pro ostrost na velkých obrazovkách.
LOGO_WIDTH = 1000

WIDTH = 1920
HEIGHT = 1080
SS = 2
# Stejná barva je v project.godot (boot_splash/bg_color) a v menu_stage.gd.
BACKGROUND = parse_hex("121411")
GLOW = parse_hex("22261E")
ACCENT = parse_hex("DBA84D")
OUTLINE = parse_hex("0B0A08")
HALO = parse_hex("E8DCC0")

# Výška písmen v px. Délky v kostrách písmen jsou díly této výšky.
CAP = 158
SUB_CAP = 34
# Tloušťka tahu a mezera mezi písmeny.
STROKE = 0.25
GAP = 0.1
# Poloměr kamene a jak daleko jsou kameny od sebe, díl průměru. Menší než 1 se překrývají.
GEM_RADIUS = 0.15
GEM_STEP = 0.74
# Písmeno se trochu natočí a posune, ať nápis nevypadá jako z tiskárny. Stupně a díly výšky.
TILT = 2.6
BOB = 0.025
# Svislé středy řádků a podtitulu. Pod podtitulem je místo pro ukazatel načítání.
LINE_Y = (388, 590)
SUB_Y = 738
# Hlavně kameny a kovy, drahokamy jen jako akcent, ať nápis není duha.
LINES = (
    ("MATERIAL", ("piskovec", "kremen", "lavovy", "zlato", "magnetit", "stribro", "jantar", "grafit")),
    ("MONSTERS", ("rubin", "magnetit", "stribro", "piskovec", "kremen", "smaragd", "zlato", "lavovy")),
)
# Drahokam vsazený do písmene z horniny nebo kovu, a jak často.
INLAYS = ("smaragd", "rubin", "safir", "jantar", "diamant")
INLAY_SHARE = 0.06
# Písmeno, které je kamennou koulí s obličejem: řádek a pořadí.
EYES = (1, 1)
# Koule: kolik kamenů je na celé kouli (Fibonacciho spirála, vidět je přední polovina)
# a jejich velikost jako díl poloměru tahu. Světlo koule jde zleva shora zepředu.
BALL_STONES = 120
BALL_GEM = 0.78
BALL_LIGHT = np.array([-0.45, -0.6, 0.66])
# Oči koule ve hře (colors.eye v monsters.json) a zuby tlamy.
BALL_EYE = parse_hex("FF3A1A")
BALL_TEETH = parse_hex("E4DCC8")
# Malé logo: obě „M“ jako začátky řádků velkého. Kreslí se velké a zmenší se na MINI px.
MINI_LINES = (("MM", ("piskovec", "rubin")),)
MINI_CANVAS = (560, 340)
MINI = 160
# Kolik barvy materiálům zůstane. 1 je plná barva katalogu.
SATURATION = 0.62
# Nejmenší jas barvy kamene (0 až 255). Grafit je ve hře skoro černý, v logu by zmizel.
MIN_LUMA = 78.0
# Jak moc se kameny jednoho písmene liší: jas a odstín (posun každého kanálu).
GEM_TONE = (0.76, 1.16)
GEM_HUE = 0.05
# Jak vypadá povrch. tilt je náklon plošek, cell jejich velikost, grain zrno, moss podíl mechu.
KINDS = {
    "stone": {"tilt": 0.32, "cell": 34, "grain": 0.2, "rough": 2.6, "moss": 0.62, "spec": 0.15},
    "crystal": {"tilt": 0.8, "cell": 46, "grain": 0.03, "rough": 0.8, "moss": 0.0, "spec": 0.6},
    "metal": {"tilt": 0.5, "cell": 58, "grain": 0.05, "rough": 1.2, "moss": 0.22, "spec": 0.7},
    "lava": {"tilt": 0.3, "cell": 30, "grain": 0.22, "rough": 2.8, "moss": 0.12, "spec": 0.1},
}
KIND = {
    "piskovec": "stone", "sira": "stone", "kremen": "stone", "grafit": "metal", "magnetit": "metal",
    "lavovy": "lava", "stribro": "metal", "zlato": "metal",
    "jantar": "crystal", "smaragd": "crystal", "rubin": "crystal", "safir": "crystal", "diamant": "crystal",
}
LIGHT = np.array([-0.5, -0.72, 0.9])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
MOSS = (parse_hex("2F5A22"), parse_hex("4F8A2E"), parse_hex("7DB045"))
GRASS = (parse_hex("2E5E24"), parse_hex("4C8F34"), parse_hex("78B84A"), parse_hex("9CCB5C"))


# --- Šum a plochy ---

def fbm(shape: tuple[int, int], cell: float, octaves: int, rng: np.random.Generator) -> np.ndarray:
    h, w = shape
    out = np.zeros(shape, np.float32)
    total = 0.0
    amp = 1.0
    for octave in range(octaves):
        size = max(cell / 2**octave, 2.0)
        grid = rng.random((int(h / size) + 4, int(w / size) + 4)).astype(np.float32)
        up = ndimage.zoom(grid, size, order=3)[:h, :w]
        out += up * amp
        total += amp
        amp *= 0.5
    return np.clip(out / total, 0.0, 1.0)


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rgb(color: tuple[int, int, int]) -> np.ndarray:
    return np.array(color, np.float32)


## Barva materiálu stažená k šedi stejného jasu.
def muted(color: tuple[int, int, int], keep: float = SATURATION) -> np.ndarray:
    value = rgb(color)
    gray = value @ np.array([0.299, 0.587, 0.114], np.float32)
    return gray + (value - gray) * keep


## Plátno s krytím. Barva je vynásobená krytím, ať jde kreslit i na průhledné pozadí.
class Canvas:
    def __init__(self, width: int, height: int, background: tuple[int, int, int] | None) -> None:
        self.width = width
        self.height = height
        self.w = width * SS
        self.h = height * SS
        self.rgb = np.zeros((self.h, self.w, 3), np.float32)
        self.alpha = np.zeros((self.h, self.w), np.float32)
        if background is not None:
            self.rgb[:] = rgb(background)
            self.alpha[:] = 1.0

    def over(self, color: np.ndarray, alpha: np.ndarray, x0: int = 0, y0: int = 0) -> None:
        h, w = alpha.shape
        region = self.rgb[y0:y0 + h, x0:x0 + w]
        cover = self.alpha[y0:y0 + h, x0:x0 + w]
        a = alpha[..., None]
        region[:] = region * (1.0 - a) + color * a
        cover[:] = cover * (1.0 - alpha) + alpha

    def layer(self, image: Image.Image) -> None:
        data = np.asarray(image, np.float32)
        self.over(data[..., :3], data[..., 3] / 255.0)

    def image(self) -> Image.Image:
        small = self.rgb.reshape(self.height, SS, self.width, SS, 3).mean(axis=(1, 3))
        cover = self.alpha.reshape(self.height, SS, self.width, SS).mean(axis=(1, 3))
        color = small / np.maximum(cover, 1e-4)[..., None]
        data = np.concatenate([color, cover[..., None] * 255.0], axis=2)
        return Image.fromarray(np.clip(np.round(data), 0, 255).astype(np.uint8), "RGBA")


# --- Písmena ---

class Letter:
    def __init__(self, char: str, material: str, x0: int, y0: int, inside: np.ndarray) -> None:
        self.char = char
        self.material = material
        self.kind = KIND[material]
        self.x0 = x0
        self.y0 = y0
        self.inside = inside
        self.alpha = inside.astype(np.float32)
        # Každý kus je o kousek světlejší nebo tmavší, ať písmeno nevypadá jako jedna barva.
        self.tone = 1.0

    @property
    def shape(self) -> tuple[int, int]:
        return self.inside.shape


# --- Kostry písmen ---
# Písmeno je šířka a seznam tahů. Tah je lomená čára středem tahu v souřadnicích písmene:
# x doprava, y dolů, výška písmene 1. Uzavřený tah (O) je dvojice (body, True).

def arc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, steps: int = 32) -> list:
    out = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        out.append((cx + rx * math.cos(a), cy - ry * math.sin(a)))
    return out


def glyph(char: str) -> tuple[float, list]:
    t = STROKE / 2
    w2 = STROKE
    if char == "M":
        w = 1.04
        return w, [[(t, 0), (t, 1)], [(w - t, 0), (w - t, 1)],
                   [(w2 - 0.03, 0.05), (w / 2, 0.72)], [(w - w2 + 0.03, 0.05), (w / 2, 0.72)]]
    if char == "A":
        w = 0.96
        return w, [[(0.1, 1), (w / 2 + 0.02, 0.02)], [(w - 0.1, 1), (w / 2 - 0.02, 0.02)],
                   [(0.27, 0.68), (w - 0.27, 0.68)]]
    if char == "T":
        w = 0.92
        return w, [[(0, t), (w, t)], [(w / 2, w2), (w / 2, 1)]]
    if char == "E":
        return 0.8, [[(t, 0), (t, 1)], [(w2, t), (0.8, t)], [(w2, 0.5), (0.7, 0.5)], [(w2, 1 - t), (0.8, 1 - t)]]
    if char == "L":
        return 0.74, [[(t, 0), (t, 1)], [(w2, 1 - t), (0.74, 1 - t)]]
    if char == "I":
        return w2, [[(t, 0), (t, 1)]]
    if char == "N":
        w = 0.92
        return w, [[(t, 0), (t, 1)], [(w - t, 0), (w - t, 1)], [(w2 - 0.03, 0.05), (w - w2 + 0.03, 0.95)]]
    if char == "O":
        return 1.0, [(arc(0.5, 0.5, 0.5 - t, 0.5 - t, 90, 450, 64)[:-1], True)]
    if char == "R":
        cy = (t + 0.56) / 2
        bowl = [(w2, t), (0.5, t)] + arc(0.5, cy, 0.22, 0.56 - cy, 90, -90) + [(0.5, 0.56), (w2, 0.56)]
        return 0.88, [[(t, 0), (t, 1)], bowl, [(0.47, 0.6), (0.82, 1)]]
    if char == "S":
        rx, ry = 0.29, 0.5 / 2 - t / 2
        cx = 0.42
        upper = arc(cx, t + ry, rx, ry, 28, 270, 30)
        lower = arc(cx, 0.5 + ry, rx, ry, 90, -152, 30)
        return 0.84, [upper + lower[1:]]
    if char == "G":
        return 1.0, [arc(0.5, 0.5, 0.5 - t, 0.5 - t, 42, 355, 48), [(0.56, 0.56), (1 - t + 0.02, 0.56)]]
    raise ValueError(f"Písmeno {char} nemá kostru.")


def resample(points: list, closed: bool) -> np.ndarray:
    pts = [np.array(point, np.float64) for point in points]
    if closed:
        pts.append(pts[0])
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        steps = max(int(np.linalg.norm(b - a) / 0.008), 1)
        for k in range(1, steps + 1):
            out.append(a + (b - a) * k / steps)
    return np.array(out)


## Kde na tahu leží kameny: středy a poloměry v souřadnicích písmene. Krajní kameny
## nepřečnívají konec tahu víc než o kousek.
def stones_of(points: list, closed: bool, rng: np.random.Generator) -> list[tuple[float, float, float]]:
    line = resample(points, closed)
    step = np.linalg.norm(np.diff(line, axis=0), axis=1)
    length = np.concatenate([[0.0], np.cumsum(step)])
    total = length[-1]
    spacing = GEM_RADIUS * 2 * GEM_STEP
    if closed:
        count = max(math.ceil(total / spacing), 3)
        spots = [total * k / count for k in range(count)]
    else:
        inset = GEM_RADIUS * 0.55
        span = max(total - inset * 2, 0.0)
        # Nahoru, ať mezi kameny krátkého tahu nezůstane mezera.
        count = max(math.ceil(span / spacing - 0.05), 0) + 1
        spots = [total / 2] if count == 1 else [inset + span * k / (count - 1) for k in range(count)]
    stones = []
    for at in spots:
        x = float(np.interp(at, length, line[:, 0]))
        y = float(np.interp(at, length, line[:, 1]))
        stones.append((x + rng.uniform(-0.01, 0.01), y + rng.uniform(-0.01, 0.01), GEM_RADIUS * rng.uniform(0.92, 1.08)))
    return stones


## Kámen jako ve hře: plošky od středu posunutého ke světlu, vnitřní ploška a korunka,
## lem po obvodu. Barví se jako v crystal.gdshader: světlost 0.32 až 1.18 a lem navíc.
def gem_piece(char: str, material: str, cx: float, cy: float, radius: float, rng: np.random.Generator,
              light_mul: float = 1.0) -> Letter:
    crystal = MATERIALS[material]["shape"] == "crystal"
    facets = CRYSTAL_FACETS if crystal else STONE_FACETS
    cap = 255 if crystal else 214
    turn = rng.uniform(-0.18, 0.18)
    pad = int(3 * SS)
    side = int(radius * 2.3) + pad * 2
    x0 = int(cx - side / 2)
    y0 = int(cy - side / 2)
    ox, oy = cx - x0, cy - y0
    points = []
    for index, (mul, _shade) in enumerate(facets):
        angle = -math.pi / 2 + index / len(facets) * math.tau + turn
        reach = radius * mul * rng.uniform(0.96, 1.04)
        points.append((ox + math.cos(angle) * reach, oy + math.sin(angle) * reach))
    # Střed plošek je posunutý doprava nahoru jako v gen_crystal.draw_mask.
    center = (ox + radius * 0.12, oy - radius * 0.17)

    def toward(a: tuple, b: tuple, t: float) -> tuple:
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    red = Image.new("L", (side, side), 0)
    blue = Image.new("L", (side, side), 0)
    alpha = Image.new("L", (side, side), 0)
    ImageDraw.Draw(alpha).polygon(points, fill=255)
    red_draw = ImageDraw.Draw(red)
    for index, (_mul, value) in enumerate(facets):
        red_draw.polygon((center, points[index], points[(index + 1) % len(points)]), fill=value)
    red_draw.polygon([toward(center, point, 0.40) for point in points], fill=min(cap, 250))
    red_draw.polygon([toward(center, point, 0.16) for point in points], fill=cap)
    rim = ImageDraw.Draw(blue)
    rim.line(points + [points[0]], fill=210, width=max(int(radius * 0.12), 2), joint="curve")
    middle = (ox, oy)
    inner = [toward(middle, point, 0.78) for point in points]
    rim.line(inner + [inner[0]], fill=120, width=max(int(radius * 0.05), 1), joint="curve")
    light = np.asarray(red, np.float32) / 255.0
    edge = np.asarray(blue, np.float32) / 255.0
    cover = np.asarray(alpha, np.float32) / 255.0
    base = muted(parse_hex(MATERIALS[material]["color"]))
    luma = float(base @ np.array([0.299, 0.587, 0.114], np.float32))
    if luma < MIN_LUMA:
        # Tmavé materiály se zesvětlí přičtením, násobení by z černé udělalo zase černou.
        base = base + (MIN_LUMA - luma)
    # Každý kámen má trochu jiný jas i odstín, ať písmeno není jedna barva.
    base = base * rng.uniform(*GEM_TONE) * rng.uniform(1.0 - GEM_HUE, 1.0 + GEM_HUE, 3) * light_mul
    color = base * (0.32 + 0.86 * light)[..., None] + base * (edge * 0.22)[..., None]
    piece = Letter(char, material, x0, y0, cover > 0.5)
    piece.alpha = cover
    piece.color = np.clip(color, 0.0, 255.0)
    piece.light = light * (cover > 0.5)
    return piece


## Kameny koule: body na kouli, vidět je přední polovina. Kámen u okraje je zkrácený pohledem
## a tmavší, kreslí se dřív, ať ho přední kameny překryjí.
def ball_stones(char: str, material: str, place, size: float, rng: np.random.Generator) -> list[Letter]:
    light = BALL_LIGHT / np.linalg.norm(BALL_LIGHT)
    spots = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for k in range(BALL_STONES):
        z = 1.0 - (k + 0.5) / BALL_STONES * 2.0
        ring = math.sqrt(max(1.0 - z * z, 0.0))
        turn = k * golden
        nx, ny, nz = ring * math.cos(turn), ring * math.sin(turn), z
        if nz < -0.05:
            continue
        spots.append((nz, nx, ny))
    spots.sort()
    stones = []
    reach = 0.5 - GEM_RADIUS * BALL_GEM * 0.55
    for nz, nx, ny in spots:
        lit = max(float(np.dot((nx, ny, nz), light)), 0.0)
        u = 0.5 + nx * reach + rng.uniform(-0.008, 0.008)
        v = 0.5 + ny * reach + rng.uniform(-0.008, 0.008)
        r = GEM_RADIUS * BALL_GEM * (0.55 + 0.45 * max(nz, 0.0)) * rng.uniform(0.92, 1.08)
        px, py = place(u, v)
        stones.append(gem_piece(char, material, px, py, r * size, rng, 0.78 + 0.62 * lit))
    return stones


class Glyph:
    """Písmeno z kusů. union je celé písmeno jako jeden obrys, pro mech a oči."""

    def __init__(self, char: str, material: str, chunks: list[Letter]) -> None:
        self.char = char
        self.material = material
        self.chunks = chunks
        x0 = min(c.x0 for c in chunks)
        y0 = min(c.y0 for c in chunks)
        x1 = max(c.x0 + c.shape[1] for c in chunks)
        y1 = max(c.y0 + c.shape[0] for c in chunks)
        inside = np.zeros((y1 - y0, x1 - x0), bool)
        for c in chunks:
            h, w = c.shape
            inside[c.y0 - y0:c.y0 - y0 + h, c.x0 - x0:c.x0 - x0 + w] |= c.inside
        self.union = Letter(char, material, x0, y0, inside)
        # Střed a poloměr koule v px plátna, jen u písmene z koule.
        self.ball: tuple[float, float, float] | None = None


## ball_at je pořadí písmene (přes všechny řádky), které se postaví jako kamenná koule.
def layout(canvas: Canvas, lines: tuple, line_y: tuple, cap: float, rng: np.random.Generator,
           inlays: bool = True, gap: float = GAP, ball_at: int = -1) -> list[Glyph]:
    size = cap * SS
    glyphs = []
    for (text, materials), center_y in zip(lines, line_y):
        shapes = [glyph(char) for char in text]
        width = sum(w for w, _ in shapes) + gap * (len(text) - 1)
        x = (canvas.w - width * size) / 2
        top = center_y * SS - size / 2
        for char, material, (w, strokes) in zip(text, materials, shapes):
            angle = math.radians(rng.uniform(-TILT, TILT))
            bob = rng.uniform(-BOB, BOB) * size
            cx, cy = w / 2, 0.5

            def place(u: float, v: float) -> tuple[float, float]:
                du, dv = u - cx, v - cy
                ru = du * math.cos(angle) - dv * math.sin(angle) + cx
                rv = du * math.sin(angle) + dv * math.cos(angle) + cy
                return x + ru * size, top + rv * size + bob

            chunks = []
            if ball_at == len(glyphs):
                ball = Glyph(char, material, ball_stones(char, material, place, size, rng))
                ball.ball = (*place(0.5, 0.5), 0.5 * size)
                glyphs.append(ball)
                x += (w + gap) * size
                continue
            for stroke in strokes:
                points, closed = stroke if isinstance(stroke, tuple) else (stroke, False)
                for u, v, r in stones_of(points, closed, rng):
                    px, py = place(u, v)
                    stuff = material
                    if inlays and MATERIALS[material]["shape"] != "crystal" and rng.random() < INLAY_SHARE:
                        stuff = str(rng.choice(INLAYS))
                    chunks.append(gem_piece(char, stuff, px, py, r * size, rng))
            glyphs.append(Glyph(char, material, chunks))
            x += (w + gap) * size
    return glyphs


def union(letters: list[Letter], canvas: Canvas) -> np.ndarray:
    mask = np.zeros((canvas.h, canvas.w), np.float32)
    for letter in letters:
        h, w = letter.shape
        region = mask[letter.y0:letter.y0 + h, letter.x0:letter.x0 + w]
        np.maximum(region, letter.alpha, out=region)
    return mask


def backdrop(canvas: Canvas) -> None:
    yy, xx = np.mgrid[0:canvas.h, 0:canvas.w].astype(np.float32)
    cx, cy = canvas.w / 2, (LINE_Y[0] + LINE_Y[1]) / 2 * SS
    r = np.sqrt(((xx - cx) / (980 * SS)) ** 2 + ((yy - cy) / (430 * SS)) ** 2)
    glow = (1.0 - smoothstep(0.0, 1.0, r)) * 0.9
    canvas.over(rgb(GLOW), glow)


def shadow_and_outline(canvas: Canvas, mask: np.ndarray, scale: float = 1.0) -> None:
    drop = max(int(14 * SS * scale), 2)
    shadow = ndimage.gaussian_filter(np.roll(np.roll(mask, drop, axis=0), drop // 2, axis=1), max(9 * SS * scale, 1.5))
    canvas.over(rgb((4, 4, 3)), np.clip(shadow * 0.75, 0.0, 1.0))
    grow = max(int(5 * SS * scale), 3)
    # Jemný světlý lem kolem tmavého obrysu, ať je nápis vidět i na tmavém pozadí.
    halo = ndimage.grey_dilation(mask, size=(grow + 2 * SS, grow + 2 * SS))
    halo = ndimage.gaussian_filter(halo, 0.8 * SS * max(scale, 0.5))
    canvas.over(rgb(HALO), np.clip(halo, 0.0, 1.0) * 0.16)
    outline = ndimage.grey_dilation(mask, size=(grow, grow))
    outline = ndimage.gaussian_filter(outline, 0.8 * SS)
    canvas.over(rgb(OUTLINE), np.clip(outline, 0.0, 1.0) * 0.92)


# --- Třpyt na drahokamech a kovu ---

## Hvězdičky na nejsvětlejších místech a drobné jiskry po celé ploše.
## Kolik jich je, jde podle třpytu materiálu v katalogu krystalů.
def sparkles(draw: ImageDraw.ImageDraw, letter: Letter, lit: np.ndarray, rng: np.random.Generator,
             scale: float = 1.0) -> None:
    shine = float(MATERIALS[letter.material]["sparkle"])
    if shine < 0.3 or MATERIALS[letter.material]["shape"] != "crystal":
        return
    glint = tuple(int(v) for v in muted(parse_hex(MATERIALS[letter.material]["glint"]), 0.8))
    inside = lit[letter.inside]
    ys, xs = np.nonzero(lit > np.quantile(inside, 0.93))
    if len(xs) == 0:
        return
    # Kus je malý, hvězdička na něm jen někdy.
    stars = rng.poisson(shine * 0.55 * scale)
    for _ in range(stars):
        i = rng.integers(len(xs))
        star(draw, letter.x0 + xs[i], letter.y0 + ys[i], rng.uniform(8, 17) * SS * scale, glint)
    ys, xs = np.nonzero(lit > np.quantile(inside, 0.6))
    for _ in range(int(shine * 7 * scale)):
        i = rng.integers(len(xs))
        x, y = letter.x0 + xs[i], letter.y0 + ys[i]
        r = rng.uniform(0.7, 1.6) * SS * max(scale, 0.6)
        draw.ellipse((x - r * 2.2, y - r * 2.2, x + r * 2.2, y + r * 2.2), fill=(*glint, 50))
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, int(rng.uniform(150, 255))))


## Odlesk jako ve hře: jádro, slabá záře a šest tenkých paprsků.
def star(draw: ImageDraw.ImageDraw, x: float, y: float, size: float, color) -> None:
    for r, a in ((size * 0.45, 36), (size * 0.24, 100)):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(*color, a))
    for k in range(6):
        angle = k * math.pi / 3 + math.pi / 6
        ca, sa = math.cos(angle), math.sin(angle)
        tip = (x + ca * size, y + sa * size)
        w = size * 0.07
        draw.polygon(((x - sa * w, y + ca * w), tip, (x + sa * w, y - ca * w)), fill=(*color, 230))
    r = size * 0.13
    draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 255))


# --- Obličej koule ---
# Jako koule2 ve hře: tmavé důlky, šikmé rudé oči se štěrbinou, víčko uřízne oko do
# zamračeného klínu, nad ním tmavý kámen obočí. Pod očima tlama, uvnitř žhne barvou očí.

def ball_face(canvas: Canvas, cx: float, cy: float, r: float) -> None:
    side_px = int(r * 2.2)
    x0 = int(cx - side_px / 2)
    y0 = int(cy - side_px / 2)
    ox, oy = cx - x0, cy - y0
    yy, xx = np.mgrid[0:side_px, 0:side_px].astype(np.float32)
    eye = rgb(BALL_EYE)
    for side in (-1, 1):
        ex, ey = ox + side * r * 0.34, oy - r * 0.08
        rx, ry = r * 0.22, r * 0.13
        # Tmavý důlek, o kus větší než oko.
        socket = np.sqrt(((xx - ex) / (rx * 1.3)) ** 2 + ((yy - ey) / (ry * 1.9)) ** 2)
        canvas.over(rgb((12, 11, 10)), np.clip((1.0 - socket) * 6.0, 0.0, 1.0) * 0.85, x0, y0)
        d = np.sqrt(((xx - ex) / rx) ** 2 + ((yy - ey) / ry) ** 2)
        # Víčko klesá k nosu: přísný pohled.
        lid = (yy - ey) + (xx - ex) * side * 0.55 + ry * 0.45
        shape = np.clip((1.0 - d) * rx * 0.5, 0.0, 1.0) * np.clip(lid * 0.5, 0.0, 1.0)
        glow = ndimage.gaussian_filter(shape, r * 0.07)
        canvas.over(eye * 0.8, np.clip(glow * 1.4, 0.0, 0.7), x0, y0)
        tone = 0.75 + 0.45 * (1.0 - np.clip(d, 0.0, 1.0))
        canvas.over(np.clip(eye[None, None, :] * tone[..., None] + 30.0, 0, 255), shape, x0, y0)
        pupil = np.clip((1.0 - np.sqrt(((xx - ex) / (rx * 0.16)) ** 2 + ((yy - ey) / (ry * 0.9)) ** 2)) * 6, 0, 1) * shape
        canvas.over(rgb((20, 6, 4)), pupil, x0, y0)
    face = Image.new("RGBA", (side_px, side_px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(face)
    for side in (-1, 1):
        ex, ey = ox + side * r * 0.34, oy - r * 0.08
        # Obočí: protažený tmavý kámen po hraně víčka, od vnějšího koutku dolů k nosu.
        outer = (ex + side * r * 0.27, ey - r * 0.23)
        inner = (ex - side * r * 0.2, ey - r * 0.04)
        dx, dy = inner[0] - outer[0], inner[1] - outer[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy / length, dx / length
        thick = r * 0.075
        brow = [(outer[0] + nx * thick, outer[1] + ny * thick), (inner[0] + nx * thick * 0.7, inner[1] + ny * thick * 0.7),
                (inner[0] - nx * thick * 0.7, inner[1] - ny * thick * 0.7), (outer[0] - nx * thick, outer[1] - ny * thick)]
        draw.polygon(brow, fill=(46, 48, 52, 255))
        draw.line(brow[3:] + brow[2:3], fill=(92, 96, 102, 255), width=max(int(r * 0.03), 1))
    # Tlama: zamračený oblouk, koutky dolů. Uvnitř žhne, nahoře zuby.
    mouth_y = oy + r * 0.38
    half = r * 0.3
    top = [(ox + half * t, mouth_y - r * 0.05 * (1.0 - t * t) + r * 0.06 * t * t) for t in np.linspace(-1, 1, 15)]
    bottom = [(ox + half * t, mouth_y + r * 0.11 * (1.0 - t * t) + r * 0.06 * t * t) for t in np.linspace(1, -1, 15)]
    draw.polygon(top + bottom, fill=(16, 10, 8, 255))
    inner_top = [(x, y + r * 0.04) for x, y in top[3:-3]]
    inner_bottom = [(x, y - r * 0.03) for x, y in bottom[3:-3]]
    glow_color = tuple(int(v * 0.75) for v in BALL_EYE)
    draw.polygon(inner_top + inner_bottom, fill=(*glow_color, 255))
    for k in range(5):
        t = -0.6 + k * 0.3
        x = ox + half * t
        y = mouth_y - r * 0.05 * (1.0 - t * t) + r * 0.06 * t * t
        w = r * 0.045
        draw.polygon(((x - w, y + r * 0.01), (x + w, y + r * 0.01), (x, y + r * 0.075)), fill=(*BALL_TEETH, 255))
    data = np.asarray(face, np.float32)
    canvas.over(data[..., :3], data[..., 3] / 255.0, x0, y0)


# --- Mech a tráva ---

## Hloubka pixelu od horního okraje písmene. Svislé stěny mech nedostanou.
def depth_from_top(inside: np.ndarray) -> np.ndarray:
    depth = np.zeros(inside.shape, np.float32)
    run = np.zeros(inside.shape[1], np.float32)
    for y in range(inside.shape[0]):
        run = np.where(inside[y], run + 1.0, 0.0)
        depth[y] = run
    return depth


def moss(canvas: Canvas, letter: Letter, rng: np.random.Generator, tops: list) -> None:
    share = KINDS[letter.kind]["moss"]
    if share <= 0.0:
        return
    inside = letter.inside
    h, w = inside.shape
    depth = depth_from_top(inside)
    patches = fbm((h, w), 34 * SS, 2, rng)
    thick = (5.0 + 12.0 * fbm((h, w), 16 * SS, 2, rng)) * SS
    cover = (depth > 0) & (depth < thick) & (patches > 1.0 - share)
    # Mech je měkký a stéká kousek dolů po stěnách.
    soft = ndimage.gaussian_filter(cover.astype(np.float32), 1.2 * SS)
    soft = np.clip(soft * 1.6, 0.0, 1.0) * inside
    if soft.max() <= 0.0:
        return
    tone = fbm((h, w), 4 * SS, 3, rng)
    color = rgb(MOSS[0]) * (1.0 - tone[..., None]) + rgb(MOSS[1]) * tone[..., None]
    light = np.clip(1.0 - depth / (thick + 1.0), 0.0, 1.0)
    color = color * (1.0 - light[..., None] * 0.5) + rgb(MOSS[2]) * light[..., None] * 0.5
    speck = (fbm((h, w), 1.5 * SS, 1, rng) > 0.78)[..., None]
    color = np.where(speck, color * 1.25, color)
    canvas.over(np.clip(color, 0, 255), soft.astype(np.float32), letter.x0, letter.y0)
    # Horní kraj mechu: místa pro trávu.
    edge = cover & (depth <= 1.5) & (soft > 0.5)
    # Jen vodorovné kusy okraje, na šikmých by tráva visela ve vzduchu.
    reach = 4 * SS
    flat = np.zeros_like(edge)
    flat[:, reach:-reach] = (depth[:, :-2 * reach] > 0) & (depth[:, :-2 * reach] < 3 * SS)         & (depth[:, 2 * reach:] > 0) & (depth[:, 2 * reach:] < 3 * SS)
    ys, xs = np.nonzero(edge & flat)
    for i in range(len(xs)):
        tops.append((letter.x0 + xs[i], letter.y0 + ys[i]))


def bumps(draw: ImageDraw.ImageDraw, tops: list, rng: np.random.Generator) -> None:
    for _ in range(len(tops) // (6 * SS)):
        x, y = tops[rng.integers(len(tops))]
        r = rng.uniform(1.6, 4.0) * SS
        color = MOSS[rng.integers(1, 3)]
        draw.ellipse((x - r, y - r * 0.9, x + r, y + r * 0.6), fill=(*color, 255))


def blade(draw: ImageDraw.ImageDraw, x: float, y: float, length: float, lean: float, width: float, color) -> None:
    points_l = []
    points_r = []
    steps = 8
    for i in range(steps + 1):
        t = i / steps
        bx = x + lean * t * t * length
        by = y - length * t
        half = width * (1.0 - t) ** 0.8
        points_l.append((bx - half, by))
        points_r.append((bx + half, by))
    draw.polygon(points_l + points_r[::-1], fill=(*color, 255))


def tufts(draw: ImageDraw.ImageDraw, tops: list, rng: np.random.Generator) -> None:
    if not tops:
        return
    for _ in range(min(len(tops) // (70 * SS), 9)):
        x, y = tops[rng.integers(len(tops))]
        for _ in range(rng.integers(3, 8)):
            color = GRASS[rng.integers(len(GRASS))]
            blade(draw, x + rng.uniform(-6, 6) * SS, y + 2 * SS, rng.uniform(12, 30) * SS,
                  rng.uniform(-0.55, 0.55), rng.uniform(1.4, 2.4) * SS, color)


# --- Podtitul ---

## Podtitul „GAME“ z drobných zlatých kusů, po stranách linky s kosočtverci.
def subtitle(canvas: Canvas, rng: np.random.Generator) -> None:
    lines = (("GAME", ("zlato",) * 4),)
    glyphs = layout(canvas, lines, (SUB_Y,), SUB_CAP, rng, inlays=False, gap=0.5)
    draw_glyphs(canvas, glyphs, rng, None, moss_on=False, scale=SUB_CAP / CAP)
    start = min(g.union.x0 for g in glyphs)
    end = max(g.union.x0 + g.union.shape[1] for g in glyphs)
    words = Image.new("RGBA", (canvas.w, canvas.h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(words)
    gap_px = 30 * SS
    length = 220 * SS
    line_y = SUB_Y * SS
    for a, b in ((start - gap_px - length, start - gap_px), (end + gap_px, end + gap_px + length)):
        draw.line((a, line_y, b, line_y), fill=(*ACCENT, 150), width=int(2 * SS))
    canvas.layer(words)
    # Konce linek zdobí malé zlaté kameny jako v nápisu.
    for gx, r in ((start - gap_px - length, 7), (end + gap_px + length, 7), (start - gap_px * 0.5, 9), (end + gap_px * 0.5, 9)):
        piece = gem_piece("", "zlato", gx, line_y, r * SS, rng)
        canvas.over(piece.color, piece.alpha, piece.x0, piece.y0)


## Písmena se stínem, spárami, třpytem a mechem.
def lettering(canvas: Canvas, lines: tuple, line_y: tuple, eyes_at: tuple | None, rng: np.random.Generator) -> None:
    ball_at = -1 if eyes_at is None else sum(len(text) for text, _ in lines[:eyes_at[0]]) + eyes_at[1]
    glyphs = layout(canvas, lines, line_y, CAP, rng, ball_at=ball_at)
    owl = None if ball_at < 0 else glyphs[ball_at]
    draw_glyphs(canvas, glyphs, rng, owl, moss_on=True, scale=1.0)


def draw_glyphs(canvas: Canvas, glyphs: list[Glyph], rng: np.random.Generator, owl: Glyph | None,
                moss_on: bool, scale: float) -> None:
    chunks = [chunk for g in glyphs for chunk in g.chunks]
    # Obrys a stín pod celým nápisem. Spáry mezi kusy jsou díky tomu tmavé.
    shadow_and_outline(canvas, union(chunks, canvas), scale)
    shine = Image.new("RGBA", (canvas.w, canvas.h), (0, 0, 0, 0))
    for chunk in chunks:
        canvas.over(chunk.color, chunk.alpha, chunk.x0, chunk.y0)
        sparkles(ImageDraw.Draw(shine), chunk, chunk.light, rng, scale)
    if owl is not None and owl.ball is not None:
        ball_face(canvas, *owl.ball)
    tops: list = []
    if moss_on:
        for g in glyphs:
            # Koule se valí, mech na ní neroste.
            if g is owl:
                continue
            # Mech roste po celém písmenu, spáry mezi kusy ho nepřeruší.
            whole = Letter(g.char, g.material, g.union.x0, g.union.y0,
                           ndimage.binary_closing(g.union.inside, iterations=int(4 * SS)) | g.union.inside)
            moss(canvas, whole, rng, tops)
    nature = Image.new("RGBA", (canvas.w, canvas.h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(nature)
    bumps(draw, tops, rng)
    tufts(draw, tops, rng)
    # Tráva má tmavý obrys jako písmena.
    alpha = nature.getchannel("A").filter(ImageFilter.MaxFilter(3 * SS + 1 if SS % 2 == 0 else 3 * SS))
    rim = Image.new("RGBA", nature.size, (*OUTLINE, 0))
    rim.putalpha(alpha.point(lambda v: int(v * 0.8)))
    canvas.layer(rim)
    canvas.layer(nature)
    canvas.layer(shine)


## Nápis se kreslí jednou na průhledné plátno. Úvodní obrazovka ho dostane na pozadí,
## hlavní menu ořezaný.
def splash(rng: np.random.Generator) -> None:
    logo = Canvas(WIDTH, HEIGHT, None)
    lettering(logo, LINES, LINE_Y, EYES, rng)
    subtitle(logo, rng)
    words = logo.image()
    back = Canvas(WIDTH, HEIGHT, BACKGROUND)
    backdrop(back)
    screen = back.image()
    screen.alpha_composite(words)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    screen.convert("RGB").save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)} {WIDTH} x {HEIGHT}")
    cropped = words.crop(words.getbbox())
    height = round(cropped.height * LOGO_WIDTH / cropped.width)
    cropped.resize((LOGO_WIDTH, height), Image.Resampling.LANCZOS).save(OUT_LOGO, optimize=True)
    print(f"{OUT_LOGO.relative_to(ROOT)} {LOGO_WIDTH} x {height}")


def mini(rng: np.random.Generator) -> None:
    canvas = Canvas(*MINI_CANVAS, None)
    lettering(canvas, MINI_LINES, (MINI_CANVAS[1] // 2 + 6,), None, rng)
    image = canvas.image()
    image = image.crop(image.getbbox())
    side = max(image.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(image, ((side - image.width) // 2, (side - image.height) // 2))
    square.resize((MINI, MINI), Image.Resampling.LANCZOS).save(OUT_MINI, optimize=True)
    print(f"{OUT_MINI.relative_to(ROOT)} {MINI} x {MINI}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    splash(np.random.default_rng(args.seed))
    mini(np.random.default_rng(args.seed + 1))


if __name__ == "__main__":
    main()
