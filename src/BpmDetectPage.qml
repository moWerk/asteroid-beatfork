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
    property bool   sessionActive: false
    property string pulseColor:     "#00ff00"
    property string tapDotColor:    "#ff69b4"
    property var    beatSource
    property int statsCycleTap: 0
    onStatsCycleTapChanged: {
        if (lastTap > 0) statsIndex = (statsIndex + 1) % statCount
    }
    property int  beatOffset:       0
    property bool beatOffsetLocked: false

    signal beatOffsetDelta(int ms)
    signal beatOffsetLockToggle()
    signal bpmValueSet(int bpm)

    // ── State ─────────────────────────────────────────────────────────────────
    property bool settled:   false
    property real lastTap:   0
    property var  intervals: []
    property int  tapCount:  0
    property int  consecutiveOutliers: 0
    property string turntableState: beatOffsetLocked ? "locked" : "idle"


    // ── Stats — frozen on each tap, persist after tapping stops ───────────────
    property int  statsIndex:    0
    readonly property int statCount: 6
    property real statPreciseBpm:  0.0
    property int  statConsistency: 0
    property int  statDriftMs:     0
    property int  statConfidence:  0
    property int  statSpreadMin:   0
    property int  statSpreadMax:   0
    property int  statMsPerBeat:   0

    function updateStats(delta, bpm) {
        statPreciseBpm  = Math.round(60000.0 / delta * 10) / 10
        statConfidence  = intervals.length
        statMsPerBeat   = Math.round(60000.0 / bpm)
        statDriftMs     = Math.round(delta - (60000.0 / bpm))
        if (intervals.length > 1) {
            var mean = 0
            for (var i = 0; i < intervals.length; i++) mean += intervals[i]
                mean /= intervals.length
                var variance = 0
                for (var j = 0; j < intervals.length; j++)
                    variance += Math.pow(intervals[j] - mean, 2)
                    var stddev = Math.sqrt(variance / intervals.length)
                    statConsistency = Math.max(0, Math.min(100,
                                                           Math.round(100 - (stddev / mean) * 100)))
        } else {
            statConsistency = 0
        }
        if (statSpreadMin === 0 || bpm < statSpreadMin) statSpreadMin = bpm
            if (bpm > statSpreadMax) statSpreadMax = bpm
    }

    function statsText() {
        switch (statsIndex) {
            case 0: return statConsistency + "%"
            case 1: return statPreciseBpm.toFixed(1) + " bpm"
            case 2: return (statDriftMs >= 0 ? "+" : "") + statDriftMs + " ms"
            case 3: return statConfidence + " of 8"
            case 4: return statSpreadMin + "–" + statSpreadMax
            case 5: return statMsPerBeat + " ms/beat"
            default: return ""
        }
    }

    function statusOrStats() {
        if (beatOffsetLocked)             return "locked"
            if (turntableState === "braking") return "braking"
                if (turntableState === "pushing") return "pushing"
                    return statsText()
    }

    // ── Ring geometry ─────────────────────────────────────────────────────────
    readonly property real ringRadius:   Dims.l(35)
    readonly property real borderCenter: ringRadius - Dims.l(0.5)
    readonly property real driftExtent:  ringRadius * 0.50
    readonly property real entryAngle:  -45.0
    readonly property real exitAngle:   -405.0
    readonly property int  fullRevMs:   Math.round(8.6 * (60000 / bpmValue))

    property bool pageActive: false
    onPageActiveChanged: {
        if (pageActive) {
            settleTimer.restart()
            indicatorRight.animate()
        } else {
            consecutiveOutliers = 0
            sessionActive = false
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

    // Auto-reset braking/pushing label back to stats after brief display
    Timer {
        id: turntableStateReset
        interval: 600
        repeat:   false
        onTriggered: if (page.turntableState !== "locked") page.turntableState = "idle"
    }

    Timer { id: brakeChevronReset; interval: 300; onTriggered: brakeChevron.opacity = 0.8 }
    Timer { id: pushChevronReset;  interval: 300; onTriggered: pushChevron.opacity  = 0.8 }

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
            z:      isTap ? 2 : 1
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

            NumberAnimation on angle {
                from:        page.entryAngle
                to:          page.exitAngle
                duration:    page.fullRevMs
                running:     true
                paused:      page.beatOffsetLocked
                easing.type: Easing.Linear
                onRunningChanged: if (!running) dot.destroy()
            }

            SequentialAnimation {
                running: true
                paused:  page.beatOffsetLocked
                PauseAnimation  { duration: page.fullRevMs * 0.65 }
                NumberAnimation {
                    target:      dotRect
                    property:    "opacity"
                    to:          0.0
                    duration:    page.fullRevMs * 0.20
                    easing.type: Easing.InQuad
                }
            }
        }
    }

    // ── Pause icon — behind pulseSmall and dots, suggests lock zone ───────────
    Row {
        id: pauseIcon
        anchors.verticalCenter:         pulseSmall.bottom
        anchors.verticalCenterOffset:   -Dims.l(1)
        anchors.horizontalCenter:       pulseSmall.horizontalCenter
        spacing: Dims.l(4)
        z: 0
        opacity: page.beatOffsetLocked ? 0.8 : 0.5
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Rectangle {
            width:  Dims.l(2.5)
            height: Dims.l(10)
            radius: Dims.l(1)
            color:  page.tapDotColor
        }
        Rectangle {
            width:  Dims.l(2.5)
            height: Dims.l(10)
            radius: Dims.l(1)
            color:  page.tapDotColor
        }
    }

    // ── Brake chevron — left of ring, clockwise orientation ───────────────────
    Item {
        id: brakeChevron
        anchors.verticalCenter:         pulseSmall.bottom
        anchors.verticalCenterOffset:   Dims.l(-1)
        anchors.horizontalCenter:       pulseSmall.left
        anchors.horizontalCenterOffset: Dims.l(1)
        width:  Dims.l(8)
        height: Dims.l(8)
        z: 0
        opacity: 0.5

        property real travel: 0.0
        transform: Translate {
            x: Math.cos((-135) * Math.PI / 180) * brakeChevron.travel
            y: Math.sin((-135) * Math.PI / 180) * brakeChevron.travel
        }

        SequentialAnimation on travel {
            loops: Animation.Infinite
            NumberAnimation { to: Dims.l(4);    duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: Dims.l(-8);   duration: 1200; easing.type: Easing.InOutSine }
        }

        // ‹ pointing upper-left — two rects forming chevron, whole item rotated -135°
        Item {
            anchors.centerIn: parent
            rotation: -135
            Rectangle {
                width:  Dims.l(1.5); height: Dims.l(4.5)
                radius: Dims.l(0.5); color:  page.tapDotColor
                x: Dims.l(1.5); y: 0
                rotation: -40; transformOrigin: Item.Bottom
            }
            Rectangle {
                width:  Dims.l(1.5); height: Dims.l(4.5)
                radius: Dims.l(0.5); color:  page.tapDotColor
                x: Dims.l(1.5); y: Dims.l(3)
                rotation: 40; transformOrigin: Item.Top
            }
        }
    }

    // ── Push chevron — right of ring, counter-clockwise orientation ───────────
    Item {
        id: pushChevron
        anchors.verticalCenter:         pulseSmall.bottom
        anchors.verticalCenterOffset:   Dims.l(-6.4)
        anchors.horizontalCenter:       pulseSmall.right
        anchors.horizontalCenterOffset: Dims.l(-6.4)
        width:  Dims.l(8)
        height: Dims.l(8)
        z: 0
        opacity: 0.5

        property real travel: 0.0
        transform: Translate {
            x: Math.cos((-45) * Math.PI / 180) * pushChevron.travel
            y: Math.sin((-45) * Math.PI / 180) * pushChevron.travel
        }

        SequentialAnimation on travel {
            loops: Animation.Infinite
            NumberAnimation { to: Dims.l(4);    duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: Dims.l(-8);   duration: 1200; easing.type: Easing.InOutSine }
        }

        // › pointing upper-right — brake mirrored, inner item rotated 45°
        Item {
            anchors.centerIn: parent
            rotation: -45
            Rectangle {
                width:  Dims.l(1.5); height: Dims.l(4.5)
                radius: Dims.l(0.5); color:  page.tapDotColor
                x: Dims.l(1.5); y: 0
                rotation: -40; transformOrigin: Item.Bottom
            }
            Rectangle {
                width:  Dims.l(1.5); height: Dims.l(4.5)
                radius: Dims.l(0.5); color:  page.tapDotColor
                x: Dims.l(1.5); y: Dims.l(3)
                rotation: 40; transformOrigin: Item.Top
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
                    labelColorFlash.restart()
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

    // ── Tap hint — visible before first tap, pulses with beat ─────────────────
    Label {
        id: tapHint
        anchors.top:              pulseSmall.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin:        Dims.h(7)
        z: 3
        //% "Tap"
        text:    qsTrId("id-tap")
        visible: !page.sessionActive
        opacity: 0.4
        font {
            pixelSize: Dims.l(9)
            weight:    Font.Bold
        }

        SequentialAnimation {
            id: tapHintPulse
            NumberAnimation { target: tapHint; property: "opacity"; to: 0.9; duration: 10;  easing.type: Easing.Linear }
            NumberAnimation { target: tapHint; property: "opacity"; to: 0.4; duration: 340; easing.type: Easing.InQuad }
        }

        Connections {
            target: page.beatSource
            function onBeat() {
                if (page.settled && page.lastTap === 0) tapHintPulse.restart()
            }
        }
    }

    // ── Stats cycler — replaces tap hint after first tap ──────────────────────
    Label {
        id: statsCycler
        anchors.top:              pulseSmall.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin:        Dims.h(9)
        z: 3
        visible: page.sessionActive
        text: page.statusOrStats()
        opacity: 0.8
        font {
            pixelSize: Dims.l(8)
            family:    "Noto Sans Condensed"
        }
    }

    // ── BPM label — tap target only ───────────────────────────────────────────
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
            NumberAnimation { target: bpmLabel; property: "scale"; to: 1.4; duration: 45;  easing.type: Easing.InQuad  }
            NumberAnimation { target: bpmLabel; property: "scale"; to: 1.0; duration: 90;  easing.type: Easing.OutQuad }
        }

        SequentialAnimation {
            id: labelColorFlash
            ColorAnimation { target: bpmLabel; property: "color"; to: page.pulseColor; duration: 10;  easing.type: Easing.Linear }
            ColorAnimation { target: bpmLabel; property: "color"; to: "#ffffff";       duration: 340; easing.type: Easing.InQuad }
        }

        Connections {
            target: page
            function onTapCountChanged() { labelPump.restart() }
        }

        MouseArea {
            anchors.fill: parent
            z: 4
            onClicked: {
                var now = new Date().getTime()

                if (page.lastTap > 0 && (now - page.lastTap) > page.sessionBreakMs) {
                    page.intervals          = []
                    page.lastTap            = 0
                    page.statSpreadMin      = 0
                    page.statSpreadMax      = 0
                    page.consecutiveOutliers = 0
                }

                page.tapCount++
                page.sessionActive = true

                if (page.lastTap === 0) {
                    dotComponent.createObject(dotContainer, {drift: 0.0, isTap: true})
                }

                if (page.lastTap > 0) {
                    var delta = now - page.lastTap

                    // ── Outlier detection ──────────────────────────────────────
                    var isOutlier = false
                    if (page.intervals.length >= 2) {
                        var sum = 0
                        for (var k = 0; k < page.intervals.length; ++k) sum += page.intervals[k]
                            var mean = sum / page.intervals.length
                            isOutlier = Math.abs(delta - mean) > mean * 0.30
                    }

                    if (isOutlier) {
                        page.consecutiveOutliers++
                        if (page.consecutiveOutliers >= 2) {
                            // Two in a row — intentional tempo change, reset window
                            page.intervals           = [delta]
                            page.consecutiveOutliers = 0
                            page.statSpreadMin       = 0
                            page.statSpreadMax       = 0
                        }
                        // Single outlier — dot spawns at drift position but BPM unchanged
                        var expected = 60000.0 / page.bpmValue
                        var drift    = Math.max(-1.0, Math.min(1.0,
                                                               (delta - expected) / (expected * 0.75)))
                        dotComponent.createObject(dotContainer, {drift: drift, isTap: true})
                        page.lastTap = now
                        return
                    }

                    // ── Clean interval — accepted ──────────────────────────────
                    page.consecutiveOutliers = 0
                    page.intervals.push(delta)
                    if (page.intervals.length > 8) page.intervals.shift()
                        var sum2 = 0
                        for (var j = 0; j < page.intervals.length; ++j) sum2 += page.intervals[j]
                            var bpm = Math.round(60000 / (sum2 / page.intervals.length))
                            bpm = Math.max(page.bpmMin, Math.min(page.bpmMax, bpm))
                            page.bpmValueSet(bpm)
                            page.updateStats(delta, bpm)

                            var expected2 = 60000.0 / bpm
                            var drift2    = Math.max(-1.0, Math.min(1.0,
                                                                    (delta - expected2) / (expected2 * 0.75)))
                            dotComponent.createObject(dotContainer, {drift: drift2, isTap: true})
                }

                page.lastTap = now
            }
        }
    }

    // ── Tempo name ────────────────────────────────────────────────────────────
    Label {
        id: tempoNameLabel
        anchors.bottom:           pulseSmall.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin:     Dims.h(9)
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

    // ── Turntable zones — below BPM label, 40/20/40 horizontal split ──────────
    MouseArea {
        id: brakeZone
        anchors.left:   parent.left
        anchors.top:    tempoNameLabel.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.40
        z: 4
        onClicked: {
            page.sessionActive  = true
            page.turntableState = "braking"
            page.beatOffsetDelta(5)
            turntableStateReset.restart()
            brakeChevron.opacity = 0.8
            brakeChevronReset.restart()
        }
    }

    MouseArea {
        id: lockZone
        anchors.left:         brakeZone.right
        anchors.top:          tempoNameLabel.bottom
        anchors.bottom:       parent.bottom
        width: parent.width * 0.20
        z: 4
        onClicked: {
            page.sessionActive = true
            page.beatOffsetLockToggle()
        }
    }

    MouseArea {
        id: pushZone
        anchors.right:  parent.right
        anchors.top:    tempoNameLabel.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.40
        z: 4
        onClicked: {
            page.sessionActive  = true
            page.turntableState = "pushing"
            page.beatOffsetDelta(-5)
            turntableStateReset.restart()
            pushChevron.opacity = 0.9
            pushChevronReset.restart()
        }
    }
}
