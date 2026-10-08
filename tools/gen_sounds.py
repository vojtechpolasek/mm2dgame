#!/usr/bin/env python3
"""Zvuky a hudba hry, vše syntézou. Výstup jsou WAV do godot/audio, po složkách.

steps/    kroky postavy podle povrchu (grass, dirt, desert, snow), čtyři varianty.
          Jemný šum s barvou povrchu a měkkým náběhem, sníh křupe ostře.
ambient/  šumění vody: tlumený šum s pomalými vlnami a bublinkami, smyčka bez švu.
basin/    dopad kamene do kotliny podle materiálu (jména z gen_crystal.MATERIALS). Levný
          tupě žuchne, s cenou přibývá výšky a zvonění, nejdražší cinkne.
monsters/ kroky příšer (pavouk cupitá, vlk tlapky, tyranosaurus duní, ptakoještěr mává
          křídly) a zařvání každého druhu, když začne honit.
sfx/      sebrání kamene, krádež příšerou, skok a dopad.
ui/       menu: posun, potvrzení, zpět, připojení a odpojení hráče, start, výhra, prohra,
          tikání posledních sekund.
music/    game_1..4 hudby do hry (dur, bez výrazné melodie), chase_1..4 hudby při honičce
          (moll, rychlé) a menu (melodická). Každá je smyčka bez švu: dozvuk za koncem
          se přičte na začátek. Hudba a voda jsou OGG Vorbis, ostatní WAV.

  py tools/gen_sounds.py
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import soundfile
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfilt

from gen_crystal import MATERIALS

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "audio"
RATE = 44100
PEAK = 0.89


# --- Pomůcky ---

def seconds(t: float) -> int:
    return int(round(t * RATE))


def noise(rng: np.random.Generator, length: int) -> np.ndarray:
    return rng.standard_normal(length)


def band(signal: np.ndarray, low: float, high: float, order: int = 2) -> np.ndarray:
    sos = butter(order, [low, high], btype="bandpass", fs=RATE, output="sos")
    return sosfilt(sos, signal)


def lowpass(signal: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sosfilt(butter(order, cutoff, btype="lowpass", fs=RATE, output="sos"), signal)


def highpass(signal: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sosfilt(butter(order, cutoff, btype="highpass", fs=RATE, output="sos"), signal)


def envelope(length: int, attack: float, decay: float) -> np.ndarray:
    """Rychlý náběh a exponenciální dozvuk, časy v sekundách."""
    t = np.arange(length) / RATE
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))


def place(target: np.ndarray, sound: np.ndarray, at: float, gain: float = 1.0) -> None:
    start = seconds(at)
    end = min(start + len(sound), len(target))
    if 0 <= start < len(target):
        target[start:end] += sound[: end - start] * gain


def normalize(signal: np.ndarray, peak: float = PEAK) -> np.ndarray:
    top = np.max(np.abs(signal))
    return signal if top == 0 else signal * (peak / top)


def fade(signal: np.ndarray, start: float = 0.002, end: float = 0.02) -> np.ndarray:
    out = signal.copy()
    a = seconds(start)
    b = seconds(end)
    if a > 0:
        out[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        out[-b:] *= np.linspace(1.0, 0.0, b)
    return out


def trim(signal: np.ndarray, floor: float = 0.0015) -> np.ndarray:
    """Ořízne ticho na konci: konec je tam, kde zvuk naposledy přesáhl floor, plus 50 ms dozvuku."""
    loud = np.nonzero(np.abs(signal) > floor)[0]
    if len(loud) == 0:
        return signal
    end = min(loud[-1] + seconds(0.05), len(signal))
    return fade(signal[:end], 0.0, 0.03)


## Kvalita OGG Vorbis: 0 je nejvyšší kvalita a největší soubor, 1 nejmenší.
OGG_COMPRESSION = 0.45


def write(name: str, signal: np.ndarray) -> Path:
    """name je cesta pod godot/audio bez přípony, třeba steps/grass_1. Smyčky (hudba, voda)
    jdou do OGG Vorbis, jsou dlouhé a ve WAV by zabraly desítky MB. Krátké zvuky zůstanou
    ve WAV, hrají bez zpoždění na dekódování, a ticho na jejich konci se ořízne."""
    loop = name.startswith("music/") or name.startswith("ambient/")
    path = OUT_DIR / f"{name}.{'ogg' if loop else 'wav'}"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not loop:
        signal = trim(signal)
    data = np.clip(signal, -1.0, 1.0)
    if loop:
        # Po kusech: libsndfile na Windows při zápisu dlouhého OGG najednou přeteče zásobník.
        channels = 1 if data.ndim == 1 else data.shape[1]
        with soundfile.SoundFile(path, "w", RATE, channels, "VORBIS", format="OGG", compression_level=OGG_COMPRESSION) as out:
            for start in range(0, len(data), 4096):
                out.write(data[start:start + 4096])
        # Starší WAV stejné skladby a jeho import z editoru by v projektu jen překážely.
        for stale in (path.with_suffix(".wav"), path.with_suffix(".wav.import")):
            if stale.exists():
                stale.unlink()
    else:
        wavfile.write(path, RATE, (data * 32767.0).astype(np.int16))
    return path


def reverb(signal: np.ndarray, size: float = 1.0, wet: float = 0.25) -> np.ndarray:
    """Jednoduchý dozvuk (Schroeder): čtyři hřebenové filtry a dva propustné."""
    combs = [0.0297, 0.0371, 0.0411, 0.0437]
    out = np.zeros_like(signal)
    for delay_s in combs:
        delay = seconds(delay_s * size)
        a = np.zeros(delay + 1)
        a[0] = 1.0
        a[delay] = -0.78
        out += lfilter([1.0], a, signal)
    out /= len(combs)
    for delay_s, gain in [(0.005, 0.7), (0.0017, 0.7)]:
        delay = seconds(delay_s)
        b = np.zeros(delay + 1)
        b[0] = -gain
        b[delay] = 1.0
        a = np.zeros(delay + 1)
        a[0] = 1.0
        a[delay] = -gain
        out = lfilter(b, a, out)
    return signal * (1.0 - wet) + out * wet


def resample(signal: np.ndarray, factor: float) -> np.ndarray:
    """Výška tónu: factor větší než 1 zrychlí a zvýší."""
    length = int(len(signal) / factor)
    return np.interp(np.arange(length) * factor, np.arange(len(signal)), signal)


def seamless(signal: np.ndarray, overlap: int) -> np.ndarray:
    """Konec se prolne se začátkem, smyčka pak nemá šev."""
    body = signal[:-overlap].copy()
    tail = signal[-overlap:]
    ramp = np.linspace(0.0, 1.0, overlap)
    if signal.ndim == 2:
        ramp = ramp[:, None]
    body[:overlap] = body[:overlap] * ramp + tail * (1.0 - ramp)
    return body


def sweep(length: int, f_from: float, f_to: float, curve: float = 1.0) -> np.ndarray:
    """Fáze tónu, který plynule jede z f_from do f_to."""
    t = np.linspace(0.0, 1.0, length)
    freq = f_from + (f_to - f_from) * t ** curve
    return 2 * math.pi * np.cumsum(freq) / RATE


# --- Kroky postavy ---

def crackles(rng: np.random.Generator, length: int, count: int, low: float, high: float, spread: float) -> np.ndarray:
    """Řídká zrna praskání v čase 0..spread sekund, každé 1 až 3 ms."""
    out = np.zeros(length)
    for _ in range(count):
        at = rng.uniform(0.0, spread) * rng.uniform(0.3, 1.0)
        size = seconds(rng.uniform(0.001, 0.003))
        grain = noise(rng, size) * np.hanning(size)
        place(out, grain, at, rng.uniform(0.3, 1.0))
    return band(out, low, high)


def thump(rng: np.random.Generator, length: int, cutoff: float, decay: float) -> np.ndarray:
    return lowpass(noise(rng, length), cutoff, 3) * envelope(length, 0.003, decay)


def step(surface: str, seed: int) -> np.ndarray:
    """Jemný krok: měkký náběh, málo výšek a praskání, tišší než ostatní zvuky."""
    rng = np.random.default_rng(seed)
    length = seconds(0.28)
    out = np.zeros(length)
    if surface == "grass":
        out += band(noise(rng, length), 900, 3800) * envelope(length, 0.018, 0.06) * 0.5
        out += crackles(rng, length, 8, 1800, 4500, 0.1) * 0.25
        out += thump(rng, length, 140, 0.03) * 0.5
    elif surface == "dirt":
        out += thump(rng, length, 200, 0.04) * 1.0
        out += band(noise(rng, length), 400, 1400) * envelope(length, 0.006, 0.025) * 0.25
        place(out, thump(rng, length, 180, 0.03) * 0.45, 0.035)
    elif surface == "desert":
        hiss = band(noise(rng, length), 1500, 5000) * envelope(length, 0.04, 0.08)
        grain = 0.7 + 0.3 * band(noise(rng, length), 20, 80, 1) * 8.0
        out += hiss * np.clip(grain, 0.0, 1.3) * 0.45
        out += thump(rng, length, 160, 0.03) * 0.4
    elif surface == "snow":
        # Sníh křupe ostře: hustší a vyšší praskání s rychlým náběhem, výšky se neořezávají.
        out += crackles(rng, length, 120, 1500, 7500, 0.14) * 1.1
        out += band(noise(rng, length), 900, 3000) * envelope(length, 0.008, 0.04) * 0.3
        out += thump(rng, length, 130, 0.035) * 0.45
    out = lowpass(out, 9000 if surface == "snow" else 5000, 2)
    out = resample(out, rng.uniform(0.94, 1.06))
    return fade(normalize(out, 0.45), 0.004, 0.03)


# --- Voda ---

def water(length_s: float = 10.0) -> np.ndarray:
    rng = np.random.default_rng(7)
    extra = 1.0
    length = seconds(length_s + extra)
    t = np.arange(length) / RATE
    left = np.zeros(length)
    right = np.zeros(length)
    for channel, phase in ((left, 0.0), (right, 1.7)):
        base = lowpass(noise(rng, length), 1100, 2)
        hush = band(noise(rng, length), 1800, 5000) * 0.25
        waves = 0.55 + 0.25 * np.sin(2 * math.pi * 0.17 * t + phase) + 0.2 * np.sin(2 * math.pi * 0.29 * t + phase * 2.0)
        channel += (base + hush) * waves
        for _ in range(int(length_s * 9)):
            dur = rng.uniform(0.02, 0.07)
            size = seconds(dur)
            tt = np.arange(size) / RATE
            f0 = rng.uniform(350, 1300)
            chirp = np.sin(2 * math.pi * (f0 * tt + f0 * 2.5 * tt * tt / dur))
            place(channel, chirp * envelope(size, 0.002, dur * 0.35), rng.uniform(0, length_s + extra), rng.uniform(0.05, 0.18))
    stereo = np.stack([left, right], axis=1)
    return normalize(seamless(stereo, seconds(extra)), 0.6)


# --- Kotlina ---

def basin_hit(value: float, seed: int) -> np.ndarray:
    """Kámen dopadne do kotliny. value je cena materiálu 0 až 1: levný tupě žuchne,
    s cenou přibývá výšky a zvonění, nejdražší cinkne."""
    rng = np.random.default_rng(seed)
    pitch = 260.0 + (2100.0 - 260.0) * value ** 1.15
    ring = 0.015 + (0.45 - 0.015) * value ** 1.6
    length = seconds(0.9 + ring)
    t = np.arange(length) / RATE
    click = highpass(noise(rng, length), 600 + 1400 * value) * envelope(length, 0.0005, 0.004 + 0.003 * value)
    out = click * (0.35 + 0.55 * value)
    for ratio, gain, damp in [(1.0, 1.0, 1.0), (2.32, 0.6, 0.7), (4.25, 0.35, 0.5), (6.63, 0.2, 0.35)]:
        f = pitch * ratio * rng.uniform(0.98, 1.02)
        out += np.sin(2 * math.pi * f * t) * np.exp(-t / (ring * damp)) * gain * (0.15 + 0.2 * value)
    # Tupý náraz: hluboké žuchnutí a šum dopadu, u levných silné, u drahých slabé.
    out += np.sin(2 * math.pi * (95 + 60 * value) * t) * np.exp(-t / 0.07) * (1.0 - 0.6 * value)
    out += lowpass(noise(rng, length), 500, 2) * envelope(length, 0.002, 0.03) * (1.0 - 0.7 * value) * 1.5
    out += basin_bounce(rng, pitch, ring, length) * (0.4 + 0.6 * value)
    out = reverb(out, 0.6, 0.18)
    return fade(normalize(out, 0.8), 0.0005, 0.05)


def basin_bounce(rng: np.random.Generator, pitch: float, ring: float, length: int) -> np.ndarray:
    """Malý odskok a druhé, tišší cvaknutí."""
    out = np.zeros(length)
    size = seconds(0.4)
    t = np.arange(size) / RATE
    hit = highpass(noise(rng, size), 2000) * envelope(size, 0.0004, 0.004) * 0.5
    hit += np.sin(2 * math.pi * pitch * 1.07 * t) * np.exp(-t / (ring * 0.5)) * 0.15
    place(out, hit, rng.uniform(0.09, 0.13))
    return out


# --- Příšery ---

def monster_step(kind: str, seed: int) -> np.ndarray:
    """Krok příšery. Pavouk cupitá několika drobnými ťuknutími, vlk dosedne tlapkou,
    tyranosaurus zaduní, ptakoještěr mávne křídly."""
    rng = np.random.default_rng(seed)
    if kind == "pavouk":
        length = seconds(0.12)
        out = np.zeros(length)
        for i in range(4):
            size = seconds(0.006)
            tick = band(noise(rng, size), 2500, 7000) * np.hanning(size)
            place(out, tick, i * rng.uniform(0.012, 0.02), rng.uniform(0.5, 1.0))
        return fade(normalize(out, 0.3), 0.001, 0.02)
    if kind == "vlk":
        length = seconds(0.22)
        out = thump(rng, length, 260, 0.04)
        out += band(noise(rng, length), 2500, 6000) * envelope(length, 0.001, 0.006) * 0.25
        return fade(normalize(resample(out, rng.uniform(0.93, 1.07)), 0.4), 0.002, 0.03)
    if kind == "tyranosaurus":
        length = seconds(0.7)
        t = np.arange(length) / RATE
        boom = np.sin(sweep(length, 70, 32, 0.5)) * np.exp(-t / 0.22)
        boom += thump(rng, length, 180, 0.12) * 0.8
        boom += lowpass(noise(rng, length), 90, 3) * envelope(length, 0.02, 0.3) * 1.2
        return fade(normalize(np.tanh(boom * 1.5), 0.8), 0.002, 0.08)
    length = seconds(0.45)
    t = np.arange(length) / RATE
    swell = np.interp(t, [0.0, 0.12, 0.22, 0.45], [0.0, 1.0, 0.35, 0.0])
    whoosh = band(noise(rng, length), 250, 1400) * swell
    whoosh += lowpass(noise(rng, length), 160, 2) * np.interp(t, [0.0, 0.1, 0.2, 0.45], [0.0, 1.0, 0.2, 0.0]) * 1.5
    return fade(normalize(whoosh, 0.45), 0.005, 0.05)


def growl_voice(rng: np.random.Generator, dur: float, points: list[float], values: list[float],
                formants: list[tuple[float, float, float]], rough_hz: float, grit: float) -> np.ndarray:
    """Hlas příšery: hrubý tón s výškou podle bodů v čase, podtón, šum dechu, filtry hrdla."""
    length = seconds(dur)
    t = np.arange(length) / RATE
    freq = np.interp(t, points, values) * (1.0 + 0.03 * lowpass(noise(rng, length), 25, 1) * 10.0)
    phase = 2 * math.pi * np.cumsum(freq) / RATE
    source = (2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0 + np.sin(phase * 0.5) * 0.5) * (1.0 + 0.35 * np.sin(2 * math.pi * rough_hz * t))
    breath = band(noise(rng, length), 300, 5000) * 0.5
    voice = np.zeros(length)
    for f, bw, gain in formants:
        voice += band(source + breath * 0.6, max(f - bw, 40.0), f + bw, 2) * gain
    return np.tanh(voice * grit)


def roar(kind: str) -> np.ndarray:
    """Zařvání, když příšera začne honit. Pavouk zasyčí a zacvaká, vlk zavrčí a štěkne,
    tyranosaurus zařve, ptakoještěr zaskřehotá."""
    rng = np.random.default_rng({"pavouk": 1, "vlk": 2, "tyranosaurus": 3, "ptakojester": 4}[kind])
    if kind == "pavouk":
        dur = 1.0
        length = seconds(dur)
        t = np.arange(length) / RATE
        hiss = band(noise(rng, length), 2500, 9000) * (0.6 + 0.4 * np.sign(np.sin(2 * math.pi * 38 * t)))
        shape = np.interp(t, [0.0, 0.08, 0.6, 1.0], [0.0, 1.0, 0.7, 0.0])
        out = hiss * shape
        for i in range(10):
            size = seconds(0.008)
            place(out, band(noise(rng, size), 1500, 5000) * np.hanning(size) * 1.5, 0.05 + i * 0.07)
        return fade(normalize(reverb(out, 0.8, 0.2), 0.7), 0.005, 0.1)
    if kind == "vlk":
        snarl = growl_voice(rng, 1.1, [0.0, 0.15, 0.7, 1.1], [150, 210, 180, 140],
                            [(400, 120, 1.0), (1200, 250, 0.6), (2600, 400, 0.3)], 42, 2.5)
        t = np.arange(len(snarl)) / RATE
        out = snarl * np.interp(t, [0.0, 0.1, 0.8, 1.1], [0.0, 1.0, 0.8, 0.0])
        bark = growl_voice(rng, 0.25, [0.0, 0.05, 0.25], [300, 420, 260],
                           [(700, 200, 1.0), (1500, 300, 0.7), (2800, 400, 0.3)], 0, 3.0)
        bark *= envelope(len(bark), 0.01, 0.07)
        full = np.zeros(seconds(1.5))
        place(full, out, 0.0)
        place(full, bark, 1.1, 1.2)
        return fade(normalize(reverb(full, 1.0, 0.25), 0.8), 0.01, 0.1)
    if kind == "tyranosaurus":
        voice = growl_voice(rng, 2.0, [0.0, 0.25, 0.7, 1.3, 2.0], [70, 135, 120, 85, 55],
                            [(520, 140, 1.0), (980, 200, 0.7), (2400, 400, 0.35), (260, 90, 0.8)], 31, 2.2)
        length = len(voice)
        t = np.arange(length) / RATE
        out = (voice + lowpass(noise(rng, length), 120, 3) * 0.6) * np.interp(t, [0.0, 0.18, 1.2, 2.0], [0.0, 1.0, 0.8, 0.0])
        return fade(normalize(reverb(out, 1.4, 0.3), 0.85), 0.01, 0.2)
    screech = growl_voice(rng, 1.2, [0.0, 0.12, 0.5, 1.2], [650, 1150, 950, 600],
                          [(1800, 400, 1.0), (3200, 600, 0.6), (900, 200, 0.4)], 55, 3.0)
    t = np.arange(len(screech)) / RATE
    out = screech * np.interp(t, [0.0, 0.05, 0.6, 1.2], [0.0, 1.0, 0.7, 0.0])
    return fade(normalize(reverb(out, 1.6, 0.35), 0.75), 0.005, 0.15)


# --- Nástroje ---

NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name: str) -> int:
    letter = name[0]
    rest = name[1:]
    shift = 0
    if rest.startswith("#"):
        shift = 1
        rest = rest[1:]
    elif rest.startswith("b"):
        shift = -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NOTES[letter] + shift


def hz(name: str) -> float:
    """A4, G#3, Bb2 a podobně."""
    return 440.0 * 2 ** ((midi(name) - 69) / 12)


