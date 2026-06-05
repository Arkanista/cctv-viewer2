import QtQuick 2.12
import QtQuick.Controls 2.12

Button {
    id: control
    property bool isPrimary: false
    property bool isSmall: false
    property string iconSource: ""
    
    implicitHeight: isSmall ? 22 : 32
    
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
        color: control.pressed ? (control.isPrimary ? "#d66600" : "#404040") : 
               (control.hovered ? (control.isPrimary ? "#ff8c00" : "#505050") : 
               (control.isPrimary ? "#ff7a00" : "#303030"))
        radius: 4
    }
}
