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
    property int    bpmValue:       120
    property int    bpmMin:         40
    property int    bpmMax:         208
    property int    sessionBreakMs: 1500
    property string pulseColor:     "#00ff00"
    property string tapDotColor:    "#ff69b4"   // pulseColors[colorIndex+1] from main
    property var    beatSource

    signal bpmValueSet(int bpm)

    // ── State ─────────────────────────────────────────────────────────────────
    property bool settled:   false
    property real lastTap:   0
    property var  intervals: []
    property int  tapCount:  0

    readonly property real ringRadius: Dims.l(35)
    readonly property real borderCenter:      ringRadius - Dims.l(0.5)
    readonly property real driftExtent:   ringRadius * 0.50
    readonly property real entryAngle:   -45.0
    readonly property real exitAngle:    -405.0
    readonly property int  fullRevMs:    Math.round(8.6 * (60000 / bpmValue))

    property bool pageActive: false
    onPageActiveChanged: {
        if (pageActive) {
            settleTimer.restart()
            indicatorRight.animate()
        } else {
            settleTimer.stop()
            settled   = false
            lastTap   = 0
            intervals = []
            pulseSmallAnim.stop()
            pulseSmall.opacity = 0.0
            for (var i = dotContainer.children.length - 1; i >= 0; i--)
                dotContainer.children[i].destroy()
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

    // ── Dot component ─────────────────────────────────────────────────────────
    Component {
        id: dotComponent
        Item {
            id: dot
            property real  drift:    0.0
            property bool  isTap:    false
            property color dotColor: isTap ? page.tapDotColor : page.pulseColor
            z: isTap ? 2 : 1
            parent: dotContainer

            readonly property real r: page.borderCenter + drift * page.driftExtent

            property real angle: page.entryAngle
            x: Math.sin(angle * Math.PI / 180) * r
            y: -Math.cos(angle * Math.PI / 180) * r

            Rectangle {
                id: dotRect
                anchors.centerIn: parent
                width:   dot.isTap ? Dims.l(6) : Dims.l(5)
                height:  width
                radius:  width / 2
                color:   dot.dotColor
                opacity: 0.7
            }

            // Travel counter-clockwise one full revolution
            NumberAnimation on angle {
                id: angleAnim
                from:        page.entryAngle
                to:          page.exitAngle
                duration:    page.fullRevMs
                running:     true
                easing.type: Easing.Linear
                onRunningChanged: if (!running) dot.destroy()
            }

            // Fade over second half, gone well before re-entering entry zone
            SequentialAnimation {
                running: true
                PauseAnimation   { duration: page.fullRevMs * 0.65 }
                NumberAnimation  {
                    target:   dotRect
                    property: "opacity"
                    to:       0.0
                    duration: page.fullRevMs * 0.20
                    easing.type: Easing.InQuad
                }
            }
        }
    }

    // ── Beat circle — reference ring + pump ───────────────────────────────────
    Rectangle {
        id: pulseSmall
        anchors.centerIn: parent
        width:   page.ringRadius * 2
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(1)
        opacity: 0.0
        z: 0

        SequentialAnimation {
            id: pulseSmallAnim
            NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.6; duration: 10;  easing.type: Easing.Linear }
            NumberAnimation { target: pulseSmall; property: "opacity"; to: 0.0; duration: 170; easing.type: Easing.InQuad }
        }

        Connections {
            target: page.beatSource
            function onBeat() {
                if (!page.settled) return
                    pulseSmallAnim.restart()
                    dotComponent.createObject(dotContainer, {drift: 0.0, isTap: false})
            }
        }
    }

    // ── Dot container ─────────────────────────────────────────────────────────
    Item {
        id: dotContainer
        anchors.centerIn: parent
        width:  0
        height: 0
        z: 1
    }

    // ── Ripple rings on tap ───────────────────────────────────────────────────
    Rectangle {
        id: ripple1
        anchors.centerIn: parent
        width:   Dims.l(70)
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(3)
        opacity: 0.0
        scale:   0.3
        z: 2

        ParallelAnimation {
            id: ripple1Anim
            NumberAnimation { target: ripple1; property: "scale";   from: 0.4; to: 0.8; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { target: ripple1; property: "opacity"; from: 0.6; to: 0.0; duration: 300; easing.type: Easing.InQuad  }
        }

        Connections {
            target: page
            function onTapCountChanged() { ripple1Anim.restart() }
        }
    }

    Rectangle {
        id: ripple2
        anchors.centerIn: parent
        width:   Dims.l(70)
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(2)
        opacity: 0.0
        scale:   0.3
        z: 2

        SequentialAnimation {
            id: ripple2Anim
            PauseAnimation { duration: 80 }
            ParallelAnimation {
                NumberAnimation { target: ripple2; property: "scale";   from: 0.4; to: 0.7; duration: 250; easing.type: Easing.OutQuad }
                NumberAnimation { target: ripple2; property: "opacity"; from: 0.5; to: 0.0; duration: 250; easing.type: Easing.InQuad  }
            }
        }

        Connections {
            target: page
            function onTapCountChanged() { ripple2Anim.restart() }
        }
    }

    // ── Tap hint ──────────────────────────────────────────────────────────────
    Label {
        anchors.top:              pulseSmall.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin:        Dims.h(7)
        z: 3
        //% "Tap"
        text:    qsTrId("id-tap")
        visible: page.lastTap === 0
        opacity: 0.6
        font {
            pixelSize: Dims.l(9)
            weight:    Font.Bold
        }
    }

    // ── BPM label ─────────────────────────────────────────────────────────────
    Label {
        id: bpmLabel
        anchors.centerIn: parent
        z: 3
        text: page.bpmValue
        font {
            pixelSize: page.bpmValue >= 100 ? Dims.l(32) : Dims.l(36)
            family:    "Noto Sans Condensed"
            weight:    Font.Bold
        }
        color:   "#ffffff"
        opacity: 0.9
        scale:   1.0

        SequentialAnimation {
            id: labelPump
            NumberAnimation { target: bpmLabel; property: "scale"; to: 1.2; duration: 45;  easing.type: Easing.InQuad  }
            NumberAnimation { target: bpmLabel; property: "scale"; to: 1.0; duration: 90;  easing.type: Easing.OutQuad }
        }

        Connections {
            target: page
            function onTapCountChanged() { labelPump.restart() }
        }
    }

    // ── Tempo name ────────────────────────────────────────────────────────────
    Label {
        anchors.bottom:           pulseSmall.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin:     Dims.h(8)
        z: 3
        text: {
            var bpm = page.bpmValue
            if      (bpm < 60)  return "Largo"
                else if (bpm < 66)  return "Larghetto"
                    else if (bpm < 76)  return "Adagio"
                        else if (bpm < 84)  return "Andante"
                            else if (bpm < 96)  return "Andantino"
                                else if (bpm < 108) return "Moderato"
                                    else if (bpm < 120) return "Allegretto"
                                        else if (bpm < 156) return "Allegro"
                                            else if (bpm < 176) return "Vivace"
                                                else if (bpm < 200) return "Presto"
                                                    else                return "Prestissimo"
        }
        font {
            pixelSize: Dims.l(8)
            family:    "Noto Sans Condensed"
        }
        opacity: 0.8
    }

    // ── Tap area ──────────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 4
        onClicked: {
            var now = new Date().getTime()

            if (page.lastTap > 0 && (now - page.lastTap) > page.sessionBreakMs) {
                page.intervals = []
                page.lastTap   = 0
                for (var k = dotContainer.children.length - 1; k >= 0; k--)
                    dotContainer.children[k].destroy()
            }

            page.tapCount++

            if (page.lastTap > 0) {
                var delta = now - page.lastTap
                page.intervals.push(delta)
                if (page.intervals.length > 8) page.intervals.shift()
                    var sum = 0
                    for (var j = 0; j < page.intervals.length; ++j) sum += page.intervals[j]
                        var bpm = Math.round(60000 / (sum / page.intervals.length))
                        bpm = Math.max(page.bpmMin, Math.min(page.bpmMax, bpm))
                        page.bpmValueSet(bpm)

                        var expected = 60000.0 / bpm
                        var drift    = Math.max(-1.0, Math.min(1.0,
                                                               (delta - expected) / (expected * 0.75)))
                        dotComponent.createObject(dotContainer, {drift: drift, isTap: true})
            }

            page.lastTap = now
        }
    }
}
