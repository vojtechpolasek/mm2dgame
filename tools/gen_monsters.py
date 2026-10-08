#!/usr/bin/env python3
"""Příšery z pohledu shora: pavouk, vlk, ptakoještěr a tyranosaurus.

64 px je 1 m, stejně jako u postavy, skal a stromů. Kreslí se ve čtyřnásobném
rozlišení do plátna druhu (canvas). Uložená buňka vrstvy je ořezaná na obsah,
střed zůstává.

Atlas má osm sloupců, příšera jde na sever. Ostatní směry otáčí uzel v Godotu.
Počet snímků cyklu (frames) má každý druh v katalogu: pavouk a vlk 8, tyranosaurus
16, ptakoještěr 24. Delší animace se zalomí do dalších řádků (atlas_columns).
Jeden atlas slouží všem materiálům druhu, barvy dodá shader.

Vrstva nese masky, ne hotovou barvu: R světlost, G podíl akcentu (kresba,
proužky), B oči, A krytí. Barva ve hře:
  tělo = barva materiálu * mix(0.35, 1.15, R)
  kůže = mix(tělo, akcent * mix(0.6, 1.1, R), G)
  výsledek = mix(kůže, oči, B)
Který materiál patří kterému druhu, určuje gen_crystal.MATERIALS (klíč monster).
Tělo má barvu color materiálu, akcent jeho monster_accent, jinak glint. Oči mají
barvu druhu.

Chodidlo na zemi jede vůči tělu rovnoměrně dozadu. Za cyklus příšera urazí
cycle_meters z katalogu a chodidla přitom neklouzají.

Pavouk: vrstva 1 (nohy a makadla, 0 m), vrstva 2 (hlavohruď a zadeček, 0,5 m).
Kořeny nohou zajíždějí pod hlavohruď, aby se vrstvy při posunu kamery neroztrhly.
Chodí střídavě: L1 P2 L3 P4 spolu, druhá čtveřice o půl cyklu později.

Vlk: vrstva 1 (nohy, 0 m), vrstva 2 (trup, ocas a hlava, 0,75 m). Klusá:
levá přední a pravá zadní spolu, druhý pár o půl cyklu později. Srst dělají
chomáče na obrysu, hřbet má tmavší sedlo (jen světlost R), maska, hříva a
špička ocasu jsou v akcentu.

Ptakoještěr pořád letí: vrstva 1 je jeho stín na zemi (0 m, jen krytí, v katalogu
shadow), vrstva 2 je tvor ve výšce letu (4 m). Při posunu kamery se stín od tvora
vzdálí. Stín hra kreslí černě s krytím shadow_alpha z katalogu. Cyklus je jedno
mávnutí: dolů jde křídlo roztažené, nahoru složené v zápěstí. Snímek glide_frame
se hodí na plachtění. Hřbet je tmavší a nohy jen vykukují zpod těla, aby tvor
nepůsobil jako zespodu. Konce křídel jsou v akcentu.

Tyranosaurus: vrstva 1 (nohy, 0 m), vrstva 2 (stehna, trup, ocas, ruce a hlava,
1,2 m). Holeň začíná pod stehnem, chodidlo vykukuje vedle břicha a kořene ocasu.
Kyčle se kývají k noze na zemi, ocas se vlní a hlava kývá proti kyčlím.

Atlasy jdou do godot/graphics/characters/monsters, náhledy do tools/preview.

  py tools/gen_monsters.py
  py tools/gen_monsters.py --name tyranosaurus
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Callable

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from gen_crystal import MATERIALS, parse_hex
from gen_trees import blank, contact_sheet, crop_square, on_grass, pack_atlas

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "characters" / "monsters"
INFO_PATH = OUT_DIR / "monsters.json"
PREVIEW = ROOT / "tools" / "preview"

PX_PER_METER = 64
# Atlas má tolik sloupců, delší animace se zalomí do dalších řádků.
COLUMNS = 8
# Délka jednoho cyklu v náhledových GIFech, pokud ho druh nepřepíše.
PREVIEW_CYCLE_MS = 720
# Kolik snímků ukáže přehled _chuz.png. Delší animace ukáže jen každý n-tý.
SHEET_FRAMES = 8
SS = 4
# Stejné číslo jako ObjectLayers.PARALLAX. Náhled „u kraje“ je příšera 480 px vpravo a 260 px pod středem okna.
PARALLAX = 0.016
EDGE = (480.0 * PARALLAX, 260.0 * PARALLAX)
# Rozsah světlosti R pro barvu těla a pro barvu akcentu.
SHADE = (0.35, 1.15)
ACCENT_SHADE = (0.6, 1.1)
# Krytí stínové vrstvy, kreslí se černě.
SHADOW_ALPHA = 0.35
# Počet soustředných pásů, ze kterých se skládá stínovaná trubice.
TUBE_BANDS = 16

Point = tuple[float, float]

# Pavouk. Souřadnice jsou v px od středu plátna, záporné Y je vpřed.
# Střed je zadní kraj hlavohrudi, kolem něj se pavouk ve hře otáčí.
SPIDER_CANVAS = 128
PROSOMA = (0.0, -1.0)
PROSOMA_R = (10.0, 11.5)
ABDOMEN = (0.0, 24.0)
ABDOMEN_R = (13.5, 16.5)
# Zadeček se kolem stopky kývá do stran, ve stupních.
PEDICEL = (0.0, 9.0)
SWAY = 4.0
# Kyčel, chodidlo v klidu a ohyb kolena pravé strany od předu. Levá strana je zrcadlo.
# Kladný ohyb posune koleno dozadu, přední nohy pak špičkou míří dopředu.
LEGS: tuple[tuple[Point, Point, float], ...] = (
    ((4.5, -8.0), (24.0, -40.0), 5.0),
    ((7.5, -4.0), (40.0, -17.0), 3.0),
    ((8.5, 1.0), (41.0, 12.0), -3.0),
    ((6.5, 5.5), (30.0, 40.0), -5.0),
)
# Stehno a holeň jako násobek klidové vzdálenosti kyčle od chodidla.
FEMUR = 0.68
TIBIA = 0.80
# Poloměr nohy u kyčle, v koleni a na špičce.
LEG_RADIUS = (2.5, 2.0, 1.3)
# Světlé kroužky na holeni, od kolena ke špičce jako díl délky.
LEG_BANDS = ((0.0, 0.12), (0.5, 0.62))
# Výšky v px. Kyčel je pod hlavohrudí. Světlost nohy roste s výškou až do TOP_Z.
HIP_Z = 9.0
TOP_Z = 26.0
# Chodidlo na zemi ujede vůči tělu STRIDE px dozadu. Cyklus jsou dva kroky.
STRIDE = 16.0
LIFT = 9.0
# Zvednuté chodidlo se přitáhne ke kyčli o tenhle díl vzdálenosti.
PULL = 0.15
# Kořen nohy je takový díl cesty od kyčle ke středu hlavohrudi.
TUCK = 0.6
# Makadlo pravé strany: kořen, kyčel, koleno, špička a jejich výšky.
PALP: tuple[Point, ...] = ((2.5, -6.0), (4.0, -10.5), (7.0, -14.5), (5.0, -19.5))
PALP_Z = (9.0, 9.0, 14.0, 5.0)
PALP_RADIUS = (1.8, 1.6, 1.9)
PALP_WIGGLE = 1.4
# Oči pravé strany: střed a poloměr. Přední pár je největší.
EYES = (
    ((1.8, -9.8), 1.4),
    ((5.0, -8.4), 1.0),
    ((2.4, -6.4), 0.8),
    ((5.7, -5.4), 0.9),
)
# Kříž a krokve na zadečku, v poloměrech zadečku. Poslední číslo je síla akcentu.
CROSS = (
    ((0.0, -0.56), 1.5, 1.0),
    ((0.0, -0.28), 2.1, 1.0),
    ((0.0, 0.02), 1.7, 1.0),
    ((0.0, 0.30), 1.3, 1.0),
    ((-0.36, -0.28), 1.5, 1.0),
    ((0.36, -0.28), 1.5, 1.0),
)
CHEVRONS = (0.50, 0.68, 0.84)

# Vlk, asi 2 m od čenichu po špičku ocasu. Střed plátna je uprostřed trupu.
WOLF_CANVAS = 176
# Trup od šíje po záď: Y a poloviční šířka v px. Nejširší je hříva na plecích.
WOLF_BODY = (
    (-32.0, 10.0),
    (-25.0, 14.0),
    (-17.0, 17.0),
    (-7.0, 16.0),
    (3.0, 14.0),
    (11.0, 12.5),
    (18.0, 13.5),
    (24.0, 12.0),
    (29.0, 8.0),
)
# Hlava od týla po čenich, klín. Nejširší jsou líce.
WOLF_HEAD = (
    (-29.0, 10.0),
    (-34.0, 12.5),
    (-40.0, 11.5),
    (-45.0, 9.0),
    (-50.0, 7.0),
    (-55.0, 5.4),
    (-60.0, 4.2),
    (-62.5, 3.0),
)
WOLF_NECK = -29.0
WOLF_TAIL = (
    (26.0, 6.0),
    (33.0, 8.5),
    (43.0, 10.0),
    (53.0, 9.5),
    (62.0, 6.5),
    (69.0, 2.8),
)
WOLF_TAIL_WAVE = 6.0
# Od tohoto dílu délky je ocas v barvě akcentu.
WOLF_TAIL_TIP = 0.72
# Plece a záď se v klusu kývají na opačné strany, v px. Hlava se natáčí ve stupních.
WOLF_FLEX = 1.2
WOLF_HEAD_YAW = 2.5
# Kloub a tlapa v klidu pravé strany, přední a zadní noha.
WOLF_LEGS: tuple[tuple[Point, Point], ...] = (
    ((9.0, -13.0), (16.0, -16.0)),
    ((9.0, 17.0), (15.0, 19.0)),
)
WOLF_STRIDE = 40.0
WOLF_PULL = 0.1
WOLF_TOES = (-36.0, -12.0, 12.0, 36.0)
# Sedlo tmavne ke hřbetu po pruzích: šířka pruhu jako díl šířky trupu a kolik světlosti trupu mu zůstane.
WOLF_SADDLE = ((0.78, 0.94), (0.68, 0.88), (0.58, 0.82), (0.48, 0.76), (0.38, 0.72))
WOLF_SADDLE_Y = (-20.0, 24.0)
WOLF_EYE = ((4.4, -44.5), 1.5)
# Světlý čenich a líce u okraje hlavy: od, do, poloměr a síla akcentu.
WOLF_MUZZLE = ((0.0, -47.0), (0.0, -56.5), 4.0, 0.55)
WOLF_CHEEK = ((9.2, -32.5), (8.8, -40.0), 2.0, 0.55)
# Ucho pravé strany: vnitřní a vnější kraj kořene, špička. Sedí v zadním rohu lebky a míří dozadu ven.
# Tmavý lem ho oddělí od hlavy i u světlých materiálů.
WOLF_EAR: tuple[Point, ...] = ((3.6, -35.5), (9.4, -38.5), (10.6, -29.0))

# Ptakoještěr, rozpětí asi 3,2 m. Střed plátna je mezi rameny a kyčlemi.
PTERO_CANVAS = 240
PTERO_HEIGHT = 4.0
# Za jedno mávnutí uletí tolik metrů. Mávání je pomalé a velké, proto víc snímků.
PTERO_CYCLE = 2.5
PTERO_FRAMES = 24
# Ve čtvrtině mávnutí jsou křídla vodorovně a roztažená, ten snímek se hodí na plachtění.
PTERO_GLIDE_FRAME = PTERO_FRAMES // 4
# Největší náklon křídla ve stupních a jak moc se křídlo při švihu nahoru složí.
PTERO_FLAP = 70.0
PTERO_FOLD = 0.75
# Rameno pravého křídla. Kosti (pažní, předloktí, prst): délka, úhel roztaženého a složeného křídla.
# Úhel 0 míří ven, kladný dozadu.
PTERO_SHOULDER = (7.0, -8.0)
PTERO_BONES = ((22.0, -8.0, 15.0), (20.0, -12.0, 35.0), (55.0, 24.0, 55.0))
# Náběžná hrana začíná na trupu před ramenem. Blána před předloktím vystupuje o PTERO_PROPATAGIUM px.
PTERO_ROOT: tuple[Point, ...] = ((1.0, -9.0), (6.0, -12.0))
PTERO_PROPATAGIUM = 4.0
# Odtoková hrana od trupu ke špičce: kořen na trupu a kotník, hloubka blány za loktem
# a zápěstím, pak díl délky prstu a hloubka blány za ním.
PTERO_TRAIL_ROOT: tuple[Point, ...] = ((1.0, 16.0), (6.5, 24.0))
PTERO_TRAIL_ELBOW = 24.0
PTERO_TRAIL_WRIST = 19.0
PTERO_TRAIL = ((0.15, 14.0), (0.45, 10.0), (0.75, 5.0))
PTERO_SAMPLES = 40
# Konec křídla v barvě akcentu: odkud podél rozpětí začíná, kolik kroků a váha u špičky.
PTERO_TIP = (0.6, 6, 0.85)
# Svaly pravého ramene na hřbetě: střed a poloosy.
PTERO_SHOULDER_DOME = ((6.5, -7.0), (4.2, 5.2))
# Tmavší hřbet jako u vlka: šířka pruhu jako díl šířky trupu a kolik světlosti trupu mu zůstane.
PTERO_SADDLE = ((0.62, 0.95), (0.52, 0.88), (0.42, 0.81), (0.32, 0.75), (0.22, 0.7))
PTERO_SADDLE_Y = (-14.0, 21.0)
# Krk se kreslí pod trup, hruď se k němu vpředu zúží.
PTERO_BODY = (
    (-16.0, 3.4),
    (-11.0, 7.6),
    (-4.0, 9.2),
    (3.0, 8.0),
    (10.0, 5.8),
    (16.0, 3.6),
    (20.0, 2.2),
    (23.0, 1.0),
)
PTERO_NECK = ((-12.0, 3.4), (-17.0, 3.1), (-22.0, 2.9))
# Oválná lebka za zúženým krkem a kratší zobák, aby se hlava shora četla jako hlava.
PTERO_HEAD = (
    (-22.5, 2.7),
    (-24.5, 6.0),
    (-28.0, 7.0),
    (-32.0, 6.2),
    (-36.0, 4.4),
    (-42.0, 3.0),
    (-48.0, 1.9),
    (-55.0, 0.7),
)
PTERO_HEAD_YAW = 2.0
PTERO_EYE = ((4.7, -28.5), 1.5)
PTERO_EYE_RIM = 0.45
# Noha pravé strany: kyčel, koleno, chodidlo. Kreslí se pod blánu a trup, vykukuje jen holeň a prsty.
PTERO_LEG: tuple[Point, ...] = ((2.5, 14.0), (4.0, 21.0), (4.6, 28.0))

# Tyranosaurus, asi 3,2 m od čenichu po špičku ocasu. Kyčle jsou ve středu plátna.
REX_CANVAS = 256
# Páteř trupu od šíje po špičku ocasu: Y a poloviční šířka v px.
REX_BODY = (
    (-62.0, 12.0),
    (-52.0, 14.0),
    (-40.0, 21.0),
    (-26.0, 25.0),
    (-10.0, 24.0),
    (4.0, 20.0),
    (16.0, 17.0),
    (34.0, 13.5),
    (54.0, 9.5),
    (74.0, 6.0),
    (92.0, 3.2),
    (106.0, 1.2),
)
# Hlava od zátylku po čenich, napojená na šíji. Nejširší je za očima, čenich je tupý.
REX_HEAD = (
    (-63.0, 14.0),
    (-68.0, 17.5),
    (-75.0, 17.0),
    (-84.0, 13.5),
    (-93.0, 10.5),
    (-100.0, 8.0),
    (-103.0, 5.5),
)
REX_NECK = -62.0
# Krk se od téhle Y stáčí proti kyčlím, ocas se od téhle Y vlní.
REX_NECK_FROM = -40.0
REX_TAIL_FROM = 6.0
REX_TAIL_LENGTH = 100.0
REX_TAIL_WAVE = 9.0
# Boční kývání kyčlí v px a natočení hlavy ve stupních.
REX_SWAY = 2.2
REX_HEAD_YAW = 3.0
# Kyčelní kloub a chodidlo v klidu, pravá strana.
REX_HIP = (17.0, 2.0)
REX_FOOT = (29.0, 2.0)
REX_STRIDE = 70.0
REX_PULL = 0.12
# Prsty od vnitřního, úhel od směru vpřed ve stupních a délka. Chodidlo se lehce stáčí ven.
REX_TOES = ((-26.0, 14.0), (0.0, 19.0), (26.0, 14.0))
REX_TOE_OUT = 8.0
# Pruhy přes hřbet: Y středu. Kraje pruhu zaostávají dozadu, pruh je krokev mířící vpřed.
REX_STRIPES = (-34.0, -22.0, -10.0, 4.0, 18.0, 32.0, 46.0, 60.0, 74.0)
REX_STRIPE_LAG = 3.5
# Ruka pravé strany: rameno, loket, dlaň.
REX_ARM: tuple[Point, ...] = ((14.0, -36.0), (24.5, -39.0), (21.0, -48.0))
REX_EYE = ((12.0, -74.0), 2.2)
REX_HORN = ((10.0, -78.0), (11.8, -82.0))
REX_NOSTRIL = ((3.6, -100.0), 1.1)

# Druhy. Materiály druhu a jejich barvy jsou v gen_crystal.MATERIALS.
# preview_shadow je obdélník elipsy stínu jen v náhledech, ve hře se nekreslí.
# Vrstva se shadow je skutečný stín v atlasu. info se zkopíruje do katalogu.
# frames je počet snímků jednoho cyklu. preview_cycle_ms je délka cyklu v náhledových GIFech.
# Pohyb ve hře: wander_meters je volné toulání, chase_meters honička za postavou, která nese
# materiál druhu (postava běží 4,5 m/s). body_meters je poloměr těla pro překážky a dotek.
# small jde přeskočit (postava a tyranosaurus přes něj skočí). jump_meters je výška překážky,
# přes kterou druh skočí, 0 neskáče.
MONSTERS = {
    "pavouk": {
        "canvas": SPIDER_CANVAS,
        "preview_shadow": ((-15.0, -12.0), (15.0, 40.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 0.5, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * STRIDE / PX_PER_METER,
        "frames": 8,
        "wander_meters": 0.8,
        "chase_meters": 4.0,
        "body_meters": 0.45,
        "small": True,
        "eye": "F04A2C",
    },
    "vlk": {
        "canvas": WOLF_CANVAS,
        "preview_shadow": ((-17.0, -46.0), (17.0, 30.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 0.75, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * WOLF_STRIDE / PX_PER_METER,
        "frames": 8,
        "wander_meters": 1.0,
        "chase_meters": 4.5,
        "body_meters": 0.45,
        "small": True,
        "eye": "FFD23A",
    },
    "ptakojester": {
        "canvas": PTERO_CANVAS,
        "preview_shadow": None,
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png", "shadow": True},
            2: {"height": PTERO_HEIGHT, "file": "layer_2.png"},
        },
        "cycle_meters": PTERO_CYCLE,
        "frames": PTERO_FRAMES,
        "info": {"flying": True, "glide_frame": PTERO_GLIDE_FRAME},
        "preview_cycle_ms": 1600,
        "wander_meters": 1.5,
        "chase_meters": 5.0,
        "body_meters": 0.8,
        "eye": "7DF2FF",
    },
    "tyranosaurus": {
        "canvas": REX_CANVAS,
        "preview_shadow": ((-28.0, -72.0), (28.0, 70.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 1.2, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * REX_STRIDE / PX_PER_METER,
        "frames": 16,
        "wander_meters": 0.8,
        "chase_meters": 5.5,
        "body_meters": 0.55,
        "jump_meters": 2.5,
        "eye": "FFC21A",
    },
}


def byte(value: float) -> int:
    return max(0, min(255, round(value * 255)))


def lerp(a: Point, b: Point, t: float) -> Point:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def rotate(point: Point, angle: float) -> Point:
    c, s = math.cos(angle), math.sin(angle)
    return (point[0] * c - point[1] * s, point[0] * s + point[1] * c)


def mirror(point: Point, side: float) -> Point:
    return (point[0] * side, point[1])


def spine_normals(spine: list[Point]) -> list[Point]:
    normals = []
    for index in range(len(spine)):
        a = spine[max(index - 1, 0)]
        b = spine[min(index + 1, len(spine) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1.0
        normals.append((-dy / length, dx / length))
    return normals


class Layer:
    """Masky jedné vrstvy ve čtyřnásobném rozlišení: světlost, akcent, oči, krytí.

    Pozdější tvar přepíše dřívější. None nechá kanál, jak byl.
    """

    def __init__(self, canvas: int) -> None:
        self.canvas = canvas
        size = canvas * SS
        self.channels = [Image.new("L", (size, size), 0) for _ in range(4)]
        self.draws = [ImageDraw.Draw(channel) for channel in self.channels]

    def px(self, point: Point) -> Point:
        return ((self.canvas / 2 + point[0]) * SS, (self.canvas / 2 + point[1]) * SS)

    def _fill(self, shade: float | None, accent: float | None, eye: float | None):
        for draw, value in zip(self.draws, (shade, accent, eye, 1.0)):
            if value is not None:
                yield draw, byte(value)

    def polygon(self, points: list[Point], shade: float | None, accent: float | None = 0.0, eye: float | None = 0.0) -> None:
        outline = [self.px(point) for point in points]
        for draw, value in self._fill(shade, accent, eye):
            draw.polygon(outline, fill=value)

    def disk(self, center: Point, radius: float, shade: float | None, accent: float | None = 0.0, eye: float | None = 0.0) -> None:
        x, y = self.px(center)
        r = radius * SS
        for draw, value in self._fill(shade, accent, eye):
            draw.ellipse((x - r, y - r, x + r, y + r), fill=value)

    def capsule(
        self,
        start: Point,
        end: Point,
        r0: float,
        r1: float,
        shade: float | None,
        accent: float | None = 0.0,
        eye: float | None = 0.0,
    ) -> None:
        ax, ay = self.px(start)
        bx, by = self.px(end)
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        a, b = r0 * SS, r1 * SS
        outline = [(ax + nx * a, ay + ny * a), (bx + nx * b, by + ny * b), (bx - nx * b, by - ny * b), (ax - nx * a, ay - ny * a)]
        for draw, value in self._fill(shade, accent, eye):
            draw.polygon(outline, fill=value)
            draw.ellipse((ax - a, ay - a, ax + a, ay + a), fill=value)
            draw.ellipse((bx - b, by - b, bx + b, by + b), fill=value)

    def dome(self, center: Point, radii: Point, angle: float, low: float, high: float) -> None:
        """Elipsa osvětlená shora. Světlo je kolmé, takže otočení uzlu stínům nevadí."""
        cx, cy = self.px(center)
        rx, ry = radii[0] * SS, radii[1] * SS
        c, s = math.cos(angle), math.sin(angle)
        reach = max(rx, ry)
        limit = self.canvas * SS
        x0, x1 = max(0, math.floor(cx - reach)), min(limit, math.ceil(cx + reach))
        y0, y1 = max(0, math.floor(cy - reach)), min(limit, math.ceil(cy + reach))
        shade, accent, eye, alpha = (channel.load() for channel in self.channels)
        for py in range(y0, y1):
            dy = py + 0.5 - cy
            for px in range(x0, x1):
                dx = px + 0.5 - cx
                u = (dx * c + dy * s) / rx
                v = (-dx * s + dy * c) / ry
                r2 = u * u + v * v
                if r2 > 1.0:
                    continue
                shade[px, py] = byte(low + (high - low) * (1.0 - r2) ** 0.4)
                accent[px, py] = 0
                eye[px, py] = 0
                alpha[px, py] = 255

    def tube(
        self,
        spine: list[Point],
        widths: list[float],
        low: float,
        high: float,
        accent: float | None = 0.0,
        depth: float = 1.0,
    ) -> None:
        """Trubice podél páteře se zaoblenými konci, osvětlená shora jako dome.

        Skládá se ze soustředných pásů, vnitřní pás je nejsvětlejší. depth je šířka
        vůči trubici pod ní: stín pak navazuje, jako by šlo o její střední pruh.
        """
        normals = spine_normals(spine)
        for band in range(TUBE_BANDS):
            outer = 1.0 - band / TUBE_BANDS
            mid = (1.0 - (band + 0.5) / TUBE_BANDS) * depth
            value = low + (high - low) * (1.0 - mid * mid) ** 0.4
            left = [(p[0] + n[0] * w * outer, p[1] + n[1] * w * outer) for p, n, w in zip(spine, normals, widths)]
            right = [(p[0] - n[0] * w * outer, p[1] - n[1] * w * outer) for p, n, w in zip(spine, normals, widths)]
            self.polygon(left + right[::-1], value, accent)
            self.disk(spine[0], widths[0] * outer, value, accent)
            self.disk(spine[-1], widths[-1] * outer, value, accent)

    def shadow(self, blur: float = 1.2) -> Layer:
        """Stín vrstvy na zemi: jen krytí, rozmazané o blur px."""
        out = Layer(self.canvas)
        out.channels[3] = self.channels[3].filter(ImageFilter.GaussianBlur(blur * SS))
        out.draws[3] = ImageDraw.Draw(out.channels[3])
        return out


def foot_at(hip: Point, rest: Point, phase: float, stride: float, pull: float) -> tuple[Point, float]:
    """První polovina cyklu na zemi, druhá ve vzduchu. Vrací chodidlo a zvednutí 0 až 1."""
    if phase < 0.5:
        return (rest[0], rest[1] - stride / 2 + stride * phase / 0.5), 0.0
    s = (phase - 0.5) / 0.5
    ease = s * s * (3.0 - 2.0 * s)
    lift = math.sin(math.pi * s)
    foot = (rest[0], rest[1] + stride / 2 - stride * ease)
    return lerp(foot, hip, pull * lift), lift


def height_shade(z: float) -> float:
    return 0.12 + 0.78 * max(0.0, min(1.0, z / TOP_Z))


def stroke(
    layer: Layer,
    start: Point,
    end: Point,
    z0: float,
    z1: float,
    r0: float,
    r1: float,
    bands: tuple[tuple[float, float], ...] = (),
    steps: int = 10,
) -> None:
    """Článek končetiny po kouscích, každý má světlost podle své výšky."""
    for step in range(steps):
        t0, t1 = step / steps, (step + 1) / steps
        mid = (t0 + t1) * 0.5
        accent = 0.85 if any(lo <= mid < hi for lo, hi in bands) else 0.0
        layer.capsule(
            lerp(start, end, t0),
            lerp(start, end, t1),
            r0 + (r1 - r0) * t0,
            r0 + (r1 - r0) * t1,
            height_shade(z0 + (z1 - z0) * mid),
            accent,
        )


def leg_phase(index: int, side: float, t: float) -> float:
    group = (index + (1 if side > 0 else 0)) % 2
    return (t + 0.5 * group) % 1.0


def knee_of(hip: Point, foot: Point, foot_z: float, femur: float, tibia: float, bend: float) -> tuple[Point, float]:
    """Koleno ve svislé rovině kyčle a chodidla, shora jen kousek vybočené."""
    dx, dy = foot[0] - hip[0], foot[1] - hip[1]
    flat = math.hypot(dx, dy) or 1.0
    rise = foot_z - HIP_Z
    reach = min(math.hypot(flat, rise), (femur + tibia) * 0.999)
    cos_hip = (femur * femur + reach * reach - tibia * tibia) / (2.0 * femur * reach)
    angle = math.atan2(rise, flat) + math.acos(max(-1.0, min(1.0, cos_hip)))
    along = femur * math.cos(angle)
    ux, uy = dx / flat, dy / flat
    nx, ny = -uy, ux
    if ny * bend < 0.0:
        nx, ny = -nx, -ny
    knee = (hip[0] + ux * along + nx * abs(bend), hip[1] + uy * along + ny * abs(bend))
    return knee, HIP_Z + femur * math.sin(angle)


def paint_leg(layer: Layer, index: int, side: float, t: float) -> None:
    hip_r, rest_r, bend = LEGS[index]
    hip, rest = mirror(hip_r, side), mirror(rest_r, side)
    reach = math.dist(hip, rest)
    foot, lift = foot_at(hip, rest, leg_phase(index, side, t), STRIDE, PULL)
    knee, knee_z = knee_of(hip, foot, LIFT * lift, reach * FEMUR, reach * TIBIA, bend)
    r_hip, r_knee, r_tip = LEG_RADIUS
    layer.capsule(lerp(hip, PROSOMA, TUCK), hip, r_hip, r_hip, height_shade(HIP_Z))
    stroke(layer, hip, knee, HIP_Z, knee_z, r_hip, r_knee)
    stroke(layer, knee, foot, knee_z, LIFT * lift, r_knee, r_tip, LEG_BANDS)


def paint_palp(layer: Layer, side: float, t: float) -> None:
    points = [mirror(point, side) for point in PALP]
    wiggle = PALP_WIGGLE * math.sin(math.tau * t + (0.0 if side > 0 else math.pi))
    points[3] = (points[3][0], points[3][1] + wiggle)
    points[2] = (points[2][0], points[2][1] + wiggle * 0.5)
    r_hip, r_knee, r_tip = PALP_RADIUS
    layer.capsule(points[0], points[1], r_hip, r_hip, height_shade(PALP_Z[0]))
    stroke(layer, points[1], points[2], PALP_Z[1], PALP_Z[2], r_hip, r_knee, steps=4)
    stroke(layer, points[2], points[3], PALP_Z[2], PALP_Z[3], r_knee, r_tip, steps=4)


def abdomen_point(center: Point, angle: float, local: Point) -> Point:
    offset = rotate((local[0] * ABDOMEN_R[0], local[1] * ABDOMEN_R[1]), angle)
    return (center[0] + offset[0], center[1] + offset[1])


def paint_spider_body(layer: Layer, t: float) -> None:
    for side in (-1.0, 1.0):
        layer.dome((side * 2.6, -13.2), (2.3, 3.2), 0.0, 0.15, 0.45)
        layer.disk((side * 1.7, -16.0), 0.9, 0.06)
    layer.dome(PROSOMA, PROSOMA_R, 0.0, 0.28, 0.86)
    layer.capsule((0.0, -4.5), (0.0, 7.5), 1.5, 1.0, None, 0.65)
    for side in (-1.0, 1.0):
        for center, radius in EYES:
            layer.disk(mirror(center, side), radius, None, 0.0, 1.0)

    sway = math.radians(SWAY) * math.sin(math.tau * t)
    offset = rotate((ABDOMEN[0] - PEDICEL[0], ABDOMEN[1] - PEDICEL[1]), sway)
    center = (PEDICEL[0] + offset[0], PEDICEL[1] + offset[1])
    layer.dome(center, ABDOMEN_R, sway, 0.22, 1.0)
    for local, radius, weight in CROSS:
        layer.disk(abdomen_point(center, sway, local), radius, None, weight)
    for along in CHEVRONS:
        width = 0.5 * (1.0 - along * 0.45)
        tip = abdomen_point(center, sway, (0.0, along + 0.07))
        for side in (-1.0, 1.0):
            arm = abdomen_point(center, sway, (side * width, along - 0.07))
            layer.capsule(arm, tip, 0.9, 0.9, None, 0.6)


def spider_layers(t: float) -> dict[int, Layer]:
    legs, body = Layer(SPIDER_CANVAS), Layer(SPIDER_CANVAS)
    for index in reversed(range(len(LEGS))):
        for side in (-1.0, 1.0):
            paint_leg(legs, index, side, t)
    for side in (-1.0, 1.0):
        paint_palp(legs, side, t)
    paint_spider_body(body, t)
    return {1: legs, 2: body}


def profile(points: tuple[Point, ...], step: float = 2.0) -> list[Point]:
    """Hustá páteř z řídkých bodů (Y, poloviční šířka). Šířka mezi body plyne jako Catmull-Rom."""
    out = []
    last = len(points) - 1
    for index in range(last):
        y0, y1 = points[index][0], points[index + 1][0]
        w0 = points[max(index - 1, 0)][1]
        w1, w2 = points[index][1], points[index + 1][1]
        w3 = points[min(index + 2, last)][1]
        count = max(1, math.ceil(abs(y1 - y0) / step))
        for k in range(count):
            s = k / count
            width = 0.5 * (
                2.0 * w1
                + (w2 - w0) * s
                + (2.0 * w0 - 5.0 * w1 + 4.0 * w2 - w3) * s * s
                + (3.0 * w1 - w0 - 3.0 * w2 + w3) * s * s * s
            )
            out.append((y0 + (y1 - y0) * s, width))
    out.append(points[-1])
    return out


def line(start: Point, end: Point, count: int = 6) -> list[Point]:
    return [lerp(start, end, k / (count - 1)) for k in range(count)]


def nearest(dense: list[Point], y: float) -> int:
    return min(range(len(dense)), key=lambda index: abs(dense[index][0] - y))


def fringe(
    layer: Layer,
    spine: list[Point],
    widths: list[float],
    first: int,
    last: int,
    count: int,
    length: float,
    shade: float,
    accent: float = 0.0,
    lean: float = 0.6,
    reach: float = 0.8,
) -> None:
    """Chomáče srsti z okraje trubice ven, nakloněné dozadu. Trubice se kreslí až po nich."""
    normals = spine_normals(spine)
    for side in (-1.0, 1.0):
        for k in range(count):
            index = min(len(spine) - 1, round(first + (last - first) * (k + 0.5) / count))
            (px, py), (nx, ny), width = spine[index], normals[index], widths[index]
            nx, ny = nx * side, ny * side
            size = length * (0.7 + 0.1 * ((k * 7 + (3 if side > 0 else 0)) % 4))
            half = size * 0.55
            edge = (px + nx * width * reach, py + ny * width * reach)
            tip = (px + nx * (width + size), py + ny * (width + size) + lean * size)
            base_a = (edge[0] + ny * half, edge[1] - nx * half)
            base_b = (edge[0] - ny * half, edge[1] + nx * half)
            layer.polygon([base_a, tip, base_b], shade, accent)


def paint_paw(layer: Layer, paw: Point, lift: float) -> None:
    raise_by = 0.25 * lift
    layer.dome(paw, (3.6, 4.4), 0.0, 0.15 + raise_by, 0.6 + raise_by)
    for angle in WOLF_TOES:
        direction = rotate((0.0, -1.0), math.radians(angle))
        layer.disk((paw[0] + direction[0] * 3.4, paw[1] + direction[1] * 3.6), 1.4, 0.5 + raise_by)
        layer.disk((paw[0] + direction[0] * 5.0, paw[1] + direction[1] * 5.2), 0.55, 0.06)


def wolf_leg(layer: Layer, index: int, side: float, t: float, flex: Callable[[float], float]) -> None:
    joint_r, rest_r = WOLF_LEGS[index]
    joint = mirror(joint_r, side)
    joint = (joint[0] + flex(joint[1]), joint[1])
    paw, lift = foot_at(joint, mirror(rest_r, side), leg_phase(index, side, t), WOLF_STRIDE, WOLF_PULL)
    bend = lerp(joint, paw, 0.5)
    # Přední noha má loket venku, zadní hlezno vzadu.
    bend = (bend[0] + side * 1.0, bend[1] + 4.0) if index else (bend[0] + side * 1.5, bend[1])
    high = 0.45 + 0.25 * lift
    layer.tube(line(joint, bend, 4), [5.0, 4.6, 4.2, 3.9], 0.12, high)
    layer.tube(line(bend, paw, 4), [3.9, 3.6, 3.3, 3.0], 0.12, high)
    paint_paw(layer, paw, lift)


def wolf_tail(layer: Layer, t: float, base_x: float) -> None:
    dense = profile(WOLF_TAIL)
    first_y = WOLF_TAIL[0][0]
    length = WOLF_TAIL[-1][0] - first_y
    spine = []
    for y, _w in dense:
        s = (y - first_y) / length
        spine.append((base_x + WOLF_TAIL_WAVE * s**1.3 * math.sin(math.tau * t - 1.2 * math.pi * s), y))
    widths = [w for _y, w in dense]
    tip = round((len(spine) - 1) * WOLF_TAIL_TIP)
    last = len(spine) - 1
    fringe(layer, spine, widths, 0, tip, 14, 2.0, 0.38, lean=0.9)
    fringe(layer, spine, widths, tip, last, 6, 2.0, 0.38, 0.8, lean=0.9)
    layer.tube(spine, widths, 0.2, 0.9)
    layer.tube(spine[tip:], widths[tip:], 0.2, 0.9, 0.8)


def wolf_head(layer: Layer, t: float, neck_x: float) -> None:
    yaw = math.radians(WOLF_HEAD_YAW) * math.sin(math.tau * t + math.pi / 2)

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - WOLF_NECK), yaw)
        return (neck_x + turned[0], WOLF_NECK + turned[1])

    dense = profile(WOLF_HEAD)
    spine = [place((0.0, y)) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(layer, spine, widths, nearest(dense, -30.0), nearest(dense, -41.0), 5, 3.0, 0.4, 0.55, lean=0.8)
    layer.tube(spine, widths, 0.22, 0.95)
    start, end, radius, accent = WOLF_MUZZLE
    layer.capsule(place(start), place(end), radius, radius * 0.8, None, accent)
    for side in (-1.0, 1.0):
        start, end, radius, accent = WOLF_CHEEK
        layer.capsule(place(mirror(start, side)), place(mirror(end, side)), radius, radius * 0.8, None, accent)
        center, radius = WOLF_EYE
        layer.disk(place(mirror(center, side)), radius, None, 0.0, 1.0)
        ear = [place(mirror(point, side)) for point in WOLF_EAR]
        middle = ((ear[0][0] + ear[1][0] + ear[2][0]) / 3, (ear[0][1] + ear[1][1] + ear[2][1]) / 3)
        layer.polygon([lerp(middle, point, 1.3) for point in ear], 0.3)
        layer.polygon(ear, 0.92)
        layer.polygon([lerp(middle, point, 0.5) for point in ear], 0.66)
    layer.disk(place((0.0, -61.0)), 2.2, 0.06)


def wolf_layers(t: float) -> dict[int, Layer]:
    sway = WOLF_FLEX * math.sin(math.tau * t)

    def flex(y: float) -> float:
        return sway * -y / 30.0

    legs, body = Layer(WOLF_CANVAS), Layer(WOLF_CANVAS)
    for index in (1, 0):
        for side in (-1.0, 1.0):
            wolf_leg(legs, index, side, t, flex)

    wolf_tail(body, t, flex(WOLF_TAIL[0][0]))
    dense = profile(WOLF_BODY)
    spine = [(flex(y), y) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(body, spine, widths, nearest(dense, -31.0), nearest(dense, -11.0), 10, 3.4, 0.4, 0.45)
    fringe(body, spine, widths, nearest(dense, -9.0), nearest(dense, 24.0), 12, 1.4, 0.36)
    body.tube(spine, widths, 0.2, 1.0)
    first, last = (nearest(dense, y) for y in WOLF_SADDLE_Y)
    saddle = spine[first : last + 1]
    for ratio, dim in WOLF_SADDLE:
        saddle_w = [w * ratio for w in widths[first : last + 1]]
        body.tube(saddle, saddle_w, 0.2 * dim, dim, depth=ratio)
    wolf_head(body, t, flex(WOLF_NECK))
    return {1: legs, 2: body}


def smooth(points: list[Point], per: int = 6) -> list[Point]:
    """Catmull-Rom přes body. Krajní body zůstanou."""
    out = []
    last = len(points) - 1
    for index in range(last):
        p0, p1 = points[max(index - 1, 0)], points[index]
        p2, p3 = points[index + 1], points[min(index + 2, last)]
        for k in range(per):
            s = k / per
            out.append(
                tuple(
                    0.5
                    * (
                        2.0 * p1[c]
                        + (p2[c] - p0[c]) * s
                        + (2.0 * p0[c] - 5.0 * p1[c] + 4.0 * p2[c] - p3[c]) * s * s
                        + (3.0 * p1[c] - p0[c] - 3.0 * p2[c] + p3[c]) * s * s * s
                    )
                    for c in (0, 1)
                )
            )
    out.append(points[-1])
    return out


def resample(points: list[Point], count: int) -> list[Point]:
    """Stejně vzdálené body po lomené čáře, od prvního po poslední."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + math.dist(a, b))
    total = lengths[-1] or 1.0
    out = []
    segment = 0
    for k in range(count):
        target = total * k / (count - 1)
        while segment < len(points) - 2 and lengths[segment + 1] < target:
            segment += 1
        span = (lengths[segment + 1] - lengths[segment]) or 1.0
        out.append(lerp(points[segment], points[segment + 1], (target - lengths[segment]) / span))
    return out


