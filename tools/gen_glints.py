#!/usr/bin/env python3
"""Mapy odlesků předpočítané ze semínek třpytu.

Shader krystalu a kamenné příšery dřív v každém pixelu hledal nejsilnější semínko v okolí
9 × 9 px a pak jeho těžiště v okolí 5 × 5 px, tedy přes sto čtení textury na pixel. Tady se to
spočítá jednou pro každý texel a shader přečte jen výsledek:

  R, G  vektor od těžiště semínka k texelu v texelech, (hodnota * 255 - 127.5) / 127.5 * REACH
  B     jas semínka, podle něj kámen blikne. 0 = v okolí žádné semínko není.

Mapa má rozměry zdrojové textury, shader ji čte bez filtru (filter_nearest) a k vektoru
přičte polohu pixelu uvnitř texelu.

Volají ho gen_crystal.py a gen_monsters.py. Samostatně přepočítá existující grafiku:

  py tools/gen_glints.py
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CRYSTAL_DIR = ROOT / "godot" / "graphics" / "objects" / "crystal"
MONSTER_DIR = ROOT / "godot" / "graphics" / "characters" / "monsters"

## Stejné míry jako dřív v shaderu: okolí hledání, okolí těžiště, váhy vzdálenosti a práh.
SEARCH = 4
CENTER = 2
SEARCH_FALLOFF = 0.10
CENTER_FALLOFF = 0.35
THRESHOLD = 0.045
## Největší délka vektoru v texelech. Semínko je nejdál SEARCH + CENTER texelů.
REACH = 8.0


def glint_map(seeds: np.ndarray) -> Image.Image:
    """seeds je 2D pole jasu semínek 0..255. Vrátí RGB obrázek mapy odlesků."""
    height, width = seeds.shape
    pad = SEARCH + CENTER
    g = np.pad(seeds.astype(np.float32) / 255.0, pad, mode="edge")

    def shifted(dx: np.ndarray | int, dy: np.ndarray | int) -> np.ndarray:
        if isinstance(dx, int):
            return g[pad + dy : pad + dy + height, pad + dx : pad + dx + width]
        rows = np.arange(height)[:, None] + pad + dy
        cols = np.arange(width)[None, :] + pad + dx
        return g[rows, cols]

    # Nejsilnější semínko, bližší má přednost. Při shodě vyhrává dřívější, jako ve smyčce shaderu.
    best = np.full((height, width), -1.0, dtype=np.float32)
    peak_x = np.zeros((height, width), dtype=np.int32)
    peak_y = np.zeros((height, width), dtype=np.int32)
    peak_g = np.zeros((height, width), dtype=np.float32)
    for y in range(-SEARCH, SEARCH + 1):
        for x in range(-SEARCH, SEARCH + 1):
            seed = shifted(x, y)
            score = seed * np.float32(np.exp(-(x * x + y * y) * SEARCH_FALLOFF))
            better = score > best
            best = np.where(better, score, best)
            peak_x = np.where(better, x, peak_x)
            peak_y = np.where(better, y, peak_y)
            peak_g = np.where(better, seed, peak_g)

    # Těžiště semínka přesněji než na texel.
    acc_x = np.zeros((height, width), dtype=np.float32)
    acc_y = np.zeros((height, width), dtype=np.float32)
    mass = np.zeros((height, width), dtype=np.float32)
    for y in range(-CENTER, CENTER + 1):
        for x in range(-CENTER, CENTER + 1):
            seed = shifted(peak_x + x, peak_y + y)
            weight = seed * np.float32(np.exp(-(x * x + y * y) * CENTER_FALLOFF))
            acc_x += (peak_x + x) * weight
            acc_y += (peak_y + y) * weight
            mass += weight
    mass = np.maximum(mass, 0.0001)
    from_x = -acc_x / mass
    from_y = -acc_y / mass

    lit = peak_g >= THRESHOLD
    out = np.zeros((height, width, 3), dtype=np.uint8)
    out[..., 0] = np.where(lit, _encode(from_x), 128)
    out[..., 1] = np.where(lit, _encode(from_y), 128)
    out[..., 2] = np.where(lit, np.round(peak_g * 255.0), 0).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def _encode(value: np.ndarray) -> np.ndarray:
    scaled = np.clip(value / REACH, -1.0, 1.0) * 127.5 + 127.5
    return np.clip(np.round(scaled), 0, 255).astype(np.uint8)


def save_glints(source: Image.Image, target: Path) -> None:
    """Mapa odlesků ze semínek v kanálu G obrázku source."""
    glint_map(np.asarray(source.convert("RGBA").getchannel("G"))).save(target)
    write_import(target)


def uid_for(res_path: str) -> str:
    alphabet = "abcdefghijklmnopqrstuvwxyz234567"
    digest = hashlib.sha256(res_path.encode()).digest()
    chars: list[str] = []
    acc = 0
    bits = 0
    for byte in digest:
        acc = (acc << 8) | byte
        bits += 8
        while bits >= 5 and len(chars) < 13:
            bits -= 5
            chars.append(alphabet[(acc >> bits) & 31])
    return "uid://" + "".join(chars)


def write_import(png: Path) -> None:
    """Data, ne obrázek: bez komprese, bez mipmap a bez úprav okrajů."""
    res = "res://" + png.relative_to(ROOT / "godot").as_posix()
    digest = hashlib.md5(res.encode()).hexdigest()
    imported = f"res://.godot/imported/{png.name}-{digest}.ctex"
    # Uid, který už soubor má, zůstane. Godot by ho jinak při importu vrátil zpátky.
    uid = uid_for(res)
    target = png.with_suffix(".png.import")
    if target.exists():
        for line in target.read_text(encoding="utf-8").splitlines():
            if line.startswith('uid="'):
                uid = line[len('uid="') : -1]
    text = f"""[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="{imported}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{res}"
dest_files=["{imported}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""
    # Stejné konce řádků, jaké soubor zapíše Godot při importu.
    with open(target, "w", encoding="utf-8", newline="\n") as file:
        file.write(text)


def glint_name(file: str) -> str:
    """layer_1.png i layer_1_spark.png -> layer_1_glint.png"""
    stem = file[: -len(".png")]
    if stem.endswith("_spark"):
        stem = stem[: -len("_spark")]
    return stem + "_glint.png"


def _remove(png: Path) -> None:
    for path in (png, png.with_suffix(".png.import")):
        if path.exists():
            path.unlink()


def convert_crystal() -> None:
    catalog_path = CRYSTAL_DIR / "crystal.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    for name, shape in catalog["shapes"].items():
        file = str(shape["file"])
        glint = glint_name(file)
        save_glints(Image.open(CRYSTAL_DIR / file), CRYSTAL_DIR / glint)
        shape["glint"] = glint
        print(f"krystal {name}: {glint}")
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def convert_monsters() -> None:
    catalog_path = MONSTER_DIR / "monsters.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    for name, info in catalog.get("species", {}).items():
        for layer in info.get("layers", {}).values():
            spark = layer.pop("sparkle_file", None)
            if spark is None:
                continue
            spark_png = MONSTER_DIR / spark
            glint = str(Path(spark).parent.as_posix()) + "/" + glint_name(Path(spark).name)
            save_glints(Image.open(spark_png), MONSTER_DIR / glint)
            _remove(spark_png)
            layer["glint_file"] = glint
            print(f"příšera {name}: {glint}")
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> None:
    convert_crystal()
    convert_monsters()


if __name__ == "__main__":
    main()
