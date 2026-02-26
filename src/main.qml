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
    id: app    // renamed from root — root is reserved, refers to delegate scope inside ListView

    anchors.fill: parent

    centerColor: app.pageCenterColors[pageView.currentIndex]
    outerColor:  app.pageOuterColors[pageView.currentIndex]

    Behavior on centerColor { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }
    Behavior on outerColor  { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    ConfigurationValue { id: bpmConfig;   key: "/asteroid/apps/beatfork/bpm";        defaultValue: 120 }
    ConfigurationValue { id: freqConfig;  key: "/asteroid/apps/beatfork/freq";       defaultValue: 440 }
    ConfigurationValue { id: colorConfig; key: "/asteroid/apps/beatfork/colorIndex"; defaultValue: 0   }

    readonly property var pageCenterColors: ["#1C325F", "#13213F", "#1A3360"]
    readonly property var pageOuterColors:  ["#090B0C", "#050708", "#070909"]
    readonly property int bpmMin:           40
    readonly property int bpmMax:           208
    readonly property int bpmModelCount:    bpmMax - bpmMin + 1
    readonly property int flashDuration:    200
    readonly property int sessionBreakMs:   1500

    property int  beatOffset:       0      // signed ms, added to beatTimer interval
    property bool beatOffsetLocked: false  // true = decay paused, offset held

    property var bpmModel: {
        var arr = []
        for (var i = bpmMin; i <= bpmMax; ++i) arr.push(i)
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
        "#FF6B00",  // 1 orange
        "#00BBFF",  // 2 sky blue
        "#FFE500",  // 3 yellow
        "#CC44FF",  // 4 purple
        "#FF4466",  // 5 coral red
        "#00E5AA",  // 6 mint green
        "#FF69B4",  // 7 hot pink
        "#AAFF33",  // 8 lime
        "#FF3300",  // 9 red-orange
        "#00CED1"   // 10 teal cyan  — pairs with red-orange and wraps to orange
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

    QtObject {
        id: page0State
        property bool sessionActive: false
    }

    QtObject {
        id: page1State
        property bool soundActive:  false
        property bool hapticActive: false
        property bool pulseVisible: false
        property int  pendingBpm:   -1
    }

    QtObject {
        id: page2State
        property bool loopActive: false
    }

    Binding {
        target:   DisplayBlanking
        property: "preventBlanking"
        value:    page1State.soundActive  ||
        page1State.hapticActive ||
        page1State.pulseVisible ||
        page2State.loopActive
    }

    SoundEffect {
        id: tickSound
        source: "file:///usr/share/sounds/tick.wav"
        volume: 1.0
    }

    NonGraphicalFeedback {
        id: hapticFeedback
        event: "press"
    }

    Timer {
        id: beatTimer
        interval:         Math.max(1, Math.round(60000 / bpmConfig.value))
        repeat:           true
        running:          !app.beatOffsetLocked
        triggeredOnStart: false
        onTriggered: {
            app.beatFlash()
            // Apply offset only here — never via binding, never resets countdown
            interval = Math.max(1, Math.round(60000 / bpmConfig.value) + app.beatOffset)
        }
    }

    Connections {
        target: bpmConfig
        function onValueChanged() {
            beatTimer.interval = Math.max(1, Math.round(60000 / bpmConfig.value) + app.beatOffset)
            beatTimer.restart()
        }
    }

    // Decay — nudges offset toward 0 by 3ms every 80ms when not locked
    Timer {
        id: offsetDecayTimer
        interval: 80
        repeat:   true
        running:  !app.beatOffsetLocked && app.beatOffset !== 0
        onTriggered: {
            if      (app.beatOffset > 0) app.beatOffset = Math.max(0, app.beatOffset - 10)
                else if (app.beatOffset < 0) app.beatOffset = Math.min(0, app.beatOffset + 10)
        }
    }

    Timer {
        id: spinnerDebounce
        interval: 1000
        repeat:   false
        onTriggered: {
            if (page1State.pendingBpm >= bpmMin) {
                bpmConfig.value       = page1State.pendingBpm
                page1State.pendingBpm = -1
            }
        }
    }

    signal beat()

    function beatFlash() {
        app.beat()
        if (page1State.soundActive)  tickSound.play()
            if (page1State.hapticActive) hapticFeedback.play()
    }

    ListView {
        id: pageView
        anchors.fill:       parent
        orientation:        ListView.Horizontal
        snapMode:           ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        flickDeceleration:  5000
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior:     Flickable.StopAtBounds
        model: DeviceSpecs.hasSpeaker ? 3 : 2

        delegate: Item {
            width:  pageView.width
            height: pageView.height

            BpmDetectPage {
                id: page0
                anchors.fill:   parent
                visible:        index === 0
                pageActive:     pageView.currentIndex === 0
                bpmValue:       bpmConfig.value
                bpmMin:         app.bpmMin
                bpmMax:         app.bpmMax
                sessionBreakMs: app.sessionBreakMs
                pulseColor:     app.pulseColor
                beatSource:     app
                onBpmValueSet: {
                    bpmConfig.value = bpm
                    var interval  = Math.max(1, Math.round(60000 / bpmConfig.value) + app.beatOffset)
                    var elapsed   = new Date().getTime() - page0.lastPressTime
                    var remaining = Math.max(1, interval - (elapsed % interval))
                    beatTimer.interval = remaining
                    beatTimer.restart()
                }
                tapDotColor:    app.pulseColors[(colorConfig.value + 1) % app.pulseColors.length]
                beatOffset:       app.beatOffset
                beatOffsetLocked: app.beatOffsetLocked
                onBeatOffsetDelta: {
                    app.beatOffset = Math.max(-300, Math.min(300, app.beatOffset + ms))
                }
                onBeatOffsetLockToggle: {
                    app.beatOffsetLocked = !app.beatOffsetLocked
                    if (!app.beatOffsetLocked) app.beatFlash()  // instant dot on release
                }
                onSessionActiveChanged: page0State.sessionActive = sessionActive
            }

            // Stats cycler overlay — sits above PageHeader for page 0
            MouseArea {
                anchors.top:    parent.top
                anchors.left:   parent.left
                anchors.right:  parent.right
                height:         Dims.h(20)
                z: 100
                enabled: pageView.currentIndex === 0
                onClicked: page0.statsCycleTap++
            }

            MetronomePage {
                anchors.fill:   parent
                visible:        index === 1
                pageActive:     pageView.currentIndex === 1
                bpmValue:       bpmConfig.value
                bpmMin:         app.bpmMin
                bpmMax:         app.bpmMax
                bpmModelCount:  app.bpmModelCount
                bpmModel:       app.bpmModel
                colorIndex:     colorConfig.value
                pulseColor:     app.pulseColor
                pulseColors:    app.pulseColors
                pulseVisible:   page1State.pulseVisible
                soundActive:    page1State.soundActive
                hapticActive:   page1State.hapticActive
                beatSource:     app
                onPulseVisibleSet: page1State.pulseVisible = active
                onSoundActiveSet:  page1State.soundActive  = active
                onHapticActiveSet: page1State.hapticActive = active
                onColorIndexSet:   colorConfig.value       = idx
                onBpmPending: {
                    page1State.pendingBpm = bpm
                    spinnerDebounce.restart()
                }
            }

            TuningForkPage {
                anchors.fill: parent
                visible:      index === 2
                pageActive:   pageView.currentIndex === 2
                freqValue:    freqConfig.value
                freqModel:    app.freqModel
                freqNames:    app.freqNames
                pulseColor:   app.pulseColor
                loopActive:   page2State.loopActive
                onFreqValueSet:  freqConfig.value      = freq
                onLoopActiveSet: page2State.loopActive = active
            }
        }
    }

    PageHeader {
        text: app.pageTitles[pageView.currentIndex]
        enabled: !(pageView.currentIndex === 0 && page0State.sessionActive)
        opacity: (pageView.currentIndex === 1 && page1State.pulseVisible) ||
        (pageView.currentIndex === 0 && page0State.sessionActive) ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
    }

    PageDot {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     Dims.h(4)
        height:       Dims.h(3)
        dotNumber:    DeviceSpecs.hasSpeaker ? 3 : 2
        currentIndex: pageView.currentIndex
    }
}
