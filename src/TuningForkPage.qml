/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 */

import QtQuick
import QtMultimedia
import org.asteroid.controls
import org.asteroid.utils

Item {
    id: page

    // ── Interface — primitives only ───────────────────────────────────────────
    property int    freqValue:  440
    property var    freqModel:  []
    property var    freqNames:  []
    property string pulseColor: "#00ff00"
    property bool   loopActive: false

    property bool   pageActive: false

    // Write-back signals
    signal freqValueSet(int freq)
    signal loopActiveSet(bool active)

    onPageActiveChanged: {
        if (pageActive) indicatorLeft.animate()
    }

    // ── Edge indicator ────────────────────────────────────────────────────────
    Indicator { id: indicatorLeft; edge: Qt.LeftEdge }

    // ── Audio ─────────────────────────────────────────────────────────────────
    SoundEffect {
        id: tone
        volume: 1.0
    }

    Timer {
        id: singlePlayStop
        interval: 1000
        repeat:   false
        onTriggered: tone.stop()
    }

    // ── Upper half ────────────────────────────────────────────────────────────
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
                var idx = page.freqModel.indexOf(page.freqValue)
                return idx >= 0 ? page.freqNames[idx] : ""
            }
            font.pixelSize: Dims.l(6)
            opacity: 0.6
        }

        Label {
            id: freqLabel
            anchors.centerIn: parent
            //% "Hz"
            text:           page.freqValue + " " + qsTrId("id-hz")
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
                page.loopActiveSet(false)
                var idx = page.freqModel.indexOf(page.freqValue)
                var nextFreq = page.freqModel[(idx + 1) % page.freqModel.length]
                page.freqValueSet(nextFreq)
                tone.source = "file:///usr/share/sounds/" + nextFreq + "hz.wav"
            }
        }
    }

    // ── Lower half ────────────────────────────────────────────────────────────
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

            property int rippleCount: 0

            Timer {
                id: rippleTimer
                interval: 1200
                repeat:   true
                running:  tone.playing
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
                    function onRippleCountChanged() {
                        if (tone.playing) forkRipple1Anim.restart()
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
                    function onRippleCountChanged() {
                        if (tone.playing) forkRipple2Anim.restart()
                    }
                }
            }

            Rectangle {
                id: forkBg
                anchors.fill: parent
                radius:  width / 2
                color:   tone.playing ? page.pulseColor : "#000000"
                opacity: 0.7
                z: 1

                Behavior on color { ColorAnimation { duration: 150 } }

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
                    if (tone.playing) {
                        singlePlayStop.stop()
                        tone.stop()
                        page.loopActiveSet(false)
                    } else {
                        tone.loops = 1
                        tone.play()
                        playingPulse.restart()
                        singlePlayStop.restart()
                        forkButton.rippleCount++
                    }
                }

                onPressAndHold: {
                    holdActive = true
                    singlePlayStop.stop()
                    tone.loops = SoundEffect.Infinite
                    if (!tone.playing) tone.play()
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
            anchors.topMargin:        Dims.h(1)
            //% "Tap to stop"
            text:           tone.playing ? qsTrId("id-tap-to-stop") : qsTrId("id-hold-to-loop")
            font.pixelSize: Dims.l(6)
            opacity: 0.6
        }
    }

    Component.onCompleted: {
        tone.source = "file:///usr/share/sounds/" + page.freqValue + "hz.wav"
    }
}