def up(name: str, octaves: int = 1) -> str:
    """Stejná nota o oktávy výš (nebo níž při záporném čísle)."""
    for i in range(len(name) - 1, -1, -1):
        if not name[i].isdigit() and name[i] != "-":
            return name[: i + 1] + str(int(name[i + 1:]) + octaves)
    return name


def saw(t: np.ndarray, freq: float, detune: tuple[float, ...] = (1.0,)) -> np.ndarray:
    return sum(2.0 * ((t * freq * d) % 1.0) - 1.0 for d in detune) / len(detune)


def tone(freq: float, dur: float, kind: str, gain: float, cut: float = 1800.0) -> np.ndarray:
    """Nástroje: pad (plocha, cut je jas), drone, bell (zvonek), bass, ostinato (krátká basa
    honičky), stab (ostrý akord), pluck (drnknutí), marimba, harp (harfa), lead (měkká flétna)."""
    length = seconds(dur + 0.9)
    t = np.arange(length) / RATE
    if kind == "pad":
        wave = lowpass(saw(t, freq, (0.993, 1.0, 1.007)), cut, 2)
        shape = np.clip(t / 0.6, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.6))
    elif kind == "drone":
        wave = np.sin(2 * math.pi * freq * t) + 0.35 * lowpass(saw(t, freq, (0.998, 1.002)), 260, 2)
        shape = np.clip(t / 1.5, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.8))
    elif kind == "bell":
        wave = np.sin(2 * math.pi * freq * t) + 0.3 * np.sin(2 * math.pi * freq * 2.76 * t) * np.exp(-t / 0.4)
        shape = envelope(length, 0.004, 1.6)
    elif kind == "bass":
        wave = lowpass(np.sin(2 * math.pi * freq * t) + 0.4 * saw(t, freq), 400, 2)
        shape = envelope(length, 0.01, 0.6) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.1))
    elif kind == "ostinato":
        wave = lowpass(saw(t, freq, (0.997, 1.003)), 700, 2) + 0.5 * np.sin(2 * math.pi * freq * t)
        shape = envelope(length, 0.002, 0.07)
    elif kind == "stab":
        wave = lowpass(saw(t, freq, (0.99, 1.0, 1.01)), cut, 2)
        shape = envelope(length, 0.004, 0.22)
    elif kind == "pluck":
        wave = lowpass(saw(t, freq) * 0.6 + np.sin(2 * math.pi * freq * t) * 0.4, cut, 2)
        shape = envelope(length, 0.003, 0.25)
    elif kind == "marimba":
        wave = np.sin(2 * math.pi * freq * t) + 0.25 * np.sin(2 * math.pi * freq * 4.0 * t) * np.exp(-t / 0.03)
        shape = envelope(length, 0.002, 0.18)
    elif kind == "harp":
        wave = np.sin(2 * math.pi * freq * t) * 0.7 + (2.0 / math.pi) * np.arcsin(np.sin(2 * math.pi * freq * t)) * 0.3
        wave += 0.15 * np.sin(2 * math.pi * freq * 2 * t) * np.exp(-t / 0.2)
        shape = envelope(length, 0.003, 0.9)
    else:
        vibrato = 1.0 + 0.004 * np.sin(2 * math.pi * 5.2 * t) * np.clip((t - 0.2) / 0.3, 0, 1)
        phase = 2 * math.pi * np.cumsum(freq * vibrato) / RATE
        wave = (2.0 / math.pi) * np.arcsin(np.sin(phase)) * 0.7 + 0.3 * np.sin(phase)
        wave = lowpass(wave, 1600, 2)
        shape = np.clip(t / 0.06, 0, 1) * np.where(t < dur, 1.0 - 0.2 * t / max(dur, 1e-3), np.exp(-(t - dur) / 0.25) * 0.8)
    return wave * shape * gain


