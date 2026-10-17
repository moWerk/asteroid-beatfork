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

#include "PitchDetector.h"

#include <QAudioDeviceInfo>
#include <QAudioInput>
#include <QDebug>
#include <QtEndian>
#include <algorithm>
#include <cmath>

extern "C" {
#include "types.h"
#include "fvec.h"
#include "pitch/pitch.h"
}

// yinfast (YIN computed with an FFT) over 4096 samples reaches down to the
// low F#1 (46 Hz) of an 8-string guitar and the E1 (41 Hz) of a bass; a hop
// of 1024 gives a new estimate every 21 ms at 48 kHz. yinfft, aubio's
// default, read sines 1-9 % sharp on the C2 self-test and always reported
// confidence 0; yin and yinfast hit them within 0.02 Hz.
static const unsigned WIN = 4096;
static const unsigned HOP = 1024;
static const int MEDIAN_OF = 6;              // hops per result, about 8 results/s
static const float MIN_CONFIDENCE = 0.8f;    // below that: no clear pitch
static const float SILENCE_DB = -55.0f;

#define PITCH (static_cast<aubio_pitch_t *>(m_pitch))
#define IN (static_cast<fvec_t *>(m_in))
#define OUT (static_cast<fvec_t *>(m_out))

PitchDetector::PitchDetector(QObject *parent)
    : QObject(parent)
{
}

PitchDetector::~PitchDetector()
{
    stop();
}

QObject *PitchDetector::qmlInstance(QQmlEngine *, QJSEngine *)
{
    return new PitchDetector;
}

void PitchDetector::setActive(bool on)
{
    if (on == m_active) return;
    m_active = on;
    emit activeChanged();
    if (on) start(); else stop();
}

void PitchDetector::setError(const QString &e)
{
    if (e == m_error) return;
    m_error = e;
    if (!e.isEmpty()) qWarning() << "PitchDetector:" << e;
    emit errorChanged();
}

void PitchDetector::initAnalysis(unsigned rate)
{
    freeAnalysis();
    m_pitch = new_aubio_pitch(const_cast<char *>("yinfast"), WIN, HOP, rate);
    aubio_pitch_set_unit(PITCH, const_cast<char *>("Hz"));
    aubio_pitch_set_silence(PITCH, SILENCE_DB);
    m_in = new_fvec(HOP);
    m_out = new_fvec(1);
    m_fill = 0;
    m_sumSquares = 0.0;
    m_window.clear();
}

void PitchDetector::freeAnalysis()
{
    if (m_pitch) del_aubio_pitch(PITCH);
    if (m_in) del_fvec(IN);
    if (m_out) del_fvec(OUT);
    m_pitch = nullptr;
    m_in = m_out = nullptr;
}

void PitchDetector::start()
{
    // the microphone, as in BpmDetector: not the default device (on the C2
    // that is the speaker monitor), not the null or fast placeholders
    QAudioDeviceInfo dev;
    for (const QAudioDeviceInfo &d : QAudioDeviceInfo::availableDevices(QAudio::AudioInput)) {
        const QString n = d.deviceName();
        if (n.contains(QLatin1String("input")) && !n.contains(QLatin1String("null"))
                && !n.contains(QLatin1String("fast")) && !n.contains(QLatin1String("monitor"))) {
            dev = d;
            break;
        }
    }
    if (dev.isNull()) {
        //% "No microphone found"
        setError(qtTrId("id-pitch-no-mic"));
        return;
    }
    QAudioFormat f;
    f.setSampleRate(48000);
    f.setChannelCount(1);
    f.setSampleSize(16);
    f.setSampleType(QAudioFormat::SignedInt);
    f.setByteOrder(QAudioFormat::LittleEndian);
    f.setCodec(QStringLiteral("audio/pcm"));
    if (!dev.isFormatSupported(f))
        f = dev.nearestFormat(f);
    if (f.sampleSize() != 16 || f.sampleType() != QAudioFormat::SignedInt
            || f.byteOrder() != QAudioFormat::LittleEndian || f.channelCount() < 1) {
        //% "Audio format not supported"
        setError(qtTrId("id-bpm-format-error"));
        return;
    }
    m_format = f;
    initAnalysis(unsigned(f.sampleRate()));
    m_pending.clear();

    m_input = new QAudioInput(dev, f, this);
    // short reads: the tuner should feel immediate
    m_input->setBufferSize(f.bytesForDuration(40000));
    m_io = m_input->start();
    if (!m_io || m_input->error() != QAudio::NoError) {
        //% "Could not open the audio source"
        setError(qtTrId("id-bpm-open-error"));
        delete m_input;
        m_input = nullptr;
        m_io = nullptr;
        freeAnalysis();
        return;
    }
    connect(m_io, &QIODevice::readyRead, this, &PitchDetector::onReadyRead);
    qInfo() << "PitchDetector: listening to" << dev.deviceName() << f.sampleRate()
            << "Hz" << f.channelCount() << "channels";
    setError(QString());
    emit runningChanged();
}

