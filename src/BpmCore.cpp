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

#include "BpmCore.h"

#include <algorithm>
#include <cmath>
#include <set>

extern "C" {
#include "types.h"
#include "fvec.h"
#include "tempo/tempo.h"
}

static const double EMIT_EVERY    = 2.0;
static const size_t KEEP          = 8;      // recent estimates kept for smoothing
static const double BEAT_WINDOW_S = 20.0;   // forget beats older than this
static const double QUIET_AFTER   = 6.0;    // seconds of silence before clearing
static const char *const METHODS[] = { "default", "specdiff", "energy" };

static double median(std::vector<double> v)
{
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    const size_t n = v.size();
    return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}

BpmCore::BpmCore(unsigned sampleRate)
    : m_rate(sampleRate)
    , m_envHz(double(sampleRate) / HOP)
    , m_envKeep(unsigned(double(sampleRate) / HOP * 20))   // 20 s of envelope
{
    // THREE trackers, not one. On a jungle break "default" locks to the
    // half-time pulse (83) while "specdiff" and "energy" follow the breaks
    // (168). Both readings are musically true, and the consensus also
    // outvotes spurious peaks that one method alone cannot recognise.
    for (const char *m : METHODS)
        m_trackers.push_back(new_aubio_tempo(m, WIN, HOP, sampleRate));
    m_beats.resize(m_trackers.size());
    m_in = new_fvec(HOP);
    m_out = new_fvec(1);
}

BpmCore::~BpmCore()
{
    for (void *t : m_trackers)
        del_aubio_tempo(static_cast<aubio_tempo_t *>(t));
    del_fvec(static_cast<fvec_t *>(m_in));
    del_fvec(static_cast<fvec_t *>(m_out));
}

void BpmCore::reset()
{
    for (auto &b : m_beats) b.clear();
    m_env.clear();
    m_recent.clear();
    m_bpm = 0;
    m_tempo = 0.0;
    m_confidence = 0;
}

void BpmCore::feed(const float *mono, float rmsInt16, double now)
{
    m_env.push_back(rmsInt16);
    if (m_env.size() > m_envKeep)
        m_env.erase(m_env.begin(), m_env.end() - m_envKeep);

    fvec_t *in = static_cast<fvec_t *>(m_in);
    fvec_t *out = static_cast<fvec_t *>(m_out);
    for (unsigned i = 0; i < HOP; ++i)
        in->data[i] = mono[i];
    for (size_t bi = 0; bi < m_trackers.size(); ++bi) {
        aubio_tempo_t *tr = static_cast<aubio_tempo_t *>(m_trackers[bi]);
        aubio_tempo_do(tr, in, out);
        if (out->data[0] != 0) {
            // Beat TIMESTAMPS, not aubio's get_bpm(): over a 32 s sample
            // get_bpm() scattered across 137.7-142.3 while the median interval
            // between those very same beats held within 135.9-137.3.
            const double t = aubio_tempo_get_last_s(tr);
            std::vector<double> &b = m_beats[bi];
            b.push_back(t);
            // Bound the memory by TIME, not by beat count: 96 beats is 34 s at
            // 170 BPM but 69 s at 83, and a 140 dubstep and a 170 jungle once
            // averaged into a fictional 111.
            const double cut = t - BEAT_WINDOW_S;
            while (!b.empty() && b.front() < cut)
                b.erase(b.begin());
        }
    }

    if (rmsInt16 < m_silenceRms) {
        if (m_quietSince < 0) m_quietSince = now;
    } else {
        m_quietSince = -1.0;
    }

    if (now - m_last < EMIT_EVERY)
        return;
    m_last = now;
    emitResult(now);
}

void BpmCore::emitResult(double now)
{
    m_emitted = true;
    // Sustained silence: forget everything rather than freeze a stale number.
    if (m_quietSince >= 0 && now - m_quietSince > QUIET_AFTER) {
        reset();
        return;
    }

    std::vector<double> votes;
    for (const auto &b : m_beats) {
        if (b.size() < 9) continue;
        std::vector<double> iv;
        for (size_t i = 1; i < b.size(); ++i) {
            const double d = b[i] - b[i - 1];
            // Plausible beat-to-beat gaps only (50..220 BPM): a missed beat
            // shows up as a doubled interval and would otherwise halve things.
            if (d > 60.0 / 220 && d < 60.0 / 50) iv.push_back(d);
        }
        if (iv.size() > 6) votes.push_back(60.0 / median(iv));
    }

    const double pick = pickTempo(votes);
    if (pick > 0) {
        m_recent.push_back(pick);
        if (m_recent.size() > KEEP) m_recent.erase(m_recent.begin());
    }
    if (m_recent.empty()) {
        m_bpm = 0;
        m_tempo = 0.0;
        m_confidence = 0;
        return;
    }
    double med = median(m_recent);
    std::vector<double> good;
    for (double v : m_recent)
        if (std::fabs(v - med) <= 0.08 * med) good.push_back(v);
    if (good.size() >= 2) med = median(good);
    const double agree = double(good.size()) / m_recent.size();
    m_tempo = med;
    m_bpm = int(std::lround(med));
    m_confidence = int(std::lround(100.0 * agree * std::min(1.0, m_recent.size() / 4.0)));
}