def kick(gain: float, deep: float = 45.0) -> np.ndarray:
    length = seconds(0.45)
    t = np.arange(length) / RATE
    freq = deep + 90 * np.exp(-t / 0.03)
    return np.sin(2 * math.pi * np.cumsum(freq) / RATE) * np.exp(-t / 0.15) * gain


def tom(rng: np.random.Generator, pitch: float, gain: float) -> np.ndarray:
    length = seconds(0.5)
    t = np.arange(length) / RATE
    freq = pitch * (1.0 + 0.6 * np.exp(-t / 0.04))
    body = np.sin(2 * math.pi * np.cumsum(freq) / RATE) * np.exp(-t / 0.18)
    hit = band(noise(rng, length), 200, 2500) * envelope(length, 0.001, 0.02) * 0.4
    return (body + hit) * gain


def snare(rng: np.random.Generator, gain: float) -> np.ndarray:
    length = seconds(0.3)
    t = np.arange(length) / RATE
    rattle = band(noise(rng, length), 1500, 7000) * envelope(length, 0.001, 0.07)
    body = np.sin(2 * math.pi * 190 * t) * np.exp(-t / 0.05) * 0.6
    return (rattle + body) * gain


def shaker(rng: np.random.Generator, gain: float) -> np.ndarray:
    length = seconds(0.08)
    return highpass(noise(rng, length), 6000) * envelope(length, 0.004, 0.02) * gain


