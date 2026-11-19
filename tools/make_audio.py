"""Generates Firstborn's soundtrack (10 ambient tracks) and UI sounds.

Everything is synthesised from scratch with numpy: soft pads, plucked strings, a breathy
flute, frame drums and a simple reverb. Output: OGG Vorbis music, WAV clicks.
"""
import os
import subprocess
import sys

import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 32000
OUT = sys.argv[1] if len(sys.argv) > 1 else "audio"
os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)

MODES = {
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "ionian": [0, 2, 4, 5, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "pent_minor": [0, 3, 5, 7, 10],
    "pent_major": [0, 2, 4, 7, 9],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
}


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def env_adsr(n, a, d, s, r):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    e = np.ones(n) * s
    a = min(a, n)
    e[:a] = np.linspace(0, 1, a, endpoint=False) if a > 0 else e[:a]
    d_end = min(a + d, n)
    if d_end > a:
        e[a:d_end] = np.linspace(1, s, d_end - a, endpoint=False)
    if r > 0 and n > r:
        e[n - r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff, order=2):
    sos = butter(order, min(cutoff, SR * 0.45), btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def pad(freqs, dur, rng, bright=0.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.0, 0.13):
            ff = f * 2 ** (det / 12.0)
            ph = rng.uniform(0, 2 * np.pi)
            lfo = 1.0 + 0.002 * np.sin(2 * np.pi * rng.uniform(0.1, 0.3) * t)
            wave = np.zeros(n)
            for h in range(1, 7):
                wave += np.sin(2 * np.pi * ff * h * t * lfo + ph * h) * (bright ** (h - 1)) / h
            out += wave
    out = lowpass(out, 1800 + 2200 * bright)
    return out * env_adsr(n, dur * 0.35, 0.1, 1.0, dur * 0.35) / (len(freqs) * 3)


def pluck(f, dur, bright=0.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for h in range(1, 12):
        amp = (bright ** (h - 1)) / h
        out += amp * np.sin(2 * np.pi * f * h * t) * np.exp(-t * (2.0 + h * 1.1))
    out *= env_adsr(n, 0.004, 0.0, 1.0, 0.05)
    return out * 0.5


def flute(f, dur, rng, vib=0.004):
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = 1.0 + vib * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.4, 0, 1)
    tone = np.sin(2 * np.pi * f * t * v) + 0.18 * np.sin(2 * np.pi * 2 * f * t * v) + 0.06 * np.sin(2 * np.pi * 3 * f * t * v)
    breath = lowpass(rng.normal(0, 1, n), f * 2.5) * 0.06
    e = env_adsr(n, 0.09, 0.15, 0.8, min(0.25, dur * 0.4))
    return (tone + breath) * e * 0.28


def drum(kind, rng):
    if kind == "low":
        dur = 0.6
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = 70 + 60 * np.exp(-t * 25)
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
        x += lowpass(rng.normal(0, 1, n), 400) * np.exp(-t * 30) * 0.3
        return x * 0.9
    if kind == "mid":
        dur = 0.35
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = 160 + 80 * np.exp(-t * 30)
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 12)
        x += lowpass(rng.normal(0, 1, n), 1500) * np.exp(-t * 35) * 0.4
        return x * 0.5
    # shaker / rattle
    dur = 0.12
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = rng.normal(0, 1, n)
    sos = butter(2, [3000, 9000], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x) * np.exp(-t * 40) * 0.25


def reverb(x, rng, size=2.4, wet=0.32):
    n = int(size * SR)
    t = np.arange(n) / SR
    ir = rng.normal(0, 1, n) * np.exp(-t * (6.0 / size))
    ir = lowpass(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2))
    y = fftconvolve(x, ir)[: len(x)]
    return x * (1 - wet) + y * wet * 1.4


def add(buf, sig, at):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