double BpmCore::familySupport(const std::vector<double> &z, double bpm) const
{
    // The point of this is metrical level. aubio finds *a* pulse reliably,
    // but on a jungle break it may lock to 111, which is 4/3 of the real 83:
    // a triplet subdivision, so no halving or doubling corrects it. A true
    // tempo carries relatives (41/83/166 together); the impostor stands alone.
    static const double rel[4][2] = { {0.5, 0.7}, {1.0, 1.0}, {2.0, 0.7}, {4.0, 0.4} };
    double tot = 0.0;
    for (const auto &r : rel) {
        const int lag = int(std::lround(60.0 * m_envHz / (bpm * r[0])));
        if (lag >= 2 && lag < int(z.size()) - 2)
            tot += r[1] * std::max(z[lag - 1], std::max(z[lag], z[lag + 1]));
    }
    return tot;
}

double BpmCore::pickTempo(const std::vector<double> &votes) const
{
    if (m_env.size() < m_envHz * 8 || votes.empty())
        return 0.0;
    // Positive first difference of the envelope, mean removed.
    std::vector<double> d(m_env.size() - 1);
    double mean = 0.0;
    for (size_t i = 0; i + 1 < m_env.size(); ++i) {
        const double v = double(m_env[i + 1]) - m_env[i];
        d[i] = v > 0 ? v : 0.0;
        mean += d[i];
    }
    mean /= d.size();
    bool any = false;
    for (double &v : d) { v -= mean; if (v != 0.0) any = true; }
    if (!any) return 0.0;

    // Autocorrelation as z-scores. Trap from the original: comparing a peak
    // against the median fails here, because the median of a mean-removed
    // autocorrelation is negative by construction. The original correlates all
    // lags; mean and spread need them too, so all are computed (n is about
    // 1875 at 48 kHz, once every 2 s).
    const size_t n = d.size();
    std::vector<double> ac(n);
    for (size_t lag = 0; lag < n; ++lag) {
        double s = 0.0;
        for (size_t i = 0; i + lag < n; ++i) s += d[i] * d[i + lag];
        ac[lag] = s;
    }
    double am = 0.0;
    for (double v : ac) am += v;
    am /= n;
    double var = 0.0;
    for (double v : ac) var += (v - am) * (v - am);
    const double sd = std::sqrt(var / n);
    if (sd <= 0) return 0.0;
    std::vector<double> z(n);
    for (size_t i = 0; i < n; ++i) z[i] = (ac[i] - am) / sd;

    // Candidates, wide on purpose: a cap at 170 once folded 175 BPM drum and
    // bass down to 87. The 3/4 and 4/3 ratios reach a triplet lock.
    std::set<double> cands;
    static const double ratios[] = { 0.5, 1.0, 2.0, 0.75, 4.0 / 3.0, 1.5, 2.0 / 3.0 };
    for (double v : votes)
        for (double r : ratios) {
            const double c = v * r;
            if (c >= 40.0 && c <= 200.0) cands.insert(std::round(c * 10.0) / 10.0);
        }
    if (cands.empty()) return 0.0;
    double best = 0.0, bestScore = -1e300;
    for (double c : cands) {
        const double s = familySupport(z, c);
        if (s > bestScore) { bestScore = s; best = c; }
    }
    return refine(z, best);
}

// SailfishOS addition, not in the original: the value only, never the
// choice. aubio places beats on whole hops of its own period estimate, so
// the votes carry about 1 % of error (a 174 loop reads 175.8, its half
// 87.8), which halving or doubling then shows as a wrong integer. Here the
// envelope autocorrelation peak next to the chosen tempo's lag is found
// and interpolated between lags with a parabola. Only a peak within 3 % of
// the pick is used; otherwise the pick stays as it is.
double BpmCore::refine(const std::vector<double> &z, double bpm) const
{
    const double lag = 60.0 * m_envHz / bpm;
    const int lo = int(std::floor(lag * 0.97)), hi = int(std::ceil(lag * 1.03));
    if (lo < 1 || hi + 1 >= int(z.size()))
        return bpm;
    int peak = lo;
    for (int i = lo; i <= hi; ++i)
        if (z[i] > z[peak]) peak = i;
    if (peak == lo || peak == hi)          // rising into the edge: no peak here
        return bpm;
    const double a = z[peak - 1], b = z[peak], c = z[peak + 1];
    const double den = a - 2.0 * b + c;
    const double off = den < 0 ? 0.5 * (a - c) / den : 0.0;
    const double refined = 60.0 * m_envHz / (peak + off);
    return std::fabs(refined - bpm) <= 0.03 * bpm ? refined : bpm;
}
