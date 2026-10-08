#!/usr/bin/env python3
"""Běh postavy z pohledu shora.

64 px je 1 m, stejně jako u skal, stromů a příšer. Kreslí se ve čtyřnásobném
rozlišení do buňky 96 px. Uložená buňka vrstvy je ořezaná na obsah, střed trupu
zůstává. Postava v kroku je zhruba stejně široká jako koruna keře ker1 (68 px).

Atlas má osm sloupců, postava běží na sever. Ostatní směry otáčí uzel v Godotu.
Prvních FRAMES snímků je jeden cyklus běhu, tedy dva kroky. Za nimi je snímek
stání (idle_frame). Střed buňky je střed trupu.

Každá vrstva nese váhy materiálu, ne hotovou barvu. Alfa je krytí.
Vrstva 1 (nohy, 0 m): R kalhoty, G boty, B tkaničky.
Vrstva 2 (tělo, 1,2 m): R triko, G kůže.
Vrstva 3 (hlava, 1,65 m): R kůže, G vlasy, B oči.
Součet vah děleno krytím nese světlost, ať se vejde do stejné textury:
  součet / krytí = shade_floor + (1 - shade_floor) * světlost
Barvy skládá godot/shaders/person_layer.gdshader:
  barva = materiál * mix(shade, světlost) + odlesk
Odlesk dostanou jen tmavé barvy na nejsvětlejších místech, jinak by třeba černé
triko zůstalo ploché. Průhledné pixely mají váhy 0, import proto nesmí opravovat
okraje průhlednosti (fix_alpha_border), jinak by okraj zesvětlal.
Kalhoty zajíždějí pod triko, aby se vrstvy při posunu kamery neroztrhly.

Běh: chodidla kývají dopředu dál než dozadu, zadní chodidlo je ve vzduchu
špičkou dolů. Ruce jsou pokrčené v lokti a kývají proti nohám, ramena se
natáčejí proti kyčlím a hlava se kývá do stran. Ve stání visí ruce podél těla.

Druhý set je jen tělo, layer_2_hold.png. Pravá ruka je po celou dobu
natažená dopředu, dlaň je prázdná. Levá kývá jako při běhu, s menším
rozkmitem. Nohy a hlava zůstávají ze základního běhu.

  py tools/gen_person.py
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from gen_trees import blank, contact_sheet, crop_square, on_grass, pack_atlas

Point = tuple[float, float]

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "characters" / "person"
PREVIEW = ROOT / "tools" / "preview"

PX_PER_METER = 64
CELL = 96
FRAMES = 16
IDLE_FRAME = FRAMES
ATLAS_FRAMES = FRAMES + 1
COLUMNS = 8
SS = 4
# Hra uběhne cyklus za 0,67 s (3 m při 4,5 m/s), náhled jde o kousek pomaleji.
PREVIEW_MS = 50
# Přehled snímků ukáže každý n-tý snímek cyklu.
SHEET_STEP = 2

# Rozsah světlosti, dno kódování světlosti a odlesk (síla, od jaké světlosti).
SHADE = (0.42, 1.1)
SHADE_FLOOR = 0.2
SHEEN = (0.16, 0.7)
LUMA = np.array((0.299, 0.587, 0.114), np.float32)
# Světlost na okraji tvaru, střed má 1. Končetiny, trup a hlava, drobné tvary.
LIMB_EDGE = 0.25
DOME_EDGE = 0.32
SMALL_EDGE = 0.45

SKIN = (246, 205, 176)
SHIRT = (32, 26, 24)
PANTS = (200, 75, 120)
SHOE = (32, 28, 30)
LACE = (176, 172, 174)
HAIR = (92, 58, 40)
EYE = (36, 28, 26)

# Výšky ve shodě s object_layers.gd. Nohy jsou na zemi, jako pařez.
LAYERS = {
    1: {"height": 0.0, "slot": 2.0, "file": "layer_1.png", "channels": ["pants", "shoe", "lace"]},
    2: {"height": 1.2, "slot": 1.0, "file": "layer_2.png", "channels": ["shirt", "skin"]},
    3: {"height": 1.65, "slot": 0.0, "file": "layer_3.png", "channels": ["skin", "hair", "eye"]},
}
LAYER_TINT = {
    1: (PANTS, SHOE, LACE),
    2: (SHIRT, SKIN, (0, 0, 0)),
    3: (SKIN, HAIR, EYE),
}
LEG_PANTS, LEG_SHOE, LEG_LACE = 0, 1, 2
BODY_SHIRT, BODY_SKIN = 0, 1
HEAD_SKIN, HEAD_HAIR, HEAD_EYE = 0, 1, 2
# Náhled „u kraje“: postava 480 px vpravo a 260 px pod středem okna.
PARALLAX = 0.016
EDGE = (480.0 * PARALLAX, 260.0 * PARALLAX)

# Kyčel pravé strany. Běžec došlapuje pod sebe, chodidla jsou blízko středu.
HIP = (6.0, 8.0)
FOOT_X = 8.0
# Jak daleko kotník kývne dopředu a dozadu. Dopředu dál, ať je přední nohavice vidět,
# ale špička nepřeleze daleko před hlavu.
STEP_AHEAD = 22.0
STEP_BACK = 18.0
THIGH_R = 5.0
SHIN_R = 4.0
# Bota od kotníku: k patě, ke špičce, poloměr.
SHOE_SHAPE = (2.4, 8.0, 3.0)
# Zadní chodidlo je ve vzduchu špičkou dolů. Shora se bota zkrátí na tenhle díl
# a podrážka vykoukne o SOLE_SHOW px za nohavicí.
SHOE_LIFTED = 0.35
SOLE_SHOW = 1.5
# Tkaničky před kotníkem, za lemem nohavice, který končí SHIN_R px před kotníkem.
LACES = (5.4, 7.4)
# Ve stání jsou chodidla pod kyčlemi, špičky vykukují zpod trupu.
IDLE_FOOT = (6.5, 0.5)
WAIST_TUCK = 14.0

TORSO = (0.0, 3.0)
TORSO_R = (17.0, 9.0)
SHOULDER = (14.0, 2.0)
# Ramena se natáčejí proti nohám o tolik stupňů, kyčle o díl HIP_TWIST na druhou stranu.
TWIST = 9.0
HIP_TWIST = 0.4
UPPER_ARM = 15.0
FOREARM = 8.0
UPPER_R = 4.6
FOREARM_R = 4.0
# Nadloktí kývá dopředu a dozadu, ve stupních od svislice. Loket je v běhu pokrčený
# a předloktí míří trochu ke středu. Pěsti zůstávají po stranách přední části hlavy:
# dál vpředu působí jako zdvižená ruka, blíž ke středu jako ruce před obličejem.
ARM_FORWARD = 22.0
ARM_BACK = 40.0
ELBOW_BEND = 90.0
ARM_INWARD = 4.5
# Volná ruka v úchopu kývá míň. Ve stání visí s lehce pokrčeným loktem.
ARM_FREE = 0.6
IDLE_ELBOW = 10.0
# Pěst před koncem rukávu: vzdálenost, poloosy podél a napříč předloktí.
FIST_AHEAD = 4.5
FIST_R = (3.0, 2.6)
# Prázdná dlaň v úchopu je široký nízký ovál PALM_AHEAD před rukávem.
PALM_AHEAD = 6.4
PALM_R = (3.6, 1.5)
# Pravá dlaň pořád na jednom místě, v linii ramene. Záporné Y je dopředu.
HOLD_PALM = (16.0, -16.0)
HOLD_ARM_R = 4.3
HOLD_FILE = "layer_2_hold.png"

# Hlava je kousek před trupem, běžec se naklání dopředu.
HEAD = (0.0, -4.0)
HEAD_R = 9.0
HEAD_SWAY = 0.7
EAR_R = 3.2
# Ovál vlasů je posunutý dozadu. Oči: posun od středu hlavy a poloosy.
HAIR_SHIFT = 5.0
HAIR_RY = 9.0
EYE_SPOT = ((4.2, -5.0), (2.2, 1.7))

_AXIS = (np.arange(CELL * SS, dtype=np.float32) + 0.5) / SS - CELL / 2
GX, GY = np.meshgrid(_AXIS, _AXIS)


def rotate(point: Point, angle: float) -> Point:
    x, y = point
    c, s = math.cos(angle), math.sin(angle)
    return (x * c - y * s, x * s + y * c)


def turn(point: Point, center: Point, angle: float) -> Point:
    x, y = rotate((point[0] - center[0], point[1] - center[1]), angle)
    return (center[0] + x, center[1] + y)


def lerp(a: Point, b: Point, t: float) -> Point:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


@dataclass
class Leg:
    hip: Point
    knee: Point
    ankle: Point
    # 0 je chodidlo vpředu nebo pod tělem, 1 zadní chodidlo nejvýš ve vzduchu.
    lift: float


@dataclass
class Arm:
    shoulder: Point
    # None je natažená ruka bez lokte.
    elbow: Point | None
    wrist: Point
    hand: Point
    hand_r: Point
    hand_angle: float


class Pose:
    """Místní souřadnice v px od středu buňky: záporné Y je vpřed (sever), kladné X vpravo.

    Úhel roste po směru hodin na obrazovce.
    """

    def __init__(self, frame: int, hold: bool = False) -> None:
        self.idle = frame >= FRAMES
        phase = 0.0 if self.idle else frame / FRAMES * math.tau
        # Při swing 1 je levá noha vpředu a levá ruka vzadu.
        swing = math.sin(phase)
        # Záporný úhel posune levé rameno dozadu.
        self.twist = -math.radians(TWIST) * swing
        self.hips = -self.twist * HIP_TWIST
        self.legs = [self._leg(side, -side * swing) for side in (-1.0, 1.0)]
        self.arms = [self._arm(side, -side * swing, hold) for side in (-1.0, 1.0)]
        self.head = (HEAD_SWAY * swing, HEAD[1])

    def _leg(self, side: float, ahead: float) -> Leg:
        hip = turn((side * HIP[0], HIP[1]), (0.0, HIP[1]), self.hips)
        if self.idle:
            ankle = (side * IDLE_FOOT[0], IDLE_FOOT[1])
            return Leg(hip, lerp(hip, ankle, 0.5), ankle, 0.0)
        reach = ahead * (STEP_AHEAD if ahead >= 0.0 else STEP_BACK)
        ankle = (side * FOOT_X, HIP[1] + 2.0 - reach)
        knee = lerp(hip, ankle, 0.45)
        return Leg(hip, (knee[0] + side * 1.5, knee[1]), ankle, max(0.0, -ahead))

    def _arm(self, side: float, back: float, hold: bool) -> Arm:
        shoulder = turn((side * SHOULDER[0], SHOULDER[1]), TORSO, self.twist)
        if hold and side > 0.0:
            # Zápěstí je za dlaní, dlaň je pořád v HOLD_PALM.
            wrist = (HOLD_PALM[0], HOLD_PALM[1] + PALM_AHEAD)
            return Arm(shoulder, None, wrist, HOLD_PALM, PALM_R, 0.0)
        if self.idle:
            theta, bend, inward = 0.0, math.radians(IDLE_ELBOW), 1.0
        else:
            back *= ARM_FREE if hold else 1.0
            theta = -math.radians(ARM_BACK if back > 0.0 else ARM_FORWARD) * back
            bend, inward = math.radians(ELBOW_BEND), ARM_INWARD
        # Shora je vidět jen průmět: svislé nadloktí se zkrátí na nulu.
        elbow = (shoulder[0] + side * 1.5, shoulder[1] - UPPER_ARM * math.sin(theta))
        wrist = (elbow[0] - side * inward * math.sin(bend), elbow[1] - FOREARM * math.sin(theta + bend))
        dx, dy = wrist[0] - elbow[0], wrist[1] - elbow[1]
        length = math.hypot(dx, dy) or 1.0
        hand = (wrist[0] + dx / length * FIST_AHEAD, wrist[1] + dy / length * FIST_AHEAD)
        return Arm(shoulder, elbow, wrist, hand, FIST_R, math.atan2(dy, dx))


def capsule(start: Point, end: Point, radius: float) -> np.ndarray:
    """Čtverec vzdálenosti od úsečky v násobcích poloměru. Uvnitř je nejvýš 1."""
    dx, dy = end[0] - start[0], end[1] - start[1]
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 < 1e-6 else np.clip(((GX - start[0]) * dx + (GY - start[1]) * dy) / length2, 0.0, 1.0)
    x = GX - (start[0] + t * dx)
    y = GY - (start[1] + t * dy)
    return (x * x + y * y) / (radius * radius)


def ellipse(center: Point, radii: Point, angle: float = 0.0) -> np.ndarray:
    """Jako capsule, pro elipsu otočenou o angle."""
    x, y = GX - center[0], GY - center[1]
    c, s = math.cos(angle), math.sin(angle)
    u = (x * c + y * s) / radii[0]
    v = (y * c - x * s) / radii[1]
    return u * u + v * v


class Weights:
    """Váhy materiálů a světlost jedné vrstvy ve čtyřnásobném rozlišení."""

    def __init__(self) -> None:
        size = CELL * SS
        self.ch = np.zeros((3, size, size), np.float32)
        self.shade = np.ones((size, size), np.float32)

    def stamp(self, channel: int, shape: np.ndarray, edge: float | None = None) -> None:
        """Překryje dosavadní kresbu. Světlost je kopule od edge na okraji po 1 uprostřed, None ji nechá."""
        inside = shape <= 1.0
        self.ch[:, inside] = 0.0
        self.ch[channel, inside] = 1.0
        if edge is not None:
            self.shade[inside] = edge + (1.0 - edge) * (1.0 - shape[inside]) ** 0.4


def render_weights(frame: int, hold: bool = False) -> dict[int, Weights]:
    pose = Pose(frame, hold)
    legs, body, head = Weights(), Weights(), Weights()

    # Zadní noha první, přední ji překryje. Bota je pod nohavicí, lem zakryje kotník.
    heel_back, toe_ahead, shoe_r = SHOE_SHAPE
    for leg in sorted(pose.legs, key=lambda leg: -leg.ankle[1]):
        x, y = leg.ankle
        heel = (x, y + heel_back + SOLE_SHOW * leg.lift)
        toe = (x, y - toe_ahead * (1.0 - (1.0 - SHOE_LIFTED) * leg.lift))
        legs.stamp(LEG_SHOE, capsule(heel, toe, shoe_r), LIMB_EDGE)
        if leg.lift < 0.3:
            for along in LACES:
                legs.stamp(LEG_LACE, capsule((x - 1.8, y - along), (x + 1.8, y - along), 0.5))
        legs.stamp(LEG_PANTS, capsule(leg.knee, leg.ankle, SHIN_R), LIMB_EDGE)
        legs.stamp(LEG_PANTS, capsule(leg.hip, leg.knee, THIGH_R), LIMB_EDGE)
    # Sedací část překryje kořeny stehen. Pás zajíždí pod triko, posun u kraje okna je asi 9 px.
    seat = np.minimum(
        ellipse((0.0, 5.0), (10.5, 7.0), pose.hips),
        ellipse((0.0, 3.0), (9.0, WAIST_TUCK * 0.5), pose.hips),
    )
    legs.stamp(LEG_PANTS, seat, DOME_EDGE)

    body.stamp(BODY_SHIRT, ellipse(TORSO, TORSO_R, pose.twist), DOME_EDGE)
    for arm in pose.arms:
        body.stamp(BODY_SKIN, ellipse(arm.hand, arm.hand_r, arm.hand_angle), SMALL_EDGE)
        if arm.elbow is None:
            # Jeden rukáv stejné šířky, bez lokte, který by spoj nafoukl.
            body.stamp(BODY_SHIRT, capsule(arm.shoulder, arm.wrist, HOLD_ARM_R), LIMB_EDGE)
        else:
            body.stamp(BODY_SHIRT, capsule(arm.elbow, arm.wrist, FOREARM_R), LIMB_EDGE)
            body.stamp(BODY_SHIRT, capsule(arm.shoulder, arm.elbow, UPPER_R), LIMB_EDGE)

    hx, hy = pose.head
    for side in (-1.0, 1.0):
        head.stamp(HEAD_SKIN, ellipse((hx + side * (HEAD_R + 1.5), hy + 2.0), (EAR_R, EAR_R)), SMALL_EDGE)
    head.stamp(HEAD_SKIN, ellipse(pose.head, (HEAD_R, HEAD_R)), DOME_EDGE)
    # Plešatý základ, ovál vlasů posunutý dozadu, oči vepředu.
    head.stamp(HEAD_HAIR, ellipse((hx, hy + HAIR_SHIFT), (HEAD_R + 1.5, HAIR_RY)), DOME_EDGE)
    (eye_x, eye_y), eye_r = EYE_SPOT
    for side in (-1.0, 1.0):
        head.stamp(HEAD_EYE, ellipse((hx + side * eye_x, hy + eye_y), eye_r))
    return {1: legs, 2: body, 3: head}


def downscale(values: np.ndarray) -> np.ndarray:
    return values.reshape(CELL, SS, CELL, SS).mean(axis=(1, 3))


def pack_mask(weights: Weights) -> Image.Image:
    stored = SHADE_FLOOR + (1.0 - SHADE_FLOOR) * np.clip(weights.shade, 0.0, 1.0)
    channels = [downscale(channel * stored) for channel in weights.ch]
    cover = downscale(weights.ch.sum(axis=0))
    rgba = np.stack(channels + [cover], axis=-1)
    return Image.fromarray(np.round(rgba * 255.0).astype(np.uint8), "RGBA")


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def colorize(mask: Image.Image, tints: tuple[tuple[int, int, int], ...]) -> Image.Image:
    """Stejný výpočet jako person_layer.gdshader."""
    data = np.asarray(mask, np.float32) / 255.0
    weights, alpha = data[..., :3], data[..., 3]
    total = weights.sum(axis=-1)
    base = (weights @ (np.array(tints, np.float32) / 255.0)) / np.maximum(total, 1e-3)[..., None]
    light = np.clip((total / np.maximum(alpha, 1e-3) - SHADE_FLOOR) / (1.0 - SHADE_FLOOR), 0.0, 1.0)
    rgb = base * (SHADE[0] + (SHADE[1] - SHADE[0]) * light)[..., None]
    rgb += (SHEEN[0] * (1.0 - base @ LUMA) * smoothstep(SHEEN[1], 1.0, light))[..., None]
    out = np.dstack([np.clip(rgb, 0.0, 1.0), alpha])
    return Image.fromarray(np.round(out * 255.0).astype(np.uint8), "RGBA")


def shadow() -> Image.Image:
    big = Image.new("L", (CELL * SS, CELL * SS), 0)
    draw = ImageDraw.Draw(big)
    cx = cy = CELL * SS / 2
    draw.ellipse((cx - 14 * SS, cy + 5 * SS, cx + 14 * SS, cy + 13 * SS), fill=70)
    alpha = big.resize((CELL, CELL), Image.Resampling.BOX)
    image = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 255))
    image.putalpha(alpha)
    return image


SHADOW = shadow()


def compose(layers: dict[int, Image.Image], shift: Point = (0.0, 0.0)) -> Image.Image:
    image = blank(CELL)
    image.alpha_composite(SHADOW)
    for key in sorted(layers):
        height = LAYERS[key]["height"]
        placed = blank(CELL)
        placed.paste(layers[key], (round(shift[0] * height), round(shift[1] * height)))
        image.alpha_composite(placed)
    return image


def colored_layers(frame: int, hold: bool = False) -> dict[int, Image.Image]:
    weights = render_weights(frame, hold)
    return {layer: colorize(pack_mask(weights[layer]), LAYER_TINT[layer]) for layer in LAYERS}


def save_gif(frames: list[Image.Image], path: Path, scale: int, ms: int) -> None:
    rgb = []
    for frame in frames:
        grass = on_grass(frame)
        if scale != 1:
            grass = grass.resize((grass.width * scale, grass.height * scale), Image.Resampling.NEAREST)
        rgb.append(grass)
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb[0].save(path, save_all=True, append_images=rgb[1:], duration=ms, loop=0, disposal=2)


def write_previews() -> None:
    shown = list(range(0, FRAMES, SHEET_STEP)) + [IDLE_FRAME]
    for hold, name, sheet, word in ((False, "person", "person_chuz", "snímek"), (True, "person_hold", "person_hold", "úchop")):
        frames = [compose(colored_layers(frame, hold)) for frame in range(ATLAS_FRAMES)]
        save_gif(frames[:FRAMES], PREVIEW / f"{name}.gif", 4, PREVIEW_MS)
        labels = [f"{word} {index}" for index in shown[:-1]] + ["stání"]
        contact_sheet([frames[index] for index in shown], labels, PREVIEW / f"{sheet}.png", 3)

    layers = colored_layers(FRAMES // 4)
    panels = [layers[1], layers[2], layers[3], compose(layers), compose(layers, EDGE)]
    labels = ["nohy · 0 m", "tělo · 1.2 m", "hlava · 1.65 m", "spolu", "u kraje"]
    contact_sheet(panels, labels, PREVIEW / "person_vrstvy.png", 3)
    stale = PREVIEW / "person_smery.png"
    if stale.exists():
        stale.unlink()


def write_info(cells: dict[int, int], hold_cell: int) -> Path:
    path = OUT_DIR / "person.json"
    cell = max(cells.values())
    catalog = {
        "px_per_meter": PX_PER_METER,
        "cell": cell,
        "frames": FRAMES,
        "atlas_frames": ATLAS_FRAMES,
        "idle_frame": IDLE_FRAME,
        "facing": "N",
        "atlas_columns": COLUMNS,
        "center": cell // 2,
        "filter": "linear",
        "shader": "res://shaders/person_layer.gdshader",
        "shade": list(SHADE),
        "shade_floor": SHADE_FLOOR,
        "sheen": list(SHEEN),
        "layers": {
            str(layer): {
                "height": info["height"],
                "slot": info["slot"],
                "file": info["file"],
                "channels": info["channels"],
                "cell": cells[layer],
                "center": cells[layer] // 2,
            }
            for layer, info in LAYERS.items()
        },
        "hold": {
            "hand": "right",
            "layer": 2,
            "file": HOLD_FILE,
            "cell": hold_cell,
            "center": hold_cell // 2,
        },
        "colors": {
            "skin": "F6CDB0",
            "hair": "5C3A28",
            "eye": "241C1A",
            "shirt": "201A18",
            "pants": "C84B78",
            "shoe": "201C1E",
            "lace": "B0ACAE",
        },
    }
    path.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    return path


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlases: dict[int, list[Image.Image]] = {layer: [] for layer in LAYERS}
    held: list[Image.Image] = []
    for frame in range(ATLAS_FRAMES):
        weights = render_weights(frame)
        for layer in LAYERS:
            atlases[layer].append(pack_mask(weights[layer]))
        held.append(pack_mask(render_weights(frame, True)[2]))
    cells: dict[int, int] = {}
    for layer, info in LAYERS.items():
        atlases[layer] = crop_square(atlases[layer])
        cells[layer] = atlases[layer][0].width
        pack_atlas(atlases[layer], COLUMNS).save(OUT_DIR / info["file"])
    held = crop_square(held)
    hold_cell = held[0].width
    pack_atlas(held, COLUMNS).save(OUT_DIR / HOLD_FILE)

    write_previews()
    info = write_info(cells, hold_cell)
    span = "–".join(str(cells[layer]) for layer in LAYERS)
    print(f"atlasy buňky {span}, úchop {hold_cell} -> {OUT_DIR}")
    print(PREVIEW / "person.gif")
    print(PREVIEW / "person_hold.gif")
    print(info)


if __name__ == "__main__":
    main()
