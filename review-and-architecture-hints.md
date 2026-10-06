# Review and architecture hints: BeatFork for SailfishOS

For anyone reviewing the `sailfishos` branch: where the code comes from, how it is laid out, what is worth reading and what is boilerplate.

## Where the code comes from

The app is the AsteroidOS watch app on `master`. This branch forks from it at `e3fbc5d`, and its commits are the SailfishOS port. The reliable view of what the port changed:

    git diff e3fbc5d sailfishos -- qml src rpm '*.pro' '*.desktop'

Many port edits carry a `SailfishOS:` comment, but not all of them. Each commit message says what changed, why, and what was not checked, and ends with an LLMGD line grading it.

The port was written by an LLM (Claude), directed and tested by the author, who has not read the code. Everything here is a prototype until a reviewer owns it. That is the point of this file.

## Architecture

This is the one port with compiled code, so it ships one package per architecture.

- `qml/harbour-asteroid-beatfork.qml`: the Silica `ApplicationWindow`. It sizes `Dims` from the screen width, then loads the app (`game/main.qml`). When the app goes to the background, the same item is moved into the cover and scaled down, so the home screen tile shows it live. The same shell is used in all eight ports.
- `qml/game/Dims.qml`, `Label.qml`, `HighlightBar.qml`, `Icon.qml`, `PageHeader.qml`, `ValueCycler.qml`, `IntSelector.qml`, `DeviceSpecs.qml` (whichever exist here): small stand-ins for AsteroidOS's `org.asteroid.controls` and `org.asteroid.utils`, so the watch QML runs unchanged where possible. Each is a few dozen lines.
- `qml/game/main.qml`: the app frame, the beat clock (`beatTimer`), the settings, and the wiring to the C++ singletons. The pages are `BpmDetectPage.qml` (tap BPM, turntable nudge, listen controls), `MetronomePage.qml` and `TuningForkPage.qml`.
- `src/ToneGenerator.*` (`ToneGen` in QML):
  - The tuning fork tone is a live sine with a raised-cosine envelope, through `QAudioOutput`.
  - The metronome tick is one persistent `QAudioOutput` stream (`TickDevice`) that plays silence between ticks. A `SoundEffect` was held paused ("corked") by SailfishOS's audio policy, and a new stream per tick played only once.
- `src/BpmDetector.*` (`BpmListener` in QML): a `QAudioInput` on the microphone (`source.primary_input`) or the speaker monitor (`sink.primary_output.monitor`), at 48 kHz stereo. Whole 512-frame blocks go to the core. The clock is the sample count, not the wall clock.
- `src/BpmCore.*`: plain C++, no Qt. A port of the author's Python detector, with the steps listed in the header:
  - three aubio tempo trackers vote with median beat intervals;
  - envelope autocorrelation z-scores and family scoring pick the metrical level;
  - smoothing over 8 results, every 2 s;
  - 6 s of silence clears the result.
- `3rdparty/aubio`: aubio 0.4.9 (GPL-3.0), only the parts the trackers need, compiled in through `aubio.pri`. See `README.SailfishOS` there.
- `tools/`: a host test harness for `BpmCore` and a generator for synthetic test tracks (`tools/README`).

## Read these first

1. `src/BpmCore.cpp`: the algorithm. `refine()` is an addition not in the original: a parabolic interpolation of the autocorrelation peak near the chosen tempo. It changes the value, never the pick, and brings the synthetic tracks from about 1 % off to within 0.2 BPM.
2. `src/BpmDetector.cpp`: device selection. Qt reports the speaker monitor as the default input on the C2, so the order is explicit. Format negotiation, the block assembly, and `runWav()` (a test hook).
3. `src/ToneGenerator.cpp`: the persistent tick stream and its idle handling.
4. `main.qml`: `applyDetectedTempo()` and the ½ / ×2 factor.

## Skim

Stand-ins, icons, translations, packaging, the vendored aubio sources.

## Worth questioning

- The detection runs on the GUI thread. On a Jolla 1 it costs about 5 % of a core, and an autocorrelation over about 1875 lags runs every 2 s. A worker thread would be cleaner.
- `onReadyRead()` removes consumed bytes from the front of a `QByteArray` on every read.
- Settings use the AsteroidOS dconf keys (`/asteroid/apps/beatfork/...`), not `/apps/harbour-asteroid-beatfork/...` as the other ports do now.
- Test hooks read environment variables in `main.cpp`: `SFOS_SELFTEST_SHOT`, `_AUDIO` (audible), `_BPM_WAV` and `_LISTEN`.
- `qt5-qtfeedback` (the haptic tick) is the only thing the Jolla Store validator rejects.
- Detection on real music was tested by the author on a C2. On synthetic tracks, the original detector and this port give the same picks.

## How it was tested

By the author on a Jolla C2 (5.1), the Jolla Tablet (4.6) and a Jolla 1 (3.4), with the per-architecture packages. The BPM detector was also checked on the host against the original Python, using synthetic tracks (`tools/`).

There are no automated tests; the on-device checks are listed in the commit messages.
