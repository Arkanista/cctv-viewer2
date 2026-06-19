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
    color: "#0f151b"
    title: qsTr("CCTV Viewer 2")

    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        RowLayout {
            spacing: 16
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                width: 36
                height: 36
                color: "#1c242c"
                radius: 18
                border.color: "#ffaa00"
                border.width: 1
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: "!"
                    font.bold: true
                    font.pixelSize: 20
                    color: "#ffaa00"
                }
            }

            Text {
                text: qsTr("Program już działa, nie możesz uruchomić drugiego")
                color: "white"
                font.bold: true
                font.pixelSize: 12
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
                id: closeBtn
                text: qsTr("ZAMKNIJ")
                implicitWidth: 100
                implicitHeight: 30
                Layout.alignment: Qt.AlignVCenter

                contentItem: Text {
                    text: closeBtn.text
                    font.bold: true
                    font.pixelSize: 11
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    color: closeBtn.pressed ? "#cc2929" : (closeBtn.hovered ? "#ff4d4d" : "#d63333")
                    radius: 15
                    border.color: closeBtn.hovered ? "#ff8080" : "transparent"
                    border.width: 1
                }

                onClicked: {
                    Qt.quit();
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