def hat(rng: np.random.Generator, gain: float) -> np.ndarray:
    length = seconds(0.05)
    return highpass(noise(rng, length), 8000) * envelope(length, 0.001, 0.012) * gain


def clap(rng: np.random.Generator, gain: float) -> np.ndarray:
    """Tlesknutí: tři rychlé záblesky šumu těsně za sebou."""
    length = seconds(0.25)
    out = np.zeros(length)
    for i, delay in enumerate((0.0, 0.008, 0.016)):
        burst = band(noise(rng, length), 900, 5000) * envelope(length, 0.0005, 0.012 if i < 2 else 0.06)
        place(out, burst, delay, 0.7 if i < 2 else 1.0)
    return out * gain


class Track:
    """Stereo stopa: zvuky se kladou na dobu s rozmístěním doleva a doprava. Dozvuk za koncem
    se při render přičte na začátek, smyčka pak navazuje."""

    def __init__(self, bars: int, bpm: float, tail: float = 3.0) -> None:
        self.beat = 60.0 / bpm
        self.total = bars * 4 * self.beat
        length = seconds(self.total + tail)
        self.left = np.zeros(length)
        self.right = np.zeros(length)

    def add(self, sound: np.ndarray, beat: float, pan: float = 0.0) -> None:
        at = beat * self.beat
        place(self.left, sound, at, math.sqrt(0.5 * (1.0 - pan)))
        place(self.right, sound, at, math.sqrt(0.5 * (1.0 + pan)))

    def render(self, size: float, wet: float, peak: float = 0.8) -> np.ndarray:
        stereo = np.stack([reverb(self.left, size, wet), reverb(self.right, size * 1.07, wet)], axis=1)
        cut = seconds(self.total)
        loop = stereo[:cut].copy()
        overflow = stereo[cut:]
        loop[: len(overflow)] += overflow
        return normalize(loop, peak)


