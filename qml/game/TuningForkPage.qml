/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 */

import QtQuick 2.6
import "."
import moWerk.ToneGenerator 1.0
import moWerk.PitchDetector 1.0


Item {
    id: page

    // ── Interface — primitives only ───────────────────────────────────────────
    // SailfishOS: a category (concert pitch or an instrument) and an entry in
    // it; play mode plays the entry, detect mode tunes to it.
    property var    categories:    []
    property int    categoryIndex: 0
    property int    entryIndex:    0
    readonly property var entries: categories.length > 0 ? categories[categoryIndex].items : []
    readonly property var entry: entries.length > 0 ? entries[Math.max(0, Math.min(entries.length - 1, entryIndex))]
                                                    : { name: "A4", hz: 440 }
    property real   freqValue: entry.hz

    property bool   detectMode: false
    property bool   snap:       false

    // live-synthesized tone (ToneGen singleton) — playing state comes
    // from the generator itself
    property bool   tonePlaying: ToneGen.playing

    function toneStart() { ToneGen.start(freqValue) }
    function toneStop()  { ToneGen.stop() }
    property string pulseColor: "#00ff00"
    property bool   loopActive: false

    property bool   pageActive: false

    // Write-back signals
    signal categoryIndexSet(int idx)
    signal entryIndexSet(int idx)
    signal loopActiveSet(bool active)
    signal detectModeSet(bool on)
    signal snapSet(bool on)

    // ── Audio ─────────────────────────────────────────────────────────────────
    // Tones are synthesized live (QAudioSink sine with raised-cosine
    // attack/release in C++) — no sound files, any frequency, and the
    // envelope makes start/stop pop-free by construction.

    Timer {
        id: singlePlayStop
        interval: 1000
        repeat:   false
        onTriggered: page.toneStop()
    }

    // detect mode: a short hint of the new target when stepping to it
    Timer {
        id: hintStop
        interval: 250
        onTriggered: page.toneStop()
    }

    function stopAll() {
        singlePlayStop.stop()
        hintStop.stop()
        page.toneStop()
        page.loopActiveSet(false)
    }

    // the nearest equal-tempered note (A4 = 440 Hz), for snap
    readonly property var noteNames: ["A", "A♯", "B", "C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯"]
    function nearestNote(f) {
        var n = Math.round(12 * Math.log(f / 440) / Math.LN2)
        var octave = 4 + Math.floor((n + 9) / 12)
        return { name: noteNames[((n % 12) + 12) % 12] + octave, hz: 440 * Math.pow(2, n / 12) }
    }
    // what the tuner measures against
    readonly property var target: snap && PitchListener.frequency > 0 ? nearestNote(PitchListener.frequency)
                                                                      : entry

    // ── Mode: play the tone, or detect (SailfishOS) ───────────────────────────
    Row {
        id: modeToggle
        anchors.top: parent.top
        anchors.topMargin: Dims.l(5)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Dims.l(6)

        Repeater {
            model: 2
            Label {
                readonly property bool on: (index === 1) === page.detectMode
                text: index === 0
                      //% "Play"
                      ? qsTrId("id-mode-play")
                      //% "Detect"
                      : qsTrId("id-mode-detect")
                color: on ? page.pulseColor : "#ffffff"
                opacity: on ? 1.0 : 0.5
                font { pixelSize: Dims.l(8); family: "Sail Sans Pro" }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Dims.l(3)
                    onClicked: {
                        if (parent.on) return
                        page.stopAll()
                        page.detectModeSet(index === 1)
                    }
                }
            }
        }
    }

    // ── Category ──────────────────────────────────────────────────────────────
    TunePicker {
        id: categoryPicker
        anchors.top: modeToggle.bottom
        anchors.topMargin: Dims.l(3)
        width: parent.width
        z: 10
        //% "Tuning"
        label: qsTrId("id-tuning")
        model: page.categories
        currentIndex: page.categoryIndex
        onPicked: {
            if (index === page.categoryIndex) return
            page.stopAll()
            page.categoryIndexSet(index)
            tuner.clear()
        }
    }

    // ── Entry: tap steps through the category ─────────────────────────────────
    Column {
        id: selector
        anchors.top: categoryPicker.bottom
        anchors.topMargin: Dims.l(4)
        anchors.horizontalCenter: parent.horizontalCenter

        Label {
            id: freqNameLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.detectMode && page.snap ? (PitchListener.frequency > 0 ? page.target.name : "–")
                                               : page.entry.name
            font.pixelSize: Dims.l(6)
            opacity: 0.6
        }

        Label {
            id: freqLabel
            anchors.horizontalCenter: parent.horizontalCenter
            //% "Hz"
            text: (page.detectMode && page.snap && !(PitchListener.frequency > 0) ? "–"
                   : (Math.round(page.target.hz) === page.target.hz ? page.target.hz
                                                                    : page.target.hz.toFixed(2)))
                  + " " + qsTrId("id-hz")
            font.pixelSize: Dims.l(12)
            opacity: 1.0

            SequentialAnimation {
                id: loopIndicator
                running:  page.loopActive
                loops:    Animation.Infinite
                NumberAnimation { target: freqLabel; property: "opacity"; to: 0.5; duration: 400; easing.type: Easing.InOutSine }
                NumberAnimation { target: freqLabel; property: "opacity"; to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) freqLabel.opacity = 1.0
            }
        }

        Label {
            id: tapChangeLabel
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !(page.detectMode && page.snap)
            //% "Tap to change"
            text:           qsTrId("id-tap-to-change")
            font.pixelSize: Dims.l(6)
            opacity: 0.6
        }
    }

    MouseArea {
        x: 0
        width: parent.width
        y: selector.y - Dims.l(2)
        height: selector.height + Dims.l(4)
        enabled: !(page.detectMode && page.snap)
        onClicked: {
            page.stopAll()
            var next = (page.entryIndex + 1) % Math.max(1, page.entries.length)
            page.entryIndexSet(next)
            tuner.clear()
            if (page.entries.length > 0) {
                // a short hint of the new tone, in both modes
                ToneGen.start(page.entries[next].hz)
                hintStop.restart()
            }
        }
    }

    // ── Snap (detect mode) ────────────────────────────────────────────────────
    Label {
        id: snapToggle
        anchors.top: selector.bottom
        anchors.topMargin: Dims.l(5)
        anchors.horizontalCenter: parent.horizontalCenter
        visible: page.detectMode
        //% "Snap to nearest note"
        text: qsTrId("id-snap-nearest")
        color: page.snap ? page.pulseColor : "#ffffff"
        opacity: page.snap ? 1.0 : 0.5
        font { pixelSize: Dims.l(7); family: "Sail Sans Pro" }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Dims.l(3)
            onClicked: {
                page.stopAll()
                page.snapSet(!page.snap)
                tuner.clear()
            }
        }
    }

    // ── Lower half ────────────────────────────────────────────────────────────
    Item {
        visible: !page.detectMode
        anchors.bottom:       parent.bottom
        anchors.left:         parent.left
        anchors.right:        parent.right
        anchors.bottomMargin: Dims.h(14)
        height: parent.height * 0.5 - Dims.h(10)

        Item {
            id: forkButton
            anchors.centerIn: parent
            // SailfishOS: closer to the page centre, the hint gets room (mo, 2026-10-17)
            anchors.verticalCenterOffset: -Dims.l(10)
            width:  Dims.l(30)
            height: Dims.l(30)

            property int rippleCount: 0

            Timer {
                id: rippleTimer
                interval: 1200
                repeat:   true
                running:  page.tonePlaying
                onTriggered: forkButton.rippleCount++
            }

            Rectangle {
                id: forkRipple1
                anchors.centerIn: parent
                width:   forkButton.width
                height:  width
                radius:  width / 2
                color:   "transparent"
                border.color: page.pulseColor
                border.width: Dims.l(0.8)
                opacity: 0.0
                scale:   1.0
                z: 0

                ParallelAnimation {
                    id: forkRipple1Anim
                    NumberAnimation { target: forkRipple1; property: "scale";   from: 1.0; to: 2.0; duration: 700; easing.type: Easing.OutQuad }
                    NumberAnimation { target: forkRipple1; property: "opacity"; from: 0.7; to: 0.0; duration: 700; easing.type: Easing.InQuad  }
                }

                Connections {
                    target: forkButton
                    onRippleCountChanged: {
                        if (page.tonePlaying) forkRipple1Anim.restart()
                    }
                }
            }

            Rectangle {
                id: forkRipple2
                anchors.centerIn: parent
                width:   forkButton.width
                height:  width
                radius:  width / 2
                color:   "transparent"
                border.color: page.pulseColor
                border.width: Dims.l(0.5)
                opacity: 0.0
                scale:   1.0
                z: 0

                SequentialAnimation {
                    id: forkRipple2Anim
                    PauseAnimation { duration: 200 }
                    ParallelAnimation {
                        NumberAnimation { target: forkRipple2; property: "scale";   from: 1.0; to: 1.7; duration: 600; easing.type: Easing.OutQuad }
                        NumberAnimation { target: forkRipple2; property: "opacity"; from: 0.45; to: 0.0; duration: 600; easing.type: Easing.InQuad  }
                    }
                }

                Connections {
                    target: forkButton
                    onRippleCountChanged: {
                        if (page.tonePlaying) forkRipple2Anim.restart()
                    }
                }
            }

            Rectangle {
                id: forkBg
                anchors.fill: parent
                radius:  width / 2
                color:   page.tonePlaying ? page.pulseColor : "#000000"
                opacity: 0.7
                z: 1

                Behavior on color { ColorAnimation { duration: 150 } }

                SequentialAnimation {
                    id: idleBreath
                    running:  !page.tonePlaying
                    loops:    Animation.Infinite
                    NumberAnimation { target: forkBg; property: "opacity"; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { target: forkBg; property: "opacity"; to: 0.7;  duration: 900; easing.type: Easing.InOutSine }
                }

                SequentialAnimation {
                    id: playingPulse
                    running: false
                    NumberAnimation { target: forkBg; property: "opacity"; to: 1.0; duration: 80;  easing.type: Easing.OutQuad }
                    NumberAnimation { target: forkBg; property: "opacity"; to: 0.7; duration: 220; easing.type: Easing.InQuad }
                }
            }

            Icon {
                anchors.centerIn: parent
                width:  Dims.l(18)
                height: Dims.l(18)
                name:   "ios-musical-note"
                z: 2
            }

            MouseArea {
                anchors.fill: parent
                z: 3
                property bool holdActive: false

                onClicked: {
                    if (holdActive) {
                        holdActive = false
                        return
                    }
                    if (page.tonePlaying) {
                        singlePlayStop.stop()
                        page.toneStop()
                        page.loopActiveSet(false)
                    } else {
                        // single play: the event loops (sound.repeat), the
                        // 1s timer bounds it to one audible strike
                        page.toneStart()
                        playingPulse.restart()
                        singlePlayStop.restart()
                        forkButton.rippleCount++
                    }
                }

                onPressAndHold: {
                    holdActive = true
                    singlePlayStop.stop()
                    if (!page.tonePlaying) page.toneStart()
                        page.loopActiveSet(true)
                        playingPulse.restart()
                        forkButton.rippleCount++
                }

                onReleased: {
                    if (holdActive) holdActive = false
                }
            }
        }

        Label {
            anchors.top:              forkButton.bottom
            anchors.horizontalCenter: forkButton.horizontalCenter
            anchors.topMargin:        Dims.h(6)
            // One //% comment per qsTrId: with both on one line lupdate gave
            // "id-hold-to-loop" no English, and the id showed on screen.
            text:           page.tonePlaying
                            //% "Tap to stop"
                            ? qsTrId("id-tap-to-stop")
                            //% "Hold to loop"
                            : qsTrId("id-hold-to-loop")
            font.pixelSize: Dims.l(6)
            opacity: 0.6
        }
    }

    // ── Tuner (SailfishOS) ────────────────────────────────────────────────────
    // Below the selector, to the bottom: the target as a vertical centre line,
    // ±100 cents across the width, a narrow in-tune band, the readings as a
    // line from the newest at the top down to the oldest.
    Item {
        id: tuner
        visible: page.detectMode
        x: Dims.l(5)
        width: parent.width - 2 * x
        y: snapToggle.y + snapToggle.height + Dims.l(8)
        height: parent.height - y - Dims.l(8)

        readonly property real inTune: 5     // cents
        readonly property real range:  100   // cents to each side
        readonly property real step:   Dims.l(2.4)
        readonly property int  maxPoints: Math.max(2, Math.floor(graphClip.height / step) + 1)
        property var  history: []            // smoothed cents, newest first; NaN = no pitch
        property real cents:   NaN
        // Smoothing: a held note wavers by tens of cents (voice, vibrato,
        // detection), the trend is what tuning needs. Each reading counts a
        // third; after a gap the next one starts fresh (mo, 2026-10-17).
        readonly property real smoothing: 0.35

        // cents from the target, octave errors folded back
        function centsOf(f) {
            if (!(f > 0)) return NaN
            var c = 1200 * Math.log(f / page.target.hz) / Math.LN2
            while (c > 600)  c -= 1200
            while (c < -600) c += 1200
            return c
        }

        function clear() {
            history = []
            cents = NaN
            graph.requestPaint()
        }

        Connections {
            target: PitchListener
            onResultChanged: {
                if (!tuner.visible) return
                var raw = tuner.centsOf(PitchListener.frequency)
                tuner.cents = isNaN(raw) ? NaN
                            : isNaN(tuner.cents) ? raw
                            : tuner.cents + tuner.smoothing * (raw - tuner.cents)
                var h = tuner.history
                h.unshift(tuner.cents)
                if (h.length > tuner.maxPoints) h.length = tuner.maxPoints
                tuner.history = h
                tuner.lastSample = Date.now()
            }
        }

        // Drawn every frame (16 ms), the scroll offset worked out in the
        // same paint from the time since the last reading, so data and
        // position always agree. An animation started per reading jumped
        // back whenever the repaint and the animation did not line up.
        property real lastSample: 0
        readonly property real interval: 128   // ms between readings (6 × 1024 samples)
        Timer {
            interval: 16
            repeat: true
            running: tuner.visible && Qt.application.active
            onTriggered: graph.requestPaint()
        }

        Label {
            id: readout
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: {
                if (PitchListener.error !== "") return PitchListener.error
                if (isNaN(tuner.cents))
                    //% "Play a string"
                    return qsTrId("id-play-a-string")
                var c = Math.round(tuner.cents)
                return PitchListener.frequency.toFixed(1) + " " + qsTrId("id-hz")
                        + " · " + (c > 0 ? "+" : "") + c + " ct"
            }
            color: !isNaN(tuner.cents) && Math.abs(tuner.cents) <= tuner.inTune ? page.pulseColor : "#ffffff"
            opacity: isNaN(tuner.cents) ? 0.5 : 1.0
            font { pixelSize: Dims.l(8); family: "Sail Sans Pro" }
        }

        Item {
            id: scaleRow
            anchors.top: readout.bottom
            anchors.topMargin: Dims.l(3)
            width: parent.width
            height: minusLabel.height
            Label { id: minusLabel; x: 0; text: "−100"; opacity: 0.5; font { pixelSize: Dims.l(5); family: "Sail Sans Pro" } }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "0"; opacity: 0.5; font { pixelSize: Dims.l(5); family: "Sail Sans Pro" } }
            Label { anchors.right: parent.right; text: "+100"; opacity: 0.5; font { pixelSize: Dims.l(5); family: "Sail Sans Pro" } }
        }

        Item {
            id: graphClip
            anchors.top: scaleRow.bottom
            anchors.topMargin: Dims.l(2)
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true

            Canvas {
                id: graph
                width: parent.width
                height: parent.height

                onPaint: {
                    var ctx = getContext("2d")
                    var w = width, h = height, mid = w / 2
                    var px = mid / tuner.range
                    ctx.clearRect(0, 0, w, h)

                    // in-tune band, centre line, ±50 cent guides
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.08)
                    ctx.fillRect(mid - tuner.inTune * px, 0, 2 * tuner.inTune * px, h)
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.6)
                    ctx.fillRect(mid - 1, 0, 2, h)
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.15)
                    ctx.fillRect(mid - 50 * px, 0, 1, h)
                    ctx.fillRect(mid + 50 * px, 0, 1, h)

                    // the readings as one line, broken where there was no pitch
                    // 0 right after a reading, one step once the next is due
                    var shift = tuner.step * Math.min(1, (Date.now() - tuner.lastSample) / tuner.interval)
                    var hist = tuner.history
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.7)
                    ctx.lineWidth = Math.max(2, Dims.l(0.5))
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    var open = false
                    for (var i = 0; i < hist.length; i++) {
                        var c = hist[i]
                        if (isNaN(c)) { open = false; continue }
                        var x = mid + Math.max(-tuner.range, Math.min(tuner.range, c)) * px
                        var y = i * tuner.step + tuner.step / 2 + shift - tuner.step
                        if (open) ctx.lineTo(x, y); else ctx.moveTo(x, y)
                        open = true
                    }
                    ctx.stroke()

                    // the newest reading as a dot
                    if (hist.length > 0 && !isNaN(hist[0])) {
                        var c0 = hist[0]
                        ctx.fillStyle = Math.abs(c0) <= tuner.inTune ? page.pulseColor : "#ffffff"
                        ctx.beginPath()
                        ctx.arc(mid + Math.max(-tuner.range, Math.min(tuner.range, c0)) * px,
                                tuner.step / 2 + shift - tuner.step, Dims.l(2.5), 0, 2 * Math.PI)
                        ctx.fill()
                    }
                }
            }
        }
    }
}