void PitchDetector::stop()
{
    if (m_input) {
        m_input->stop();
        delete m_input;
        m_input = nullptr;
        m_io = nullptr;
        emit runningChanged();
    }
    freeAnalysis();
    if (m_frequency != 0.0) {
        m_frequency = 0.0;
        emit resultChanged();
    }
    if (m_level != 0.0) {
        m_level = 0.0;
        emit levelChanged();
    }
}

void PitchDetector::onReadyRead()
{
    if (!m_io) return;
    m_pending += m_io->readAll();
    const int ch = m_format.channelCount();
    const int frames = m_pending.size() / (2 * ch);
    if (frames == 0) return;
    process(reinterpret_cast<const qint16 *>(m_pending.constData()), frames, ch);
    m_pending.remove(0, frames * 2 * ch);
}

void PitchDetector::process(const qint16 *data, int count, int ch)
{
    for (int i = 0; i < count; ++i) {
        double mix = 0.0;
        for (int c = 0; c < ch; ++c)
            mix += qFromLittleEndian<qint16>(data[i * ch + c]);
        const float s = float(mix / ch / 32768.0);
        m_sumSquares += double(s) * s;
        IN->data[m_fill++] = s;
        if (m_fill == int(HOP)) {
            analyseHop();
            m_fill = 0;
        }
    }
}

void PitchDetector::analyseHop()
{
    aubio_pitch_do(PITCH, IN, OUT);
    const float hz = OUT->data[0];
    const float conf = aubio_pitch_get_confidence(PITCH);
    m_window << ((conf >= MIN_CONFIDENCE && hz > 20.0f && hz < 5000.0f) ? hz : 0.0f);

    if (m_window.size() < MEDIAN_OF)
        return;

    // the median of the last hops; no pitch unless most of them had one
    QVector<float> sorted = m_window;
    std::sort(sorted.begin(), sorted.end());
    const float median = sorted.at(sorted.size() / 2);
    m_window.clear();

    const double rms = std::sqrt(m_sumSquares / (HOP * MEDIAN_OF));
    m_sumSquares = 0.0;
    // log scale, 0 at -60 dBFS, 1 at 0 dBFS
    m_level = qBound(0.0, (20.0 * std::log10(qMax(rms, 1e-6)) + 60.0) / 60.0, 1.0);
    emit levelChanged();

    m_frequency = median;
    emit resultChanged();
}

void PitchDetector::runSine(double hz)
{
    const unsigned rate = 48000;
    PitchDetector d;
    d.m_format.setSampleRate(int(rate));
    d.m_format.setChannelCount(1);
    d.initAnalysis(rate);
    int n = 0;
    connect(&d, &PitchDetector::resultChanged, [&d, &n, hz]() {
        if (++n % 5) return;   // every fifth result is enough for the log
        const double f = d.m_frequency;
        const double cents = f > 0 ? 1200.0 * std::log2(f / hz) : 0.0;
        qInfo().noquote() << QStringLiteral("PitchDetector sine %1 Hz: detected %2 Hz (%3 ct)")
                             .arg(hz, 0, 'f', 2).arg(f, 0, 'f', 2).arg(cents, 0, 'f', 1);
    });
    // 3 seconds of sine at -12 dBFS
    QVector<qint16> pcm(int(rate) * 3);
    for (int i = 0; i < pcm.size(); ++i)
        pcm[i] = qint16(8000.0 * std::sin(2.0 * M_PI * hz * i / rate));
    d.process(pcm.constData(), pcm.size(), 1);
    QObject::disconnect(&d, nullptr, nullptr, nullptr);
}