# --- Hudba do hry: dur, vesele, bez výrazné melodie ---

GAME = [
    # C G Am F, 100 BPM: rozklad akordů, poskakující basa, kopák s tlesknutím.
    {"bpm": 100, "seed": 11, "comp": "arp", "drums": "pop", "swing": 0.0, "pad": 1800,
     "chords": [(["C3", "G3", "E4"], "C2"), (["G2", "D3", "B3"], "G1"), (["A2", "E3", "C4"], "A1"), (["F2", "C3", "A3"], "F1")],
     "bass": [(0, "root", 0.9, 0.3), (1.5, "root", 0.4, 0.2), (2, "fifth", 0.9, 0.24), (3.5, "root", 0.4, 0.2)]},
    # G Em C D, 96 BPM, houpavě: marimba v šestnáctinách, chrastítko se švihem.
    {"bpm": 96, "seed": 12, "comp": "marimba", "drums": "shuffle", "swing": 0.16, "pad": 1500,
     "chords": [(["G3", "B3", "D4"], "G1"), (["E3", "G3", "B3"], "E2"), (["C3", "E3", "G3"], "C2"), (["D3", "F#3", "A3"], "D2")],
     "bass": [(0, "root", 0.6, 0.3), (1, "fifth", 0.4, 0.2), (2, "oct", 0.6, 0.24), (3, "fifth", 0.4, 0.2)]},
    # D C G D, 108 BPM, zvesela: drnkané akordy na každou dobu, tlesknutí na 2 a 4.
    {"bpm": 108, "seed": 13, "comp": "strum", "drums": "pop", "swing": 0.0, "pad": 2000,
     "chords": [(["D3", "F#3", "A3"], "D2"), (["C3", "E3", "G3"], "C2"), (["G2", "B2", "D3"], "G1"), (["D3", "F#3", "A3"], "D2")],
     "bass": [(0, "root", 0.4, 0.3), (0.75, "root", 0.2, 0.18), (1.5, "fifth", 0.4, 0.22), (2.5, "oct", 0.4, 0.22), (3.5, "fifth", 0.4, 0.18)]},
    # F Dm Bb C, 92 BPM, uvolněně: akordy na lehké doby, kopák jen na trojku.
    {"bpm": 92, "seed": 14, "comp": "offbeat", "drums": "drop", "swing": 0.0, "pad": 1400,
     "chords": [(["F3", "A3", "C4"], "F1"), (["D3", "F3", "A3"], "D2"), (["Bb2", "D3", "F3"], "Bb1"), (["C3", "E3", "G3"], "C2")],
     "bass": [(0, "root", 1.4, 0.32), (2, "fifth", 0.6, 0.22), (2.75, "root", 0.4, 0.2), (3.5, "oct", 0.4, 0.18)]},
]


def swung(beat: float, swing: float) -> float:
    """Druhá osmina doby se opozdí o swing doby, hudba se houpe."""
    whole = math.floor(beat)
    part = beat - whole
    if abs(part - 0.5) < 1e-6:
        return whole + 0.5 + swing
    if abs(part - 0.75) < 1e-6:
        return whole + 0.75 + swing * 0.5
    return beat


