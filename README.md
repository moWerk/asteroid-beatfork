# asteroid-beatfork

A metronome, BPM detector and tuning fork app for [AsteroidOS](https://asteroidos.org).

---

## Features

### Detect BPM
Tap anywhere on screen to detect tempo by measuring the intervals between taps. A rolling average of up to eight taps produces a stable reading across the supported range of 40–208 BPM. Starting a new tap series after a pause automatically discards previous data so switching tempos is immediate. A pulsing circle with ripple rings and sparkle rays visualises each tap. The detected BPM is shared with the Metronome page and persisted across app restarts.

### Metronome
A full-screen pulsing circle runs at the stored BPM — opt-in so it does not surprise you on first open. The tempo is adjusted with a circular spinner. Four toggle buttons independently activate the beat flash, an audible tick, haptic (vibration) feedback, and color cycling. Active buttons pulse in BPM rhythm in lockstep with the beat clock. The page header fades while the flash is running to maximise lit pixels. Useful for eyes-free or sports use.

### Tuning Fork
Tap the frequency display to cycle through seven reference pitches — G4 (392 Hz), Ab4 (415 Hz), A4 Verdi (432 Hz), A4 Standard (440 Hz), A4 Orchestra (442 Hz), A4 High (444 Hz) and Bb4 (452 Hz). Tap the play button for a one-second preview. Hold to lock a continuous gapless loop that keeps playing until you tap to stop. The button emits ripple rings while playing. The selected frequency is persisted across app restarts.

---

## Screen keepalive

The display stays on automatically while any active output is running — metronome sound, haptic, flash, or a locked tuning fork loop. It sleeps normally in all other states.

---

## Sound files

All sound assets are generated offline using [SoX](https://sox.sourceforge.net) and shipped as 16-bit mono PCM WAV files.

**Metronome tick**
```bash
sox -n -r 44100 -b 16 -c 1 tick.wav synth 0.025 tri 2000 fade h 0.002 0.025 0.008 vol 0.7
```

**Tuning fork tones** (repeat for each frequency)
```bash
sox -n -r 44100 -b 16 -c 1 440hz.wav synth 3 sine 440 vol -1dB
```

---

## Dependencies

- [AsteroidOS](https://asteroidos.org) / [asteroid-launcher](https://github.com/AsteroidOS/asteroid-launcher)
- `nemo-keepalive` — conditional screen blanking
- `nemo-ngf` — haptic feedback
- Qt 5.15 / QtMultimedia 5.8

---

## License

GNU Lesser General Public License v2.1 — see [LICENSE](LICENSE) for details.
