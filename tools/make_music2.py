"""Second set of ten Firstborn soundtrack pieces (11-20).

Same instruments and mixing as make_audio.py (soft pads, plucked strings, flute, frame drums,
reverb), plus a horn-like brass voice, a field snare and timpani for the marching pieces.
Usage: python3 tools/make_music2.py audio
"""
import os
import sys

import numpy as np
from scipy.signal import butter, sosfilt

sys.path.insert(0, os.path.dirname(__file__))
import make_audio as A  # noqa: E402

SR = A.SR
OUT = sys.argv[1] if len(sys.argv) > 1 else "audio"


def brass(f, dur, vib=0.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    ff = f * (1.0 + vib * 0.005 * np.sin(2 * np.pi * 5.3 * t) * np.clip(t / 0.35, 0, 1))
    ph = 2 * np.pi * np.cumsum(ff) / SR
    bright = np.clip(t / 0.07, 0, 1) * 0.8 + 0.2
    sig = np.zeros(n)
    for h in range(1, 11):
        sig += (1.0 / h ** 1.2) * np.clip(bright * 11 / h, 0, 1) * np.sin(h * ph)
    att = np.clip(t / 0.03, 0, 1)
    rel = np.clip((dur - t) / 0.09, 0, 1)
    sig = A.lowpass(sig, 3200)
    return sig * att * rel * 0.32


def snare(rng, vel=1.0):
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    x = rng.normal(0, 1, n)
    sos = butter(2, [1200, 5000], btype="band", fs=SR, output="sos")
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5
    return (sosfilt(sos, x) * np.exp(-t * 26) + body) * 0.2 * vel


def timp(f, rng, vel=1.0):
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) + 0.45 * np.sin(2 * np.pi * f * 1.5 * t) * np.exp(-t * 6)
    x += A.lowpass(rng.normal(0, 1, n), 500) * np.exp(-t * 28) * 0.3
    return x * np.exp(-t * 3.5) * 0.6 * vel


TRACKS = [
    # name, root, mode, bpm, progression, instruments, seed, length (s)
    ("march_of_the_tribe", 50, "mixolydian", 108, [0, 3, 4, 0], {"pad": 0.6, "pluck": 0.5, "flute": 0.0, "drum": 0.4, "brass": 1.0, "march": 1.0}, 211, 150),
    ("bronze_legion", 45, "aeolian", 100, [0, 5, 6, 4], {"pad": 0.8, "pluck": 0.4, "flute": 0.0, "drum": 0.5, "brass": 1.1, "march": 1.1}, 222, 150),
    ("banners_at_dawn", 55, "ionian", 92, [0, 4, 5, 3], {"pad": 0.9, "pluck": 0.7, "flute": 0.4, "drum": 0.0, "brass": 0.8, "march": 0.6}, 233, 150),
    ("hearth_lullaby", 52, "pent_major", 58, [0, 3, 0, 4], {"pad": 1.0, "pluck": 0.9, "flute": 0.8, "drum": 0.0}, 244, 160),
    ("mammoth_trail", 43, "pent_minor", 88, [0, 2, 3, 0], {"pad": 0.8, "pluck": 0.6, "flute": 0.6, "drum": 1.3}, 255, 145),
    ("spring_thaw", 57, "dorian", 76, [0, 3, 1, 4], {"pad": 0.9, "pluck": 1.1, "flute": 0.9, "drum": 0.4}, 266, 150),
    ("smoke_and_stars", 48, "aeolian", 56, [0, 5, 3, 6], {"pad": 1.2, "pluck": 0.5, "flute": 0.7, "drum": 0.0}, 277, 160),
    ("war_horns", 47, "phrygian", 90, [0, 1, 6, 0], {"pad": 0.9, "pluck": 0.3, "flute": 0.0, "drum": 0.9, "brass": 1.2, "march": 0.9}, 288, 140),
    ("the_long_road", 53, "mixolydian", 84, [0, 6, 3, 0], {"pad": 0.7, "pluck": 1.0, "flute": 0.5, "drum": 0.5, "brass": 0.6}, 299, 150),
    ("riverstone", 50, "pent_major", 70, [0, 2, 4, 1], {"pad": 1.0, "pluck": 0.8, "flute": 1.0, "drum": 0.2}, 310, 150),
]

