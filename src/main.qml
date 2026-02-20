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
    outerColor: "#090B0C"

    ConfigurationValue { id: bpmConfig;  key: "/asteroid/apps/beatfork/bpm";  defaultValue: 120 }
    ConfigurationValue { id: freqConfig; key: "/asteroid/apps/beatfork/freq"; defaultValue: 440 }

    property var freqModel: [392, 415, 432, 440, 442, 444, 452]

    property var bpmModel: {
        var arr = []
        for (var i = root.bpmMin; i <= root.bpmMax; ++i) arr.push(i)
            return arr
    }
    readonly property int bpmMin: 40
    readonly property int bpmMax: 208
    readonly property int bpmModelCount: bpmMax - bpmMin + 1  // 169

    readonly property int flashDuration: 200
    readonly property int sessionBreakMs: 1500  // one beat at 40 BPM

    readonly property var pageTitles: ["Detect BPM", "Metronome", "Tuning Fork"]

    ListView {
        id: pageView
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        model: 3

        delegate: Item {
            width: pageView.width
            height: pageView.height

            // PAGE 0 ── BPM Tap + pulsing circle behind BPM display
            Item {
                id: page0
                anchors.fill: parent
                visible: index === 0

                property real lastTap: 0
                property var  intervals: []

                Rectangle {
                    id: pulseSmall
                    anchors.centerIn: parent
                    width: Dims.l(57)
                    height: width
                    radius: width / 2
                    color: "#ff69b4"
                    opacity: 0.1
                    z: 0

                    SequentialAnimation {
                        id: tapPulse
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.1; duration: 140; easing.type: Easing.InQuad }
                    }

                    SequentialAnimation {
                        id: timedPulse
                        running: false
                        loops: Animation.Infinite

                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.1; duration: 140; easing.type: Easing.InQuad }
                        PauseAnimation  { id: pauseSmall; duration: 400 }
                    }

                    function startAuto(beatMs) {
                        timedPulse.stop()
                        pauseSmall.duration = Math.max(0, beatMs - root.flashDuration)
                        timedPulse.restart()
                    }
                }

                Label {
                    anchors.centerIn: parent
                    z: 1
                    text: bpmConfig.value
                    font.pixelSize: Dims.l(36)
                    font.family: "Noto Sans Condensed"
                    font.weight: Font.Bold
                    color: "#ffffff"
                }

                // "Tap" hint — visible only until the user taps once.
                Label {
                    anchors.bottom: pulseSmall.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: Dims.h(3)
                    z: 1
                    text: "Tap"
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
                            page0.lastTap = 0
                        }

                        timedPulse.stop()
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

                        resumeTimer.interval = Math.max(0, beatMs - root.flashDuration)
                        resumeTimer.restart()
                    }
                }

                Timer {
                    id: resumeTimer
                    repeat: false
                    onTriggered: pulseSmall.startAuto(bpmConfig.value > 0 ? 60000 / bpmConfig.value : 500)
                }

                Component.onCompleted: pulseSmall.startAuto(60000 / bpmConfig.value)
            }

            // PAGE 1 ── Full Metronome + BPM CircularSpinner
            Item {
                id: page1
                anchors.fill: parent
                visible: index === 1

                SoundEffect {
                    id: tickSound
                    source: "file:///usr/share/sounds/tick.wav"
                    volume: 1.0
                }

                NonGraphicalFeedback {
                    id: hapticFeedback
                    event: "press"
                }

                property bool soundActive:  false
                property bool hapticActive: false

                // ── Spinner debounce
                property int pendingBpm: -1

                Timer {
                    id: spinnerDebounce
                    interval: 1000
                    repeat: false
                    onTriggered: {
                        if (page1.pendingBpm >= root.bpmMin) {
                            bpmConfig.value = page1.pendingBpm
                            page1.pendingBpm = -1
                        }
                    }
                }

                // ── Full-screen pulse circle
                Rectangle {
                    id: pulseBig
                    anchors.centerIn: parent
                    width: Dims.l(90)
                    height: width
                    radius: width / 2
                    color: "#ff69b4"
                    opacity: 0.1
                    z: 0

                    SequentialAnimation on opacity {
                        id: metroAnim
                        running: false
                        loops: Animation.Infinite

                        ScriptAction {
                            script: {
                                if (page1.soundActive)  tickSound.play()
                                    if (page1.hapticActive) hapticFeedback.play()
                            }
                        }
                        NumberAnimation { to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
                        NumberAnimation { to: 0.1; duration: 140; easing.type: Easing.InQuad }
                        PauseAnimation  { id: pauseBig; duration: 400 }
                    }
                }

                // ── BPM CircularSpinner
                CircularSpinner {
                    id: bpmSpinner
                    anchors.centerIn: parent
                    width: Dims.w(40)
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
                            page1.pendingBpm = v
                            spinnerDebounce.restart()
                        }
                    }
                }

                Connections {
                    target: bpmConfig
                    function onValueChanged() {
                        metroAnim.stop()
                        pauseBig.duration = Math.max(0, 60000 / bpmConfig.value - root.flashDuration)
                        metroAnim.restart()
                    }
                }

                // ── Sound toggle button (left)
                Item {
                    anchors.left: parent.left
                    anchors.leftMargin: Dims.w(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Dims.l(20)
                    height: Dims.l(20)
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#000000"
                        opacity: page1.soundActive ? 0.7 : 0.2
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12)
                        height: Dims.l(12)
                        name: "ios-musical-notes"
                        opacity: page1.soundActive ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page1.soundActive = !page1.soundActive
                    }
                }

                // ── Haptic toggle button (right) ──────────────────────────────
                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: Dims.w(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Dims.l(20)
                    height: Dims.l(20)
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#000000"
                        opacity: page1.hapticActive ? 0.7 : 0.2
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: Dims.l(12)
                        height: Dims.l(12)
                        name: "ios-watch-vibrating"
                        opacity: page1.hapticActive ? 1.0 : 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page1.hapticActive = !page1.hapticActive
                    }
                }

                Component.onCompleted: {
                    pauseBig.duration = Math.max(0, 60000 / bpmConfig.value - root.flashDuration)
                    metroAnim.start()
                }
            }

            // PAGE 2 ── Tuning Fork
            Item {
                anchors.fill: parent
                visible: index === 2

                SoundEffect { id: tone; volume: 1.0 }

                Timer {
                    id: toneLoop
                    interval: 3000
                    repeat: true
                    onTriggered: tone.play()
                }

                // Upper half: frequency display, tap to advance carousel.
                Item {

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: Dims.h(20)
                    height: parent.height * 0.5 - Dims.h(20)

                    Label {
                        id: freqLabel
                        anchors.centerIn: parent
                        text: freqConfig.value + " Hz"
                        font.pixelSize: Dims.l(14)
                    }

                    Label {
                        anchors.top: freqLabel.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: Dims.h(2)
                        text: "Tap to change"
                        font.pixelSize: Dims.l(7)
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

                // Lower half: pitchfork icon, tap to play / hold to loop.
                Item {

                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottomMargin: Dims.h(10)
                    height: parent.height * 0.5 - Dims.h(10)

                    Label {
                        id: forkLabel
                        anchors.centerIn: parent
                        text: "\u2442"
                        font.pixelSize: Dims.l(28)
                    }

                    Label {
                        anchors.top: forkLabel.bottom
                        anchors.horizontalCenter: forkLabel.horizontalCenter
                        anchors.topMargin: Dims.h(2)
                        text: "Hold to loop"
                        font.pixelSize: Dims.l(7)
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
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Dims.h(4)
        height: Dims.h(3)
        dotNumber: 3
        currentIndex: pageView.currentIndex
    }
}
