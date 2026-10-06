# BeatFork

A BPM counter, metronome, and tuning fork for AsteroidOS.

Swipe left and right to move between the three pages.

[![BeatFork on AsteroidOS](https://img.youtube.com/vi/2JLklKeVPCg/0.jpg)](https://www.youtube.com/watch?v=2JLklKeVPCg)

---

## Page 1 — Detect BPM

Tap the large BPM number in the center of the screen to the beat of any music.

**Reading the display**

The ring of dots around the center circle is your tap history. Each dot represents one beat:
- Dots in the **main color** are generated automatically by the running BPM clock
- Dots in the **accent color** (slightly different hue) are your finger taps
- A dot sitting **inside** the ring means you tapped early; **outside** means you tapped late
- The ring rotates counter-clockwise — older dots are further along, new ones appear at the top-left

The number in the center is the current BPM, updated after each tap. It takes 2–3 taps to establish a reading and improves up to 8 taps.

**Stats**

Once you start tapping, the area above the BPM shows a stat readout. Tap the upper area of the screen (where the title was) to cycle through:
- **%** — how consistent your tapping is, 100% is perfect
- **X.X bpm** — precise BPM to one decimal place
- **±ms** — how early or late your last tap was
- **n of 8** — how many taps are in the current average
- **min–max** — the range of BPM values detected this session
- **ms/beat** — the raw beat interval in milliseconds

**Turntable controls**

Three zones at the bottom of the screen let you nudge the beat timing without changing the BPM:
- **Tap left** — slow the beat slightly (brake)
- **Tap right** — speed the beat slightly (push)
- **Tap center bottom** — freeze the beat. The ring dots pause in place. Tap again to release and restart exactly on the beat

The nudge decays back to neutral automatically when you stop using it.

**Tips**
- Tap to the strongest pulse in the music — kick drum or snare rather than melody
- A reading of XX.5 BPM often means you are tapping at half the actual tempo — the true BPM is double
- If you tap at the wrong speed by accident, just keep tapping at the correct speed — two consistent off-tempo taps resets the average automatically
- After you find the BPM, swipe to the Metronome page — it will already be set to the detected tempo

---

## Page 2 — Metronome

Set the BPM using the circular spinner. Tap the pulse circle to start and stop the visual flash. Toggle the speaker icon for an audible tick and the haptic icon for vibration.

The color theme cycles through 10 options using the palette button.

---

## Page 3 — Tuning Fork

Select a reference frequency using the circular spinner. Long-press the tuning fork icon to play a continuous tone. The available frequencies are G4, Ab4, A4 Verdi (432 Hz), A4 Standard (440 Hz), A4 Orchestra (442 Hz), A4 High (444 Hz), and Bb4.

This page is only available on watches with a speaker.

---

## Tips across all pages

- The BPM set on any page is shared — detect on page 1, practice on page 2
- The screen stays on whenever the metronome, tick sound, or tuning fork is active

---

## SailfishOS

Reviewing the code? Start with [review-and-architecture-hints.md](review-and-architecture-hints.md).

The `sailfishos` branch is the SailfishOS version, built for Sailfish OS
5.1 on aarch64 and run on a Jolla C2. The three pages are the watch app;
they keep the watch proportions across the phone's width.

- The metronome tick plays through the app's own audio stream, not
  through an ngfd event: an ngfd event needs a file in
  `/usr/share/ngfd/events.d` and an ngfd restart. The vibration uses
  QtFeedback.
- The tuning fork tone is synthesised live as on the watch, through
  Qt 5's `QAudioOutput` instead of Qt 6's `QAudioSink`.
- Install: `devel-su pkcon install-local harbour-asteroid-beatfork-1.6.0-1.<arch>.rpm`
  (aarch64 for 4.5 and later, armv7hl for 3.4 and later, i486 for 4.5
  and later).
- Build: `mb2 -t SailfishOS-5.1.0.11-aarch64 build` with the Sailfish
  Platform SDK.

The author tested the port on his C2. The metronome tick was silent at
first: SailfishOS held its sound effect stream paused, so the tick now
plays through its own audio stream like the tuning fork. The BPM number
and the tempo names are smaller than on the watch, at his request.

```
Disclosure: LLMGD-3 · origin O1 (LLM-ported; the author tested it on his Jolla C2 and had the tick and the font sizes changed; code not read; self-graded)
LLMGD: v0.2; assurance=A3; flags=U,T; origin={O0:.7,O1:.3}; origin_headline=O0; scope=port(code+assets+packaging+docs); graded-by=claude-opus-5-5; retrieval=author-side
```

### Tempo detection from audio (SailfishOS only, 1.6.0)

Above the ring on the Detect BPM page sits **Listen**. Tap it to cycle
through Off, **Microphone** and **Playback**. Playback is the monitor of
the phone's speaker output, so it hears whatever the phone itself plays
(a music app, a stream), without the room. The label shows the source
and how sure the detection is; a thin bar under it shows the input
level. Once the detection is at least 50 % sure, its tempo becomes the
app's tempo, and the metronome follows it (in tempo, not in phase).
Tapping the BPM number takes over again and switches listening off.

While listening, **½** and **×2** sit left and right of the label. The
detector finds a pulse reliably, but whether it is the tempo, its half
or its double is the hard part: modern electronic music at 175 often
reads 87.5. ×2 doubles every detected value from then on, ½ halves it,
and the other button steps back to 1. The choice holds until listening
stops or the source changes, so the next song starts neutral.
Listening stops on the other pages and while the app is in the
background, so the microphone is not held.

The detection is a port of the BPM detector of the author's moSushi
Klang dashboard: three aubio tempo trackers (default, specdiff, energy)
vote with the median interval of their beats over 20 seconds, and an
autocorrelation of the onset envelope picks the metrical level among
half, double, 3/4 and 4/3 of those votes. A result comes every 2
seconds, smoothed over the last 8; 6 seconds of silence clear it. It
needs 9 beats per tracker, so the first number comes after about 15
seconds.

One addition to the original: aubio places beats on whole analysis
steps (10.7 ms), which leaves about 1 % of error in the votes, so a 174
track read 175.8 and its half 87.8, and doubling showed 176. The chosen
tempo is now refined from the envelope autocorrelation, interpolated
between steps. That changes only the value, never which tempo is
picked.

aubio 0.4.9 (GPL-3.0, <https://aubio.org>) is built into the app from
`3rdparty/aubio`, the parts the tempo trackers need; see
`3rdparty/aubio/README.SailfishOS`.

The app now asks for the Microphone permission. Whether that permission
also lets the sandboxed app record the speaker monitor is not confirmed:
the permission file says playback and recording can not be separated on
PulseAudio, which suggests it does.

What was checked, and what was not:
- Without the refinement, the C++ port gives the same results as the
  original Python detector on the same synthetic test tracks (90, 128,
  140, 168, 174 BPM). On those perfectly regular loops both report half
  the tempo for 128, 140 and 174; on hip hop at 90 both are right.
- With the refinement every track reads within 0.2 BPM of the true
  value at the level picked (63.95, 70.12, 86.81, 89.97, 83.97), so ×2
  gives 128, 140, 174 and 168.
- The author tried listening on his C2 and was happy with it; the ½ and
  ×2 buttons came from that test.
- The same test runs on the phone (`SFOS_SELFTEST_BPM_WAV=<16 bit wav>`,
  silent) with the same numbers on a Jolla C2 (aarch64) and a Jolla 1
  (armv7hl, SailfishOS 3.4). The Jolla 1 needs 2 to 3 seconds for 60
  seconds of audio.
- On the C2 both sources open at 48 kHz stereo; the microphone reads
  an RMS of about 32 in a quiet room, below the silence threshold of 60.
- Detection from the live microphone or from playback with music has
  not been tried: it was night, and the test would have been audible.
- All phone tests ran the app directly from a shell, outside the
  sandbox. Started from the launcher, the first start asks for the
  Microphone permission; that path has not been tried.

```
Disclosure: LLMGD-3 · origin O1 (detector specified by the author's own Python original; LLM-ported to C++ and integrated; compared against the original on synthetic tracks only; live music detection untested; self-graded)
LLMGD: v0.2; assurance=A3; flags=U,T; origin={O0:.6,O1:.4}; origin_headline=O0; scope=feature(code+3rdparty+docs); graded-by=claude-opus-5-5; retrieval=author-side
```
