import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

Button {
    id: control
    property bool isPrimary: false
    property bool isCeladon: false
    property bool isSmall: false
    property string iconSource: ""
    
    implicitHeight: isSmall ? 30 : 32
    implicitWidth: text === "" ? implicitHeight : (leftPadding + contentItem.implicitWidth + rightPadding)
    
    // Layout properties to maintain size in layout containers
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.fillWidth: false
    Layout.fillHeight: false
    
    // Add extra padding for pill shape if it contains both text and icon
    leftPadding: text !== "" ? (iconSource !== "" ? 12 : 14) : 0
    rightPadding: text !== "" ? 14 : 0
    topPadding: text !== "" ? 6 : 0
    bottomPadding: text !== "" ? 6 : 0

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        
        Row {
            id: contentRow
            spacing: 4
            anchors.centerIn: parent
            
            Image {
                source: control.iconSource
                visible: control.iconSource !== ""
                width: control.text !== "" ? (control.isSmall ? 12 : 16) : (control.isSmall ? 22 : 24)
                height: control.text !== "" ? (control.isSmall ? 12 : 16) : (control.isSmall ? 22 : 24)
                sourceSize: Qt.size(width, height)
                anchors.verticalCenter: parent.verticalCenter
            }
            
            Text {
                text: control.text
                visible: control.text !== ""
                font.bold: true
                font.pixelSize: control.isSmall ? 10 : 13
                color: control.isCeladon ? "#121214" : "white"
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    background: Rectangle {
        color: control.pressed
            ? (control.isCeladon ? "#00a33c" : (control.isPrimary ? "#d66600" : "#cc121214"))
            : (control.hovered
                ? (control.isCeladon ? "#00ff77" : (control.isPrimary ? "#ff8c00" : "#3a4550"))
                : (control.isCeladon ? "#00e676" : (control.isPrimary ? "#ff7a00" : "#1c242c")))
        radius: height / 2
        border.color: control.hovered
            ? (control.isCeladon ? "#00ff99" : (control.isPrimary ? "#ff9e00" : "#8898a6"))
            : (control.isCeladon ? "#00e676" : (control.isPrimary ? "#ff7a00" : "#2a3540"))
        border.width: 1
    }
}
