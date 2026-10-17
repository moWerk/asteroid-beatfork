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
import Sailfish.Silica 1.0
import "game" as Game

ApplicationWindow {
    id: app

    // The watch has Noto Sans Condensed system wide; here it comes with the
    // app. Qt files the three cuts as family "Noto Sans" with the styles
    // "Condensed", "Condensed SemiBold" and "Condensed Bold", so they are
    // asked for by family and styleName.
    FontLoader { source: "game/fonts/NotoSans-Condensed.ttf" }
    FontLoader { source: "game/fonts/NotoSans-CondensedSemiBold.ttf" }
    FontLoader { source: "game/fonts/NotoSans-CondensedBold.ttf" }

    allowedOrientations: Orientation.Portrait

    initialPage: Component {
        Page {
            id: page

            allowedOrientations: Orientation.Portrait

            Loader {
                id: gameLoader
                anchors.fill: parent
                active: false
                source: "game/main.qml"
            }

            // The pages read their scale once at start, so the size has to
            // be known before they are loaded. Laid out for a square watch:
            // sizes follow the width.
            onStatusChanged: {
                if (status === PageStatus.Active && !gameLoader.active) {
                    Game.Dims.width = page.width
                    Game.Dims.height = page.width
                    gameLoader.active = true
                }
            }

            Binding { target: app; property: "game"; value: gameLoader.item }
        }
    }

    property Item game: null

    cover: Component {
        CoverBackground {
            Column {
                anchors.centerIn: parent
                spacing: Theme.paddingSmall

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.game ? app.game.bpm : ""
                    color: Theme.highlightColor
                    font { family: "Noto Sans"; styleName: "Condensed SemiBold"; pixelSize: Theme.fontSizeHuge * 1.5 }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "BPM"
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            Label {
                anchors {
                    bottom: parent.bottom
                    bottomMargin: Theme.paddingLarge
                    horizontalCenter: parent.horizontalCenter
                }
                text: "BeatFork"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