TRACKS = [
    # name, root, mode, bpm, progression (scale degrees), instruments, seed, length (s)
    ("first_fire", 50, "dorian", 66, [0, 3, 4, 0], {"pad": 1.0, "pluck": 0.9, "flute": 0.5, "drum": 0.6}, 11, 150),
    ("river_dawn", 55, "pent_major", 72, [0, 4, 3, 0], {"pad": 0.9, "pluck": 1.0, "flute": 0.8, "drum": 0.0}, 22, 150),
    ("long_winter", 45, "aeolian", 54, [0, 5, 3, 4], {"pad": 1.2, "pluck": 0.4, "flute": 0.6, "drum": 0.0}, 33, 160),
    ("stone_circle", 48, "phrygian", 60, [0, 1, 0, 6], {"pad": 1.0, "pluck": 0.5, "flute": 0.4, "drum": 1.0}, 44, 150),
    ("bronze_market", 53, "mixolydian", 92, [0, 6, 3, 4], {"pad": 0.7, "pluck": 1.2, "flute": 0.6, "drum": 0.9}, 55, 140),
    ("wandering_herds", 52, "pent_minor", 80, [0, 2, 3, 0], {"pad": 0.8, "pluck": 1.0, "flute": 0.9, "drum": 0.7}, 66, 150),
    ("night_drums", 43, "dorian", 96, [0, 0, 3, 4], {"pad": 0.8, "pluck": 0.3, "flute": 0.3, "drum": 1.4}, 77, 140),
    ("iron_rain", 47, "aeolian", 70, [0, 6, 5, 4], {"pad": 1.1, "pluck": 0.8, "flute": 0.4, "drum": 0.8}, 88, 150),
    ("harvest_song", 57, "ionian", 84, [0, 3, 4, 0], {"pad": 0.8, "pluck": 1.1, "flute": 1.0, "drum": 0.6}, 99, 140),
    ("distant_shores", 50, "pent_major", 62, [0, 2, 4, 3], {"pad": 1.1, "pluck": 0.6, "flute": 0.8, "drum": 0.0}, 110, 160),
]


