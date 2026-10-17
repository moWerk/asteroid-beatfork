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

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "."
import Nemo.Configuration 1.0
import QtMultimedia 5.6
import QtFeedback 5.0
import Nemo.KeepAlive 1.2
import moWerk.ToneGenerator 1.0
import moWerk.BpmDetector 1.0

// SailfishOS: the three pages are tabs, as in Jolla Clock: a TabBar with
// the titles at the top, a swipe moves between them. The ambience shows
// through. TabView is private Silica API (fine for Chum, not for the store).
Item {
    id: app    // renamed from root — root is reserved, refers to delegate scope inside ListView

    anchors.fill: parent

    // the tab in front: 0 Detect BPM, 1 Metronome, 2 Tuning Fork
    readonly property int currentTab: tabs.currentIndex
    // for the cover
    readonly property int bpm: bpmConfig.value

    ConfigurationValue { id: bpmConfig;   key: "/asteroid/apps/beatfork/bpm";        defaultValue: 120 }
    ConfigurationValue { id: freqConfig;  key: "/asteroid/apps/beatfork/freq";       defaultValue: 440 }
    ConfigurationValue { id: colorConfig; key: "/asteroid/apps/beatfork/colorIndex"; defaultValue: 0   }

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
        // SailfishOS: chosen audio source for tempo detection, -1 = off
        property int  listenSource:  typeof selftestListen !== "undefined" ? selftestListen : -1
        // half or double of what the detector finds (mo, 2026-10-06): the
        // metrical level is the hard part, 87.5 is often a 175 drum and bass.
        // Holds while listening; a new source or stopping resets it.
        property real listenFactor:  1.0
        onListenSourceChanged: listenFactor = 1.0
    }

    function applyDetectedTempo() {
        var bpm = Math.round(BpmListener.tempo * page0State.listenFactor)
        if (bpm >= app.bpmMin && bpm <= app.bpmMax
                && BpmListener.confidence >= 50 && bpm !== bpmConfig.value)
            bpmConfig.value = bpm
    }

    // Listen only while the BPM page is in front and the app is active:
    // the microphone is not held in the background or on the other pages.
    Binding {
        target:   BpmListener
        property: "source"
        // (the test hook also listens with the phone locked)
        value:    app.currentTab === 0
                  && (Qt.application.active
                      || (typeof selftestListen !== "undefined" && selftestListen >= 0))
                  ? page0State.listenSource : -1
    }

    // A detected tempo becomes the app tempo once it is reasonably sure;
    // the metronome then follows it (its phase is not aligned to the music).
    Connections {
        target: BpmListener
        onResultChanged: app.applyDetectedTempo()
    }

    // Test hook: log the input level once a second while listening
    Timer {
        interval: 1000
        repeat:   true
        running:  typeof selftestListen !== "undefined" && selftestListen >= 0
        onTriggered: console.log("selftest listen: running " + BpmListener.running
                                 + " level " + BpmListener.level.toFixed(2)
                                 + " bpm " + BpmListener.bpm
                                 + " tempo " + BpmListener.tempo.toFixed(2)
                                 + " confidence " + BpmListener.confidence
                                 + " error '" + BpmListener.error + "'")
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

    DisplayBlanking {
        preventBlanking: page1State.soundActive  ||
                         page1State.hapticActive ||
                         page1State.pulseVisible ||
                         page2State.loopActive
    }

    // Tick plays via ngfd (event beatfork-tick, shipped in events.d/) —
    // QtMultimedia SoundEffect on Qt6 chops playback and holds the
    // PulseAudio sink open permanently (battery drain), see the
    // asteroid-launcher ngf migration.
    // SailfishOS: the tick plays through ToneGen.tick(), a QAudioOutput
    // stream like the tuning fork. A SoundEffect stayed silent on the C2:
    // its PulseAudio sample stream was held paused ("corked") by the audio
    // policy. An ngfd event would need a system file and an ngfd restart.
    // The haptic tick is QtFeedback's ThemeEffect.
    QtObject {
        id: tickSound
        function play() { ToneGen.tick() }
    }

    ThemeEffect {
        id: hapticFeedback
        effect: ThemeEffect.Press
    }

    // Test hook (set from main.cpp): one tick and one second of tone
    Timer {
        interval: 2000
        running: typeof selftestAudio !== "undefined" && selftestAudio
        onTriggered: {
            tickSound.play()
            hapticFeedback.play()
            console.log("selftest tick played; haptic supported " + hapticFeedback.supported)
            ToneGen.start(440)
            selftestStop.start()
        }
    }
    Timer {
        id: selftestStop
        interval: 1000
        onTriggered: { ToneGen.stop(); console.log("selftest tone stopped") }
    }
    // Test hook: four more ticks at 120 BPM, to see repeated ticks play
    Timer {
        interval: 500
        repeat: true
        property int n: 0
        running: typeof selftestAudio !== "undefined" && selftestAudio && n < 4
        onTriggered: { n++; tickSound.play() }
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
        onValueChanged: {
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
            if      (app.beatOffset > 0) app.beatOffset = Math.max(0, app.beatOffset - 10) | 0
                else if (app.beatOffset < 0) app.beatOffset = Math.min(0, app.beatOffset + 10) | 0
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

    TabView {
        id: tabs
        anchors.fill: parent
        currentIndex: 0
        header: TabBar {
            model: ListModel {
                ListElement {
                    //% "Detect BPM"
                    title: qsTrId("id-detect-bpm")
                }
                ListElement {
                    //% "Metronome"
                    title: qsTrId("id-metronome")
                }
                ListElement {
                    //% "Tuning Fork"
                    title: qsTrId("id-tuning-fork")
                }
            }
        }
        model: DeviceSpecs.hasSpeaker ? [bpmTab, metronomeTab, forkTab] : [bpmTab, metronomeTab]
    }

    Component {
        id: bpmTab
        TabItem {
            // the tab view sizes each tab by its implicit size
            implicitWidth: tabs.width
            implicitHeight: tabs.height - tabs.tabBarHeight

            Item {
                id: bpmArea
                anchors.fill: parent

                BpmDetectPage {
                    id: page0
                    anchors.fill:   parent
                    pageActive:     app.currentTab === 0
                    bpmValue:       bpmConfig.value
                    bpmMin:         app.bpmMin
                    bpmMax:         app.bpmMax
                    sessionBreakMs: app.sessionBreakMs
                    pulseColor:     app.pulseColor
                    beatSource:     app
                    onBpmValueSet: {
                        // a tap takes over from listening
                        page0State.listenSource = -1
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
                        app.beatOffset = Math.max(-300, Math.min(300, app.beatOffset + ms)) | 0
                    }
                    onBeatOffsetLockToggle: {
                        app.beatOffsetLocked = !app.beatOffsetLocked
                        if (!app.beatOffsetLocked) app.beatFlash()  // instant dot on release
                    }
                    onSessionActiveChanged: page0State.sessionActive = sessionActive
                    listenSources:    BpmListener.sources
                    listenSource:     page0State.listenSource
                    listenRunning:    BpmListener.running
                    listenBpm:        BpmListener.bpm
                    listenConfidence: BpmListener.confidence
                    listenLevel:      BpmListener.level
                    listenError:      BpmListener.error
                    onListenSourceSet: page0State.listenSource = idx
                    listenFactor:     page0State.listenFactor
                    onListenFactorSet: {
                        page0State.listenFactor = factor
                        app.applyDetectedTempo()
                    }
                }

                // Stats cycler overlay over the top of the BPM page
                MouseArea {
                    anchors.top:    parent.top
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    height:         Dims.h(20)
                    z: 100
                    onClicked: page0.statsCycleTap++
                }
            }
        }
    }

    Component {
        id: metronomeTab
        TabItem {
            // the tab view sizes each tab by its implicit size
            implicitWidth: tabs.width
            implicitHeight: tabs.height - tabs.tabBarHeight

            MetronomePage {
                anchors.fill:   parent
                pageActive:     app.currentTab === 1
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
        }
    }

    Component {
        id: forkTab
        TabItem {
            // the tab view sizes each tab by its implicit size
            implicitWidth: tabs.width
            implicitHeight: tabs.height - tabs.tabBarHeight

            TuningForkPage {
                anchors.fill: parent
                pageActive:   app.currentTab === 2
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
}