# third set (21-30): more marches and brass, same style
TRACKS_B = [
    ("drums_of_the_host", 48, "dorian", 112, [0, 3, 4, 3], {"pad": 0.6, "pluck": 0.4, "flute": 0.0, "drum": 0.5, "brass": 1.1, "march": 1.2}, 321, 145),
    ("the_chiefs_return", 53, "ionian", 100, [0, 4, 3, 4], {"pad": 0.8, "pluck": 0.6, "flute": 0.3, "drum": 0.3, "brass": 1.0, "march": 0.9}, 332, 150),
    ("shield_wall", 45, "aeolian", 104, [0, 6, 5, 4], {"pad": 0.7, "pluck": 0.3, "flute": 0.0, "drum": 0.6, "brass": 1.2, "march": 1.1}, 343, 145),
    ("copper_crown", 50, "mixolydian", 96, [0, 6, 3, 4], {"pad": 0.9, "pluck": 0.7, "flute": 0.4, "drum": 0.3, "brass": 0.9, "march": 0.8}, 354, 150),
    ("march_to_the_sea", 55, "pent_major", 108, [0, 2, 4, 3], {"pad": 0.7, "pluck": 0.8, "flute": 0.5, "drum": 0.3, "brass": 0.9, "march": 1.0}, 365, 145),
    ("iron_vanguard", 43, "phrygian", 110, [0, 1, 0, 6], {"pad": 0.8, "pluck": 0.3, "flute": 0.0, "drum": 0.8, "brass": 1.2, "march": 1.2}, 376, 140),
    ("standard_bearers", 52, "dorian", 98, [0, 3, 1, 4], {"pad": 0.8, "pluck": 0.6, "flute": 0.3, "drum": 0.4, "brass": 1.0, "march": 1.0}, 387, 150),
    ("victory_feast", 57, "ionian", 92, [0, 3, 4, 0], {"pad": 0.8, "pluck": 1.0, "flute": 0.8, "drum": 0.5, "brass": 0.8, "march": 0.5}, 398, 150),
    ("border_watch", 47, "aeolian", 88, [0, 5, 3, 4], {"pad": 1.0, "pluck": 0.5, "flute": 0.5, "drum": 0.4, "brass": 0.7, "march": 0.7}, 409, 150),
    ("the_last_legion", 45, "dorian", 102, [0, 6, 3, 4], {"pad": 0.9, "pluck": 0.4, "flute": 0.0, "drum": 0.6, "brass": 1.2, "march": 1.1}, 420, 150),
]


