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

#include <sailfishapp.h>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQuickView>
#include <QScopedPointer>
#include <QTimer>
#include <QtQml>
#include "ToneGenerator.h"
#include "BpmDetector.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setOrganizationName(QStringLiteral("net.mowerk"));
    app->setApplicationName(QStringLiteral("harbour-asteroid-beatfork"));

    // A short audio buffer keeps the metronome tick and the tone on time.
    if (!qEnvironmentVariableIsSet("PULSE_LATENCY_MSEC"))
        qputenv("PULSE_LATENCY_MSEC", QByteArray::number(ToneGenerator::kPulseLatencyMs));
    qmlRegisterSingletonType<ToneGenerator>(
        "moWerk.ToneGenerator", 1, 0, "ToneGen",
        ToneGenerator::qmlInstance);
    qmlRegisterSingletonType<BpmDetector>(
        "moWerk.BpmDetector", 1, 0, "BpmListener",
        BpmDetector::qmlInstance);

    // Test hook: SFOS_SELFTEST_BPM_WAV=<file> runs a 16 bit WAV through the
    // tempo detection, logs every result and exits. Silent, no window.
    const QByteArray wav = qgetenv("SFOS_SELFTEST_BPM_WAV");
    if (!wav.isEmpty())
        return BpmDetector::runWav(QString::fromLocal8Bit(wav)) ? 0 : 1;

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    // Test hook: SFOS_SELFTEST_AUDIO=1 plays the tuning fork tone and the
    // metronome tick once and logs their state, without a tap.
    view->rootContext()->setContextProperty(QStringLiteral("selftestAudio"),
                                            qEnvironmentVariableIsSet("SFOS_SELFTEST_AUDIO"));
    // Test hook: SFOS_SELFTEST_LISTEN=<source index> starts listening at
    // once and logs the input level, without a tap. Records, plays nothing.
    view->rootContext()->setContextProperty(QStringLiteral("selftestListen"),
                                            qEnvironmentVariableIsSet("SFOS_SELFTEST_LISTEN")
                                            ? qgetenv("SFOS_SELFTEST_LISTEN").toInt() : -1);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    // Test hook, not used in normal runs: with SFOS_SELFTEST_SHOT=<file>
    // the window is grabbed after SFOS_SELFTEST_DELAY ms (default 6000)
    // and saved, so a build can be checked without looking at the phone.
    const QByteArray shot = qgetenv("SFOS_SELFTEST_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIsSet("SFOS_SELFTEST_DELAY")
                ? qgetenv("SFOS_SELFTEST_DELAY").toInt() : 6000;
        QQuickView *v = view.data();
        QTimer::singleShot(delay, v, [v, shot]() {
            v->grabWindow().save(QString::fromLocal8Bit(shot));
        });
    }
    return app->exec();
}
