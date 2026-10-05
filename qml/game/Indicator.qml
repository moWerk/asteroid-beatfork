/*
 * Copyright (C) 2026 - Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
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
import "."

// Stand-in for Indicator of org.asteroid.controls: a small diamond at one
// edge that hints at more content in that direction. animate() pulses it
// in from the edge; keepExpanded leaves it visible.
Item {
    id: ind
    property int edge: Qt.TopEdge
    property bool keepExpanded: false
    readonly property real finWidth: Dims.l(3)

    function animate()    { pulse.restart() }
    function animateFar() { pulse.restart() }

    anchors.fill: parent

    Rectangle {
        id: diamond
        width: ind.finWidth
        height: width
        rotation: 45
        color: "white"
        opacity: ind.keepExpanded ? 0.8 : 0
        x: ind.edge === Qt.LeftEdge  ? ind.finWidth * 0.6
         : ind.edge === Qt.RightEdge ? parent.width - width - ind.finWidth * 0.6
         : (parent.width - width) / 2
        y: ind.edge === Qt.TopEdge    ? ind.finWidth * 0.6
         : ind.edge === Qt.BottomEdge ? parent.height - height - ind.finWidth * 0.6
         : (parent.height - height) / 2
    }

    SequentialAnimation {
        id: pulse
        NumberAnimation { target: diamond; property: "opacity"; to: 0.9; duration: 250 }
        PauseAnimation  { duration: 600 }
        NumberAnimation { target: diamond; property: "opacity"; to: ind.keepExpanded ? 0.8 : 0; duration: 500 }
    }
}