def ptero_wing(t: float) -> tuple[list[Point], list[Point], list[Point], float]:
    """Pravé křídlo: náběžná a odtoková hrana od trupu ke špičce, klouby a náklon.

    Náklon zkrátí rozpětí, jak ho vidí kamera shora. Při švihu nahoru se křídlo složí.
    """
    tilt = math.radians(PTERO_FLAP) * math.cos(math.tau * t)
    fold = PTERO_FOLD * max(0.0, -math.sin(math.tau * t))
    angles = [math.radians(spread + (folded - spread) * fold) for _length, spread, folded in PTERO_BONES]
    joints = [PTERO_SHOULDER]
    for (length, _spread, _folded), angle in zip(PTERO_BONES, angles):
        x, y = joints[-1]
        joints.append((x + length * math.cos(angle), y + length * math.sin(angle)))
    shoulder, elbow, wrist, tip = joints

    def behind(point: Point, angle: float, depth: float) -> Point:
        return (point[0] - math.sin(angle) * depth, point[1] + math.cos(angle) * depth)

    arm = math.atan2(wrist[1] - shoulder[1], wrist[0] - shoulder[0])
    lead = list(PTERO_ROOT) + [behind(lerp(shoulder, wrist, 0.5), arm, -PTERO_PROPATAGIUM), wrist, tip]
    trail = list(PTERO_TRAIL_ROOT) + [
        behind(elbow, (angles[0] + angles[1]) / 2, PTERO_TRAIL_ELBOW),
        behind(wrist, (angles[1] + angles[2]) / 2, PTERO_TRAIL_WRIST),
    ]
    trail += [behind(lerp(wrist, tip, along), angles[2], depth) for along, depth in PTERO_TRAIL]
    trail.append(tip)

    def flap(point: Point) -> Point:
        return (shoulder[0] + (point[0] - shoulder[0]) * math.cos(tilt), point[1])

    return [flap(point) for point in lead], [flap(point) for point in trail], [flap(point) for point in joints], tilt


