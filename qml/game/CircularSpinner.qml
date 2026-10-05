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

// Stand-in for CircularSpinner of org.asteroid.controls: a vertical,
// wrapping PathView with the current item in the middle. The AsteroidOS
// version fades the ends with a Qt 6 shader; here the delegates fade.
PathView {
    id: pv
    property alias showSeparator: separator.visible
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange
    highlightMoveDuration: 0
    snapMode: PathView.SnapToItem
    dragMargin: width / 2
    clip: true
    delegate: SpinnerDelegate { }
    path: Path {
        startX: pv.width / 2; startY: pv.height / 2 - pv.count * Dims.h(6)
        PathLine { x: pv.width / 2; y: pv.height / 2 + pv.count * Dims.h(6) }
    }
    Rectangle {
        id: separator
        width: 1
        height: parent.height * 0.8
        color: "#88FFFFFF"
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        visible: false
    }
}
