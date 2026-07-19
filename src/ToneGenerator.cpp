/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 */

#include "ToneGenerator.h"

#include <QAudioFormat>
#include <QMediaDevices>
#include <QTimer>
#include <QtQml>
#include <cmath>

static const int kSampleRate = 48000;
static const double kAmplitude = 0.6;

SineDevice::SineDevice(QObject *parent)
    : QIODevice(parent)
{
}

void SineDevice::configure(int sampleRate, double frequency)
{
    m_sampleRate = sampleRate;
    m_frequency = frequency;
    m_phase = 0.0;
    m_envPos = 0;
    m_envLen = sampleRate / 100;   // 10 ms
    m_phaseState = Attack;
}

void SineDevice::beginRelease()
{
    if (m_phaseState != Done) {
        m_envPos = 0;
        m_phaseState = Release;
    }
}

qint64 SineDevice::bytesAvailable() const
{
    // report one modest chunk (20 ms) so the pull-mode sink paces its
    // reads instead of stuffing the PulseAudio queue ("Failed to push
    // data into queue" spam + seconds of over-buffered latency)
    return (m_sampleRate / 50) * qint64(sizeof(qint16))
           + QIODevice::bytesAvailable();
}

qint64 SineDevice::readData(char *data, qint64 maxlen)
{
    qint16 *out = reinterpret_cast<qint16 *>(data);
    const qint64 frames = maxlen / qint64(sizeof(qint16));
    const double step = 2.0 * M_PI * m_frequency / m_sampleRate;

    for (qint64 i = 0; i < frames; ++i) {
        double env = 0.0;
        switch (m_phaseState) {
        case Attack:
            // raised-cosine 0 -> 1
            env = 0.5 * (1.0 - std::cos(M_PI * m_envPos / double(m_envLen)));
            if (++m_envPos >= m_envLen) m_phaseState = Sustain;
            break;
        case Sustain:
            env = 1.0;
            break;
        case Release:
            // raised-cosine 1 -> 0
            env = 0.5 * (1.0 + std::cos(M_PI * m_envPos / double(m_envLen)));
            if (++m_envPos >= m_envLen) m_phaseState = Done;
            break;
        case Done:
            env = 0.0;
            break;
        }

        out[i] = qint16(std::lround(kAmplitude * env * 32767.0 * std::sin(m_phase)));
        m_phase += step;
        if (m_phase > 2.0 * M_PI) m_phase -= 2.0 * M_PI;
    }
    return frames * qint64(sizeof(qint16));
}

ToneGenerator::ToneGenerator(QObject *parent)
    : QObject(parent)
{
}

ToneGenerator::~ToneGenerator()
{
    if (m_sink) m_sink->stop();
}

void ToneGenerator::start(double frequency)
{
    // restart cleanly on frequency change or re-trigger
    if (m_sink) {
        m_sink->stop();
        m_sink.reset();
    }

    QAudioFormat format;
    format.setSampleRate(kSampleRate);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Int16);

    m_device.configure(kSampleRate, frequency);
    if (!m_device.isOpen())
        m_device.open(QIODevice::ReadOnly);

    m_sink.reset(new QAudioSink(QMediaDevices::defaultAudioOutput(), format));
    // bound end-to-end latency to ~100 ms: keeps stop responsive and
    // the pulse queue shallow
    m_sink->setBufferSize(kSampleRate / 10 * int(sizeof(qint16)));
    m_sink->start(&m_device);
    setPlaying(true);
}

void ToneGenerator::stop()
{
    if (!m_sink) {
        setPlaying(false);
        return;
    }
    // let the release envelope (10 ms) plus the bounded sink buffer
    // (~100 ms) play out before closing, so the tail is not truncated;
    // then release the sink so it can suspend (no held stream)
    m_device.beginRelease();
    QTimer::singleShot(150, this, &ToneGenerator::drainAndClose);
    setPlaying(false);
}

void ToneGenerator::drainAndClose()
{
    if (m_sink) {
        m_sink->stop();
        m_sink.reset();
    }
    if (m_device.isOpen())
        m_device.close();
}

void ToneGenerator::setPlaying(bool p)
{
    if (m_playing != p) {
        m_playing = p;
        emit playingChanged();
    }
}

ToneGenerator *ToneGenerator::qmlInstance(QQmlEngine *, QJSEngine *)
{
    return new ToneGenerator();
}