def paint_ptero_wing(layer: Layer, t: float, side: float) -> None:
    lead, trail, joints, tilt = ptero_wing(t)
    lead = [mirror(point, side) for point in resample(smooth(lead), PTERO_SAMPLES)]
    trail = [mirror(point, side) for point in resample(smooth(trail), PTERO_SAMPLES)]
    shoulder, elbow, wrist, tip = (mirror(point, side) for point in joints)
    # Vodorovné křídlo je nejsvětlejší, zvednuté o kousek světlejší než spuštěné.
    bright = 0.7 + 0.3 * math.cos(tilt) + 0.08 * math.sin(tilt)
    for band in range(TUBE_BANDS):
        reach = 1.0 - band / TUBE_BANDS
        mid = 1.0 - (band + 0.5) / TUBE_BANDS
        edge = [lerp(a, b, reach) for a, b in zip(lead, trail)]
        layer.polygon(lead + edge[::-1], (0.46 + 0.4 * (1.0 - mid) ** 0.7) * bright)
    last = len(lead) - 1
    start, steps, weight = PTERO_TIP
    for step in range(steps):
        first = round((start + (1.0 - start) * step / steps) * last)
        layer.polygon(lead[first:] + trail[first:][::-1], None, weight * (step + 1) / steps)
    # Shora kryjí kosti svaly, náběžná hrana je jen oblý val bez tmavého obrysu.
    high = 0.95 * bright
    low = 0.55 * bright
    layer.tube(line(shoulder, elbow, 3), [3.6, 3.0, 2.7], low, high)
    layer.tube(line(elbow, wrist, 3), [2.7, 2.4, 2.2], low, high)
    layer.tube(line(wrist, tip, 6), [2.2, 1.9, 1.6, 1.3, 1.0, 0.7], low, high)
    for spread in (-10.0, 10.0, 30.0):
        direction = rotate((0.0, -1.0), math.radians(side * spread))
        claw = (wrist[0] + direction[0] * 4.0, wrist[1] + direction[1] * 4.0)
        layer.capsule(wrist, claw, 0.9, 0.5, 0.4)
        layer.disk(claw, 0.55, 0.06)


