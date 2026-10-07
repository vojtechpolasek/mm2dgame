#!/usr/bin/env python3
"""Chůze postavy z pohledu shora.

64 px je 1 m, stejně jako u skal a stromů. Buňka 96 px. Postava v kroku
je zhruba stejně široká jako koruna keře ker1 (68 px) a třetinová proti
patě strom1 (200 px).

Atlas je jedna řada osmi snímků, postava jde na sever. Ostatní směry
otáčí uzel v Godotu. Střed buňky je střed trupu.

Každá vrstva nese váhy materiálu, ne hotovou barvu. Alfa je krytí.
Vrstva 1 (nohy, 0 m): R kalhoty, G boty, B tkaničky.
Vrstva 2 (tělo, 1,2 m): R triko, G kůže.
Vrstva 3 (hlava, 1,65 m): R kůže, G vlasy, B oči.
Kalhoty zajíždějí pod triko, aby se vrstvy při posunu kamery neroztrhly.
Barvy skládá godot/shaders/person_layer.gdshader.

  py tools/gen_person.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

from gen_trees import GRASS, blank, contact_sheet, pack_atlas

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "characters" / "person"
PREVIEW = ROOT / "tools" / "preview"

PX_PER_METER = 64
CELL = 96
FRAMES = 8
COLUMNS = 8
SS = 4

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
# Náhled „u kraje“: postava 480 px vpravo a 260 px pod středem okna.
PARALLAX = 0.016
EDGE = (480.0 * PARALLAX, 260.0 * PARALLAX)
WAIST_TUCK = 14.0


def rotate(point: tuple[float, float], angle: float) -> tuple[float, float]:
    x, y = point
    c, s = math.cos(angle), math.sin(angle)
    return (x * c - y * s, x * s + y * c)


class Pose:
    """Místní souřadnice: záporné Y je vpřed (sever). Úhel roste po směru hodin na obrazovce."""

    def __init__(self, frame: int) -> None:
        phase = frame / FRAMES * math.tau
        self.swing = math.sin(phase)
        self.angle = 0.0
        self.origin = CELL / 2
        # Dopředu delší krok než dozadu, ať je přední nohavice vidět.
        # Rozkmit je kousek za kyčlemi, míň než v původní poloze vpředu.
        hip_y = 8.0
        stride_back = 3.0
        self.hip_l = (-7.0, hip_y)
        self.hip_r = (7.0, hip_y)
        self.foot_l = (-12.0, hip_y + stride_back - self._stride(self.swing))
        self.foot_r = (12.0, hip_y + stride_back - self._stride(-self.swing))
        self.knee_l = self._outward(self.hip_l, self.foot_l, 2.0)
        self.knee_r = self._outward(self.hip_r, self.foot_r, 2.0)
        twist = self.swing * 2.5
        # Trup kousek před kyčlemi. Hlava zůstává před ním.
        body_y = 4.0
        self.shoulder_l = (-15.0, -2.0 + body_y + twist)
        self.shoulder_r = (15.0, -2.0 + body_y - twist)
        self.cuff_l = (-23.0, 2.0 + body_y + self.swing * 11.0)
        self.cuff_r = (23.0, 2.0 + body_y - self.swing * 11.0)
        self.elbow_l = self._outward(self.shoulder_l, self.cuff_l, 2.5, 0.55)
        self.elbow_r = self._outward(self.shoulder_r, self.cuff_r, 2.5, 0.55)
        self.head = (0.0, -3.0)
        self.head_r = 9.0

    @staticmethod
    def _stride(swing: float) -> float:
        if swing >= 0.0:
            return swing * 30.0
        return swing * 16.0

    @staticmethod
    def _outward(
        start: tuple[float, float],
        end: tuple[float, float],
        amount: float,
        along: float = 0.5,
    ) -> tuple[float, float]:
        x = start[0] + (end[0] - start[0]) * along
        y = start[1] + (end[1] - start[1]) * along
        sign = -1.0 if start[0] < 0.0 else 1.0
        return (x + sign * amount, y)

    def px(self, point: tuple[float, float]) -> tuple[float, float]:
        x, y = rotate(point, self.angle)
        return ((self.origin + x) * SS, (self.origin + y) * SS)


class Weights:
    def __init__(self) -> None:
        size = CELL * SS
        self.ch = [Image.new("L", (size, size), 0) for _ in range(3)]

    def stamp(self, channel: int, part: Image.Image) -> None:
        inv = ImageChops.invert(part)
        self.ch = [ImageChops.multiply(image, inv) for image in self.ch]
        self.ch[channel] = ImageChops.lighter(self.ch[channel], part)


def new_part() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("L", (CELL * SS, CELL * SS), 0)
    return image, ImageDraw.Draw(image)


def fill_ellipse(
    draw: ImageDraw.ImageDraw,
    pose: Pose,
    center: tuple[float, float],
    rx: float,
    ry: float,
) -> None:
    points = []
    for step in range(36):
        angle = step / 36 * math.tau
        local = (center[0] + math.cos(angle) * rx, center[1] + math.sin(angle) * ry)
        points.append(pose.px(local))
    draw.polygon(points, fill=255)


def fill_disk(draw: ImageDraw.ImageDraw, pose: Pose, center: tuple[float, float], radius: float) -> None:
    x, y = pose.px(center)
    r = radius * SS
    draw.ellipse((x - r, y - r, x + r, y + r), fill=255)


def fill_capsule(
    draw: ImageDraw.ImageDraw,
    pose: Pose,
    start: tuple[float, float],
    end: tuple[float, float],
    radius: float,
) -> None:
    ax, ay = pose.px(start)
    bx, by = pose.px(end)
    r = radius * SS
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy) or 1.0
    px, py = -dy / length * r, dx / length * r
    draw.polygon(
        [(ax + px, ay + py), (bx + px, by + py), (bx - px, by - py), (ax - px, ay - py)],
        fill=255,
    )
    draw.ellipse((ax - r, ay - r, ax + r, ay + r), fill=255)
    draw.ellipse((bx - r, by - r, bx + r, by + r), fill=255)


def paint_palm(draw: ImageDraw.ImageDraw, pose: Pose, cuff: tuple[float, float]) -> None:
    # Široký nízký ovál. Největší šířka je kousek před rukávem.
    fill_ellipse(draw, pose, (cuff[0], cuff[1] - 6.4), 3.6, 1.5)


def paint_shoe(draw: ImageDraw.ImageDraw, pose: Pose, ankle: tuple[float, float]) -> None:
    # Špička míří pořád dopředu, bez ohledu na to, kam je noha v kroku.
    heel = (ankle[0], ankle[1] + 2.4)
    toe = (ankle[0], ankle[1] - 8.0)
    fill_capsule(draw, pose, heel, toe, 3.0)


def paint_laces(draw: ImageDraw.ImageDraw, pose: Pose, ankle: tuple[float, float]) -> None:
    for along in (4.6, 6.4):
        cy = ankle[1] - along
        start = pose.px((ankle[0] - 1.8, cy))
        end = pose.px((ankle[0] + 1.8, cy))
        draw.line((start, end), fill=255, width=SS)


def render_weights(frame: int) -> dict[int, Weights]:
    pose = Pose(frame)
    legs, body, head = Weights(), Weights(), Weights()
    limbs = (
        (pose.hip_l, pose.knee_l, pose.foot_l),
        (pose.hip_r, pose.knee_r, pose.foot_r),
    )

    for _hip, knee, foot in limbs:
        part, draw = new_part()
        paint_shoe(draw, pose, foot)
        legs.stamp(1, part)
        part, draw = new_part()
        paint_laces(draw, pose, foot)
        legs.stamp(2, part)

    part, draw = new_part()
    fill_ellipse(draw, pose, (0.0, 5.0), 11.0, 7.0)
    # Pás zajíždí pod triko. Posun u kraje okna je asi 9 px, přesah je větší.
    fill_ellipse(draw, pose, (0.0, 3.0), 9.0, WAIST_TUCK * 0.5)
    legs.stamp(0, part)

    for hip, knee, foot in limbs:
        part, draw = new_part()
        fill_capsule(draw, pose, hip, knee, 5.2)
        fill_capsule(draw, pose, knee, foot, 4.2)
        legs.stamp(0, part)

    for cuff in (pose.cuff_l, pose.cuff_r):
        part, draw = new_part()
        paint_palm(draw, pose, cuff)
        body.stamp(1, part)
    for shoulder, elbow, cuff in (
        (pose.shoulder_l, pose.elbow_l, pose.cuff_l),
        (pose.shoulder_r, pose.elbow_r, pose.cuff_r),
    ):
        part, draw = new_part()
        fill_capsule(draw, pose, shoulder, elbow, 5.2)
        fill_capsule(draw, pose, elbow, cuff, 5.0)
        body.stamp(0, part)
    part, draw = new_part()
    fill_ellipse(draw, pose, (0.0, 3.0), 18.0, 9.0)
    body.stamp(0, part)

    part, draw = new_part()
    for sign in (-1.0, 1.0):
        fill_disk(draw, pose, (pose.head[0] + sign * (pose.head_r + 1.5), pose.head[1] + 2.0), 3.2)
    head.stamp(0, part)
    part, draw = new_part()
    fill_disk(draw, pose, pose.head, pose.head_r)
    head.stamp(0, part)
    # Plešatý základ, ovál vlasů posunutý dozadu, oči vepředu.
    part, draw = new_part()
    fill_ellipse(draw, pose, (pose.head[0], pose.head[1] + 5.0), pose.head_r + 1.5, 9.0)
    head.stamp(1, part)
    part, draw = new_part()
    for sign in (-1.0, 1.0):
        fill_ellipse(draw, pose, (pose.head[0] + sign * 4.2, pose.head[1] - 5.0), 2.2, 1.7)
    head.stamp(2, part)
    return {1: legs, 2: body, 3: head}


def downscale(image: Image.Image) -> Image.Image:
    return image.resize((CELL, CELL), Image.Resampling.BOX)


def pack_mask(weights: Weights) -> Image.Image:
    channels = [downscale(image) for image in weights.ch]
    pixels = [channel.load() for channel in channels]
    out = Image.new("RGBA", (CELL, CELL))
    target = out.load()
    for y in range(CELL):
        for x in range(CELL):
            values = [pixels[i][x, y] for i in range(3)]
            total = sum(values)
            if total > 255:
                values = [value * 255 // total for value in values]
                total = sum(values)
            target[x, y] = (values[0], values[1], values[2], total)
    return out


def colorize(mask: Image.Image, tints: tuple[tuple[int, int, int], ...]) -> Image.Image:
    source = mask.load()
    out = Image.new("RGBA", mask.size)
    target = out.load()
    for y in range(mask.height):
        for x in range(mask.width):
            weights = source[x, y]
            total = weights[0] + weights[1] + weights[2]
            if total <= 0:
                target[x, y] = (0, 0, 0, 0)
                continue
            if total > 255:
                total = 255
            color = [0, 0, 0]
            for channel in range(3):
                for component in range(3):
                    color[component] += tints[channel][component] * weights[channel]
            cover = weights[3] if weights[3] else total
            target[x, y] = tuple(component // max(total, 1) for component in color) + (min(255, cover),)
    return out


def premultiply(image: Image.Image) -> Image.Image:
    red, green, blue, alpha = image.split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    )


def blit_straight(canvas: Image.Image, sprite: Image.Image, x: float, y: float) -> None:
    left = int(round(x))
    top = int(round(y))
    crop_l = max(0, -left)
    crop_t = max(0, -top)
    crop_r = min(sprite.width, canvas.width - left)
    crop_b = min(sprite.height, canvas.height - top)
    if crop_l >= crop_r or crop_t >= crop_b:
        return
    piece = sprite.crop((crop_l, crop_t, crop_r, crop_b))
    canvas.paste(piece, (left + crop_l, top + crop_t), piece)


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


def compose(frames: dict[int, Image.Image], shift: tuple[float, float] = (0.0, 0.0)) -> Image.Image:
    image = blank(CELL)
    image.alpha_composite(premultiply(SHADOW))
    for layer in (1, 2, 3):
        height = LAYERS[layer]["height"]
        blit_straight(image, frames[layer], shift[0] * height, shift[1] * height)
    return image


def colored_layers(frame: int) -> dict[int, Image.Image]:
    weights = render_weights(frame)
    return {layer: colorize(pack_mask(weights[layer]), LAYER_TINT[layer]) for layer in LAYERS}


def on_grass(image: Image.Image) -> Image.Image:
    background = Image.new("RGBA", image.size, GRASS + (255,))
    background.paste(image, (0, 0), image)
    return background.convert("RGB")


def save_gif(frames: list[Image.Image], path: Path, scale: int, ms: int) -> None:
    rgb = []
    for frame in frames:
        grass = on_grass(frame)
        if scale != 1:
            grass = grass.resize((grass.width * scale, grass.height * scale), Image.Resampling.NEAREST)
        rgb.append(grass)
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb[0].save(path, save_all=True, append_images=rgb[1:], duration=ms, loop=0, disposal=2)


def write_info() -> Path:
    path = OUT_DIR / "person.json"
    path.write_text(
        json.dumps(
            {
                "px_per_meter": PX_PER_METER,
                "cell": CELL,
                "frames": FRAMES,
                "facing": "S",
                "atlas_columns": COLUMNS,
                "center": CELL // 2,
                "filter": "linear",
                "shader": "res://shaders/person_layer.gdshader",
                "layers": {
                    str(layer): {
                        "height": info["height"],
                        "slot": info["slot"],
                        "file": info["file"],
                        "channels": info["channels"],
                    }
                    for layer, info in LAYERS.items()
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
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return path


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlases = {layer: [] for layer in LAYERS}
    for frame in range(FRAMES):
        weights = render_weights(frame)
        for layer in LAYERS:
            atlases[layer].append(pack_mask(weights[layer]))
    for layer, info in LAYERS.items():
        pack_atlas(atlases[layer], COLUMNS).save(OUT_DIR / info["file"])

    walk = [compose(colored_layers(frame)) for frame in range(FRAMES)]
    save_gif(walk, PREVIEW / "person.gif", 4, 110)
    contact_sheet(
        [premultiply(frame) for frame in walk],
        [f"krok {index}" for index in range(FRAMES)],
        PREVIEW / "person_chuz.png",
        3,
    )

    stride = 2
    layers = colored_layers(stride)
    panels = [layers[1], layers[2], layers[3], compose(layers), compose(layers, EDGE)]
    contact_sheet(
        [premultiply(panel) for panel in panels],
        ["nohy · 0 m", "tělo · 1.2 m", "hlava · 1.65 m", "spolu", "u kraje"],
        PREVIEW / "person_vrstvy.png",
        3,
    )
    stale = PREVIEW / "person_smery.png"
    if stale.exists():
        stale.unlink()
    info = write_info()
    print(f"atlasy {COLUMNS * CELL}×{CELL} -> {OUT_DIR}")
    print(PREVIEW / "person.gif")
    print(info)


if __name__ == "__main__":
    main()
