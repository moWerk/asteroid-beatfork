/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 */

import QtQuick 2.9
import org.asteroid.controls 1.0
import org.asteroid.utils 1.0

Item {
    id: page

    // ── Interface — primitives only ───────────────────────────────────────────
    property int    bpmValue:     120
    property int    bpmMin:       40
    property int    bpmMax:       208
    property int    bpmModelCount: 169
    property var    bpmModel:     []
    property int    colorIndex:   0
    property string pulseColor:   "#00ff00"
    property var    pulseColors:  []
    property bool   pulseVisible: false
    property bool   soundActive:  false
    property bool   hapticActive: false
    property var    beatSource

    property bool   pageActive: false

    // Write-back signals
    signal pulseVisibleSet(bool active)
    signal soundActiveSet(bool active)
    signal hapticActiveSet(bool active)
    signal colorIndexSet(int idx)
    signal bpmPending(int bpm)          // main restarts spinnerDebounce and sets pendingBpm

    // ── Settle guard ──────────────────────────────────────────────────────────
    property bool settled: false

    onPageActiveChanged: {
        if (pageActive) {
            settleTimer.restart()
            indicatorLeft.animate()
            if (indicatorRight.visible) indicatorRight.animate()
        } else {
            settleTimer.stop()
            settled = false
            pulseBigAnim.stop()
            pulseBig.opacity = 0.0
            pulseToggleBeat.stop();  pulseToggleBg.beatColor  = "#000000"
            colorCycleBeat.stop();   colorCycleBg.beatColor   = "#000000"
            soundToggleBeat.stop();  soundToggleBg.beatColor  = "#000000"
            hapticToggleBeat.stop(); hapticToggleBg.beatColor = "#000000"
        }
    }

    Timer {
        id: settleTimer
        interval: 800
        repeat:   false
        onTriggered: page.settled = true
    }

    // ── Edge indicators ───────────────────────────────────────────────────────
    Indicator { id: indicatorLeft;  edge: Qt.LeftEdge  }
    Indicator { id: indicatorRight; edge: Qt.RightEdge; visible: DeviceSpecs.hasSpeaker }

    // ── Upper-left: pulse visibility toggle ───────────────────────────────────
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
            opacity: page.pulseVisible ? 0.7 : 0.2

            property color beatColor: "#000000"
            color: beatColor

            SequentialAnimation {
                id: pulseToggleBeat
                ColorAnimation { target: pulseToggleBg; property: "beatColor"; to: page.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                ColorAnimation { target: pulseToggleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
            }

            Connections {
                target: page.beatSource
                function onBeat() {
                    if (page.settled && page.pulseVisible) pulseToggleBeat.restart()
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            width: Dims.l(12); height: Dims.l(12)
            name:    page.pulseVisible ? "ios-watch-aod-on" : "ios-watch-aod-off"
            opacity: page.pulseVisible ? 1.0 : 0.7
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                var next = !page.pulseVisible
                page.pulseVisibleSet(next)
                if (!next) {
                    pulseBigAnim.stop()
                    pulseBig.opacity = 0.0
                    pulseToggleBeat.stop()
                    pulseToggleBg.beatColor = "#000000"
                }
            }
        }
    }

    // ── Upper-right: pulse color cycle ────────────────────────────────────────
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
            opacity: page.pulseVisible ? 0.55 : 0.1

            property color beatColor: "#000000"
            color: beatColor

            SequentialAnimation {
                id: colorCycleBeat
                ColorAnimation { target: colorCycleBg; property: "beatColor"; to: page.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                ColorAnimation { target: colorCycleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
            }

            Connections {
                target: page.beatSource
                function onBeat() {
                    if (page.settled && page.pulseVisible) colorCycleBeat.restart()
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width:  Dims.l(7); height: Dims.l(7)
            radius: width / 2
            color:   page.pulseColor
            opacity: page.pulseVisible ? 0.9 : 0.6
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                page.colorIndexSet((page.colorIndex + 1) % page.pulseColors.length)
            }
        }
    }

    // ── Lower-left: sound toggle ──────────────────────────────────────────────
    Item {
        anchors.left:                 parent.left
        anchors.leftMargin:           Dims.w(16)
        anchors.verticalCenter:       parent.verticalCenter
        anchors.verticalCenterOffset: Dims.h(24)
        width: Dims.l(20); height: Dims.l(20)
        visible: DeviceSpecs.hasSpeaker
        z: 2

        Rectangle {
            id: soundToggleBg
            anchors.fill: parent
            radius:  width / 2
            opacity: page.soundActive ? 0.7 : 0.2

            property color beatColor: "#000000"
            color: beatColor

            SequentialAnimation {
                id: soundToggleBeat
                ColorAnimation { target: soundToggleBg; property: "beatColor"; to: page.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                ColorAnimation { target: soundToggleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
            }

            Connections {
                target: page.beatSource
                function onBeat() {
                    if (page.settled && page.soundActive) soundToggleBeat.restart()
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            width: Dims.l(12); height: Dims.l(12)
            name:    "ios-musical-note"
            opacity: page.soundActive ? 1.0 : 0.7
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                var next = !page.soundActive
                page.soundActiveSet(next)
                if (!next) {
                    soundToggleBeat.stop()
                    soundToggleBg.beatColor = "#000000"
                }
            }
        }
    }

    // ── Lower-right: haptic toggle ────────────────────────────────────────────
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
            opacity: page.hapticActive ? 0.7 : 0.2

            property color beatColor: "#000000"
            color: beatColor

            SequentialAnimation {
                id: hapticToggleBeat
                ColorAnimation { target: hapticToggleBg; property: "beatColor"; to: page.pulseColor; duration: 150; easing.type: Easing.OutQuad }
                ColorAnimation { target: hapticToggleBg; property: "beatColor"; to: "#000000";       duration: 350; easing.type: Easing.InQuad  }
            }

            Connections {
                target: page.beatSource
                function onBeat() {
                    if (page.settled && page.hapticActive) hapticToggleBeat.restart()
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            width: Dims.l(12); height: Dims.l(12)
            name:    "ios-watch-vibrating"
            opacity: page.hapticActive ? 1.0 : 0.7
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                var next = !page.hapticActive
                page.hapticActiveSet(next)
                if (!next) {
                    hapticToggleBeat.stop()
                    hapticToggleBg.beatColor = "#000000"
                }
            }
        }
    }

    // ── Full-screen pulse circle ──────────────────────────────────────────────
    Rectangle {
        id: pulseBig
        anchors.centerIn: parent
        width:   Dims.l(100)
        height:  width
        radius:  width / 2
        color:   page.pulseColor
        opacity: 0.0
        z: pulseBigAnim.running ? 11 : 0

        SequentialAnimation {
            id: pulseBigAnim
            NumberAnimation { target: pulseBig; property: "opacity"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
            NumberAnimation { target: pulseBig; property: "opacity"; to: 0.0; duration: 140; easing.type: Easing.InQuad }
        }

        Connections {
            target: page.beatSource
            function onBeat() {
                if (page.settled && page.pulseVisible) pulseBigAnim.restart()
            }
        }
    }

    // ── BPM CircularSpinner ───────────────────────────────────────────────────
    CircularSpinner {
        id: bpmSpinner
        anchors.centerIn: parent
        width:  Dims.w(40)
        height: Dims.h(60)
        z: 1
        model: page.bpmModelCount
        currentIndex: {
            var idx = page.bpmValue - page.bpmMin
            return (idx >= 0 && idx < page.bpmModelCount) ? idx : 80
        }
        delegate: SpinnerDelegate {
            text: page.bpmModel[index]
        }
    }

    Connections {
        target: bpmSpinner
        function onCurrentIndexChanged() {
            var v = page.bpmModel[bpmSpinner.currentIndex]
            if (v !== undefined) page.bpmPending(v)
        }
    }
}
