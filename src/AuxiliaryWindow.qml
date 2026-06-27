import QtQml 2.12
import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Models 1.0
import CCTV_Viewer.Themes 1.0

Window {
    id: auxWindow

    title: qsTr("KVision - Okno pomocnicze") + " " + Qt.application.version
    width: 800
    height: 600
    color: "#0f151b"

    property bool closeAccepted: false

    onClosing: {
        if (!closeAccepted) {
            close.accepted = false;
            quitConfirmDialog.open();
        }
    }

    property var layoutsModel
    property var generalSettings
    property var layoutsCollectionSettings
    property var sidebarWindow
    property var toolsWindow

    property int initialLayoutIndex: -1
    property int initialVisibility: Window.Windowed

    property alias layoutRepeater: layoutRepeater
    property alias stackLayout: stackLayout
    property alias layoutIndex: stackLayout.currentIndex
    property var selectedLayoutModel: null

    onLayoutIndexChanged: {
        if (layoutIndex >= 0 && layoutIndex < layoutsModel.count) {
            selectedLayoutModel = layoutsModel.get(layoutIndex);
        } else {
            selectedLayoutModel = null;
        }
    }

    onActiveChanged: {
        if (active) {
            rootWindow.activeLayoutWindow = auxWindow;
        }
    }

    Component.onCompleted: {
        visibility = initialVisibility;
        if (initialLayoutIndex >= 0 && initialLayoutIndex < layoutsModel.count) {
            layoutIndex = initialLayoutIndex;
        } else {
            layoutIndex = -1;
        }
    }

    function changeGridSize(gridSize) {
        if (selectedLayoutModel) {
            selectedLayoutModel.size = Qt.size(gridSize, gridSize);
        }
    }

    Shortcut {
        sequence: "M"
        onActivated: {
            var activeLayout = Utils.currentLayout();
            if (selectedLayoutModel && activeLayout && activeLayout.focusIndex >= 0) {
                var item = selectedLayoutModel.get(activeLayout.focusIndex);
                var viewport = activeLayout.get(activeLayout.focusIndex);

                if (viewport.hasAudio) {
                    if (item.volume > 0) {
                        item.volume = 0;
                    } else {
                        item.volume = 1;
                    }
                }
            }
        }
    }

    Shortcut {
        sequences: ["F11", StandardKey.FullScreen]
        onActivated: {
            if (visibility === Window.FullScreen) {
                visibility = Window.Windowed;
            } else {
                visibility = Window.FullScreen;
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: rootWindow.openAuxiliaryWindow()
    }

    // Viewports Grid or Placeholder (fills the window)
    Item {
        anchors.fill: parent

        // Placeholder when no view is selected
        Rectangle {
            anchors.fill: parent
            color: "#0f151b"
            visible: auxWindow.layoutIndex === -1

            // Seledynowa ramka wewnątrz pustego pola (matching the archive viewport placeholder style)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 16
                color: "transparent"
                border.color: "#00f5d4"
                border.width: 1.5
                radius: 8
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Image {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    Layout.alignment: Qt.AlignHCenter
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='3' width='20' height='14' rx='2' ry='2'></rect><line x1='8' y1='21' x2='16' y2='21'></line><line x1='12' y1='17' x2='12' y2='21'></line></svg>"
                }

                Text {
                    text: qsTr("Nie wybrano widoku, wybierz widok")
                    color: "#00f5d4"
                    font.bold: true
                    font.pixelSize: 18
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: qsTr("Wybierz widok z menu na górnym pasku, aby rozpocząć wyświetlanie kamer.")
                    color: "#8898a6"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // Viewports Layout inside StackLayout
        StackLayout {
            id: stackLayout
            anchors.fill: parent
            visible: auxWindow.layoutIndex !== -1

            Repeater {
                id: layoutRepeater
                model: layoutsModel

                ViewportsLayout {
                    model: layoutModel
                    focus: true
                }
            }
        }
    }

    // --- Absolute positioned hover-slide toolbar ---

    Timer {
        id: keepVisibleTimer
        interval: 350
        repeat: false
    }

    // Hover area at the very top edge of the window to slide down the top bar
    MouseArea {
        id: hoverArea
        height: 12
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        hoverEnabled: true
        z: 99999
        onContainsMouseChanged: {
            if (containsMouse) {
                keepVisibleTimer.stop();
            } else if (!topToolBarMouseArea.containsMouse) {
                keepVisibleTimer.start();
            }
        }
    }

    // Sleek premium horizontal top bar for settings and grid layout options
    Rectangle {
        id: topToolBar
        height: 44
        anchors.left: parent.left
        anchors.right: parent.right
        color: "#cc121214"
        z: 9999

        // Slide animation based on hover states of the top edge or the bar itself
        y: (hoverArea.containsMouse || topToolBarMouseArea.containsMouse || keepVisibleTimer.running) ? 0 : -height

        Behavior on y {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: "#2a3540"
            z: 10
        }

        MouseArea {
            id: topToolBarMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: {
                if (containsMouse) {
                    keepVisibleTimer.stop();
                } else if (!hoverArea.containsMouse) {
                    keepVisibleTimer.start();
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Button {
                    id: quitButton
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    contentItem: Text {
                        text: "✕"
                        font.bold: true
                        font.pixelSize: 14
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: quitButton.pressed ? "#cc2929" : (quitButton.hovered ? "#ff4d4d" : "#d63333")
                        radius: 15
                    }

                    onClicked: {
                        quitConfirmDialog.open();
                    }
                }

                Button {
                    id: optionsButton
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var colorStr = optionsButton.hovered ? "%23ff9e00" : "%23ff7a00";
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='3'></circle><path d='M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z'></path></svg>";
                        }
                    }

                    background: Rectangle {
                        color: optionsButton.pressed ? "#cc121214" : (optionsButton.hovered ? "#3a4550" : "#1c242c")
                        radius: 15
                        border.color: optionsButton.hovered ? "#ff9e00" : "#2a3540"
                        border.width: 1
                    }

                    onClicked: {
                        if (sidebarWindow) {
                            sidebarWindow.visible = !sidebarWindow.visible;
                            if (sidebarWindow.visible) {
                                sidebarWindow.raise();
                                sidebarWindow.requestActivate();
                            }
                        }
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: optionsButton.hovered
                    ToolTip.text: qsTr("Opcje i ustawienia panelu bocznego")
                }

                Button {
                    id: newWindowButton
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var colorStr = newWindowButton.hovered ? "%23c084fc" : "%23a855f7";
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='3' width='14' height='12' rx='2' ry='2'></rect><path d='M8 21h8'></path><path d='M12 17v4'></path><path d='M22 8v10a2 2 0 0 1-2 2H10'></path></svg>";
                        }
                    }

                    background: Rectangle {
                        color: newWindowButton.pressed ? "#cc121214" : (newWindowButton.hovered ? "#3a4550" : "#1c242c")
                        radius: 15
                        border.color: newWindowButton.hovered ? "#c084fc" : "#2a3540"
                        border.width: 1
                    }

                    onClicked: {
                        rootWindow.openAuxiliaryWindow();
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: newWindowButton.hovered
                    ToolTip.text: qsTr("Otwórz nowe okno pomocnicze")
                }

                Button {
                    id: instructionsButton
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var colorStr = instructionsButton.hovered ? "%23facc15" : "%23eab308";
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z'></path><path d='M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z'></path></svg>";
                        }
                    }

                    background: Rectangle {
                        color: instructionsButton.pressed ? "#cc121214" : (instructionsButton.hovered ? "#3a4550" : "#1c242c")
                        radius: 15
                        border.color: instructionsButton.hovered ? "#facc15" : "#2a3540"
                        border.width: 1
                    }

                    onClicked: {
                        instructionsWindow.show();
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: instructionsButton.hovered
                    ToolTip.text: qsTr("Instrukcja obsługi programu")
                }

                Rectangle {
                    width: 1
                    height: 20
                    color: "#2a3540"
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: qsTr("Siatka widoku:")
                    color: "#8898a6"
                    font.bold: true
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }

                RowLayout {
                    spacing: 4

                    Button {
                        id: fullScreenBtn
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28

                        property bool isActive: auxWindow.visibility === Window.FullScreen

                        contentItem: Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            source: {
                                var colorStr = fullScreenBtn.isActive ? "white" : (fullScreenBtn.hovered ? "white" : "%238898a6");
                                if (fullScreenBtn.isActive) {
                                    return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M4 10h6V4m10 6h-6V4M4 14h6v6m10-6h-6v6'></path></svg>";
                                } else {
                                    return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3'></path></svg>";
                                }
                            }
                        }

                        background: Rectangle {
                            color: fullScreenBtn.isActive ? "#ff7a00" : (fullScreenBtn.pressed ? "#cc121214" : (fullScreenBtn.hovered ? "#3a4550" : "#1c242c"))
                            radius: 4
                            border.color: fullScreenBtn.isActive ? "#ff9e00" : (fullScreenBtn.hovered ? "#8898a6" : "#2a3540")
                            border.width: 1
                        }

                        onClicked: {
                            if (auxWindow.visibility === Window.FullScreen) {
                                auxWindow.visibility = Window.Windowed;
                            } else {
                                auxWindow.visibility = Window.FullScreen;
                            }
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: fullScreenBtn.hovered
                        ToolTip.text: qsTr("Toggle Full Screen")
                    }

                    Switch {
                        id: lockGridSwitch
                        checked: generalSettings ? generalSettings.lockGridSize : true
                        text: qsTr("🔒 Blokuj zmianę")

                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter

                        indicator: Rectangle {
                            implicitWidth: 36
                            implicitHeight: 18
                            x: lockGridSwitch.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 9
                            color: lockGridSwitch.checked ? "#ff7a00" : "#1c242c"
                            border.color: lockGridSwitch.checked ? "#ff9e00" : "#2a3540"
                            border.width: 1

                            Rectangle {
                                x: lockGridSwitch.checked ? parent.width - width - 2 : 2
                                y: 2
                                width: 14
                                height: 14
                                radius: 7
                                color: "white"

                                Behavior on x {
                                    NumberAnimation { duration: 150 }
                                }
                            }
                        }

                        contentItem: Text {
                            text: lockGridSwitch.text
                            font.bold: true
                            font.pixelSize: 10
                            color: lockGridSwitch.checked ? "white" : (lockGridSwitch.hovered ? "#ffffff" : "#8898a6")
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: lockGridSwitch.indicator.width + 6
                        }

                        onCheckedChanged: {
                            if (generalSettings) {
                                generalSettings.lockGridSize = checked;
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 20
                        color: "#2a3540"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Repeater {
                        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]
                        delegate: Button {
                            id: gridBtn
                            property int gridSize: modelData
                            text: gridSize + "x" + gridSize
                            enabled: !lockGridSwitch.checked && auxWindow.layoutIndex !== -1

                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30

                            property bool isActive: {
                                try {
                                    var curr = auxWindow.selectedLayoutModel;
                                    return curr && curr.size.width === gridSize && curr.size.height === gridSize;
                                } catch(e) {
                                    return false;
                                }
                            }

                            contentItem: Text {
                                text: gridBtn.text
                                font.bold: true
                                font.pixelSize: 10
                                color: gridBtn.enabled ? (gridBtn.isActive ? "white" : (gridBtn.hovered ? "#ffffff" : "#8898a6")) : "#555555"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                color: gridBtn.isActive ? "#ff7a00" : (gridBtn.pressed ? "#cc121214" : (gridBtn.hovered ? "#3a4550" : "#1c242c"))
                                radius: 15
                                border.color: gridBtn.isActive ? "#ff9e00" : (gridBtn.hovered ? "#8898a6" : "#2a3540")
                                border.width: 1
                                opacity: gridBtn.enabled ? 1.0 : 0.4
                            }

                            onClicked: {
                                auxWindow.changeGridSize(gridSize);
                            }
                        }
                    }

                    Button {
                        id: moreOptionsButton
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 16
                            sourceSize.height: 16
                            fillMode: Image.PreserveAspectFit
                            source: {
                                var colorStr = moreOptionsButton.hovered ? "white" : "%238898a6";
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><line x1='3' y1='12' x2='21' y2='12'></line><line x1='3' y1='6' x2='21' y2='6'></line><line x1='3' y1='18' x2='21' y2='18'></line></svg>";
                            }
                        }

                        background: Rectangle {
                            color: moreOptionsButton.pressed ? "#cc121214" : (moreOptionsButton.hovered ? "#3a4550" : "#1c242c")
                            radius: 15
                            border.color: moreOptionsButton.hovered ? "#ff9e00" : "#2a3540"
                            border.width: 1
                        }

                        onClicked: {
                            if (toolsWindow) {
                                toolsWindow.visible = !toolsWindow.visible;
                                if (toolsWindow.visible) {
                                    toolsWindow.raise();
                                    toolsWindow.requestActivate();
                                }
                            }
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: moreOptionsButton.hovered
                        ToolTip.text: qsTr("Więcej opcji")
                    }
                }

                Item {
                    Layout.fillWidth: true // Spacer to push existing views to the right
                }

                // Right-aligned Existing Views/Presets selector
                Text {
                    text: qsTr("Wybór widoku:")
                    color: "#8898a6"
                    font.bold: true
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }

                RowLayout {
                    spacing: 4

                    Repeater {
                        model: layoutsModel
                        delegate: Button {
                            id: viewBtn
                            property int layoutIndex: model.index

                            visible: {
                                try {
                                    var layout = model.layoutModel;
                                    if (layout) {
                                        return layout.visible;
                                    }
                                } catch(e) {}
                                return true;
                            }

                            text: {
                                try {
                                    var layout = model.layoutModel;
                                    if (layout) {
                                        if (layout.name && layout.name.trim() !== "") {
                                            return layout.name;
                                        }
                                        if (layout.isNvr) {
                                            return "📹 " + rootWindow.getRecorderName(layout.nvrIp);
                                        } else {
                                            var count = 1;
                                            for (var i = 0; i < layoutIndex; ++i) {
                                                var l = layoutsModel.get(i);
                                                if (l && !l.isNvr) count++;
                                            }
                                            return "Widok " + count;
                                        }
                                    }
                                } catch(e) {}
                                return "Widok " + (layoutIndex + 1);
                            }

                            Layout.preferredHeight: 30
                            leftPadding: 12
                            rightPadding: 12

                            // Highlight if this is the currently active view!
                            property bool isActive: auxWindow.layoutIndex === layoutIndex

                            contentItem: Text {
                                text: viewBtn.text.toUpperCase()
                                font.bold: true
                                font.pixelSize: 10
                                color: viewBtn.isActive ? "#121214" : (viewBtn.hovered ? "#ffffff" : "#8898a6")
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                color: viewBtn.isActive ? "#00f5d4" : (viewBtn.pressed ? "#cc121214" : (viewBtn.hovered ? "#3a4550" : "#1c242c"))
                                radius: 15
                                border.color: viewBtn.isActive ? "#00f5d4" : (viewBtn.hovered ? "#8898a6" : "#2a3540")
                                border.width: 1
                            }

                            onClicked: {
                                auxWindow.layoutIndex = layoutIndex;
                            }
                        }
                    }
                }
            }
        }
    }

    InstructionsWindow {
        id: instructionsWindow
        visible: false
    }

    ConfirmDialog {
        id: quitConfirmDialog
        title: qsTr("Zamknij program")
        message: qsTr("Czy na pewno zamknąć program?")
        confirmButtonText: qsTr("TAK")
        cancelButtonText: qsTr("NIE")
        isDanger: true
        onAccepted: {
            auxWindow.closeAccepted = true;
            auxWindow.hide();
            Qt.quit();
        }
    }
}
