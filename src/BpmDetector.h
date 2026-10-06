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

#ifndef BPMDETECTOR_H
#define BPMDETECTOR_H

#include <QObject>
#include <QAudioDeviceInfo>
#include <QAudioFormat>
#include <QByteArray>
#include <QList>
#include <QScopedPointer>
#include <QStringList>
#include <QVector>

class QAudioInput;
class QIODevice;
class BpmCore;

// Listens to one audio source and runs BpmCore on it. The sources are the
// PulseAudio inputs Qt lists: the microphone, and the monitor of the
// speaker output, which carries whatever the phone itself plays.
class BpmDetector : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList sources READ sources CONSTANT)
    Q_PROPERTY(int source READ source WRITE setSource NOTIFY sourceChanged)   // -1 = off
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int bpm READ bpm NOTIFY resultChanged)
    // unrounded: 87.5 doubled must give 175, not 176
    Q_PROPERTY(qreal tempo READ tempo NOTIFY resultChanged)
    Q_PROPERTY(int confidence READ confidence NOTIFY resultChanged)
    Q_PROPERTY(qreal level READ level NOTIFY levelChanged)   // 0..1, for a meter
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
public:
    explicit BpmDetector(QObject *parent = nullptr);
    ~BpmDetector() override;

    QStringList sources() const { return m_names; }
    int source() const { return m_source; }
    void setSource(int index);
    bool running() const { return m_input != nullptr; }
    int bpm() const { return m_bpm; }
    qreal tempo() const { return m_tempo; }
    int confidence() const { return m_confidence; }
    qreal level() const { return m_level; }
    QString error() const { return m_error; }

    // Test hook: run a 16 bit PCM WAV through the same path as live audio,
    // as fast as possible, and log every result. Returns false on a bad file.
    static bool runWav(const QString &path);

    // Qt 5.6's qmlRegisterSingletonType wants a QObject * callback
    static QObject *qmlInstance(class QQmlEngine *, class QJSEngine *);

signals:
    void sourceChanged();
    void runningChanged();
    void resultChanged();
    void levelChanged();
    void errorChanged();

private slots:
    void onReadyRead();

private:
    void start();
    void stop();
    void setError(const QString &e);
    // interleaved int16 frames in; whole HOP blocks go to the core
    void process(const qint16 *frames, int count);

    QList<QAudioDeviceInfo> m_devices;
    QStringList m_names;
    int m_source = -1;
    QAudioFormat m_format;
    QAudioInput *m_input = nullptr;
    QIODevice *m_io = nullptr;
    QScopedPointer<BpmCore> m_core;
    QByteArray m_pending;
    QVector<float> m_mono;
    double m_sumSquares = 0.0;
    int m_blockFill = 0;
    qint64 m_frames = 0;
    double m_levelAcc = 0.0;
    int m_levelBlocks = 0;
    int m_bpm = 0;
    qreal m_tempo = 0.0;
    int m_confidence = 0;
    qreal m_level = 0.0;
    QString m_error;
};

#endif // BPMDETECTOR_H
