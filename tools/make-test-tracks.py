#!/usr/bin/env python3
"""Synthetic drum tracks at known tempi for the BpmCore host test.

Not music, but the patterns that trap tempo trackers: four-on-the-floor,
half-time dubstep, drum and bass breaks, a jungle break over a half-time
bassline, and a slow hip-hop groove. 48 kHz stereo, 16 bit.
usage: make-test-tracks.py <out dir>
"""
import sys, wave
import numpy as np

RATE = 48000
rng = np.random.default_rng(1)

def kick(n=6000):
    t = np.arange(n) / RATE
    f = 50 + 90 * np.exp(-t * 40)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 9)

def snare(n=5000):
    t = np.arange(n) / RATE
    return (rng.standard_normal(n) * 0.7 + np.sin(2 * np.pi * 190 * t) * 0.5) * np.exp(-t * 22)

def hat(n=1500):
    t = np.arange(n) / RATE
    x = rng.standard_normal(n)
    x = np.diff(np.concatenate([[0], x]))          # crude high pass
    return x * np.exp(-t * 60) * 0.35

def bass(freq, n):
    t = np.arange(n) / RATE
    return np.sin(2 * np.pi * freq * t) * np.minimum(1, t * 50) * np.exp(-t * 1.5) * 0.6

def render(bpm, pattern, seconds=60, extra=None):
    """pattern: list of (step in 16ths within one bar, instrument)"""
    out = np.zeros(int(seconds * RATE) + RATE)
    step = 60.0 / bpm / 4
    bar = 16 * step
    t0 = 0.0
    while t0 < seconds:
        for s, inst in pattern:
            i = int((t0 + s * step) * RATE)
            x = inst()
            out[i:i + len(x)] += x[:len(out) - i]
        if extra:
            for s, x in extra(bar):
                i = int((t0 + s * step) * RATE)
                out[i:i + len(x)] += x[:len(out) - i]
        t0 += bar
    out = out[:int(seconds * RATE)]
    out /= np.max(np.abs(out)) * 1.2
    return out

def save(path, x):
    pcm = (np.stack([x, x * 0.97], axis=1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(pcm.tobytes())

K, S, H = kick, snare, hat
out = sys.argv[1]
tracks = {
    'house-128': (128, [(0, K), (4, K), (8, K), (12, K), (2, H), (6, H), (10, H), (14, H), (4, S), (12, S)]),
    'dubstep-140': (140, [(0, K), (8, S), (10, K), (2, H), (6, H), (10, H), (14, H)]),
    'dnb-174': (174, [(0, K), (4, S), (10, K), (12, S), (0, H), (2, H), (4, H), (6, H), (8, H), (10, H), (12, H), (14, H)]),
    'hiphop-90': (90, [(0, K), (7, K), (10, K), (4, S), (12, S), (0, H), (2, H), (4, H), (6, H), (8, H), (10, H), (12, H), (14, H)]),
}
for name, (bpm, pat) in tracks.items():
    save('%s/%s.wav' % (out, name), render(bpm, pat))
# jungle: 168 break over a half-time bassline at 84 (the brief's trap case)
jb = [(0, K), (4, S), (7, S), (10, K), (12, S), (15, S), (2, H), (6, H), (10, H), (14, H)]
save('%s/jungle-168.wav' % out, render(168, jb, extra=lambda bar: [(0, bass(55, int(bar * RATE)))]))
# silence after music, to check the 6 s clear
x = render(128, tracks['house-128'][1], seconds=30)
save('%s/house-then-silence.wav' % out, np.concatenate([x, np.zeros(RATE * 15)]))
print('ok')
