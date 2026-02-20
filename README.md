# asteroid-beatfork

A metronome and tuning fork app for [AsteroidOS](https://asteroidos.org).

---

## Features

### Detect BPM
Tap anywhere on screen to detect tempo by measuring the intervals between taps. A rolling average of up to eight taps produces a stable reading across the supported range of 40–208 BPM. Starting a new tap series after a pause automatically discards previous tap data so switching tempos is immediate. A pulsing circle visualises the current BPM continuously. The detected BPM is shared with the Metronome page and persisted across app restarts.

### Metronome
A full-screen pulsing circle runs at the stored BPM. The tempo can be adjusted with a circular spinner. Two toggle buttons independently activate an audible tick and haptic (vibration) feedback on each beat, useful for eyes-free or sports use.

### Tuning Fork
Tap the frequency display to cycle through a set of reference pitches: 392, 415, 432, 440, 442, 444 and 452 Hz. Tap the tuning fork icon to play the selected pitch once. Press and hold to loop it continuously until released. The selected frequency is persisted across app restarts.


Tick created using

sox  -n -r 44100 -b 16 -c 1 tick.wav synth 0.025 tri 2000 fade h 0.002 0.025 0.008 vol 0.7

Tones created using

$ sox -n -r 44100 -b 16 -c 1 440hz.wav synth 3 sine 440 vol -1dB
