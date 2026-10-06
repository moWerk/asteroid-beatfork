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

#include "BpmDetector.h"
#include "BpmCore.h"

#include <QAudioInput>
#include <QDataStream>
#include <QDebug>
#include <QFile>
#include <QtEndian>
#include <cmath>

// Silence thresholds on the int16 RMS scale. 120 is the original's value for
// a line level stream; the speaker monitor is a digital stream like that.
// The microphone in a quiet room reads about 32 on the Jolla C2 (measured
// 2026-10-06, night, phone on a table), the idle speaker monitor about 25.
static const float SILENCE_LINE = 120.0f;
static const float SILENCE_MIC = 60.0f;

static QString friendlyName(const QAudioDeviceInfo &d)
{
    const QString n = d.deviceName();
    //% "Playback"
    if (n.contains(QLatin1String("monitor"))) return qtTrId("id-source-playback");
    //% "Microphone"
    if (n.contains(QLatin1String("input"))) return qtTrId("id-source-microphone");
    return n;
}

BpmDetector::BpmDetector(QObject *parent)
    : QObject(parent)
{
    // Microphone first, then the speaker monitor. Not by default device:
    // on the C2 Qt reports the speaker monitor as the default input. The
    // null sink and source are PulseAudio placeholders, the fast sink a
    // low latency path without its own content.
    const QList<QAudioDeviceInfo> all = QAudioDeviceInfo::availableDevices(QAudio::AudioInput);
    for (const QAudioDeviceInfo &d : all)
        qInfo() << "BpmDetector: input device" << d.deviceName();
    const char *const order[] = { "input", "monitor" };
    for (const char *kind : order)
        for (const QAudioDeviceInfo &d : all) {
            const QString n = d.deviceName();
            if (n.contains(QLatin1String("null")) || n.contains(QLatin1String("fast")))
                continue;
            if (!n.contains(QLatin1String(kind)))
                continue;
            m_devices << d;
            m_names << friendlyName(d);
        }
}

BpmDetector::~BpmDetector()
{
    stop();
}

QObject *BpmDetector::qmlInstance(QQmlEngine *, QJSEngine *)
{
    return new BpmDetector;
}

void BpmDetector::setSource(int index)
{
    if (index < -1 || index >= m_devices.size())
        index = -1;
    if (index == m_source)
        return;
    stop();
    m_source = index;
    emit sourceChanged();
    if (m_source >= 0)
        start();
}

void BpmDetector::setError(const QString &e)
{
    if (e == m_error) return;
    m_error = e;
    if (!e.isEmpty()) qWarning() << "BpmDetector:" << e;
    emit errorChanged();
}

void BpmDetector::start()
{
    const QAudioDeviceInfo &dev = m_devices.at(m_source);
    QAudioFormat f;
    f.setSampleRate(48000);
    f.setChannelCount(2);
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
    m_core.reset(new BpmCore(unsigned(f.sampleRate())));
    m_core->setSilenceRms(dev.deviceName().contains(QLatin1String("monitor"))
                          ? SILENCE_LINE : SILENCE_MIC);
    m_pending.clear();
    m_mono.resize(BpmCore::HOP);
    m_blockFill = 0;
    m_sumSquares = 0.0;
    m_frames = 0;

    m_input = new QAudioInput(dev, f, this);
    // about 100 ms per read keeps the result clock steady
    m_input->setBufferSize(f.bytesForDuration(100000));
    m_io = m_input->start();
    if (!m_io || m_input->error() != QAudio::NoError) {
        //% "Could not open the audio source"
        setError(qtTrId("id-bpm-open-error"));
        delete m_input;
        m_input = nullptr;
        m_io = nullptr;
        return;
    }
    connect(m_io, &QIODevice::readyRead, this, &BpmDetector::onReadyRead);
    qInfo() << "BpmDetector: listening to" << dev.deviceName() << f.sampleRate()
            << "Hz" << f.channelCount() << "channels";
    setError(QString());
    emit runningChanged();
}

void BpmDetector::stop()
{
    if (m_input) {
        m_input->stop();
        delete m_input;
        m_input = nullptr;
        m_io = nullptr;
        emit runningChanged();
    }
    m_core.reset();
    if (m_bpm || m_confidence) {
        m_bpm = 0;
        m_confidence = 0;
        emit resultChanged();
    }
    if (m_level != 0.0) {
        m_level = 0.0;
        emit levelChanged();
    }
}