def make_track(name, root, mode, bpm, prog, inst, seed, length):
    # strings, pads, flute and drums come from the original generator
    base = A.make_track(name, root, mode, bpm, prog, {k: inst.get(k, 0.0) for k in ("pad", "pluck", "flute", "drum")}, seed, length)
    if inst.get("brass", 0) <= 0 and inst.get("march", 0) <= 0:
        return base
    rng = np.random.default_rng(seed + 7)
    scale = A.MODES[mode]
    beat = 60.0 / bpm
    bar = beat * 4
    n = base.shape[0] + int(4 * SR)
    left = np.zeros(n)
    right = np.zeros(n)

    def deg(d, octave=0):
        k = len(scale)
        return root + scale[d % k] + 12 * (d // k + octave)

    bars = int(length / bar)
    # a proud call the horns keep returning to: short-short-long rhythms
    call = [(0, 0.5), (0, 0.25), (2, 0.25), (4, 1.0), (2, 0.5), (4, 0.5), (7, 1.5)]
    for b in range(0, bars, 2):
        chord = prog[(b // 2) % len(prog)]
        t0 = b * bar
        frac = b / max(1, bars)
        if frac < 0.06 or frac > 0.95:
            continue
        # marching snare and timpani
        if inst.get("march", 0) > 0:
            mv = inst["march"]
            for bb in range(2):
                bt = t0 + bb * bar
                A.add(left, timp(A.hz(deg(chord, -2)), rng, 0.8 * mv), bt)
                A.add(right, timp(A.hz(deg(chord, -2)), rng, 0.8 * mv), bt)
                A.add(left, timp(A.hz(deg(chord + 4, -3)), rng, 0.55 * mv), bt + beat * 2)
                A.add(right, timp(A.hz(deg(chord + 4, -3)), rng, 0.55 * mv), bt + beat * 2)
                for q in range(8):
                    at = bt + q * beat / 2
                    if q in (2, 6):
                        A.add(left, snare(rng, 0.9 * mv) * 0.8, at)
                        A.add(right, snare(rng, 0.9 * mv), at)
                    elif rng.random() < 0.2:
                        A.add(left, snare(rng, 0.35 * mv), at)
                        A.add(right, snare(rng, 0.3 * mv), at)
                if bb == 1 and rng.random() < 0.6:
                    # a roll into the next phrase
                    for r in range(6):
                        A.add(left, snare(rng, (0.25 + r * 0.08) * mv), bt + beat * 3 + r * beat / 6)
                        A.add(right, snare(rng, (0.25 + r * 0.08) * mv), bt + beat * 3 + r * beat / 6 + 0.004)
        # horns: the call in two voices (a third apart), every other phrase in the full middle
        if inst.get("brass", 0) > 0 and 0.12 < frac < 0.9 and ((b // 2) % 2 == 0 or rng.random() < 0.35):
            bv = inst["brass"]
            tt = t0
            for d, ln in call:
                dur = beat * ln * 2 * 0.92
                vib = 1.0 if ln >= 1.0 else 0.0
                hi = brass(A.hz(deg(chord + d, 0)), dur, vib) * bv
                lo = brass(A.hz(deg(chord + d - 2, 0)), dur, vib) * bv * 0.7
                A.add(left, hi * 0.9 + lo * 0.6, tt)
                A.add(right, hi * 0.7 + lo * 0.8, tt + 0.006)
                tt += beat * ln * 2
        # sustained low horns under the chord
        if inst.get("brass", 0) > 0 and frac > 0.1:
            hl = brass(A.hz(deg(chord, -1)), bar * 2 * 0.95, 0.5) * inst["brass"] * 0.35
            A.add(left, hl, t0)
            A.add(right, hl, t0 + 0.01)
    left = A.reverb(left, rng, 2.0, 0.28)
    right = A.reverb(right, np.random.default_rng(seed + 9), 2.0, 0.28)
    extra = np.stack([left, right], axis=1)[: base.shape[0]]
    fade = int(5 * SR)
    extra[:fade] *= np.linspace(0, 1, fade)[:, None]
    extra[-fade:] *= np.linspace(1, 0, fade)[:, None]
    peak = np.max(np.abs(extra)) + 1e-9
    mix = base + extra / peak * 0.55
    mpk = np.max(np.abs(mix)) + 1e-9
    return np.tanh(mix / mpk * 1.1) * 0.7


if __name__ == "__main__":
    # python3 make_music2.py audio [b] [indices...]   ("b" = the third set, tracks 21-30)
    args = sys.argv[2:]
    tracks, first = TRACKS, 11
    if args and args[0] == "b":
        tracks, first = TRACKS_B, 21
        args = args[1:]
    which = [int(x) for x in args] if args else range(len(tracks))
    for i in which:
        tr = tracks[i]
        st = make_track(*tr)
        path = os.path.join(OUT, "music", "%02d_%s.ogg" % (i + first, tr[0]))
        A.write_ogg(path, st)
        print("wrote", path, flush=True)