def paint_ptero_leg(layer: Layer, side: float, t: float) -> None:
    hip, knee, foot = (mirror(point, side) for point in PTERO_LEG)
    foot = (foot[0], foot[1] + 0.8 * math.sin(math.tau * t))
    layer.tube(line(hip, knee, 3), [1.9, 1.7, 1.5], 0.15, 0.5)
    layer.tube(line(knee, foot, 3), [1.5, 1.3, 1.1], 0.15, 0.5)
    for spread in (-15.0, 0.0, 15.0):
        direction = rotate((0.0, 1.0), math.radians(side * spread))
        layer.capsule(foot, (foot[0] + direction[0] * 2.6, foot[1] + direction[1] * 2.6), 0.6, 0.35, 0.08)


def ptero_head(layer: Layer, t: float) -> None:
    yaw = math.radians(PTERO_HEAD_YAW) * math.sin(math.tau * t)
    pivot = PTERO_NECK[-1][0]

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - pivot), yaw)
        return (turned[0], pivot + turned[1])

    dense = profile(PTERO_HEAD)
    layer.tube([place((0.0, y)) for y, _w in dense], [w for _y, w in dense], 0.22, 0.95)
    center, radius = PTERO_EYE
    for side in (-1.0, 1.0):
        eye = place(mirror(center, side))
        layer.disk(eye, radius + PTERO_EYE_RIM, 0.1)
        layer.disk(eye, radius, None, 0.0, 1.0)


