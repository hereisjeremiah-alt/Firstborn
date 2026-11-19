# Synthesises a short brass fanfare: "bum bum du-buuuum" with two trumpets in harmony and a timpani roll.
import numpy as np, wave, sys
SR = 44100

def brass(freq, dur, vel=1.0, vib=0.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    # vibrato on long notes
    f = freq * (1.0 + vib * 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.35, 0, 1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    # brightness rises with the attack, like a real horn opening up
    bright = np.clip(t / 0.06, 0, 1) * 0.85 + 0.15
    sig = np.zeros(n)
    for h in range(1, 14):
        amp = (1.0 / h ** 1.15) * np.clip(bright * 14 / h, 0, 1)
        sig += amp * np.sin(h * ph)
    # envelope: quick attack, slight swell, release
    att = np.clip(t / 0.025, 0, 1)
    rel = np.clip((dur - t) / 0.08, 0, 1)
    swell = 1.0 + 0.15 * np.sin(np.pi * np.clip(t / max(dur, 0.01), 0, 1))
    return sig * att * rel * swell * vel

def timpani(freq, dur, vel=1.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = np.exp(-t * 4.0)
    sig = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 1.5 * t) * np.exp(-t * 7)
    noise = np.random.default_rng(3).normal(0, 1, n) * np.exp(-t * 30) * 0.3
    return (sig + noise) * env * vel

def place(buf, sig, at):
    i = int(at * SR)
    buf[i:i + len(sig)] += sig[: max(0, len(buf) - i)]

G4, B4, D5, G5, C5, E5 = 392.0, 493.9, 587.3, 784.0, 523.3, 659.3
D4 = 293.7
total = 2.6
L = np.zeros(int(SR * total)); R = np.zeros(int(SR * total))
# "bum  bum   du  buuuuum"
notes = [(0.00, 0.20, G4, D4), (0.26, 0.20, G4, D4), (0.52, 0.13, B4, G4), (0.68, 1.55, D5, B4)]
for at, dur, hi, lo in notes:
    long = dur > 1.0
    place(L, brass(hi, dur, 0.55, 1.0 if long else 0.0), at)
    place(R, brass(hi * 1.002, dur, 0.50, 1.0 if long else 0.0), at + 0.004)
    place(L, brass(lo, dur, 0.38, 0.8 if long else 0.0), at + 0.003)
    place(R, brass(lo * 0.998, dur, 0.42, 0.8 if long else 0.0), at)
# timpani under the beats, and a roll into the last note
for at in (0.0, 0.26):
    place(L, timpani(98.0, 0.5, 0.5), at); place(R, timpani(98.0, 0.5, 0.5), at)
for k in range(5):
    place(L, timpani(98.0, 0.3, 0.18 + k * 0.06), 0.52 + k * 0.03)
    place(R, timpani(98.0, 0.3, 0.18 + k * 0.06), 0.53 + k * 0.03)
place(L, timpani(73.4, 1.2, 0.8), 0.68); place(R, timpani(73.4, 1.2, 0.8), 0.68)
# a little hall reverb
def reverb(x):
    out = x.copy()
    for d, g in ((0.031, 0.28), (0.047, 0.22), (0.071, 0.17), (0.103, 0.12), (0.149, 0.08)):
        k = int(d * SR)
        out[k:] += x[:-k] * g
    return out
L = reverb(L); R = reverb(R)
peak = max(np.abs(L).max(), np.abs(R).max())
L = L / peak * 0.85; R = R / peak * 0.85
fade = np.clip((total - np.arange(len(L)) / SR) / 0.25, 0, 1)
L *= fade; R *= fade
data = (np.stack([L, R], axis=1) * 32767).astype(np.int16)
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
print("ok", len(L) / SR, "s")
