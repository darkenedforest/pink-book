import QtQuick

Rectangle {
    id: control
    property string label
    property bool marked: false
    property real unit: 1
    property color ink: "#25221f"
    signal clicked()
    implicitWidth: Math.max(50 * unit, caption.implicitWidth + 26 * unit)
    implicitHeight: 42 * unit
    radius: 6 * unit
    color: !enabled ? "#f2efea" : (tap.pressed || marked ? ink : "#faf8f3")
    border.color: !enabled ? "#dbd4ca" : (activeFocus ? "#824638" : ink)
    border.width: activeFocus ? 2 : 1
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: if (enabled) clicked()
    Keys.onSpacePressed: if (enabled) clicked()
    Keys.onReturnPressed: if (enabled) clicked()

    Text {
        id: caption
        anchors.centerIn: parent
        text: control.label
        color: !control.enabled ? "#625b54" : (tap.pressed || control.marked ? "#ffffff" : control.ink)
        font.pixelSize: 14 * control.unit
        font.bold: control.marked
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        onClicked: control.clicked()
    }
}