def ptero_layers(t: float) -> dict[int, Layer]:
    body = Layer(PTERO_CANVAS)
    for side in (-1.0, 1.0):
        paint_ptero_leg(body, side, t)
    for side in (-1.0, 1.0):
        paint_ptero_wing(body, t, side)
    neck = profile(PTERO_NECK)
    body.tube([(0.0, y) for y, _w in neck], [w for _y, w in neck], 0.22, 0.9)
    dense = profile(PTERO_BODY)
    spine = [(0.0, y) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(body, spine, widths, 0, len(spine) - 1, 10, 1.3, 0.35)
    body.tube(spine, widths, 0.22, 0.95)
    center, radii = PTERO_SHOULDER_DOME
    for side in (-1.0, 1.0):
        body.dome(mirror(center, side), radii, 0.0, 0.4, 0.95)
    first, last = (nearest(dense, y) for y in PTERO_SADDLE_Y)
    saddle = spine[first : last + 1]
    for ratio, dim in PTERO_SADDLE:
        body.tube(saddle, [w * ratio for w in widths[first : last + 1]], 0.22 * dim, 0.95 * dim, depth=ratio)
    ptero_head(body, t)
    return {1: body.shadow(), 2: body}


def rex_spine_x(y: float, t: float, hips: float) -> float:
    if y < REX_NECK_FROM:
        bend = min(1.0, (REX_NECK_FROM - y) / (REX_NECK_FROM - REX_NECK))
        return hips * (1.0 - 1.6 * bend)
    if y > REX_TAIL_FROM:
        s = min(1.0, (y - REX_TAIL_FROM) / REX_TAIL_LENGTH)
        return hips * (1.0 - s) + REX_TAIL_WAVE * s**1.5 * math.sin(math.tau * t - 1.6 * math.pi * s)
    return hips


def rex_leg(side: float, t: float, hips: float) -> tuple[Point, Point, Point, float]:
    """Kyčel, koleno pod stehnem, pata a zvednutí chodidla. Levá noha je na zemi v první polovině."""
    phase = (t + (0.0 if side < 0 else 0.5)) % 1.0
    hip = (side * REX_HIP[0] + hips, REX_HIP[1])
    foot, lift = foot_at(hip, mirror(REX_FOOT, side), phase, REX_STRIDE, REX_PULL)
    knee = lerp(hip, foot, 0.4)
    return hip, (knee[0] + side * 4.0, knee[1]), foot, lift


def paint_rex_foot(layer: Layer, heel: Point, side: float, lift: float) -> None:
    pad = (heel[0], heel[1] - 3.0)
    curl = 1.0 - 0.3 * lift
    raise_by = 0.25 * lift
    for angle, length in REX_TOES:
        heading = math.radians(side * (angle + REX_TOE_OUT))
        direction = rotate((0.0, -1.0), heading)
        tip = (pad[0] + direction[0] * length * curl, pad[1] + direction[1] * length * curl)
        layer.tube(line(pad, tip, 4), [4.2, 3.6, 3.0, 2.5], 0.14 + raise_by, 0.62 + raise_by)
        claw = (tip[0] + direction[0] * 4.5, tip[1] + direction[1] * 4.5)
        layer.capsule(tip, claw, 1.6, 0.6, 0.06)
    layer.dome(pad, (7.5, 8.5), 0.0, 0.16 + raise_by, 0.66 + raise_by)


def rex_head(layer: Layer, t: float, hips: float) -> None:
    yaw = math.radians(REX_HEAD_YAW) * math.sin(math.tau * t)
    neck = (rex_spine_x(REX_NECK, t, hips), REX_NECK)

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - REX_NECK), yaw)
        return (neck[0] + turned[0], neck[1] + turned[1])

    dense = profile(REX_HEAD)
    layer.tube([place((0.0, y)) for y, _w in dense], [w for _y, w in dense], 0.22, 0.95)
    for side in (-1.0, 1.0):
        horn_from, horn_to = (mirror(point, side) for point in REX_HORN)
        layer.capsule(place(horn_from), place(horn_to), 1.3, 0.8, None, 0.9)
        center, radius = REX_EYE
        layer.disk(place(mirror(center, side)), radius, None, 0.0, 1.0)
        center, radius = REX_NOSTRIL
        layer.disk(place(mirror(center, side)), radius, 0.12)


