/*
 * Copyright (C) 2026 - Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef BPMCORE_H
#define BPMCORE_H

// Tempo detection from audio, ported from the moSushi Klang dashboard's
// bpm-detect.py (mosushi-portal, klang/backend, commit 362eaf5). Plain C++
// on top of aubio, no Qt, so the same code runs in the app and in a host test.
//
// What it does, in the order of the original:
//  1. mono float blocks of HOP samples in, plus the block's RMS on the int16 scale
//  2. three aubio tempo trackers (default, specdiff, energy) report beat times
//  3. per tracker: beats of the last 20 s, intervals inside 50-220 BPM, the vote
//     is 60 / median interval (at least 9 beats, more than 6 intervals)
//  4. an onset envelope (block RMS, 20 s), its positive first difference,
//     mean-removed, autocorrelated, as z-scores
//  5. candidates: every vote x 0.5, 1, 2, 0.75, 4/3, 1.5, 2/3 inside 40-200 BPM
//  6. family scoring picks the metrical level (half 0.7, self 1.0, double 0.7,
//     quadruple 0.4)
//  7. every 2 s the pick joins the last 8; the output is the median of those
//     within 8 % of the median; confidence = share within 8 % x min(1, n / 4)
//  8. silence (block RMS under a threshold) for more than 6 s clears everything
// The traps the original documents are kept in the comments where they apply.

#include <vector>


class BpmCore
{
public:
    explicit BpmCore(unsigned sampleRate = 48000);
    ~BpmCore();
    BpmCore(const BpmCore &) = delete;
    BpmCore &operator=(const BpmCore &) = delete;

    static const unsigned HOP = 512;     // aubio hop size and envelope block
    static const unsigned WIN = 1024;    // aubio analysis window

    // One block of HOP mono samples in [-1, 1], and its RMS on the int16 scale
    // (computed over all channels, as the original does). nowSeconds is the
    // caller's clock; it drives the 2 s emit rhythm and the silence timeout.
    void feed(const float *mono, float rmsInt16, double nowSeconds);

    // Set by feed() every EMIT_EVERY seconds.
    bool hasResult() const { return m_bpm > 0; }
    int bpm() const { return m_bpm; }              // 0 = nothing detected
    double tempo() const { return m_tempo; }       // the same, unrounded
    int confidence() const { return m_confidence; } // 0..100
    bool emitted() { bool e = m_emitted; m_emitted = false; return e; }

    // Silence threshold on the int16 scale. 120 was set for a line level
    // digital stream; a microphone needs its own value (measure on the device).
    void setSilenceRms(float v) { m_silenceRms = v; }
    float silenceRms() const { return m_silenceRms; }

    void reset();

private:
    void emitResult(double now);   // not "emit": that is a Qt macro
    double pickTempo(const std::vector<double> &votes) const;
    double familySupport(const std::vector<double> &z, double bpm) const;
    double refine(const std::vector<double> &z, double bpm) const;

    unsigned m_rate;
    double m_envHz;
    unsigned m_envKeep;
    // aubio types kept opaque here so the header needs no aubio include
    std::vector<void *> m_trackers;   // aubio_tempo_t *
    void *m_in = nullptr;             // fvec_t *
    void *m_out = nullptr;            // fvec_t *
    std::vector<std::vector<double>> m_beats;
    std::vector<float> m_env;
    std::vector<double> m_recent;
    double m_last = 0.0;
    double m_quietSince = -1.0;
    float m_silenceRms = 120.0f;
    int m_bpm = 0;
    double m_tempo = 0.0;
    int m_confidence = 0;
    bool m_emitted = false;
};

#endif // BPMCORE_H
