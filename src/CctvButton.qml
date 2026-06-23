import QtQuick 2.12
import QtQuick.Controls 2.12

Button {
    id: control
    property bool isPrimary: false
    property bool isSmall: false
    property string iconSource: ""
    
    implicitHeight: isSmall ? 30 : 32
    
    // Add extra padding for pill shape if it contains both text and icon
    leftPadding: text !== "" ? (iconSource !== "" ? 12 : 14) : 8
    rightPadding: text !== "" ? 14 : 8

    contentItem: Row {
        spacing: 4
        anchors.centerIn: parent
        
        Image {
            source: control.iconSource
            visible: control.iconSource !== ""
            width: control.isSmall ? 12 : 16
            height: control.isSmall ? 12 : 16
            sourceSize: Qt.size(width, height)
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Text {
            text: control.text
            visible: control.text !== ""
            font.bold: true
            font.pixelSize: control.isSmall ? 10 : 13
            color: "white"
            verticalAlignment: Text.AlignVCenter
        }
    }

    background: Rectangle {
        color: control.pressed
            ? (control.isPrimary ? "#d66600" : "#cc121214")
            : (control.hovered
                ? (control.isPrimary ? "#ff8c00" : "#3a4550")
                : (control.isPrimary ? "#ff7a00" : "#1c242c"))
        radius: 15
        border.color: control.hovered
            ? (control.isPrimary ? "#ff9e00" : "#8898a6")
            : (control.isPrimary ? "#ff7a00" : "#2a3540")
        border.width: 1
    }
}
