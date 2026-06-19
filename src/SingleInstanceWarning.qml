import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

Window {
    id: warningWindow
    visible: true
    width: 380
    height: 150
    minimumWidth: 380
    minimumHeight: 150
    maximumWidth: 380
    maximumHeight: 150
    color: "#1c242c"
    title: qsTr("CCTV Viewer 2")

    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            height: 42
            color: "#0f151b"

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: "#2a3540"
            }

            Text {
                anchors.fill: parent
                anchors.leftMargin: 16
                text: warningWindow.title
                color: "#00f5d4"
                font.bold: true
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Content
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 16

            Image {
                source: "qrc:/images/icon-warning.svg"
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                fillMode: Image.PreserveAspectFit
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: qsTr("Program już działa, nie możesz uruchomić drugiego")
                color: "white"
                font.pixelSize: 12
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Footer
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: "#0f151b"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: "#2a3540"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 8
                anchors.bottomMargin: 8

                Item { Layout.fillWidth: true }

                Button {
                    id: closeBtn
                    text: qsTr("ZAMKNIJ")
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 30

                    contentItem: Text {
                        text: closeBtn.text
                        font.bold: true
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: closeBtn.pressed ? "#cc2929" : (closeBtn.hovered ? "#ff4d4d" : "#d63333")
                        radius: 4
                    }

                    onClicked: {
                        Qt.quit();
                    }
                }
            }
        }
    }
}
