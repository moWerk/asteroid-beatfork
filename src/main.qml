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
import org.asteroid.controls 1.0
import org.asteroid.utils 1.0

Application {
    id: root

    anchors.fill: parent

    centerColor: "#119DA4"
    outerColor:  "#090B0C"

    // ── Persisted config ──────────────────────────────────────────────────────
    ConfigurationValue { id: bpmConfig;   key: "/asteroid/apps/beatfork/bpm";        defaultValue: 120 }
    ConfigurationValue { id: freqConfig;  key: "/asteroid/apps/beatfork/freq";       defaultValue: 440 }
    ConfigurationValue { id: colorConfig; key: "/asteroid/apps/beatfork/colorIndex"; defaultValue: 0   }

    // ── BPM / model constants ─────────────────────────────────────────────────
    readonly property int bpmMin:         40
    readonly property int bpmMax:         208
    readonly property int bpmModelCount:  bpmMax - bpmMin + 1  // 169
    readonly property int flashDuration:  200
    readonly property int sessionBreakMs: 1500  // one beat at 40 BPM

    property var bpmModel: {
        var arr = []
        for (var i = root.bpmMin; i <= root.bpmMax; ++i) arr.push(i)
            return arr
    }

    property var freqModel: [392, 415, 432, 440, 442, 444, 452]

    readonly property var pulseColors: [
        "#FF69B4", "#C5FCE4", "#FF4B0A",
        "#FFEC1F", "#0ABAFF", "#98D831"
    ]

    // All pages bind to this — updates reactively when colorConfig changes.
    readonly property string pulseColor: pulseColors[colorConfig.value]

    readonly property var pageTitles: [
        //% "Detect BPM"
        qsTrId("id-detect-bpm"),
        //% "Metronome"
        qsTrId("id-metronome"),
        //% "Tuning Fork"
        qsTrId("id-tuning-fork")
    ]

    // ── Page 1 state — lives at root to survive delegate recycling ────────────
    QtObject {
        id: page1State
        property bool soundActive:  false
        property bool hapticActive: false
        property bool pulseVisible: true
        property int  pendingBpm:   -1
    }

    // ── Audio / haptics — root-level, always loaded ───────────────────────────
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
    // Single source of truth for the beat. Survives page navigation.
    // All visual and audio subscribers are driven from beatFlash().
    Timer {
        id: beatTimer
        interval:         Math.round(60000 / bpmConfig.value)
        repeat:           true
        running:          true
        triggeredOnStart: false
        onTriggered:      root.beatFlash()
    }

    // Restart with correct interval whenever BPM changes.
    Connections {
        target: bpmConfig
        function onValueChanged() {
            beatTimer.interval = Math.round(60000 / bpmConfig.value)
            beatTimer.restart()
        }
    }

    // ── Spinner debounce — root-level, shared ─────────────────────────────────
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
    // Each subscriber checks its own guard. Adding new indicators is additive.
    // Animations live inside delegates and cannot be called from root scope
    // directly — they may not exist if the delegate isn't instantiated.
    // Emit a signal instead; each delegate subscribes locally.
    signal beat()

    function beatFlash() {
        root.beat()
        if (page1State.soundActive)  tickSound.play()
            if (page1State.hapticActive) hapticFeedback.play()
    }

    // ─────────────────────────────────────────────────────────────────────────
    ListView {
        id: pageView
        anchors.fill: parent
        orientation:        ListView.Horizontal
        snapMode:           ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
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
                    color:   root.pulseColor   // reactive to colorConfig
                    opacity: 0.1
                    z: 0

                    // Tap flash — immediate user feedback on each tap
                    SequentialAnimation {
                        id: tapPulse
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.7; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.1; duration: 140; easing.type: Easing.InQuad }
                    }

                    // Beat flash — driven by root.beat() signal
                    SequentialAnimation {
                        id: pulseSmallAnim
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.7; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.1; duration: 140; easing.type: Easing.InQuad }
                    }

                    Connections {
                        target: root
                        function onBeat() { pulseSmallAnim.restart() }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    z: 1
                    text:           bpmConfig.value
                    font {
                        pixelSize: Dims.l(38)
                        family:    "Noto Sans Condensed"
                        weight:    Font.Bold
                    }
                    color: "#ffffff"
                }

                // "Tap" hint — disappears after first tap
                Label {
                    anchors.bottom:           pulseSmall.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin:     Dims.h(4)
                    z: 1
                    //% "Tap"
                    text:    qsTrId("id-tap")
                    opacity: pulseSmall.opacity
                    visible: page0.lastTap === 0
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

                        // Tap feedback — stop beat flash so they don't fight
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

                // ── Upper-left: pulse visibility toggle
                Item {
                    anchors.left:                 parent.left
                    anchors.leftMargin:           Dims.w(12)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: -Dims.h(25)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius:  width / 2
                        color:   "#000000"
                        opacity: page1State.pulseVisible ? 0.7 : 0.2
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
                                pulseBig.opacity = 0.1
                            }
                        }
                    }
                }

                // ── Upper-right: pulse color cycle
                Item {
                    anchors.right:                parent.right
                    anchors.rightMargin:          Dims.w(12)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: -Dims.h(25)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius:  width / 2
                        color:   "#000000"
                        opacity: page1State.pulseVisible ? 0.7 : 0.2
                    }

                    // Small colored dot shows current active color
                    Rectangle {
                        anchors.centerIn: parent
                        width:  Dims.l(7); height: Dims.l(7)
                        radius: width / 2
                        color:   root.pulseColor
                        opacity: page1State.pulseVisible ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            colorConfig.value = (colorConfig.value + 1) % root.pulseColors.length
                        }
                    }
                }

                // ── Lower-left: sound toggle
                Item {
                    anchors.left:                 parent.left
                    anchors.leftMargin:           Dims.w(12)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: Dims.h(25)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius:  width / 2
                        color:   "#000000"
                        opacity: page1State.soundActive ? 0.7 : 0.2
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12); height: Dims.l(12)
                        name:    "ios-musical-note"
                        opacity: page1State.soundActive ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page1State.soundActive = !page1State.soundActive
                    }
                }

                // ── Lower-right: haptic toggle
                Item {
                    anchors.right:                parent.right
                    anchors.rightMargin:          Dims.w(12)
                    anchors.verticalCenter:       parent.verticalCenter
                    anchors.verticalCenterOffset: Dims.h(25)
                    width: Dims.l(20); height: Dims.l(20)
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius:  width / 2
                        color:   "#000000"
                        opacity: page1State.hapticActive ? 0.7 : 0.2
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12); height: Dims.l(12)
                        name:    "ios-watch-vibrating"
                        opacity: page1State.hapticActive ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page1State.hapticActive = !page1State.hapticActive
                    }
                }

                // ── Full-screen pulse circle
                Rectangle {
                    id: pulseBig
                    anchors.centerIn: parent
                    width:   Dims.l(100)
                    height:  width
                    radius:  width / 2
                    color:   root.pulseColor   // reactive to colorConfig
                    opacity: 0.1
                    z: pulseBigAnim.running ? 11 : 0

                    // Beat flash — driven by root.beat() signal when pulseVisible
                    SequentialAnimation {
                        id: pulseBigAnim
                        NumberAnimation { target: pulseBig; property: "opacity"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseBig; property: "opacity"; to: 0.1; duration: 140; easing.type: Easing.InQuad }
                    }

                    Connections {
                        target: root
                        function onBeat() {
                            if (page1State.pulseVisible) pulseBigAnim.restart()
                        }
                    }
                }

                // ── BPM CircularSpinner
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

                SoundEffect { id: tone; volume: 1.0 }

                Timer {
                    id: toneLoop
                    interval: 3000
                    repeat:   true
                    onTriggered: tone.play()
                }

                // Upper half: frequency display, tap to advance carousel.
                Item {
                    anchors.top:       parent.top
                    anchors.left:      parent.left
                    anchors.right:     parent.right
                    anchors.topMargin: Dims.h(16)
                    height: parent.height * 0.5 - Dims.h(20)

                    Label {
                        id: freqLabel
                        anchors.centerIn: parent
                        //% "Hz"
                        text:           freqConfig.value + " " + qsTrId("id-hz")
                        font.pixelSize: Dims.l(14)
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
                            var idx = root.freqModel.indexOf(freqConfig.value)
                            freqConfig.value = root.freqModel[(idx + 1) % root.freqModel.length]
                            tone.source = "file:///usr/share/sounds/" + freqConfig.value + "hz.wav"
                        }
                    }
                }

                // Lower half: fork icon, tap to play / hold to loop.
                Item {
                    anchors.bottom:       parent.bottom
                    anchors.left:         parent.left
                    anchors.right:        parent.right
                    anchors.bottomMargin: Dims.h(16)
                    height: parent.height * 0.5 - Dims.h(10)

                    Icon {
                        id: forkLabel
                        anchors.centerIn: parent
                        width: Dims.l(24); height: Dims.l(24)
                        name: "ios-musical-note"
                    }

                    Label {
                        anchors.top:              forkLabel.bottom
                        anchors.horizontalCenter: forkLabel.horizontalCenter
                        //% "Hold to loop"
                        text:           qsTrId("id-hold-to-loop")
                        font.pixelSize: Dims.l(6)
                        opacity: 0.6
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: tone.play()
                        onPressAndHold: {
                            tone.play()
                            toneLoop.start()
                        }
                        onReleased: toneLoop.stop()
                    }
                }

                Component.onCompleted: tone.source = "file:///usr/share/sounds/" + freqConfig.value + "hz.wav"
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