def game_music(cfg: dict) -> np.ndarray:
    rng = np.random.default_rng(cfg["seed"])
    bars = 16
    track = Track(bars, cfg["bpm"], 3.0)
    swing = cfg["swing"]
    for bar in range(bars):
        start = bar * 4
        triad, root = cfg["chords"][bar % 4]
        for note in triad:
            track.add(tone(hz(note), 4 * track.beat, "pad", 0.07, cfg["pad"]), start, rng.uniform(-0.5, 0.5))
        # Basa: základní tón, čistá kvinta nad ním a oktáva.
        notes = {"root": hz(root), "fifth": hz(root) * 2 ** (7 / 12), "oct": hz(root) * 2.0}
        if bar >= 1:
            for beat, which, length, gain in cfg["bass"]:
                track.add(tone(notes[which], length * track.beat, "bass", gain), start + swung(beat, swing))
        if bar >= 2:
            comp(track, cfg["comp"], triad, start, swing, rng)
        if bar >= 4:
            drums(track, cfg["drums"], start, swing, rng)
        if bar >= 8:
            top = up(triad[2])
            for beat in (0.5, 1.5, 2.5, 3.5) if bar % 2 else (0.5, 2.5):
                track.add(tone(hz(top), 0.5 * track.beat, "bell", 0.04), start + swung(beat, swing), rng.uniform(-0.6, 0.6))
    return track.render(1.4, 0.24)


def comp(track: Track, style: str, triad: list[str], start: float, swing: float, rng: np.random.Generator) -> None:
    """Doprovod: rozklad akordu, marimba, drnkání nebo akordy na lehké doby."""
    if style == "arp":
        arp = [triad[0], triad[2], triad[1], triad[2]]
        for i in range(8):
            track.add(tone(hz(up(arp[i % 4])), 0.35 * track.beat, "lead", 0.05), start + swung(i * 0.5, swing), 0.45 if i % 2 else -0.45)
    elif style == "marimba":
        pattern = [triad[0], triad[1], triad[2], up(triad[0]), triad[2], triad[1]]
        for i in range(16):
            if i % 4 == 3:
                continue
            note = up(pattern[i % len(pattern)])
            track.add(tone(hz(note), 0.2 * track.beat, "marimba", 0.09 if i % 4 == 0 else 0.06), start + swung(i * 0.25, swing), rng.uniform(-0.5, 0.5))
    elif style == "strum":
        for beat in range(4):
            gain = 0.07 if beat % 2 == 0 else 0.05
            for k, note in enumerate(triad + [up(triad[0])]):
                track.add(tone(hz(up(note)), 0.6 * track.beat, "pluck", gain, 2400), start + beat + k * 0.03, -0.3 + k * 0.2)
    else:
        for beat in (0.5, 1.5, 2.5, 3.5):
            for note in triad:
                track.add(tone(hz(up(note)), 0.25 * track.beat, "pluck", 0.055, 2000), start + beat, rng.uniform(-0.4, 0.4))


def drums(track: Track, style: str, start: float, swing: float, rng: np.random.Generator) -> None:
    """Bicí: pop (kopák 1 a 3, tlesknutí 2 a 4), shuffle (se švihem), drop (kopák jen na 3)."""
    if style == "drop":
        track.add(kick(0.32, 46.0), start + 2)
        track.add(clap(rng, 0.11), start + 1, 0.2)
        track.add(clap(rng, 0.11), start + 3, 0.2)
        for six in range(16):
            track.add(hat(rng, 0.03 if six % 2 else 0.05), start + six * 0.25, 0.5)
        return
    track.add(kick(0.3, 48.0), start)
    track.add(kick(0.22, 48.0), start + 2)
    if style == "pop":
        track.add(kick(0.12, 48.0), start + 2.75)
    track.add(clap(rng, 0.15), start + 1, 0.15)
    track.add(clap(rng, 0.15), start + 3, 0.15)
    for half in range(8):
        track.add(shaker(rng, 0.03 if half % 2 else 0.045), start + swung(half * 0.5, swing), 0.6)


# --- Hudba při honičce: moll, rychle, napětí ---

CHASE = [
    # Am Am F E, 140 BPM: basa v šestnáctinách, kopák na každou dobu.
    {"bpm": 140, "seed": 21, "drums": "four", "stab_beats": [0, 2.5],
     "roots": ["A1", "A1", "F1", "E1"],
     "stabs": [["A3", "C4", "E4"], ["A3", "C4", "E4"], ["F3", "A3", "C4"], ["E3", "G#3", "B3"]],
     "pattern": [1, 1, 2, 1] * 4},
    # Em C D B, 150 BPM: cval (osmina a dvě šestnáctiny), víry tomů.
    {"bpm": 150, "seed": 22, "drums": "gallop", "stab_beats": [0, 3],
     "roots": ["E1", "C2", "D2", "B1"],
     "stabs": [["E3", "G3", "B3"], ["C3", "E3", "G3"], ["D3", "F#3", "A3"], ["B2", "D#3", "F#3"]],
     "pattern": [1, 0, 1, 1] * 4},
    # Bm G A F#, 132 BPM: těžký poloviční rytmus, šestnáctinové činely, stoupající akordy.
    {"bpm": 132, "seed": 23, "drums": "half", "stab_beats": [0, 1.5, 3],
     "roots": ["B1", "G1", "A1", "F#1"],
     "stabs": [["B2", "D3", "F#3"], ["G2", "B2", "D3"], ["A2", "C#3", "E3"], ["F#2", "A#2", "C#3"]],
     "pattern": [1, 2, 1, 1, 2, 1, 1, 2, 1, 1, 2, 1, 2, 1, 2, 2]},
    # Dm Bb C A, 146 BPM: pulzující oktávy, virbl s duchy, akordy na lehké doby.
    {"bpm": 146, "seed": 24, "drums": "break", "stab_beats": [0.5, 1.5, 2.5, 3.5],
     "roots": ["D2", "Bb1", "C2", "A1"],
     "stabs": [["D3", "F3", "A3"], ["Bb2", "D3", "F3"], ["C3", "E3", "G3"], ["A2", "C#3", "E3"]],
     "pattern": [1, 2] * 8},
]


def chase_music(cfg: dict) -> np.ndarray:
    rng = np.random.default_rng(cfg["seed"])
    bars = 8
    track = Track(bars, cfg["bpm"], 2.0)
    for bar in range(bars):
        start = bar * 4
        root = cfg["roots"][bar % 4]
        for six, kind in enumerate(cfg["pattern"]):
            if kind == 0:
                continue
            note = up(root) if kind == 2 else root
            gain = 0.32 if six % 4 == 0 else 0.22
            track.add(tone(hz(note), 0.2 * track.beat, "ostinato", gain), start + six * 0.25)
        rise = 1.0 + 0.04 * (bar % 4) if cfg["drums"] == "half" else 1.0
        for beat in cfg["stab_beats"]:
            for note in cfg["stabs"][bar % 4]:
                track.add(tone(hz(note) * rise, 0.4 * track.beat, "stab", 0.1), start + beat, rng.uniform(-0.4, 0.4))
        chase_drums(track, cfg["drums"], start, bar, rng)
    for i in range(16):
        track.add(snare(rng, 0.08 + 0.2 * i / 16), (bars - 1) * 4 + 2 + i * 0.125, 0.1)
    return track.render(1.2, 0.22, 0.85)


