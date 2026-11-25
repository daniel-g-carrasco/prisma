// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls.Basic
import Casa.Controls as C
import Casa.Theme

ApplicationWindow {
    id: window

    required property string statusTitle
    required property string statusDescription

    visible: true
    width: Theme.size.READING + 4 * Theme.space.XL
    height: Math.round(width * 0.65)
    color: Theme.colors.window

    C.EmptyState {
        anchors.fill: parent
        title: window.statusTitle
        description: window.statusDescription
    }
}
