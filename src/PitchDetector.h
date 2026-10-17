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

#ifndef PITCHDETECTOR_H
#define PITCHDETECTOR_H

#include <QAudioFormat>
#include <QByteArray>
#include <QObject>
#include <QString>
#include <QVector>

class QAudioInput;
class QIODevice;

// The tuner's ear: listens to the microphone and reports the dominant
// frequency with aubio's yinfast pitch detector. A result comes about 8
// times a second (the median of six analysis steps); 0 means no clear
// pitch. Only listens while `active` is set, so the microphone is free
// on the other pages and in the background.
class PitchDetector : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(qreal frequency READ frequency NOTIFY resultChanged)   // Hz, 0 = none
    Q_PROPERTY(qreal level READ level NOTIFY levelChanged)            // 0..1, for a meter
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit PitchDetector(QObject *parent = nullptr);
    ~PitchDetector() override;

    bool active() const { return m_active; }
    void setActive(bool on);
    bool running() const { return m_input != nullptr; }
    qreal frequency() const { return m_frequency; }
    qreal level() const { return m_level; }
    QString error() const { return m_error; }

    // Test hook: a few seconds of sine at `hz` through the same analysis,
    // every result logged. No audio device involved.
    static void runSine(double hz);

    static QObject *qmlInstance(class QQmlEngine *, class QJSEngine *);

signals:
    void activeChanged();
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
    void initAnalysis(unsigned rate);
    void freeAnalysis();
    // interleaved int16 frames in, mixed to mono, analysed per hop
    void process(const qint16 *frames, int count, int channels);
    void analyseHop();

    bool m_active = false;
    QAudioFormat m_format;
    QAudioInput *m_input = nullptr;
    QIODevice *m_io = nullptr;
    QByteArray m_pending;

    // aubio types kept opaque here so the header needs no aubio include
    void *m_pitch = nullptr;
    void *m_in = nullptr;
    void *m_out = nullptr;
    int m_fill = 0;
    double m_sumSquares = 0.0;
    QVector<float> m_window;   // per-hop estimates for the median

    qreal m_frequency = 0.0;
    qreal m_level = 0.0;
    QString m_error;
};

#endif // PITCHDETECTOR_H
