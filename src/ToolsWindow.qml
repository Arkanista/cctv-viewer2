import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt.labs.settings 1.0
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Themes 1.0
import CCTV_Viewer.Utils 1.0

Window {
    id: toolsWindow
    title: qsTr("Layout & Grid Tools")
    width: 380
    height: 600
    color: "#0f151b"
    x: rootWindow.x + (rootWindow.width - width) / 2
    y: rootWindow.y + (rootWindow.height - height) / 2

    Settings {
        id: sideBarSettings
        fileName: Context.config.fileName
        category: "SideBar"
        property string windowDivision
    }

    ScrollView {
        id: page1ScrollView
        anchors.fill: parent
        anchors.margins: 16
        clip: true

        ColumnLayout {
            id: page1Layout
            width: page1ScrollView.width - 10
            spacing: 20

            Text {
                text: qsTr("Layout & Grid Tools")
                color: "#00f5d4"
                font {
                    pixelSize: 16
                    bold: true
                }
            }

            Switch {
                id: toolsUnlockSwitch
                text: qsTr("Unlock tools pane")
                checked: false
                Layout.fillWidth: true
                
                indicator: Rectangle {
                    implicitWidth: 40
                    implicitHeight: 20
                    x: toolsUnlockSwitch.leftPadding
                    y: parent.height / 2 - height / 2
                    radius: 10
                    color: toolsUnlockSwitch.checked ? "#ff7a00" : "#1c242c"
                    border.color: toolsUnlockSwitch.checked ? "#ff9e00" : "#2a3540"
                    border.width: 1

                    Rectangle {
                        x: toolsUnlockSwitch.checked ? parent.width - width - 2 : 2
                        y: 2
                        width: 16
                        height: 16
                        radius: 8
                        color: "white"
                        
                        Behavior on x {
                            NumberAnimation { duration: 150 }
                        }
                    }
                }
                
                contentItem: Text {
                    text: toolsUnlockSwitch.text
                    font.pixelSize: 12
                    font.bold: true
                    color: toolsUnlockSwitch.checked ? "#ff7a00" : "#a0aec0"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: toolsUnlockSwitch.indicator.width + toolsUnlockSwitch.spacing
                }
            }

            GroupBox {
                title: qsTr("Window Division")
                enabled: toolsUnlockSwitch.checked && !(Utils.currentLayout().fullScreenIndex >= 0)
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

                GridLayout {
                    columns: 3
                    anchors.fill: parent
                    rowSpacing: 8
                    columnSpacing: 8

                    ListModel {
                        id: divisionModel

                        ListElement { size: "1x1" }
                        ListElement { size: "2x2" }
                        ListElement { size: "3x3" }
                        ListElement { size: "4x4" }
                        ListElement { size: "5x5" }
                        ListElement { size: "6x6" }
                        ListElement { size: "7x7" }
                        ListElement { size: "8x8" }
                        ListElement { size: "9x9" }

                        Component.onCompleted: {
                            fromJSValue(sideBarSettings.windowDivision);
                            divisionModel.dataChanged.connect(() => {
                                sideBarSettings.windowDivision = JSON.stringify(toJSValue());
                            });
                        }

                        function fromJSValue(model) {
                            var arr;
                            try {
                                if (!model.isEmpty()) {
                                    arr = JSON.parse(model);
                                }
                            } catch(err) {
                                Utils.log_error(qsTr("Error reading configuration!"));
                            }

                            if (arr instanceof Array) {
                                for (var i = 0; i < arr.length; ++i) {
                                    divisionModel.set(i, arr[i]);
                                }
                            }
                        }

                        function toJSValue() {
                            var arr = [];
                            for (var i = 0; i < divisionModel.count; ++i) {
                                arr[i] = divisionModel.get(i);
                            }
                            return arr;
                        }
                    }

                    Repeater {
                        model: divisionModel
                        delegate: Item {
                            id: divisionItem
                            implicitWidth: 100
                            implicitHeight: 36
                            Layout.fillWidth: true

                            Keys.onEscapePressed: {
                                event.accepted = divisionTextField.visible;
                                divisionTextField.cancel();
                            }
                            Keys.onPressed: {
                                if (event.key === Qt.Key_F2) {
                                    divisionTextField.edit();
                                }
                            }

                             Button {
                                id: gridCellBtn
                                text: size
                                highlighted: Utils.currentModel() && Utils.currentModel().size === str2size(size)
                                enabled: !generalSettings.lockGridSize
                                anchors.fill: parent
                                onClicked: {
                                    if (Utils.currentModel()) {
                                        Utils.currentModel().size = str2size(size);
                                    }
                                }
                                onPressAndHold: divisionTextField.edit()

                                background: Rectangle {
                                    color: gridCellBtn.pressed ? "#cc121214" : (gridCellBtn.highlighted ? "#ff7a00" : (gridCellBtn.hovered ? "#3a4550" : "#1c242c"))
                                    radius: 6
                                    border.color: gridCellBtn.highlighted ? "#ff9e00" : (gridCellBtn.hovered ? "#8898a6" : "#2a3540")
                                    border.width: 1
                                    opacity: gridCellBtn.enabled ? 1.0 : 0.4
                                }
                                contentItem: Text {
                                    text: gridCellBtn.text
                                    color: gridCellBtn.enabled ? (gridCellBtn.highlighted ? "#ffffff" : (gridCellBtn.hovered ? "#ffffff" : "#a0aec0")) : "#555555"
                                    font.bold: gridCellBtn.highlighted
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                ToolTip.delay: Compact.toolTipDelay
                                ToolTip.timeout: Compact.toolTipTimeout
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Hold to edit division value")
                            }

                            TextField {
                                id: divisionTextField
                                visible: false
                                anchors.fill: parent
                                horizontalAlignment: TextInput.AlignHCenter
                                selectByMouse: true
                                onEditingFinished: {
                                    visible = false;
                                    if(str2size(text)) {
                                        size = text;
                                    }
                                }

                                function edit() {
                                    text = size;
                                    visible = true;
                                    forceActiveFocus();
                                }
                                function cancel() {
                                    text = size;
                                    visible = false;
                                }
                            }

                            function str2size(str) {
                                var separatorTr = qsTr("x");
                                var regexp = new RegExp("^[1-9][x%1][1-9]$".arg(separatorTr));
                                if (regexp.test(str)) {
                                    var size = str.split(new RegExp("[x%1]".arg(separatorTr)));
                                    return Qt.size(size[0], size[1]);
                                }
                                return null;
                            }
                        }
                    }
                }
            }

            GroupBox {
                title: qsTr("Geometry Ratio")
                enabled: toolsUnlockSwitch.checked
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

                    RowLayout {
                        spacing: 12
                        Layout.fillWidth: true

                        Button {
                            id: btn16_9
                            text: qsTr("16:9 Aspect Ratio")
                            highlighted: Utils.currentModel() && Utils.currentModel().aspectRatio === Qt.size(16, 9)
                            Layout.fillWidth: true
                            onClicked: {
                                if (Utils.currentModel()) {
                                    Utils.currentModel().aspectRatio = Qt.size(16, 9);
                                    rootWindow.setRootWindowRatio(Utils.currentModel().aspectRatio);
                                }
                            }
                            background: Rectangle {
                                color: btn16_9.pressed ? "#cc121214" : (btn16_9.highlighted ? "#00b4d8" : (btn16_9.hovered ? "#3a4550" : "#1c242c"))
                                radius: 6
                                border.color: btn16_9.highlighted ? "#00f5d4" : (btn16_9.hovered ? "#8898a6" : "#2a3540")
                                border.width: 1
                            }
                            contentItem: Text {
                                text: btn16_9.text
                                color: btn16_9.highlighted ? "#ffffff" : (btn16_9.hovered ? "#ffffff" : "#a0aec0")
                                font.bold: btn16_9.highlighted
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Button {
                            id: btn4_3
                            text: qsTr("4:3 Aspect Ratio")
                            highlighted: Utils.currentModel() && Utils.currentModel().aspectRatio === Qt.size(4, 3)
                            Layout.fillWidth: true
                            onClicked: {
                                if (Utils.currentModel()) {
                                    Utils.currentModel().aspectRatio = Qt.size(4, 3);
                                    rootWindow.setRootWindowRatio(Utils.currentModel().aspectRatio);
                                }
                            }
                            background: Rectangle {
                                color: btn4_3.pressed ? "#cc121214" : (btn4_3.highlighted ? "#00b4d8" : (btn4_3.hovered ? "#3a4550" : "#1c242c"))
                                radius: 6
                                border.color: btn4_3.highlighted ? "#00f5d4" : (btn4_3.hovered ? "#8898a6" : "#2a3540")
                                border.width: 1
                            }
                            contentItem: Text {
                                text: btn4_3.text
                                color: btn4_3.highlighted ? "#ffffff" : (btn4_3.hovered ? "#ffffff" : "#a0aec0")
                                font.bold: btn4_3.highlighted
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Button {
                        id: btnFullScreen
                        text: qsTr("Toggle Full Screen")
                        highlighted: Context.config.fullScreen
                        Layout.fillWidth: true
                        onClicked: Context.config.fullScreen = !Context.config.fullScreen
                        background: Rectangle {
                            color: btnFullScreen.pressed ? "#cc121214" : (btnFullScreen.highlighted ? "#00b4d8" : (btnFullScreen.hovered ? "#3a4550" : "#1c242c"))
                            radius: 6
                            border.color: btnFullScreen.highlighted ? "#00f5d4" : (btnFullScreen.hovered ? "#8898a6" : "#2a3540")
                            border.width: 1
                        }
                        contentItem: Text {
                            text: btnFullScreen.text
                            color: btnFullScreen.highlighted ? "#ffffff" : (btnFullScreen.hovered ? "#ffffff" : "#a0aec0")
                            font.bold: btnFullScreen.highlighted
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            GroupBox {
                title: qsTr("Grid Operations")
                enabled: toolsUnlockSwitch.checked
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

                RowLayout {
                    anchors.fill: parent
                    spacing: 10

                    Button {
                        id: btnMergeCells
                        text: qsTr("Merge Highlighted Cells")
                        enabled: Utils.currentLayout().mergeCells(true)
                        Layout.fillWidth: true
                        onClicked: Utils.currentLayout().mergeCells()
                        background: Rectangle {
                            color: !btnMergeCells.enabled ? "#cc1c242c" : (btnMergeCells.pressed ? "#cc121214" : (btnMergeCells.hovered ? "#059669" : "#10b981"))
                            radius: 6
                            border.color: !btnMergeCells.enabled ? "#2a3540" : (btnMergeCells.hovered ? "#34d399" : "#059669")
                            border.width: 1
                            opacity: btnMergeCells.enabled ? 1.0 : 0.4
                        }
                        contentItem: Text {
                            text: btnMergeCells.text
                            color: btnMergeCells.enabled ? "#ffffff" : "#4a5568"
                            font.bold: btnMergeCells.enabled
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
