/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils

Item {
    id: page

    // ── Interface — primitives only, no object references ─────────────────────
    property int    bpmValue:       120
    property int    bpmMin:         40
    property int    bpmMax:         208
    property int    sessionBreakMs: 1500
    property bool   sessionActive:  false
    property string pulseColor:     "#00ff00"
    property string tapDotColor:    "#ff69b4"
    property int    rippleDur:      Math.min(300, Math.round(30000 / bpmValue))
    property var    beatSource
    property int    statsCycleTap:  0
    property real lastPressTime: 0
    onStatsCycleTapChanged: {
        if (lastTap > 0) statsIndex = (statsIndex + 1) % statCount
    }
    property int  beatOffset:       0
    property bool beatOffsetLocked: false

    signal beatOffsetDelta(int ms)
    signal beatOffsetLockToggle()
    signal bpmValueSet(int bpm)

    // ── State ─────────────────────────────────────────────────────────────────
    property bool settled:            false
    property real lastTap:            0
    property var  intervals:          []
    property int  tapCount:           0
    property int  consecutiveOutliers: 0
    property string turntableState:   beatOffsetLocked ? "locked" : "idle"

    // ── Stats ─────────────────────────────────────────────────────────────────
    property int  statsIndex:      0
    readonly property int statCount: 6
    property real statPreciseBpm:  0.0
    property int  statConsistency: 0
    property int  statDriftMs:     0
    property int  statConfidence:  0
    property int  statSpreadMin:   0
    property int  statSpreadMax:   0
    property int  statMsPerBeat:   0

    function updateStats(delta, bpm, avgInterval) {
        statPreciseBpm  = Math.round(60000.0 / avgInterval * 10) / 10
        statConfidence  = Math.min(8, intervals.length + 1)
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

    // ── Dot pool ──────────────────────────────────────────────────────────────
    readonly property int poolSize: 24

    function acquireDot(drift, isTap) {
        for (var i = 0; i < dotPool.count; i++) {
            var d = dotPool.itemAt(i)
            if (d && !d.active) {
                d.drift      = drift
                d.isTap      = isTap
                d.angle      = page.entryAngle
                d.dotOpacity = 1.0
                d.active     = true
                return
            }
        }
    }

    property bool pageActive: false
    onPageActiveChanged: {
        if (pageActive) {
            settleTimer.restart()
            indicatorRight.animate()
        } else {
            consecutiveOutliers = 0
            statConfidence      = 0
            sessionActive       = false
            settleTimer.stop()
            settled             = false
            lastTap             = 0
            intervals           = []
            pulseSmall.opacity  = 0.0
            for (var i = 0; i < dotPool.count; i++) {
                var d = dotPool.itemAt(i)
                if (d) d.active = false
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 400
        repeat:   false
        onTriggered: page.settled = true
    }

    Timer {
        id: turntableStateReset
        interval: 600
        repeat:   false
        onTriggered: if (page.turntableState !== "locked") page.turntableState = "idle"
    }

    // ── Turntable indicators — shared sequencer ───────────────────────────────
    readonly property int indicatorCount: 5
    property int          indicatorPhase: 0

    function chevronOpacity(idx, phase) {
        var trail = (phase - idx + indicatorCount) % indicatorCount
        if (trail === 0) return 0.5
            if (trail === 1) return 0.4
                if (trail === 2) return 0.2
                    if (trail === 3) return 0.1
                        return 0
    }

    // ── Edge indicator ────────────────────────────────────────────────────────
    Indicator { id: indicatorRight; edge: Qt.RightEdge }

    // ── Pause icon ────────────────────────────────────────────────────────────
    Row {
        id: pauseIcon
        anchors.verticalCenter:       pulseSmall.bottom
        anchors.verticalCenterOffset: -Dims.l(1)
        anchors.horizontalCenter:     pulseSmall.horizontalCenter
        spacing: Dims.l(4)
        z: 0
        opacity: page.beatOffsetLocked ? 0.8 : 0.5
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle {
            width:  Dims.l(2.5); height: Dims.l(10)
            radius: Dims.l(1);   color:  page.tapDotColor
        }
        Rectangle {
            width:  Dims.l(2.5); height: Dims.l(10)
            radius: Dims.l(1);   color:  page.tapDotColor
        }
    }

    // Brake arc — 200°→260°, wave travels clockwise
    Item {
        id: brakeIndicator
        anchors.centerIn: parent
        width: 0; height: 0
        z: 0
        Repeater {
            model: page.indicatorCount
            Text {
                readonly property real arcAngle: 205 + index * 11
                x: Math.sin(arcAngle * Math.PI / 180) * (page.ringRadius + Dims.l(10)) - width  / 2
                y: -Math.cos(arcAngle * Math.PI / 180) * (page.ringRadius + Dims.l(10)) - height / 2
                text:           "›"
                rotation:       arcAngle
                color:          page.tapDotColor
                opacity:        page.chevronOpacity(index, page.indicatorPhase)
                font {
                    pixelSize: Dims.l(14)
                    family:    "Noto Sans Condensed"
                    weight:    Font.Bold
                }
            }
        }
    }

    // Push arc — 160°→100°, wave travels counterclockwise
    Item {
        id: pushIndicator
        anchors.centerIn: parent
        width: 0; height: 0
        z: 0
        Repeater {
            model: page.indicatorCount
            Text {
                readonly property real arcAngle: 158 - index * 11
                x: Math.sin(arcAngle * Math.PI / 180) * (page.ringRadius + Dims.l(7)) - width  / 2
                y: -Math.cos(arcAngle * Math.PI / 180) * (page.ringRadius + Dims.l(7)) - height / 2
                text:           "›"
                rotation:       arcAngle + 180
                color:          page.tapDotColor
                opacity:        page.chevronOpacity(index, page.indicatorPhase)
                font {
                    pixelSize: Dims.l(14)
                    family:    "Noto Sans Condensed"
                    weight:    Font.Bold
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

        Timer {
            id: pulseSmallOff
            repeat: false
            onTriggered: pulseSmall.opacity = 0.0
        }

        Connections {
            target: page.beatSource
            function onBeat() {
                if (!page.settled) return
                    pulseSmall.opacity = 1.0
                    pulseSmallOff.interval = Math.round(30000 / page.bpmValue)
                    pulseSmallOff.restart()
                    page.indicatorPhase = (page.indicatorPhase + 1) % page.indicatorCount

                    var guard = Math.round(9000 / page.bpmValue)
                    var now   = new Date().getTime()
                    if (page.lastTap === 0 || (now - page.lastTap) > guard)
                        page.acquireDot(0.0, false)
            }
        }
    }

    // ── Dot container + pool ──────────────────────────────────────────────────
    Item {
        id: dotContainer
        anchors.centerIn: parent
        width:  0
        height: 0
        z: 1

        Repeater {
            id: dotPool
            model: page.poolSize

            Item {
                id: poolDot
                property bool  active:     false
                property real  drift:      0.0
                property bool  isTap:      false
                property real  dotOpacity: 0.0
                property color dotColor:   isTap ? page.tapDotColor : page.pulseColor
                z:       isTap ? 2 : 1
                visible: active

                readonly property real r: page.borderCenter + drift * page.driftExtent
                property real angle: page.entryAngle

                x: Math.sin(angle * Math.PI / 180) * r
                y: -Math.cos(angle * Math.PI / 180) * r

                Rectangle {
                    anchors.centerIn: parent
                    width:   poolDot.isTap ? Dims.l(5) : Dims.l(4)
                    height:  width
                    radius:  width / 2
                    color:   poolDot.dotColor
                    opacity: poolDot.dotOpacity
                }

                NumberAnimation {
                    id: angleAnim
                    target:      poolDot
                    property:    "angle"
                    from:        page.entryAngle
                    to:          page.exitAngle
                    duration:    page.fullRevMs
                    running:     poolDot.active
                    paused:      page.beatOffsetLocked || !page.pageActive
                    easing.type: Easing.Linear
                    onStopped:   if (poolDot.active && !page.beatOffsetLocked) poolDot.active = false
                }

                SequentialAnimation {
                    id: fadeAnim
                    running: poolDot.active
                    paused:      page.beatOffsetLocked || !page.pageActive
                    PauseAnimation  { duration: page.fullRevMs * 0.65 }
                    NumberAnimation {
                        target:      poolDot
                        property:    "dotOpacity"
                        to:          0.0
                        duration:    page.fullRevMs * 0.20
                        easing.type: Easing.InQuad
                        onStopped:   poolDot.active = false
                    }
                }

                onActiveChanged: {
                    if (!active) {
                        dotOpacity = 0.0
                        angleAnim.stop()
                        fadeAnim.stop()
                    }
                }
            }
        }
    }

    // ── Ripple rings — spawn at pulseSmall edge, travel outward ───────────────
    Rectangle {
        id: ripple1
        anchors.centerIn: parent
        width:   page.ringRadius * 2
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(2)
        opacity: 0.0
        scale:   1.0
        z: 2

        ParallelAnimation {
            id: ripple1Anim
            NumberAnimation { target: ripple1; property: "scale";   from: 1.0; to: 1.35; duration: page.rippleDur; easing.type: Easing.OutQuad }
            NumberAnimation { target: ripple1; property: "opacity"; from: 0.55; to: 0.0; duration: page.rippleDur; easing.type: Easing.InQuad }
        }

        Connections {
            target: page
            function onTapCountChanged() { ripple1Anim.restart() }
        }
    }

    Rectangle {
        id: ripple2
        anchors.centerIn: parent
        width:   page.ringRadius * 2
        height:  width
        radius:  width / 2
        color:   "transparent"
        border.color: page.pulseColor
        border.width: Dims.l(1.5)
        opacity: 0.0
        scale:   1.0
        z: 2

        SequentialAnimation {
            id: ripple2Anim
            PauseAnimation { duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: ripple2; property: "scale";   from: 1.0; to: 1.25; duration: page.rippleDur; easing.type: Easing.OutQuad }
                NumberAnimation { target: ripple2; property: "opacity"; from: 0.40; to: 0.0; duration: page.rippleDur; easing.type: Easing.InQuad }
            }
        }

        Connections {
            target: page
            function onTapCountChanged() { ripple2Anim.restart() }
        }
    }

    // ── Tap hint ──────────────────────────────────────────────────────────────
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
        font { pixelSize: Dims.l(9); weight: Font.Bold }

        SequentialAnimation {
            id: tapHintPulse
            NumberAnimation { target: tapHint; property: "opacity"; to: 0.9; duration: 10;  easing.type: Easing.Linear }
            NumberAnimation { target: tapHint; property: "opacity"; to: 0.4; duration: 340; easing.type: Easing.InQuad }
        }

        Connections {
            target: page.beatSource
            function onBeat() {
                if (page.settled && !page.sessionActive) tapHintPulse.restart()
            }
        }
    }

    // ── Stats cycler ──────────────────────────────────────────────────────────
    Label {
        id: statsCycler
        anchors.top:              pulseSmall.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin:        Dims.h(9)
        z: 3
        visible: page.sessionActive
        text:    page.statusOrStats()
        opacity: 0.8
        font { pixelSize: Dims.l(8); family: "Noto Sans Condensed" }
    }

    // ── BPM label — tap target ────────────────────────────────────────────────
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
        scale:   1.0

        SequentialAnimation {
            id: labelPump
            NumberAnimation { target: bpmLabel; property: "scale"; to: 1.3; duration: 30;  easing.type: Easing.InQuad  }
            NumberAnimation { target: bpmLabel; property: "scale"; to: 1.0; duration: 60;  easing.type: Easing.OutQuad }
        }

        Connections {
            target: page
            function onTapCountChanged() { labelPump.restart() }
        }

        MouseArea {
            anchors.fill: parent
            z: 4

            onPressed: {
                page.lastPressTime = new Date().getTime()
                pulseSmall.opacity = 1.0
            }

            onReleased: {
                pulseSmallOff.interval = Math.round(30000 / page.bpmValue)
                pulseSmallOff.restart()
            }

            onClicked: {
                var now = new Date().getTime()

                if (page.lastTap > 0 && (now - page.lastTap) > page.sessionBreakMs) {
                    page.intervals           = []
                    page.lastTap             = 0
                    page.statSpreadMin       = 0
                    page.statSpreadMax       = 0
                    page.statConfidence      = 0
                    page.consecutiveOutliers = 0
                }

                page.tapCount++
                page.sessionActive = true

                if (page.lastTap === 0) {
                    page.statConfidence = 1
                    page.acquireDot(0.0, true)
                }

                if (page.lastTap > 0) {
                    var delta = now - page.lastTap

                    var isOutlier = false
                    if (page.intervals.length >= 2) {
                        var sum = 0
                        for (var k = 0; k < page.intervals.length; ++k) sum += page.intervals[k]
                            var mean = sum / page.intervals.length
                            isOutlier = Math.abs(delta - mean) > mean * 0.30
                    }

                    if (isOutlier) {
                        var isHarmonic = page.intervals.length >= 2 &&
                        (Math.abs(delta - mean * 2.0) < mean * 0.30 ||
                        Math.abs(delta - mean * 0.5) < mean * 0.15)

                        if (isHarmonic) {
                            page.intervals           = [delta]
                            page.consecutiveOutliers = 0
                            page.statSpreadMin       = 0
                            page.statSpreadMax       = 0
                        } else {
                            page.consecutiveOutliers++
                            if (page.consecutiveOutliers >= 2) {
                                page.intervals           = [delta]
                                page.consecutiveOutliers = 0
                                page.statSpreadMin       = 0
                                page.statSpreadMax       = 0
                            }
                        }
                        var expected = 60000.0 / page.bpmValue
                        var drift    = Math.max(-1.0, Math.min(1.0,
                                                               (delta - expected) / (expected * 0.75)))
                        page.acquireDot(drift, true)
                        page.lastTap = now
                        return
                    }

                    page.consecutiveOutliers = 0
                    page.intervals.push(delta)
                    if (page.intervals.length > 8) page.intervals.shift()
                        var sum2 = 0
                        for (var j = 0; j < page.intervals.length; ++j) sum2 += page.intervals[j]
                            var bpm = Math.round(60000 / (sum2 / page.intervals.length))
                            bpm = Math.max(page.bpmMin, Math.min(page.bpmMax, bpm))
                            page.bpmValueSet(bpm)
                            page.updateStats(delta, bpm, sum2 / page.intervals.length)

                            var expected2 = 60000.0 / bpm
                            var drift2    = Math.max(-1.0, Math.min(1.0,
                                                                    (delta - expected2) / (expected2 * 0.75)))
                            page.acquireDot(drift2, true)
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
        font { pixelSize: Dims.l(8); family: "Noto Sans Condensed" }
        opacity: 0.8
    }

    // ── Turntable zones ───────────────────────────────────────────────────────
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
        }
    }

    MouseArea {
        id: lockZone
        anchors.left:   brakeZone.right
        anchors.top:    tempoNameLabel.bottom
        anchors.bottom: parent.bottom
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
        }
    }
}
