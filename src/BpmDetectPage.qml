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

    // ── Interface — primitives only, no object references ─────────────────────
    property int    bpmValue:      120
    property int    bpmMin:        40
    property int    bpmMax:        208
    property int    sessionBreakMs: 1500
    property string pulseColor:    "#00ff00"
    property var    beatSource          // root item ref — only used as Connections target

    signal bpmValueSet(int bpm)         // write-back to bpmConfig.value in main

    // ── Settle guard ──────────────────────────────────────────────────────────
    property bool settled:   false
    property real lastTap:   0
    property var  intervals: []
    property int  tapCount:  0

    property bool pageActive: false
    onPageActiveChanged: {
        if (pageActive) {
            settleTimer.restart()
            indicatorRight.animate()
        } else {
            settleTimer.stop()
            settled = false
            pulseSmallAnim.stop()
            pulseSmall.opacity = 0.0
        }
    }

    Timer {
        id: settleTimer
        interval: 800
        repeat:   false
        onTriggered: page.settled = true
    }

    // ── Edge indicator ────────────────────────────────────────────────────────
    Indicator { id: indicatorRight; edge: Qt.RightEdge }

    // ── Beat circle ───────────────────────────────────────────────────────────
    Rectangle {
        id: pulseSmall
        anchors.centerIn: parent
        width:   Dims.l(66)
        height:  width
        radius:  width / 2
        color:   page.pulseColor
        opacity: 0.0
        z: 0

        SequentialAnimation {
            id: pulseSmallAnim
            NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.7; duration: 60;  easing.type: Easing.OutQuad }
            NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.0; duration: 140; easing.type: Easing.InQuad }
        }

        Connections {
            target: page.beatSource
            function onBeat() {
                if (page.settled) pulseSmallAnim.restart()
            }
        }
    }

    // ── Ripple rings ──────────────────────────────────────────────────────────
    Rectangle {
        id: ripple1
        anchors.centerIn: parent
        width:   pulseSmall.width
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(0.8)
        opacity: 0.0
        scale:   1.0
        z: 1

        ParallelAnimation {
            id: ripple1Anim
            NumberAnimation { target: ripple1; property: "scale";   from: 1.0; to: 1.7; duration: 500; easing.type: Easing.OutQuad }
            NumberAnimation { target: ripple1; property: "opacity"; from: 0.6; to: 0.0; duration: 500; easing.type: Easing.InQuad  }
        }

        Connections {
            target: page
            function onTapCountChanged() { ripple1Anim.restart() }
        }
    }

    Rectangle {
        id: ripple2
        anchors.centerIn: parent
        width:   pulseSmall.width
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(0.5)
        opacity: 0.0
        scale:   1.0
        z: 1

        SequentialAnimation {
            id: ripple2Anim
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                NumberAnimation { target: ripple2; property: "scale";   from: 1.0; to: 1.55; duration: 450; easing.type: Easing.OutQuad }
                NumberAnimation { target: ripple2; property: "opacity"; from: 0.4; to: 0.0;  duration: 450; easing.type: Easing.InQuad  }
            }
        }

        Connections {
            target: page
            function onTapCountChanged() { ripple2Anim.restart() }
        }
    }

    // ── Sparkle dots ──────────────────────────────────────────────────────────
    Repeater {
        model: 6
        z: 1

        Item {
            anchors.centerIn: parent
            rotation: index * 60

            property real dotX:      Dims.l(33)
            property real dotOpacity: 0.0

            Rectangle {
                width:  Dims.l(2.2)
                height: Dims.l(2.2)
                radius: width / 2
                color:  page.pulseColor
                x: parent.dotX
                y: -height / 2
                opacity: parent.dotOpacity
            }

            SequentialAnimation {
                id: sparkAnim
                ParallelAnimation {
                    NumberAnimation {
                        property: "dotX"
                        from: Dims.l(33); to: Dims.l(54)
                        duration: 480; easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        NumberAnimation { property: "dotOpacity"; to: 0.95; duration: 60  }
                        NumberAnimation { property: "dotOpacity"; to: 0.0;  duration: 420; easing.type: Easing.InQuad }
                    }
                }
            }

            Connections {
                target: page
                function onTapCountChanged() { sparkAnim.restart() }
            }
        }
    }

    // ── BPM label ─────────────────────────────────────────────────────────────
    Label {
        id: bpmLabel
        anchors.centerIn: parent
        z: 2
        text: page.bpmValue
        font {
            pixelSize: page.bpmValue >= 100 ? Dims.l(32) : Dims.l(38)
            family:    "Noto Sans Condensed"
            weight:    Font.Bold
        }
        color:   "#ffffff"
        opacity: 0.6

        SequentialAnimation {
            id: labelPump
            NumberAnimation { target: bpmLabel; property: "opacity"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
            NumberAnimation { target: bpmLabel; property: "opacity"; to: 0.6; duration: 600; easing.type: Easing.InQuad }
        }

        Connections {
            target: page
            function onTapCountChanged() { labelPump.restart() }
        }
    }

    Label {
        anchors.bottom:           pulseSmall.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin:     Dims.h(6)
        z: 2
        //% "Tap"
        text:    qsTrId("id-tap")
        visible: page.lastTap === 0
        opacity: 0.7
        font {
            pixelSize: Dims.l(8)
            weight:    Font.Bold
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 3
        onClicked: {
            var now = new Date().getTime()

            if (page.lastTap > 0 && (now - page.lastTap) > page.sessionBreakMs) {
                page.intervals = []
                page.lastTap   = 0
            }

            page.tapCount++

            var beatMs = 60000 / page.bpmValue

            if (page.lastTap > 0) {
                var delta = now - page.lastTap
                page.intervals.push(delta)
                if (page.intervals.length > 8) page.intervals.shift()
                    var sum = 0
                    for (var j = 0; j < page.intervals.length; ++j) sum += page.intervals[j]
                        var bpm = Math.round(60000 / (sum / page.intervals.length))
                        bpm = Math.max(page.bpmMin, Math.min(page.bpmMax, bpm))
                        page.bpmValueSet(bpm)
                        beatMs = 60000 / bpm
            }

            page.lastTap = now
        }
    }
}
