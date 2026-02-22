/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.9
import QtMultimedia 5.8
import Nemo.Configuration 1.0
import Nemo.Ngf 1.0
import Nemo.KeepAlive 1.1
import org.asteroid.controls 1.0
import org.asteroid.utils 1.0

Application {
    id: root

    anchors.fill: parent

    // ── Per-page background colors ────────────────────────────────────────────
    readonly property var pageCenterColors: ["#119DA4", "#07454B", "#0E8890"]
    readonly property var pageOuterColors:  ["#090B0C", "#050708", "#070909"]

    centerColor: pageCenterColors[pageView.currentIndex]
    outerColor:  pageOuterColors[pageView.currentIndex]

    Behavior on centerColor { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }
    Behavior on outerColor  { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    // ── Persisted config ──────────────────────────────────────────────────────
    ConfigurationValue { id: bpmConfig;   key: "/asteroid/apps/beatfork/bpm";        defaultValue: 120 }
    ConfigurationValue { id: freqConfig;  key: "/asteroid/apps/beatfork/freq";       defaultValue: 440 }
    ConfigurationValue { id: colorConfig; key: "/asteroid/apps/beatfork/colorIndex"; defaultValue: 0   }

    // ── BPM / model constants ─────────────────────────────────────────────────
    readonly property int bpmMin:         40
    readonly property int bpmMax:         208
    readonly property int bpmModelCount:  bpmMax - bpmMin + 1  // 169
    readonly property int flashDuration:  200
    readonly property int sessionBreakMs: 1500

    property var bpmModel: {
        var arr = []
        for (var i = root.bpmMin; i <= root.bpmMax; ++i) arr.push(i)
            return arr
    }

    property var freqModel: [392, 415, 432, 440, 442, 444, 452]

    readonly property var freqNames: [
        //% "G4"
        qsTrId("id-freq-g4"),
        //% "Ab4"
        qsTrId("id-freq-ab4"),
        //% "A4 Verdi"
        qsTrId("id-freq-a4-verdi"),
        //% "A4 Standard"
        qsTrId("id-freq-a4-standard"),
        //% "A4 Orchestra"
        qsTrId("id-freq-a4-orchestra"),
        //% "A4 High"
        qsTrId("id-freq-a4-high"),
        //% "Bb4"
        qsTrId("id-freq-bb4")
    ]

    readonly property var pulseColors: [
        "#FF69B4", "#C5FCE4", "#FF4B0A",
        "#FFEC1F", "#0ABAFF", "#98D831"
    ]

    readonly property string pulseColor: pulseColors[colorConfig.value]

    readonly property var pageTitles: [
        //% "Detect BPM"
        qsTrId("id-detect-bpm"),
        //% "Metronome"
        qsTrId("id-metronome"),
        //% "Tuning Fork"
        qsTrId("id-tuning-fork")
    ]

    // ── Page state objects — live at root to survive delegate recycling ────────
    QtObject {
        id: page1State
        property bool soundActive:  false
        property bool hapticActive: false
        property bool pulseVisible: false
        property int  pendingBpm:   -1
    }

    // loopActive mirrors tone.loops === Infinite && tone.playing from page 2.
    // Kept here so DisplayBlanking can see it without delegate-scope gymnastics.
    QtObject {
        id: page2State
        property bool loopActive: false
    }

    // ── Screen blanking — prevent when any active output is running ───────────
    // 1s preview does not qualify; only deliberate holds and metronome outputs.
    Binding {
        target:   DisplayBlanking
        property: "preventBlanking"
        value:    page1State.soundActive  ||
        page1State.hapticActive ||
        page1State.pulseVisible ||
        page2State.loopActive
    }

    // ── Audio / haptics ───────────────────────────────────────────────────────
    SoundEffect {
        id: tickSound
        source: "file:///usr/share/sounds/tick.wav"
        volume: 1.0
    }

    NonGraphicalFeedback {
        id: hapticFeedback
        event: "press"
    }

    // ── Master beat timer ─────────────────────────────────────────────────────
    Timer {
        id: beatTimer
        interval:         Math.round(60000 / bpmConfig.value)
        repeat:           true
        running:          true
        triggeredOnStart: false
        onTriggered:      root.beatFlash()
    }

    Connections {
        target: bpmConfig
        function onValueChanged() {
            beatTimer.interval = Math.round(60000 / bpmConfig.value)
            beatTimer.restart()
        }
    }

    // ── Spinner debounce ──────────────────────────────────────────────────────
    Timer {
        id: spinnerDebounce
        interval: 1000
        repeat:   false
        onTriggered: {
            if (page1State.pendingBpm >= root.bpmMin) {
                bpmConfig.value       = page1State.pendingBpm
                page1State.pendingBpm = -1
            }
        }
    }

    // ── Beat dispatcher ───────────────────────────────────────────────────────
    signal beat()

    function beatFlash() {
        root.beat()
        if (page1State.soundActive)  tickSound.play()
            if (page1State.hapticActive) hapticFeedback.play()
    }

    // ─────────────────────────────────────────────────────────────────────────
    ListView {
        id: pageView
        anchors.fill:       parent
        orientation:        ListView.Horizontal
        snapMode:           ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        flickDeceleration:  5000
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior:     Flickable.StopAtBounds
        model: 3

        delegate: Item {
            width:  pageView.width
            height: pageView.height

            // PAGE 0 ── Detect BPM ────────────────────────────────────────────
            Item {
                id: page0
                anchors.fill: parent
                visible: index === 0

                property real lastTap:   0
                property var  intervals: []

                Rectangle {
                    id: pulseSmall
                    anchors.centerIn: parent
                    width:   Dims.l(66)
                    height:  width
                    radius:  width / 2
                    color:   root.pulseColor
                    opacity: 0.0
                    z: 0

                    SequentialAnimation {
                        id: tapPulse
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.7; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.0; duration: 140; easing.type: Easing.InQuad }
                    }

                    SequentialAnimation {
                        id: pulseSmallAnim
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.7; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.0; duration: 140; easing.type: Easing.InQuad }
                    }

                    Connections {
                        target: root
                        function onBeat() { pulseSmallAnim.restart() }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    z: 1
                    text: bpmConfig.value
                    font {
                        pixelSize: bpmConfig.value >= 100 ? Dims.l(32) : Dims.l(38)
                        family:    "Noto Sans Condensed"
                        weight:    Font.Bold
                    }
                    color: "#ffffff"
                }

                Label {
                    anchors.bottom:           pulseSmall.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin:     Dims.h(6)
                    z: 1
                    //% "Tap"
                    text:    qsTrId("id-tap")
                    visible: page0.lastTap === 0
                    opacity: pulseSmall.opacity * 1.1
                    font {
                        pixelSize: Dims.l(8)
                        weight:    Font.Bold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 2
                    onClicked: {
                        var now = new Date().getTime()

                        if (page0.lastTap > 0 && (now - page0.lastTap) > root.sessionBreakMs) {
                            page0.intervals = []
                            page0.lastTap   = 0
                        }

                        pulseSmallAnim.stop()
                        tapPulse.restart()

                        var beatMs = 60000 / bpmConfig.value

                        if (page0.lastTap > 0) {
                            var delta = now - page0.lastTap
                            page0.intervals.push(delta)
                            if (page0.intervals.length > 8) page0.intervals.shift()
                                var sum = 0
                                for (var j = 0; j < page0.intervals.length; ++j) sum += page0.intervals[j]
                                    var bpm = Math.round(60000 / (sum / page0.intervals.length))
                                    bpm = Math.max(root.bpmMin, Math.min(root.bpmMax, bpm))
                                    bpmConfig.value = bpm
                                    beatMs = 60000 / bpm
                        }

                        page0.lastTap = now
                    }
                }
            }

            // PAGE 1 ── Metronome ─────────────────────────────────────────────
            Item {
                id: page1
                anchors.fill: parent
                visible: index === 1

                // ── Upper-left: pulse visibility toggle ───────────────────────
                Item {
                    anchors.left:                 parent.left
                    anchors.leftMargin:           Dims.w(16)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: -Dims.h(24)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        id: pulseToggleBg
                        anchors.fill: parent
                        radius:  width / 2
                        opacity: page1State.pulseVisible ? 0.7 : 0.2

                        property color beatColor: "#000000"
                        color: beatColor

                        SequentialAnimation {
                            id: pulseToggleBeat
                            ColorAnimation { target: pulseToggleBg; property: "beatColor"; to: root.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                            ColorAnimation { target: pulseToggleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
                        }

                        Connections {
                            target: root
                            function onBeat() {
                                if (page1State.pulseVisible) pulseToggleBeat.restart()
                            }
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12); height: Dims.l(12)
                        name:    page1State.pulseVisible ? "ios-watch-aod-on" : "ios-watch-aod-off"
                        opacity: page1State.pulseVisible ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            page1State.pulseVisible = !page1State.pulseVisible
                            if (!page1State.pulseVisible) {
                                pulseBigAnim.stop()
                                pulseBig.opacity = 0.0
                                pulseToggleBeat.stop()
                                pulseToggleBg.beatColor = "#000000"
                            }
                        }
                    }
                }

                // ── Upper-right: pulse color cycle ────────────────────────────
                Item {
                    anchors.right:                parent.right
                    anchors.rightMargin:          Dims.w(16)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: -Dims.h(24)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        id: colorCycleBg
                        anchors.fill: parent
                        radius:  width / 2
                        opacity: page1State.pulseVisible ? 0.55 : 0.1

                        property color beatColor: "#000000"
                        color: beatColor

                        SequentialAnimation {
                            id: colorCycleBeat
                            ColorAnimation { target: colorCycleBg; property: "beatColor"; to: root.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                            ColorAnimation { target: colorCycleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
                        }

                        Connections {
                            target: root
                            function onBeat() {
                                if (page1State.pulseVisible) colorCycleBeat.restart()
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width:  Dims.l(7); height: Dims.l(7)
                        radius: width / 2
                        color:   root.pulseColor
                        opacity: page1State.pulseVisible ? 0.9 : 0.6
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            colorConfig.value = (colorConfig.value + 1) % root.pulseColors.length
                        }
                    }
                }

                // ── Lower-left: sound toggle ──────────────────────────────────
                Item {
                    anchors.left:                 parent.left
                    anchors.leftMargin:           Dims.w(16)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: Dims.h(24)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        id: soundToggleBg
                        anchors.fill: parent
                        radius:  width / 2
                        opacity: page1State.soundActive ? 0.7 : 0.2

                        property color beatColor: "#000000"
                        color: beatColor

                        SequentialAnimation {
                            id: soundToggleBeat
                            ColorAnimation { target: soundToggleBg; property: "beatColor"; to: root.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                            ColorAnimation { target: soundToggleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
                        }

                        Connections {
                            target: root
                            function onBeat() {
                                if (page1State.soundActive) soundToggleBeat.restart()
                            }
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12); height: Dims.l(12)
                        name:    "ios-musical-note"
                        opacity: page1State.soundActive ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            page1State.soundActive = !page1State.soundActive
                            if (!page1State.soundActive) {
                                soundToggleBeat.stop()
                                soundToggleBg.beatColor = "#000000"
                            }
                        }
                    }
                }

                // ── Lower-right: haptic toggle ────────────────────────────────
                Item {
                    anchors.right:                parent.right
                    anchors.rightMargin:          Dims.w(16)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: Dims.h(24)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        id: hapticToggleBg
                        anchors.fill: parent
                        radius:  width / 2
                        opacity: page1State.hapticActive ? 0.7 : 0.2

                        property color beatColor: "#000000"
                        color: beatColor

                        SequentialAnimation {
                            id: hapticToggleBeat
                            ColorAnimation { target: hapticToggleBg; property: "beatColor"; to: root.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                            ColorAnimation { target: hapticToggleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
                        }

                        Connections {
                            target: root
                            function onBeat() {
                                if (page1State.hapticActive) hapticToggleBeat.restart()
                            }
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12); height: Dims.l(12)
                        name:    "ios-watch-vibrating"
                        opacity: page1State.hapticActive ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            page1State.hapticActive = !page1State.hapticActive
                            if (!page1State.hapticActive) {
                                hapticToggleBeat.stop()
                                hapticToggleBg.beatColor = "#000000"
                            }
                        }
                    }
                }

                // ── Full-screen pulse circle ──────────────────────────────────
                Rectangle {
                    id: pulseBig
                    anchors.centerIn: parent
                    width:   Dims.l(100)
                    height:  width
                    radius:  width / 2
                    color:   root.pulseColor
                    opacity: 0.0
                    z: pulseBigAnim.running ? 11 : 0

                    SequentialAnimation {
                        id: pulseBigAnim
                        NumberAnimation { target: pulseBig; property: "opacity"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseBig; property: "opacity"; to: 0.0; duration: 140; easing.type: Easing.InQuad }
                    }

                    Connections {
                        target: root
                        function onBeat() {
                            if (page1State.pulseVisible) pulseBigAnim.restart()
                        }
                    }
                }

                // ── BPM CircularSpinner ───────────────────────────────────────
                CircularSpinner {
                    id: bpmSpinner
                    anchors.centerIn: parent
                    width:  Dims.w(40)
                    height: Dims.h(60)
                    z: 1
                    model: root.bpmModelCount
                    currentIndex: {
                        var idx = bpmConfig.value - root.bpmMin
                        return (idx >= 0 && idx < root.bpmModelCount) ? idx : 80
                    }
                    delegate: SpinnerDelegate {
                        text: root.bpmModel[index]
                    }
                }

                Connections {
                    target: bpmSpinner
                    function onCurrentIndexChanged() {
                        var v = root.bpmModel[bpmSpinner.currentIndex]
                        if (v !== undefined) {
                            page1State.pendingBpm = v
                            spinnerDebounce.restart()
                        }
                    }
                }
            }

            // PAGE 2 ── Tuning Fork ───────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: index === 2

                SoundEffect {
                    id: tone
                    volume: 1.0
                }

                // Cuts the single-play preview after 1 s
                Timer {
                    id: singlePlayStop
                    interval: 1000
                    repeat:   false
                    onTriggered: {
                        tone.stop()
                        // 1s preview never sets loopActive, nothing to clear
                    }
                }

                // Upper half: frequency name + value, tap to advance carousel
                Item {
                    anchors.top:       parent.top
                    anchors.left:      parent.left
                    anchors.right:     parent.right
                    anchors.topMargin: Dims.h(18)
                    height: parent.height * 0.5 - Dims.h(20)

                    Label {
                        id: freqNameLabel
                        anchors.bottom:           freqLabel.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin:     Dims.h(-2)
                        text: {
                            var idx = root.freqModel.indexOf(freqConfig.value)
                            return idx >= 0 ? root.freqNames[idx] : ""
                        }
                        font.pixelSize: Dims.l(6)
                        opacity: 0.6
                    }

                    Label {
                        id: freqLabel
                        anchors.centerIn: parent
                        //% "Hz"
                        text:           freqConfig.value + " " + qsTrId("id-hz")
                        font.pixelSize: Dims.l(12)
                        opacity: 1.0

                        // Pulses while loop is locked — upper-half feedback
                        // when finger covers the play button
                        SequentialAnimation {
                            id: loopIndicator
                            running:  page2State.loopActive
                            loops:    Animation.Infinite
                            NumberAnimation { target: freqLabel; property: "opacity"; to: 0.5; duration: 400; easing.type: Easing.InOutSine }
                            NumberAnimation { target: freqLabel; property: "opacity"; to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                            onRunningChanged: if (!running) freqLabel.opacity = 1.0
                        }
                    }

                    Label {
                        anchors.top:              freqLabel.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin:        Dims.h(-2)
                        //% "Tap to change"
                        text:           qsTrId("id-tap-to-change")
                        font.pixelSize: Dims.l(6)
                        opacity: 0.6
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            singlePlayStop.stop()
                            tone.stop()
                            page2State.loopActive = false
                            var idx = root.freqModel.indexOf(freqConfig.value)
                            freqConfig.value = root.freqModel[(idx + 1) % root.freqModel.length]
                            tone.source = "file:///usr/share/sounds/" + freqConfig.value + "hz.wav"
                        }
                    }
                }

                // Lower half: play button
                // tap  → 1 s preview (tap again to stop early)
                // hold → lock infinite loop (tap to stop)
                Item {
                    anchors.bottom:       parent.bottom
                    anchors.left:         parent.left
                    anchors.right:        parent.right
                    anchors.bottomMargin: Dims.h(14)
                    height: parent.height * 0.5 - Dims.h(10)

                    Item {
                        id: forkButton
                        anchors.centerIn: parent
                        width:  Dims.l(30)
                        height: Dims.l(30)

                        Rectangle {
                            id: forkBg
                            anchors.fill: parent
                            radius:  width / 2
                            color:   tone.playing ? root.pulseColor : "#000000"
                            opacity: 0.7

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            SequentialAnimation {
                                id: idleBreath
                                running:  !tone.playing
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
                        }

                        MouseArea {
                            anchors.fill: parent
                            property bool holdActive: false

                            onClicked: {
                                if (holdActive) {
                                    holdActive = false
                                    return
                                }
                                if (tone.playing) {
                                    singlePlayStop.stop()
                                    tone.stop()
                                    page2State.loopActive = false
                                } else {
                                    // 1 s preview — does not keep screen awake
                                    tone.loops = 1
                                    tone.play()
                                    playingPulse.restart()
                                    singlePlayStop.restart()
                                }
                            }

                            onPressAndHold: {
                                holdActive = true
                                singlePlayStop.stop()
                                tone.loops = SoundEffect.Infinite
                                if (!tone.playing) tone.play()
                                    page2State.loopActive = true
                                    playingPulse.restart()
                            }

                            // Release does NOT stop the loop — next tap does.
                            onReleased: {
                                if (holdActive) holdActive = false
                            }
                        }
                    }

                    Label {
                        anchors.top:              forkButton.bottom
                        anchors.horizontalCenter: forkButton.horizontalCenter
                        anchors.topMargin:        Dims.h(1)
                        //% "Tap to stop"
                        text:           tone.playing ? qsTrId("id-tap-to-stop") : qsTrId("id-hold-to-loop")
                        font.pixelSize: Dims.l(6)
                        opacity: 0.6
                    }
                }

                Component.onCompleted: {
                    tone.source = "file:///usr/share/sounds/" + freqConfig.value + "hz.wav"
                }
            }
        }
    }

    PageHeader {
        text: root.pageTitles[pageView.currentIndex]
    }

    PageDot {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     Dims.h(4)
        height:       Dims.h(3)
        dotNumber:    3
        currentIndex: pageView.currentIndex
    }
}