def rex_stripes(layer: Layer, spine: list[Point], widths: list[float]) -> None:
    normals = spine_normals(spine)
    ys = [point[1] for point in spine]

    def sample(y: float) -> tuple[Point, Point, float]:
        index = min(range(len(ys)), key=lambda k: abs(ys[k] - y))
        return spine[index], normals[index], widths[index]

    for y in REX_STRIPES:
        front, _n, _w = sample(y - 2.4)
        back, _n, _w = sample(y + 2.4)
        point, normal, width = sample(y + REX_STRIPE_LAG)
        reach = width * 0.82
        left = (point[0] + normal[0] * reach, point[1] + normal[1] * reach)
        right = (point[0] - normal[0] * reach, point[1] - normal[1] * reach)
        layer.polygon([front, left, back, right], None, 0.7)


def rex_arm(layer: Layer, side: float, t: float, hips: float) -> None:
    """Ruka roste z podbřišku. Kreslí se před trupem, ten zakryje rameno a ve stínu je celá."""
    swing = 1.2 * math.sin(math.tau * t + (0.0 if side > 0 else math.pi))
    shoulder, elbow, hand = (mirror(point, side) for point in REX_ARM)
    shift = rex_spine_x(shoulder[1], t, hips)
    shoulder = (shoulder[0] + shift, shoulder[1])
    elbow = (elbow[0] + shift, elbow[1] + swing * 0.5)
    hand = (hand[0] + shift, hand[1] + swing)
    layer.tube(line(shoulder, elbow, 3), [3.6, 3.3, 3.0], 0.15, 0.6)
    layer.tube(line(elbow, hand, 3), [3.0, 2.6, 2.3], 0.15, 0.6)
    for spread in (-12.0, 12.0):
        direction = rotate((0.0, -1.0), math.radians(side * spread))
        layer.capsule(hand, (hand[0] + direction[0] * 3.2, hand[1] + direction[1] * 3.2), 0.9, 0.4, 0.08)