void BpmDetector::onReadyRead()
{
    if (!m_io) return;
    m_pending += m_io->readAll();
    const int frameBytes = 2 * m_format.channelCount();
    const int frames = m_pending.size() / frameBytes;
    if (frames == 0) return;
    process(reinterpret_cast<const qint16 *>(m_pending.constData()), frames);
    m_pending.remove(0, frames * frameBytes);
}

void BpmDetector::process(const qint16 *data, int count)
{
    const int ch = m_format.channelCount();
    for (int i = 0; i < count; ++i) {
        // RMS over all channels as the original computes it; the trackers
        // get the mono mix
        double mix = 0.0;
        for (int c = 0; c < ch; ++c) {
            const double s = qFromLittleEndian<qint16>(data[i * ch + c]);
            m_sumSquares += s * s;
            mix += s;
        }
        m_mono[m_blockFill++] = float(mix / ch / 32768.0);
        if (m_blockFill < int(BpmCore::HOP))
            continue;

        const float rms = float(std::sqrt(m_sumSquares / (BpmCore::HOP * ch)));
        m_frames += BpmCore::HOP;
        m_blockFill = 0;
        m_sumSquares = 0.0;
        // The clock is the sample count, not the wall clock: a late read
        // then cannot squeeze or stretch the beat timestamps.
        m_core->feed(m_mono.constData(), rms, double(m_frames) / m_format.sampleRate());

        m_levelAcc += rms;
        if (++m_levelBlocks >= 8) {
            // log scale, 0 at RMS 10, 1 at RMS 10000
            const double mean = m_levelAcc / m_levelBlocks;
            m_level = qBound(0.0, (std::log10(qMax(mean, 1.0)) - 1.0) / 3.0, 1.0);
            m_levelAcc = 0.0;
            m_levelBlocks = 0;
            emit levelChanged();
        }
        if (m_core->emitted()
                && (m_core->bpm() != m_bpm || m_core->confidence() != m_confidence)) {
            m_bpm = m_core->bpm();
            m_confidence = m_core->confidence();
            emit resultChanged();
        }
    }
}

bool BpmDetector::runWav(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "BpmDetector: cannot open" << path;
        return false;
    }
    const QByteArray all = file.readAll();
    // minimal RIFF walk: fmt chunk for the layout, data chunk for samples
    int pos = 12, channels = 0, rate = 0, bits = 0;
    QByteArray pcm;
    while (pos + 8 <= all.size()) {
        const QByteArray id = all.mid(pos, 4);
        const quint32 len = qFromLittleEndian<quint32>(
                    reinterpret_cast<const uchar *>(all.constData() + pos + 4));
        const char *body = all.constData() + pos + 8;
        if (id == "fmt ") {
            channels = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(body + 2));
            rate = int(qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(body + 4)));
            bits = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(body + 14));
        } else if (id == "data") {
            pcm = all.mid(pos + 8, int(len));
        }
        pos += 8 + int(len) + (len & 1);
    }
    if (bits != 16 || channels < 1 || rate <= 0 || pcm.isEmpty()) {
        qWarning() << "BpmDetector: need a 16 bit PCM WAV:" << path;
        return false;
    }

    BpmDetector d;
    d.m_format.setChannelCount(channels);
    d.m_format.setSampleRate(rate);
    d.m_core.reset(new BpmCore(unsigned(rate)));
    d.m_mono.resize(BpmCore::HOP);
    connect(&d, &BpmDetector::resultChanged, [&d]() {
        qInfo().noquote() << QStringLiteral("BpmDetector wav: %1 s  bpm %2  confidence %3")
                             .arg(double(d.m_frames) / d.m_format.sampleRate(), 6, 'f', 1)
                             .arg(d.m_bpm).arg(d.m_confidence);
    });
    d.process(reinterpret_cast<const qint16 *>(pcm.constData()),
              pcm.size() / (2 * channels));
    // the destructor's stop() clears the result; that is not a result to log
    QObject::disconnect(&d, nullptr, nullptr, nullptr);
    return true;
}
