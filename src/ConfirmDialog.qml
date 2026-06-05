import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

Dialog {
    id: rootDialog
    modal: true
    anchors.centerIn: parent
    width: 380

    leftPadding: 16
    rightPadding: 16
    topPadding: 16
    bottomPadding: 16

    property string message: ""
    property string iconSource: "qrc:/images/icon-warning.svg"
    property string confirmButtonText: qsTr("Yes")
    property string cancelButtonText: qsTr("No")
    property bool isDanger: true

    background: Rectangle {
        color: "#1c242c"
        border.color: "#2a3540"
        border.width: 1
        radius: 8
    }

    header: Rectangle {
        color: "#0f151b"
        height: 42
        implicitHeight: 42
        radius: 8

        // Prevent bottom corners from rounding in the header
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 4
            color: "#0f151b"
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: "#2a3540"
        }

        Text {
            anchors.fill: parent
            anchors.leftMargin: 16
            text: rootDialog.title
            color: "#00f5d4"
            font.bold: true
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
    }

    contentItem: RowLayout {
        spacing: 16

        Image {
            source: rootDialog.iconSource
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            fillMode: Image.PreserveAspectFit
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: rootDialog.message
            color: "white"
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    footer: Rectangle {
        implicitHeight: 48
        color: "#0f151b"
        border.color: "#2a3540"
        border.width: 1

        // Round only bottom corners
        radius: 8
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 4
            color: "#0f151b"
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Item { Layout.fillWidth: true }

            Button {
                id: cancelBtn
                text: rootDialog.cancelButtonText
                Layout.preferredWidth: 80
                Layout.preferredHeight: 30

                contentItem: Text {
                    text: cancelBtn.text
                    font.bold: true
                    color: cancelBtn.pressed ? "#8898a6" : "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: cancelBtn.pressed ? "#2a3540" : (cancelBtn.hovered ? "#3a4550" : "#222c36")
                    radius: 4
                    border.color: "#2a3540"
                }
                onClicked: rootDialog.reject()
            }

            Button {
                id: confirmBtn
                text: rootDialog.confirmButtonText
                Layout.preferredWidth: 80
                Layout.preferredHeight: 30

                contentItem: Text {
                    text: confirmBtn.text
                    font.bold: true
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: confirmBtn.pressed ? (rootDialog.isDanger ? "#cc2929" : "#00ccb0") : (confirmBtn.hovered ? (rootDialog.isDanger ? "#ff4d4d" : "#00ffd8") : (rootDialog.isDanger ? "#d63333" : "#00f5d4"))
                    radius: 4
                }
                onClicked: rootDialog.accept()
            }
        }
    }
}
