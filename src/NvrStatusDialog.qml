import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import CCTV_Viewer.Hikvision 1.0
import QtQuick.Window 2.12

Dialog {
    id: nvrStatusDialog
    modal: true
    anchors.centerIn: parent
    width: 520
    height: Math.min(Math.max(implicitHeight, 380), Screen.height * 0.85)

    leftPadding: 16
    rightPadding: 16
    topPadding: 16
    bottomPadding: 16

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
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Status rejestratorów")
            color: "#00f5d4"
            font.bold: true
            font.pixelSize: 13
        }
    }

    contentItem: ColumnLayout {
        spacing: 12

        // Checking / Loading State Indicator
        RowLayout {
            visible: NvrStatusManager.isChecking
            Layout.fillWidth: true
            spacing: 8
            Layout.alignment: Qt.AlignHCenter

            BusyIndicator {
                id: checkingSpinner
                running: NvrStatusManager.isChecking
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
            }

            Text {
                text: qsTr("Trwa sprawdzanie stanu rejestratorów...")
                color: "#8898a6"
                font.pixelSize: 11
            }
        }

        // List Frame when recorders are present
        Frame {
            visible: recorderListView.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: recorderListView.contentHeight + topPadding + bottomPadding
            background: Rectangle {
                color: "#0f151b"
                border.color: "#2a3540"
                border.width: 1
                radius: 6
            }
            padding: 6

            ListView {
                id: recorderListView
                anchors.fill: parent
                clip: true
                model: NvrStatusManager.checkedRecorders
                spacing: 8

                delegate: Rectangle {
                    width: recorderListView.width
                    implicitHeight: recorderColumn.implicitHeight + 20
                    color: "#1c242c"
                    border.color: modelData.hasError ? "#ff4d4d" : "#2a3540"
                    border.width: 1
                    radius: 6

                    ColumnLayout {
                        id: recorderColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Status Dot
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.hasError ? "#ff4d4d" : "#22c55e"
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    text: modelData.name + " (" + modelData.ip + ")"
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 11
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: qsTr("Ostatnie sprawdzenie: ") + (modelData.lastCheck ? modelData.lastCheck : qsTr("brak"))
                                    color: "#8898a6"
                                    font.pixelSize: 10
                                    Layout.fillWidth: true
                                }
                            }

                            // OK / BŁĄD Badge
                            Rectangle {
                                width: 54
                                height: 20
                                radius: 4
                                color: modelData.hasError ? "#33ff4d4d" : "#3322c55e"
                                border.color: modelData.hasError ? "#ff4d4d" : "#22c55e"
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.hasError ? qsTr("BŁĄD") : qsTr("OK")
                                    color: modelData.hasError ? "#ff4d4d" : "#22c55e"
                                    font.bold: true
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Specific recorder errors
                        Repeater {
                            model: modelData.hasError ? modelData.errors : []
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 18
                                spacing: 6

                                Text {
                                    text: "•"
                                    color: "#ff4d4d"
                                    font.bold: true
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: modelData.target ? (modelData.target + ": " + modelData.details) : modelData.details
                                    color: "#ff4d4d"
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                ScrollIndicator.vertical: ScrollIndicator {}
            }
        }

        // Placeholder State when there are no records
        ColumnLayout {
            visible: recorderListView.count === 0 && !NvrStatusManager.isChecking
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 48
                height: 48
                radius: 24
                color: "#0f151b"
                border.color: "#2a3540"
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    text: "i"
                    color: "#8898a6"
                    font.bold: true
                    font.pixelSize: 24
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Brak danych o statusie")
                color: "white"
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Naciśnij przycisk poniżej, aby sprawdzić status rejestratorów.")
                color: "#8898a6"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    footer: Rectangle {
        implicitHeight: 48
        color: "#0f151b"
        border.color: "#2a3540"
        border.width: 1
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

            Button {
                id: checkNowBtn
                text: qsTr("Sprawdź teraz")
                Layout.preferredWidth: 140
                Layout.preferredHeight: 30
                enabled: !NvrStatusManager.isChecking

                contentItem: Text {
                    text: checkNowBtn.text
                    font.bold: true
                    color: checkNowBtn.enabled ? "white" : "#8898a6"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: checkNowBtn.pressed ? "#1a2530" : (checkNowBtn.hovered ? "#2d3a4a" : "#1c242c")
                    radius: 4
                    border.color: "#ff7a00"
                    border.width: 1
                }
                onClicked: {
                    NvrStatusManager.checkNow();
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                id: closeBtn
                text: qsTr("Zamknij")
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
                    color: closeBtn.pressed ? "#2a3540" : (closeBtn.hovered ? "#3a4550" : "#222c36")
                    radius: 4
                    border.color: "#2a3540"
                    border.width: 1
                }
                onClicked: nvrStatusDialog.close()
            }
        }
    }
}