def chase_drums(track: Track, style: str, start: float, bar: int, rng: np.random.Generator) -> None:
    if style == "half":
        track.add(kick(0.45), start)
        track.add(kick(0.35), start + 1.5)
        track.add(snare(rng, 0.35), start + 2, 0.1)
        for six in range(16):
            track.add(hat(rng, 0.05 if six % 2 else 0.08), start + six * 0.25, 0.5)
    elif style == "break":
        for beat in (0, 0.75, 2.5):
            track.add(kick(0.42), start + beat)
        track.add(snare(rng, 0.32), start + 1, 0.1)
        track.add(snare(rng, 0.32), start + 3, 0.1)
        for ghost in (1.75, 2.25, 3.75):
            track.add(snare(rng, 0.08), start + ghost, 0.1)
        for half in range(8):
            track.add(hat(rng, 0.06), start + half * 0.5, 0.5)
    else:
        for beat in range(4):
            track.add(kick(0.42), start + beat)
        track.add(snare(rng, 0.3), start + 1, 0.1)
        track.add(snare(rng, 0.3), start + 3, 0.1)
        for half in range(8):
            track.add(shaker(rng, 0.04 if half % 2 else 0.06), start + half * 0.5, 0.5)
    if bar % 2 == 1:
        for i, pitch in enumerate([180, 150, 120, 95]):
            track.add(tom(rng, pitch, 0.35 if style != "gallop" else 0.42), start + 3 + i * 0.25, -0.5 + i * 0.33)


# --- Hudba do menu: melodická ---

def menu_music() -> np.ndarray:
    """Hudba do menu: D dur, 76 BPM, klidně a hezky. Čtyři takty úvodu s harfou a plochou,
    pak melodie flétny ve dvou osmitaktových větách, ve druhé ji zdvojí zvonek o oktávu výš."""
    rng = np.random.default_rng(31)
    track = Track(20, 76, 5.0)
    chords = {
        "D": (["D3", "F#3", "A3"], "D2"), "A": (["A2", "C#3", "E3"], "A1"), "Bm": (["B2", "D3", "F#3"], "B1"),
        "G": (["G2", "B2", "D3"], "G1"), "Em": (["E3", "G3", "B3"], "E2"),
    }
    progression = ["D", "A", "Bm", "G"] + ["D", "A", "Bm", "G", "D", "A", "G", "A"] + ["Bm", "G", "D", "A", "Bm", "G", "Em", "A"]
    melody = [
        [(0, 1.5, "F#5"), (1.5, 0.5, "E5"), (2, 2, "D5")],
        [(0, 1, "C#5"), (1, 1, "E5"), (2, 2, "A4")],
        [(0, 1.5, "D5"), (1.5, 0.5, "C#5"), (2, 1, "B4"), (3, 1, "F#4")],
        [(0, 3, "G4"), (3, 1, "A4")],
        [(0, 1.5, "F#5"), (1.5, 0.5, "G5"), (2, 1, "A5"), (3, 1, "F#5")],
        [(0, 1, "E5"), (1, 1, "C#5"), (2, 2, "E5")],
        [(0, 1, "D5"), (1, 1, "B4"), (2, 1, "G4"), (3, 1, "B4")],
        [(0, 4, "A4")],
        [(0, 1.5, "B5"), (1.5, 0.5, "A5"), (2, 2, "F#5")],
        [(0, 1, "G5"), (1, 1, "F#5"), (2, 2, "D5")],
        [(0, 1.5, "F#5"), (1.5, 0.5, "E5"), (2, 1, "D5"), (3, 1, "A4")],
        [(0, 2, "C#5"), (2, 2, "E5")],
        [(0, 1, "D5"), (1, 1, "F#5"), (2, 2, "B5")],
        [(0, 1.5, "A5"), (1.5, 0.5, "G5"), (2, 2, "D5")],
        [(0, 1, "E5"), (1, 1, "F#5"), (2, 1, "G5"), (3, 1, "C#5")],
        [(0, 2, "E5"), (2, 2, "A4")],
    ]
    for bar, name in enumerate(progression):
        start = bar * 4
        triad, root = chords[name]
        for note in triad:
            track.add(tone(hz(note), 4 * track.beat, "pad", 0.06, 1500), start, rng.uniform(-0.5, 0.5))
        track.add(tone(hz(root), 3.8 * track.beat, "bass", 0.18), start)
        harp = [triad[0], triad[1], triad[2], up(triad[0]), up(triad[1]), up(triad[0]), triad[2], triad[1]]
        for i, note in enumerate(harp):
            track.add(tone(hz(note), 0.5 * track.beat, "harp", 0.07), start + i * 0.5, -0.6 + 0.17 * i)
        if bar >= 4:
            phrase = melody[bar - 4]
            for at, length, note in phrase:
                track.add(tone(hz(note), length * track.beat * 0.97, "lead", 0.15), start + at, -0.05)
                if bar >= 12:
                    track.add(tone(hz(up(note)), length * track.beat, "bell", 0.025), start + at, 0.3)
        if bar >= 12:
            for half in range(8):
                if half % 2:
                    track.add(shaker(rng, 0.015), start + half * 0.5, 0.6)
    return track.render(2.0, 0.34, 0.8)


# --- Efekty a menu ---

def chime(notes: list[tuple[float, str, float]], kind: str = "bell", gain: float = 0.6, total: float = 0.6) -> np.ndarray:
    """Pár tónů za sebou: (čas v sekundách, nota, délka)."""
    out = np.zeros(seconds(total + 1.0))
    for at, note, length in notes:
        place(out, tone(hz(note), length, kind, gain), at)
    return out


