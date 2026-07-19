/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef TONEGENERATOR_H
#define TONEGENERATOR_H

#include <QObject>
#include <QIODevice>
#include <QAudioSink>
#include <QScopedPointer>

// Live sine synthesis for the tuning fork: exact frequency from math,
// no sound file assets. A raised-cosine attack/release envelope makes
// the waveform step-free, so start/stop cannot pop regardless of the
// audio sink's suspend state. The sink is released after the release
// envelope finishes - no held PulseAudio stream, no standby drain.
class SineDevice : public QIODevice
{
    Q_OBJECT
public:
    explicit SineDevice(QObject *parent = nullptr);

    void configure(int sampleRate, double frequency);
    void beginRelease();
    bool releaseDone() const { return m_phaseState == Done; }

    qint64 readData(char *data, qint64 maxlen) override;
    qint64 writeData(const char *, qint64) override { return 0; }
    qint64 bytesAvailable() const override;
    bool isSequential() const override { return true; }

private:
    enum PhaseState { Attack, Sustain, Release, Done };
    int m_sampleRate = 48000;
    double m_frequency = 440.0;
    double m_phase = 0.0;
    int m_envPos = 0;
    int m_envLen = 480;            // 10 ms at 48 kHz
    PhaseState m_phaseState = Attack;
};

class ToneGenerator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
public:
    explicit ToneGenerator(QObject *parent = nullptr);
    ~ToneGenerator() override;

    Q_INVOKABLE void start(double frequency);
    Q_INVOKABLE void stop();

    bool playing() const { return m_playing; }

    static ToneGenerator *qmlInstance(class QQmlEngine *, class QJSEngine *);

signals:
    void playingChanged();

private slots:
    void drainAndClose();

private:
    void setPlaying(bool p);

    QScopedPointer<QAudioSink> m_sink;
    SineDevice m_device;
    bool m_playing = false;
};

#endif // TONEGENERATOR_H