def rex_layers(t: float) -> dict[int, Layer]:
    hips = -REX_SWAY * math.sin(math.tau * t)
    legs, body = Layer(REX_CANVAS), Layer(REX_CANVAS)

    for side in (-1.0, 1.0):
        hip, knee, heel, lift = rex_leg(side, t, hips)
        legs.tube(line(hip, knee), [10.0, 9.5, 9.0, 8.5, 8.0, 7.5], 0.15, 0.7)
        legs.tube(line(knee, heel), [7.0, 6.6, 6.2, 5.8, 5.4, 5.0], 0.12, 0.5 + 0.25 * lift)
        paint_rex_foot(legs, heel, side, lift)
        thigh = lerp(hip, heel, 0.32)
        body.tube(line(hip, (thigh[0] + side * 5.0, thigh[1])), [13.0, 12.3, 11.6, 10.9, 10.2, 9.5], 0.2, 0.82)
        rex_arm(body, side, t, hips)

    dense = profile(REX_BODY)
    spine = [(rex_spine_x(y, t, hips), y) for y, _w in dense]
    widths = [w for _y, w in dense]
    body.tube(spine, widths, 0.2, 1.0)
    rex_stripes(body, spine, widths)
    rex_head(body, t, hips)
    return {1: legs, 2: body}


# Kreslení druhu dostane fázi cyklu 0 až 1, ne číslo snímku.
RENDERERS: dict[str, Callable[[float], dict[int, Layer]]] = {
    "pavouk": spider_layers,
    "vlk": wolf_layers,
    "ptakojester": ptero_layers,
    "tyranosaurus": rex_layers,
}


def pack(layer: Layer) -> Image.Image:
    """Zmenší masky. Světlost, akcent a oči jsou průměr zakrytých vzorků, alfa je krytí."""
    shade, accent, eye, alpha = layer.channels
    cell = layer.canvas
    size = (cell, cell)
    cover = alpha.convert("F").resize(size, Image.Resampling.BOX).load()
    sums = [
        ImageChops.multiply(channel, alpha).convert("F").resize(size, Image.Resampling.BOX).load()
        for channel in (shade, accent, eye)
    ]
    out = Image.new("RGBA", size)
    target = out.load()
    for y in range(cell):
        for x in range(cell):
            a = cover[x, y]
            if a <= 0.0:
                target[x, y] = (0, 0, 0, 0)
                continue
            r, g, b = (min(255, round(total[x, y] * 255.0 / a)) for total in sums)
            target[x, y] = (r, g, b, min(255, round(a)))
    return out


def colorize(
    mask: Image.Image,
    body: tuple[int, int, int],
    accent: tuple[int, int, int],
    eye: tuple[int, int, int],
) -> Image.Image:
    """Stejný vzorec, jaký použije shader ve hře."""
    source = mask.load()
    out = Image.new("RGBA", mask.size)
    target = out.load()
    for y in range(mask.height):
        for x in range(mask.width):
            r, g, b, a = source[x, y]
            if a == 0:
                target[x, y] = (0, 0, 0, 0)
                continue
            light = SHADE[0] + (SHADE[1] - SHADE[0]) * r / 255.0
            glint = ACCENT_SHADE[0] + (ACCENT_SHADE[1] - ACCENT_SHADE[0]) * r / 255.0
            mix_g, mix_b = g / 255.0, b / 255.0
            rgb = []
            for channel in range(3):
                base = body[channel] * light
                skin = base + (accent[channel] * glint - base) * mix_g
                rgb.append(max(0, min(255, round(skin + (eye[channel] - skin) * mix_b))))
            target[x, y] = (rgb[0], rgb[1], rgb[2], a)
    return out


def darken(mask: Image.Image) -> Image.Image:
    """Stínová vrstva tak, jak ji nakreslí hra: černá s krytím SHADOW_ALPHA."""
    image = Image.new("RGBA", mask.size, (0, 0, 0, 255))
    image.putalpha(mask.getchannel("A").point(lambda value: round(value * SHADOW_ALPHA)))
    return image


