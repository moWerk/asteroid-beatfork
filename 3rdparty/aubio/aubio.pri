# aubio 0.4.9, the parts BeatFork's tempo detection needs, compiled into
# the app (no shared library to package, nothing for the store validator to
# flag as a foreign library). See README.SailfishOS for what was taken.
DEFINES += HAVE_CONFIG_H
INCLUDEPATH += $$PWD/src
QMAKE_CFLAGS += -std=c99 -Wno-unused-parameter -Wno-sign-compare
SOURCES += $$files($$PWD/src/*.c) $$files($$PWD/src/spectral/*.c) \
    $$files($$PWD/src/tempo/*.c) $$files($$PWD/src/onset/*.c) \
    $$files($$PWD/src/temporal/*.c) $$files($$PWD/src/utils/*.c)
