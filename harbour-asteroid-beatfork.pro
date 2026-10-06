TARGET = harbour-asteroid-beatfork

CONFIG += sailfishapp sailfishapp_i18n sailfishapp_i18n_idbased sailfishapp_i18n_unfinished

SOURCES += src/main.cpp \
    src/ToneGenerator.cpp \
    src/BpmCore.cpp \
    src/BpmDetector.cpp

HEADERS += src/ToneGenerator.h \
    src/BpmCore.h \
    src/BpmDetector.h

# tempo detection: aubio 0.4.9 (GPL-3.0), built into the app
include(3rdparty/aubio/aubio.pri)

QT += multimedia

DISTFILES += qml/harbour-asteroid-beatfork.qml \
    qml/game/*.qml \
    qml/game/qmldir \
    rpm/harbour-asteroid-beatfork.spec \
    harbour-asteroid-beatfork.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# qsTrId() with //% engineering English: the id based build keeps the
# unfinished entries, so the default .qm carries that English.
TRANSLATIONS += translations/harbour-asteroid-beatfork.ts
