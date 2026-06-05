import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import CCTV_Viewer.Utils 1.0

Dialog {
    id: viewportSettingsDialog
    title: qsTr("Viewport Settings")
    modal: true
    anchors.centerIn: parent
    width: 420

    leftPadding: 16
    rightPadding: 16
    topPadding: 16
    bottomPadding: 16

    property int index: -1

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
            text: viewportSettingsDialog.title + (index >= 0 ? " #" + (index + 1) : "")
            color: "#00f5d4"
            font.bold: true
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
    }

    onVisibleChanged: {
        if (visible) {
            loadSettings();
        }
    }

    contentItem: ColumnLayout {
        spacing: 16

        // Camera Streams Configuration
        GroupBox {
            title: qsTr("Active Stream Connection")
            Layout.fillWidth: true

            background: Rectangle {
                color: "#141a21"
                border.color: "#2a3540"
                border.width: 1
                radius: 8
            }
            label: Text {
                text: parent.title
                color: "#00f5d4"
                font.bold: true
                font.pixelSize: 12
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true
                    Label {
                        text: qsTr("Primary Stream URL")
                        color: "#8898a6"
                        font.pixelSize: 11
                    }
                    TextField {
                        id: primaryUrlField
                        selectByMouse: true
                        Layout.fillWidth: true
                        color: "white"
                        font.pixelSize: 12
                        placeholderText: "rtsp://..."
                        background: Rectangle {
                            color: "#0f151b"
                            radius: 4
                            border.color: primaryUrlField.activeFocus ? "#ff7a00" : "#2a3540"
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true
                    Label {
                        text: qsTr("Secondary Backup URL")
                        color: "#8898a6"
                        font.pixelSize: 11
                    }
                    TextField {
                        id: secondaryUrlField
                        selectByMouse: true
                        Layout.fillWidth: true
                        color: "white"
                        font.pixelSize: 12
                        placeholderText: "rtsp://..."
                        background: Rectangle {
                            color: "#0f151b"
                            radius: 4
                            border.color: secondaryUrlField.activeFocus ? "#ff7a00" : "#2a3540"
                        }
                    }
                }
            }
        }

        // Global Viewport Settings
        GroupBox {
            title: qsTr("Global Options")
            Layout.fillWidth: true

            background: Rectangle {
                color: "#141a21"
                border.color: "#2a3540"
                border.width: 1
                radius: 8
            }
            label: Text {
                text: parent.title
                color: "#00f5d4"
                font.bold: true
                font.pixelSize: 12
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                CheckBox {
                    id: unmuteWhenFullScreenCheckBox
                    text: qsTr("Unmute when the viewport is in full screen mode")
                    palette.highlight: "#00f5d4"
                    Layout.fillWidth: true
                    
                    contentItem: Text {
                        text: unmuteWhenFullScreenCheckBox.text
                        font.pixelSize: 12
                        color: "white"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: unmuteWhenFullScreenCheckBox.indicator.width + unmuteWhenFullScreenCheckBox.spacing
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Label {
                        text: qsTr("Default FFmpeg options")
                        color: "#8898a6"
                        font.pixelSize: 11
                    }

                    TextField {
                        id: defaultAVFormatOptions
                        selectByMouse: true
                        Layout.fillWidth: true
                        color: "white"
                        font.pixelSize: 12
                        background: Rectangle {
                            color: "#0f151b"
                            radius: 4
                            border.color: defaultAVFormatOptions.activeFocus ? "#ff7a00" : "#2a3540"
                        }
                    }
                }
            }
        }
    }

    footer: Rectangle {
        implicitHeight: 48
        color: "#0f151b"
        border.color: "#2a3540"
        border.width: 1
        radius: 8

        // Round only bottom corners
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
                text: qsTr("Cancel")
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
                onClicked: viewportSettingsDialog.reject()
            }

            Button {
                id: confirmBtn
                text: qsTr("Save")
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
                    color: confirmBtn.pressed ? "#00ccb0" : (confirmBtn.hovered ? "#00ffd8" : "#00f5d4")
                    radius: 4
                }
                onClicked: {
                    saveSettings();
                    viewportSettingsDialog.accept();
                }
            }
        }
    }

    function loadSettings() {
        if (index >= 0) {
            var item = Utils.currentModel().get(index);
            if (item) {
                primaryUrlField.text = item.url;
                secondaryUrlField.text = item.secondaryUrl;
            }
        } else {
            primaryUrlField.text = "";
            secondaryUrlField.text = "";
        }

        unmuteWhenFullScreenCheckBox.checked = viewportSettings.unmuteWhenFullScreen;

        defaultAVFormatOptions.text = "";
        var options = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");
        for (var key in options) {
            if (typeof options[key] === "string" || typeof options[key] === "number") {
                defaultAVFormatOptions.text += "-%1 %2 ".arg(key).arg(options[key]);
            }
        }
        defaultAVFormatOptions.text = defaultAVFormatOptions.text.trim();
    }

    function saveSettings() {
        if (index >= 0) {
            var item = Utils.currentModel().get(index);
            if (item) {
                item.url = primaryUrlField.text;
                item.secondaryUrl = secondaryUrlField.text;
            }
        }
        viewportSettings.unmuteWhenFullScreen = unmuteWhenFullScreenCheckBox.checked;
        layoutsCollectionSettings.defaultAVFormatOptions = JSON.stringify(Utils.parseOptions(defaultAVFormatOptions.text));
    }
}