def sfx(name: str) -> np.ndarray:
    rng = np.random.default_rng(len(name) * 7)
    if name == "pickup":
        out = chime([(0.0, "E6", 0.15), (0.06, "B6", 0.25)], "bell", 0.5, 0.4)
        out += highpass(noise(rng, len(out)), 5000) * envelope(len(out), 0.002, 0.05) * 0.1
        return fade(normalize(reverb(out, 0.7, 0.2), 0.55), 0.001, 0.2)
    if name == "steal":
        length = seconds(0.6)
        t = np.arange(length) / RATE
        whoosh = band(noise(rng, length), 400, 3000) * np.interp(t, [0.0, 0.08, 0.6], [0.0, 1.0, 0.0])
        down = np.sin(sweep(length, 520, 140, 0.7)) * envelope(length, 0.01, 0.25) * 0.8
        down += np.sin(sweep(length, 555, 150, 0.7)) * envelope(length, 0.01, 0.25) * 0.5
        return fade(normalize(whoosh * 0.6 + down, 0.7), 0.002, 0.1)
    if name == "jump":
        length = seconds(0.25)
        t = np.arange(length) / RATE
        out = band(noise(rng, length), 600, 3000) * np.interp(t, [0.0, 0.05, 0.25], [0.0, 1.0, 0.0])
        return fade(normalize(out, 0.3), 0.002, 0.05)
    if name == "land":
        length = seconds(0.3)
        out = thump(rng, length, 220, 0.05) + band(noise(rng, length), 600, 2500) * envelope(length, 0.002, 0.02) * 0.3
        return fade(normalize(out, 0.45), 0.002, 0.04)
    return np.zeros(1)


def ui(name: str) -> np.ndarray:
    rng = np.random.default_rng(len(name) * 13)
    if name == "move":
        return fade(normalize(tone(hz("A5"), 0.05, "marimba", 1.0)[: seconds(0.15)], 0.35), 0.001, 0.05)
    if name == "select":
        return fade(normalize(chime([(0.0, "E5", 0.1), (0.07, "A5", 0.2)], "marimba", 1.0, 0.35), 0.5), 0.001, 0.15)
    if name == "back":
        return fade(normalize(chime([(0.0, "A5", 0.1), (0.07, "E5", 0.2)], "marimba", 1.0, 0.35), 0.45), 0.001, 0.15)
    if name == "join":
        out = chime([(0.0, "C5", 0.12), (0.07, "E5", 0.12), (0.14, "G5", 0.12), (0.21, "C6", 0.35)], "bell", 0.6, 0.7)
        return fade(normalize(reverb(out, 0.8, 0.2), 0.55), 0.001, 0.2)
    if name == "leave":
        out = chime([(0.0, "G5", 0.12), (0.08, "D5", 0.12), (0.16, "G4", 0.3)], "marimba", 1.0, 0.6)
        return fade(normalize(out, 0.45), 0.001, 0.15)
    if name == "start":
        length = seconds(1.4)
        t = np.arange(length) / RATE
        rise = band(noise(rng, length), 800, 6000) * np.interp(t, [0.0, 0.5, 0.6, 1.4], [0.0, 0.8, 0.2, 0.0]) * 0.4
        out = rise + chime([(0.5, "D4", 1.0), (0.5, "F#4", 1.0), (0.5, "A4", 1.0), (0.5, "D5", 1.0)], "pluck", 0.4, 0.9)[:length]
        return fade(normalize(reverb(out, 1.2, 0.25), 0.7), 0.002, 0.3)
    if name == "win":
        notes = [(0.0, "C5", 0.18), (0.15, "E5", 0.18), (0.3, "G5", 0.18), (0.45, "C6", 0.5),
                 (0.7, "C5", 1.2), (0.7, "E5", 1.2), (0.7, "G5", 1.2)]
        out = chime(notes, "pluck", 0.4, 2.0) + chime([(0.45, "C7", 0.8), (0.75, "G6", 0.8)], "bell", 0.15, 2.0)
        return fade(normalize(reverb(out, 1.4, 0.3), 0.75), 0.002, 0.4)
    if name == "lose":
        notes = [(0.0, "A4", 0.3), (0.3, "F4", 0.3), (0.6, "D4", 0.3), (0.9, "C#4", 1.2),
                 (0.9, "A3", 1.2), (0.9, "E4", 1.2)]
        out = chime(notes, "pad", 0.25, 2.2) + chime([(0.0, "A2", 2.0)], "bass", 0.3, 2.2)
        return fade(normalize(reverb(out, 1.6, 0.3), 0.7), 0.01, 0.5)
    if name == "tick":
        length = seconds(0.08)
        out = band(noise(rng, length), 2000, 6000) * envelope(length, 0.0005, 0.006)
        out += tone(hz("E6"), 0.02, "marimba", 0.3)[:length]
        return fade(normalize(out, 0.4), 0.0005, 0.02)
    return np.zeros(1)


def main() -> None:
    written: list[Path] = []
    for surface in ("grass", "dirt", "desert", "snow"):
        for variant in range(4):
            written.append(write(f"steps/{surface}_{variant + 1}", step(surface, 100 + variant * 17 + len(surface))))
    written.append(write("ambient/water", water()))
    names = sorted(MATERIALS, key=lambda name: MATERIALS[name]["points"])
    for order, name in enumerate(names):
        written.append(write(f"basin/{name}", basin_hit(order / max(len(names) - 1, 1), 5 + order)))
    for kind in ("pavouk", "vlk", "tyranosaurus", "ptakojester"):
        for variant in range(3):
            written.append(write(f"monsters/{kind}_step_{variant + 1}", monster_step(kind, 40 + variant * 11 + len(kind))))
        written.append(write(f"monsters/{kind}_roar", roar(kind)))
    for name in ("pickup", "steal", "jump", "land"):
        written.append(write(f"sfx/{name}", sfx(name)))
    for name in ("move", "select", "back", "join", "leave", "start", "win", "lose", "tick"):
        written.append(write(f"ui/{name}", ui(name)))
    for i, cfg in enumerate(GAME):
        written.append(write(f"music/game_{i + 1}", game_music(cfg)))
    for i, cfg in enumerate(CHASE):
        written.append(write(f"music/chase_{i + 1}", chase_music(cfg)))
    written.append(write("music/menu", menu_music()))
    for path in written:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
