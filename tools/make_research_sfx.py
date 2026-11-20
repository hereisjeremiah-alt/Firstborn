# A warm "discovery" chime for researching a tech by hand: a soft whoosh rising into a
# bell-like major arpeggio over a low wooden knock, with a gentle shimmer tail.
import sys
import wave

import numpy as np

SR = 44100
total = 1.6
n = int(SR * total)
t = np.arange(n) / SR
rng = np.random.default_rng(5)
L = np.zeros(n)
R = np.zeros(n)


def place(buf, sig, at):
    i = int(at * SR)
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def bell(f, dur, vel):
    m = int(SR * dur)
    tt = np.arange(m) / SR
    s = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * f * 2.0 * tt) * np.exp(-tt * 3)
         + 0.18 * np.sin(2 * np.pi * f * 3.01 * tt) * np.exp(-tt * 6) + 0.08 * np.sin(2 * np.pi * f * 4.2 * tt) * np.exp(-tt * 9))
    return s * np.exp(-tt * 2.6) * np.clip(tt / 0.004, 0, 1) * vel


# whoosh: filtered noise swelling up
w = int(0.35 * SR)
noise = rng.normal(0, 1, w)
k = np.ones(60) / 60
noise = np.convolve(noise, k, mode="same")
swell = np.linspace(0, 1, w) ** 2
place(L, noise * swell * 0.25, 0.0)
place(R, noise[::-1] * swell * 0.25, 0.0)
# low wooden knock on arrival
m = int(0.25 * SR)
tt = np.arange(m) / SR
knock = np.sin(2 * np.pi * (180 + 120 * np.exp(-tt * 40)) * tt) * np.exp(-tt * 18)
place(L, knock * 0.5, 0.33)
place(R, knock * 0.5, 0.33)
# rising arpeggio C5 E5 G5 C6, then a soft chord
notes = [523.25, 659.25, 783.99, 1046.5]
for i, f in enumerate(notes):
    at = 0.33 + i * 0.075
    place(L, bell(f, 1.2, 0.42 - i * 0.04), at)
    place(R, bell(f * 1.003, 1.2, 0.38 - i * 0.04), at + 0.006)
for f in (523.25, 659.25, 783.99):
    place(L, bell(f / 2, 1.0, 0.16), 0.62)
    place(R, bell(f / 2, 1.0, 0.16), 0.63)
# shimmer
sh = int(0.9 * SR)
tt = np.arange(sh) / SR
shim = np.zeros(sh)
for f in (2093.0, 2637.0, 3136.0):
    shim += np.sin(2 * np.pi * f * tt) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * tt + f))
place(L, shim * np.exp(-tt * 4) * 0.035, 0.6)
place(R, shim * np.exp(-tt * 4.5) * 0.035, 0.62)


def reverb(x):
    out = x.copy()
    for d, g in ((0.029, 0.3), (0.043, 0.24), (0.067, 0.18), (0.097, 0.13), (0.139, 0.09), (0.19, 0.06)):
        kk = int(d * SR)
        out[kk:] += x[:-kk] * g
    return out


L = reverb(L)
R = reverb(R)
peak = max(np.abs(L).max(), np.abs(R).max())
L = L / peak * 0.8
R = R / peak * 0.8
fade = np.clip((total - t) / 0.3, 0, 1)
L *= fade
R *= fade
data = (np.stack([L, R], axis=1) * 32767).astype(np.int16)
with wave.open(sys.argv[1], "wb") as wf:
    wf.setnchannels(2)
    wf.setsampwidth(2)
    wf.setframerate(SR)
    wf.writeframes(data.tobytes())
print("ok")