def make_track(name, root, mode, bpm, prog, inst, seed, length):
    rng = np.random.default_rng(seed)
    scale = MODES[mode]
    beat = 60.0 / bpm
    bar = beat * 4
    n = int((length + 4) * SR)
    left = np.zeros(n)
    right = np.zeros(n)

    def deg(d, octave=0):
        k = len(scale)
        return root + scale[d % k] + 12 * (d // k + octave)

    bars = int(length / bar)
    chord_bars = 2
    melody_seed = rng.integers(0, 10000)
    mrng = np.random.default_rng(melody_seed)
    # a short motif the melody keeps coming back to
    motif = [int(x) for x in mrng.integers(0, len(scale) + 2, 6)]
    for b in range(0, bars, chord_bars):
        chord_deg = prog[(b // chord_bars) % len(prog)]
        t0 = b * bar
        dur = bar * chord_bars
        # section shape: sparse intro and outro, fuller middle
        frac = b / max(1, bars)
        density = 0.45 + 0.55 * np.sin(np.pi * min(1.0, frac * 1.15)) ** 1.2
        if inst["pad"] > 0:
            freqs = [hz(deg(chord_deg, -1)), hz(deg(chord_deg + 2, -1)), hz(deg(chord_deg + 4, -1)), hz(deg(chord_deg, -2))]
            p = pad(freqs, dur + 1.5, rng, 0.35) * inst["pad"] * 0.55
            add(left, p, t0)
            add(right, p * 0.95, t0 + 0.01)
        if inst["pluck"] > 0:
            # arpeggio pattern
            steps = int(dur / (beat / 2))
            pattern = [0, 2, 4, 2, 7, 4, 2, 4]
            for s in range(steps):
                if rng.random() > 0.55 + density * 0.45:
                    continue
                d = chord_deg + pattern[s % len(pattern)]
                f = hz(deg(d, 0))
                pl = pluck(f, 1.6, 0.55) * inst["pluck"] * 0.35 * (0.8 + 0.2 * rng.random())
                pan = 0.5 + 0.35 * np.sin(s * 0.7)
                add(left, pl * (1 - pan) * 1.4, t0 + s * beat / 2)
                add(right, pl * pan * 1.4, t0 + s * beat / 2)
        if inst["flute"] > 0 and frac > 0.12 and frac < 0.92 and rng.random() < 0.75 * density:
            # a phrase built from the motif, shifted to the chord
            tt = t0 + beat * rng.integers(0, 2)
            for i, m in enumerate(motif):
                if rng.random() < 0.25:
                    continue
                d = chord_deg + m + (1 if rng.random() < 0.2 else 0)
                ln = beat * (1 if i < len(motif) - 1 else 2.5) * (1.5 if rng.random() < 0.3 else 1.0)
                fl = flute(hz(deg(d, 1)), ln + 0.2, rng) * inst["flute"] * 0.55
                add(left, fl * 0.85, tt)
                add(right, fl, tt + 0.008)
                tt += ln
                if tt > t0 + dur:
                    break
        if inst["drum"] > 0 and frac > 0.06 and frac < 0.96:
            for bb in range(chord_bars):
                bt = t0 + bb * bar
                for q in range(8):
                    at = bt + q * beat / 2
                    if q in (0, 5) or (q == 3 and rng.random() < 0.5 * density):
                        dr = drum("low", rng) * inst["drum"] * 0.55
                        add(left, dr, at)
                        add(right, dr, at)
                    elif q in (2, 6) and rng.random() < 0.8 * density:
                        dr = drum("mid", rng) * inst["drum"] * 0.45
                        add(left, dr * 0.7, at)
                        add(right, dr, at)
                    if rng.random() < 0.55 * density:
                        sh = drum("shaker", rng) * inst["drum"] * 0.6
                        add(left, sh, at + beat / 4)
                        add(right, sh * 0.6, at + beat / 4)
    # ambience: soft wind
    wind = lowpass(rng.normal(0, 1, n), 600) * 0.012
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * np.arange(n) / SR)
    left += wind
    right += wind[::-1]
    left = reverb(left, rng)
    right = reverb(right, np.random.default_rng(seed + 1))
    st = np.stack([left, right], axis=1)
    st = st[: int(length * SR)]
    # fades so tracks blend into each other
    fade = int(5 * SR)
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    peak = np.max(np.abs(st)) + 1e-9
    st = np.tanh(st / peak * 1.1) * 0.7
    return st


def write_ogg(path, st):
    raw = (np.clip(st, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", path], input=raw, check=True)


def write_wav(path, mono):
    import wave
    data = (np.clip(mono, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(data)


def ui_sounds():
    sr = 44100
    rng = np.random.default_rng(7)
    # click: a soft wooden "tock"
    n = int(0.09 * sr)
    t = np.arange(n) / sr
    tock = np.sin(2 * np.pi * 820 * t) * np.exp(-t * 70) + 0.4 * np.sin(2 * np.pi * 1640 * t) * np.exp(-t * 110)
    tock += 0.15 * rng.normal(0, 1, n) * np.exp(-t * 400)
    write_wav(os.path.join(OUT, "sfx", "click.wav"), tock * 0.5)
    # toggle: two quick ticks
    n = int(0.12 * sr)
    t = np.arange(n) / sr
    tick = np.sin(2 * np.pi * 1200 * t) * np.exp(-t * 90)
    t2 = np.clip(t - 0.045, 0, None)
    tick += (t > 0.045) * np.sin(2 * np.pi * 1500 * t2) * np.exp(-t2 * 90)
    write_wav(os.path.join(OUT, "sfx", "toggle.wav"), tick * 0.4)
    # hover: very soft high blip
    n = int(0.05 * sr)
    t = np.arange(n) / sr
    blip = np.sin(2 * np.pi * 1900 * t) * np.exp(-t * 120)
    write_wav(os.path.join(OUT, "sfx", "hover.wav"), blip * 0.12)
    # confirm: a pleasant rising chime
    n = int(0.45 * sr)
    t = np.arange(n) / sr
    ch = np.zeros(n)
    for i, f in enumerate([660, 880, 1320]):
        tt = np.clip(t - i * 0.06, 0, None)
        ch += (t >= i * 0.06) * np.sin(2 * np.pi * f * tt) * np.exp(-tt * 8)
    write_wav(os.path.join(OUT, "sfx", "confirm.wav"), ch * 0.25)


if __name__ == "__main__":
    ui_sounds()
    for i, tr in enumerate(TRACKS):
        st = make_track(*tr)
        path = os.path.join(OUT, "music", "%02d_%s.ogg" % (i + 1, tr[0]))
        write_ogg(path, st)
        print("wrote", path)