def preview_shadow(canvas: int, box: tuple[Point, Point] | None) -> Image.Image:
    if box is None:
        return blank(canvas)
    layer = Layer(canvas)
    x0, y0 = layer.px(box[0])
    x1, y1 = layer.px(box[1])
    big = Image.new("L", (canvas * SS, canvas * SS), 0)
    ImageDraw.Draw(big).ellipse((x0, y0, x1, y1), fill=60)
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 255))
    image.putalpha(big.resize((canvas, canvas), Image.Resampling.BOX))
    return image


def compose(
    sprites: dict[int, Image.Image],
    heights: dict[int, float],
    under: Image.Image,
    shift: Point = (0.0, 0.0),
) -> Image.Image:
    canvas = under.width
    image = blank(canvas)
    image.alpha_composite(under)
    for key in sorted(sprites):
        sprite = sprites[key]
        left = round((canvas - sprite.width) / 2 + shift[0] * heights[key])
        top = round((canvas - sprite.height) / 2 + shift[1] * heights[key])
        image.alpha_composite(sprite, (left, top))
    return image


def save_gif(frames: list[Image.Image], path: Path, scale: int, ms: int) -> None:
    rgb = []
    for frame in frames:
        grass = on_grass(frame)
        if scale != 1:
            grass = grass.resize((grass.width * scale, grass.height * scale), Image.Resampling.NEAREST)
        rgb.append(grass)
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb[0].save(path, save_all=True, append_images=rgb[1:], duration=ms, loop=0, disposal=2)


def side_by_side(images: list[Image.Image]) -> Image.Image:
    strip = Image.new("RGBA", (sum(image.width for image in images), images[0].height), (0, 0, 0, 0))
    left = 0
    for image in images:
        strip.alpha_composite(image, (left, 0))
        left += image.width
    return strip


def materials_of(name: str) -> list[str]:
    """Materiály druhu od nejlevnějšího."""
    owned = [material for material, info in MATERIALS.items() if info.get("monster") == name]
    return sorted(owned, key=lambda material: MATERIALS[material]["points"])


def palette(preset: dict, material: str) -> tuple[tuple[int, int, int], ...]:
    info = MATERIALS[material]
    return (
        parse_hex(info["color"]),
        parse_hex(info.get("monster_accent", info["glint"])),
        parse_hex(preset["eye"]),
    )


def check(name: str, preset: dict) -> None:
    if name not in RENDERERS:
        raise SystemExit(f"{name}: druh nemá kreslení")
    if not materials_of(name):
        raise SystemExit(f"{name}: žádný materiál v gen_crystal.MATERIALS nemá tuhle příšeru")


def check_materials() -> None:
    for material, info in MATERIALS.items():
        if info.get("monster") not in MONSTERS:
            raise SystemExit(f"{material}: neznámá příšera {info.get('monster')}")


def generate(name: str, preset: dict) -> dict:
    check(name, preset)
    render = RENDERERS[name]
    layers = preset["layers"]
    count = preset["frames"]
    frames = {key: [] for key in layers}
    for index in range(count):
        rendered = render(index / count)
        for key in layers:
            frames[key].append(pack(rendered[key]))
    folder = OUT_DIR / name
    folder.mkdir(parents=True, exist_ok=True)
    entry = {}
    for key, info in layers.items():
        frames[key] = crop_square(frames[key])
        cell = frames[key][0].width
        pack_atlas(frames[key], COLUMNS).save(folder / info["file"])
        entry[str(key)] = {
            "height": info["height"],
            "file": f"{name}/{info['file']}",
            "cell": cell,
            "center": cell // 2,
        }
        if info.get("shadow"):
            entry[str(key)]["shadow"] = True
    write_previews(name, preset, frames)
    return {
        "cycle_meters": round(preset["cycle_meters"], 4),
        "frames": count,
        "atlas_columns": COLUMNS,
        "wander_meters": preset["wander_meters"],
        "chase_meters": preset["chase_meters"],
        "body_meters": preset["body_meters"],
        "small": preset.get("small", False),
        "jump_meters": preset.get("jump_meters", 0.0),
        **preset.get("info", {}),
        "layers": entry,
        "colors": {"eye": preset["eye"]},
    }


def write_previews(name: str, preset: dict, frames: dict[int, list[Image.Image]]) -> None:
    layers = preset["layers"]
    heights = {key: info["height"] for key, info in layers.items()}
    materials = materials_of(name)
    count = preset["frames"]
    # Přehledy ukazují stejné fáze cyklu bez ohledu na počet snímků.
    step = max(1, count // SHEET_FRAMES)
    # Plátno pojme i vrstvu posunutou „u kraje“.
    drift = math.ceil(max(abs(EDGE[0]), abs(EDGE[1])) * max(heights.values()))
    size = max(preset["canvas"], max(frames[key][0].width for key in frames) + 2 * drift + 4)
    under = preview_shadow(size + size % 2, preset["preview_shadow"])

    def tint(key: int, mask: Image.Image, colors: tuple[tuple[int, int, int], ...]) -> Image.Image:
        return darken(mask) if layers[key].get("shadow") else colorize(mask, *colors)

    def walk(material: str, shift: Point = (0.0, 0.0)) -> list[Image.Image]:
        colors = palette(preset, material)
        return [
            compose({key: tint(key, frames[key][index], colors) for key in frames}, heights, under, shift)
            for index in range(count)
        ]

    walks = {material: crop_square(walk(material)) for material in materials}
    first = walks[materials[0]]
    scale = math.ceil(300 / first[0].width)
    small = max(1, scale - 1)
    # GIF ukládá délku snímku v setinách sekundy.
    ms = 10 * max(2, round(preset.get("preview_cycle_ms", PREVIEW_CYCLE_MS) / count / 10))
    save_gif(first, PREVIEW / f"{name}.gif", scale, ms)
    shown = range(0, count, step)
    contact_sheet(
        [first[index] for index in shown],
        [f"snímek {index}" for index in shown],
        PREVIEW / f"{name}_chuz.png",
        small,
    )
    if any(info.get("shadow") for info in layers.values()):
        save_gif(crop_square(walk(materials[0], EDGE)), PREVIEW / f"{name}_u_kraje.gif", scale, ms)

    colors = palette(preset, materials[0])
    sprites = {key: tint(key, frames[key][step], colors) for key in frames}
    panels = [compose({key: sprites[key]}, heights, under) for key in sorted(sprites)]
    panels += [compose(sprites, heights, under), compose(sprites, heights, under, EDGE)]
    labels = [
        f"{'stín' if layers[key].get('shadow') else f'vrstva {key}'} · {heights[key]:g} m" for key in sorted(sprites)
    ] + ["spolu", "u kraje"]
    contact_sheet(crop_square(panels), labels, PREVIEW / f"{name}_vrstvy.png", scale)

    contact_sheet(
        [walks[material][step] for material in materials],
        materials,
        PREVIEW / f"{name}_materialy.png",
        scale,
    )
    strips = [side_by_side([walks[material][index] for material in materials]) for index in range(count)]
    save_gif(strips, PREVIEW / f"{name}_materialy.gif", small, ms)


def write_info(species: dict) -> Path:
    """Doplní vygenerované druhy ke druhům, které už v katalogu jsou."""
    known = {}
    if INFO_PATH.exists():
        known = json.loads(INFO_PATH.read_text(encoding="utf-8")).get("species", {})
    known.update(species)
    catalog = {
        "px_per_meter": PX_PER_METER,
        "facing": "N",
        "filter": "linear",
        "channels": ["shade", "accent", "eye"],
        "shade": list(SHADE),
        "accent_shade": list(ACCENT_SHADE),
        "shadow_alpha": SHADOW_ALPHA,
        "species": {name: known[name] for name in MONSTERS if name in known},
    }
    INFO_PATH.parent.mkdir(parents=True, exist_ok=True)
    INFO_PATH.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return INFO_PATH


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", choices=sorted(MONSTERS), help="jen jeden druh")
    args = parser.parse_args()
    check_materials()
    names = [args.name] if args.name else list(MONSTERS)
    species = {}
    for name in names:
        species[name] = generate(name, MONSTERS[name])
        cells = "–".join(str(layer["cell"]) for layer in species[name]["layers"].values())
        print(f"{name}: buňky {cells}, cyklus {species[name]['cycle_meters']} m")
        print(PREVIEW / f"{name}.gif")
    print(write_info(species))


if __name__ == "__main__":
    main()
