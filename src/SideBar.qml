import QtQml 2.12
import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt.labs.settings 1.0
import QtGraphicalEffects 1.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Themes 1.0
import CCTV_Viewer.Utils 1.0

FocusScope {
    id: rootSideBar

    enum State {
        Compact,
        Popup,
        Expanded
    }

    anchors.fill: parent
    implicitWidth: 800
    implicitHeight: 600

    property int state: SideBar.Expanded
    property int currentViewportIndex: Utils.currentLayout().focusIndex

    property var regularIndices: []
    property var nvrIndices: []
    property var nvrPresetIndices: []

    function updateIndices() {
        var regs = [];
        var nvrs = [];
        var nvrPres = [];
        for (var i = 0; i < layoutsCollectionModel.count; ++i) {
            var layout = layoutsCollectionModel.get(i);
            if (layout) {
                if (layout.isNvr) {
                    nvrs.push(i);
                } else if (layout.isNvrPreset) {
                    nvrPres.push(i);
                } else {
                    regs.push(i);
                }
            }
        }
        regularIndices = regs;
        nvrIndices = nvrs;
        nvrPresetIndices = nvrPres;
    }

    Component.onCompleted: {
        layoutsCollectionModel.changed.connect(updateIndices);
        updateIndices();
    }

    Settings {
        id: sideBarSettings
        fileName: Context.config.fileName
        category: "SideBar"
        property string windowDivision
        property string itemsState
    }

    function getRecorderName(ip) {
        try {
            var list = JSON.parse(rootWindow.hikvisionRecordersJson);
            for (var i = 0; i < list.length; ++i) {
                if (list[i].ip === ip) {
                    if (list[i].name && list[i].name.trim() !== "") {
                        return list[i].name;
                    }
                    break;
                }
            }
        } catch(e) {}
        return ip;
    }

    // Split Layout Container
    RowLayout {
        id: splitLayout
        anchors.fill: parent
        spacing: 0

        // Left Navigation Sidebar
        Rectangle {
            id: leftSidebar
            Layout.fillHeight: true
            width: 220
            color: "#0b0f13"

            // Right glow separator
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: "#2a3540"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // Logo/Header area
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: qsTr("CCTV Viewer 2")
                        color: "#ffffff"
                        font {
                            pixelSize: 20
                            bold: true
                        }
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Wersja %1").arg(Qt.application.version)
                        color: "#00f5d4"
                        font {
                            pixelSize: 12
                            bold: true
                        }
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Oryginalny autor: Evgeny S. Maksimov")
                        color: "#8898a6"
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Modyfikacja: arkanista (z pomocą AI)")
                        color: "#ff7a00"
                        font {
                            pixelSize: 10
                            bold: true
                        }
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#2a3540"
                }

                // Page selection buttons
                ColumnLayout {
                    id: tabsColumn
                    Layout.fillWidth: true
                    spacing: 8

                    property int activeIndex: 3

                    function selectTab(index) {
                        activeIndex = index;
                        pagesStack.currentIndex = index;
                    }

                    // Viewport Page Button
                    Button {
                        id: btnViewport
                        visible: false
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 0 ? "#1c242c" : (btnViewport.hovered ? "#141a21" : "transparent")
                            radius: 6

                            // Active Glowing border
                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 0
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgViewport
                                    source: "qrc:/images/menu-viewport.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgViewport
                                    source: imgViewport
                                    color: tabsColumn.activeIndex === 0 ? "#00f5d4" : (btnViewport.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Viewport%1").arg(rootSideBar.currentViewportIndex >= 0 ? qsTr(" #%1").arg(rootSideBar.currentViewportIndex + 1) : "")
                                color: tabsColumn.activeIndex === 0 ? "#00f5d4" : (btnViewport.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 0
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(0)
                    }

                    // Tools Page Button
                    Button {
                        id: btnTools
                        visible: false
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 1 ? "#1c242c" : (btnTools.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 1
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgTools
                                    source: "qrc:/images/menu-tools.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgTools
                                    source: imgTools
                                    color: tabsColumn.activeIndex === 1 ? "#00f5d4" : (btnTools.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Tools")
                                color: tabsColumn.activeIndex === 1 ? "#00f5d4" : (btnTools.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 1
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(1)
                    }

                    // Recorders Page Button
                    Button {
                        id: btnRecorders
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 2 ? "#1c242c" : (btnRecorders.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 2
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgRecorders
                                    source: "qrc:/images/menu-recorders.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgRecorders
                                    source: imgRecorders
                                    color: tabsColumn.activeIndex === 2 ? "#00f5d4" : (btnRecorders.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Recorders")
                                color: tabsColumn.activeIndex === 2 ? "#00f5d4" : (btnRecorders.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 2
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(2)
                    }

                    // Presets Page Button
                    Button {
                        id: btnPresets
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 3 ? "#1c242c" : (btnPresets.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 3
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgPresets
                                    source: "qrc:/images/menu-presets.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgPresets
                                    source: imgPresets
                                    color: tabsColumn.activeIndex === 3 ? "#00f5d4" : (btnPresets.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Presets")
                                color: tabsColumn.activeIndex === 3 ? "#00f5d4" : (btnPresets.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 3
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(3)
                    }

                    // General Settings Page Button
                    Button {
                        id: btnSettings
                        Layout.fillWidth: true
                        height: 40
                        hoverEnabled: true

                        background: Rectangle {
                            color: tabsColumn.activeIndex === 4 ? "#1c242c" : (btnSettings.hovered ? "#141a21" : "transparent")
                            radius: 6

                            Rectangle {
                                anchors.left: parent.left
                                width: 3
                                height: parent.height
                                color: "#00f5d4"
                                visible: tabsColumn.activeIndex === 4
                            }
                        }

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            Item {
                                implicitWidth: 14
                                implicitHeight: 14

                                Image {
                                    id: imgSettings
                                    source: "qrc:/images/menu-settings.svg"
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                }

                                ColorOverlay {
                                    anchors.fill: imgSettings
                                    source: imgSettings
                                    color: tabsColumn.activeIndex === 4 ? "#00f5d4" : (btnSettings.hovered ? "white" : "#8898a6")
                                    cached: true
                                }
                            }

                            Text {
                                text: qsTr("Settings")
                                color: tabsColumn.activeIndex === 4 ? "#00f5d4" : (btnSettings.hovered ? "white" : "#8898a6")
                                font {
                                    pixelSize: 12
                                    bold: tabsColumn.activeIndex === 4
                                }
                                Layout.fillWidth: true
                            }
                        }

                        onClicked: tabsColumn.selectTab(4)
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                // Footer version link
                Text {
                    text: "<a href=\"https://github.com/arkanista/cctv-viewer2\" style=\"color: #8898a6; text-decoration: none;\">GitHub Project</a>"
                    font.pixelSize: 11
                    textFormat: Text.RichText
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    onLinkActivated: Qt.openUrlExternally(link)
                }
            }
        }

        // Right Stack Panel showing selected page
        StackLayout {
            id: pagesStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 3

            // PAGE 0: Viewport settings
            ScrollView {
                id: page0ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page0Layout
                    x: 24
                    width: page0ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("Viewport Details")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    // Placeholder when no viewport is active
                    Text {
                        text: qsTr("Please select a viewport in the main grid to customize its settings.")
                        color: "#8898a6"
                        font {
                            pixelSize: 13
                            italic: true
                        }
                        visible: rootSideBar.currentViewportIndex < 0
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        visible: rootSideBar.currentViewportIndex >= 0

                        Switch {
                            id: configUnlockSwitch
                            text: qsTr("Unlock config pane")
                            checked: false
                            palette.highlight: "#4CAF50"
                            Layout.fillWidth: true
                        }

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
                                spacing: 12

                                TextField {
                                    text: (rootSideBar.currentViewportIndex >= 0 && Utils.currentModel()) ? Utils.currentModel().get(rootSideBar.currentViewportIndex).url : ""
                                    placeholderText: qsTr("Primary Stream URL")
                                    selectByMouse: true
                                    enabled: configUnlockSwitch.checked && (Utils.currentModel() ? (!Utils.currentModel().isNvr && !Utils.currentModel().isNvrPreset) : true)
                                    Layout.fillWidth: true
                                    onEditingFinished: {
                                        if (rootSideBar.currentViewportIndex >= 0) {
                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).url = text;
                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).streamMode = 0;
                                        }
                                    }
                                }

                                TextField {
                                    text: (rootSideBar.currentViewportIndex >= 0 && Utils.currentModel()) ? Utils.currentModel().get(rootSideBar.currentViewportIndex).secondaryUrl : ""
                                    placeholderText: qsTr("Secondary Backup URL")
                                    selectByMouse: true
                                    enabled: configUnlockSwitch.checked && (Utils.currentModel() ? (!Utils.currentModel().isNvr && !Utils.currentModel().isNvrPreset) : true)
                                    Layout.fillWidth: true
                                    onEditingFinished: {
                                        if (rootSideBar.currentViewportIndex >= 0) {
                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).secondaryUrl = text;
                                        }
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: qsTr("Audio & Rendering Options")
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

                                Button {
                                    text: qsTr("Mute / Unmute Audio")
                                    enabled: configUnlockSwitch.checked && (rootSideBar.currentViewportIndex >= 0 ? Utils.currentLayout().get(rootSideBar.currentViewportIndex).hasAudio : false)
                                    highlighted: !(rootSideBar.currentViewportIndex >= 0 && Utils.currentModel().get(rootSideBar.currentViewportIndex).volume > 0 || viewportSettings.unmuteWhenFullScreen && Utils.currentLayout().fullScreenIndex >= 0)
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (rootSideBar.currentViewportIndex >= 0) {
                                            if (Utils.currentModel().get(rootSideBar.currentViewportIndex).volume > 0) {
                                                Utils.currentModel().get(rootSideBar.currentViewportIndex).volume = 0;
                                            } else {
                                                Utils.currentModel().get(rootSideBar.currentViewportIndex).volume = 1;
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("FFmpeg Options Override")
                                        color: "white"
                                        font.pixelSize: 11
                                    }

                                    TextField {
                                        text: (rootSideBar.currentViewportIndex >= 0 && Utils.currentModel()) ? getOptionsString(Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions) : ""
                                        selectByMouse: true
                                        enabled: configUnlockSwitch.checked
                                        Layout.fillWidth: true
                                        onEditingFinished: {
                                            if (rootSideBar.currentViewportIndex >= 0) {
                                                var options = Utils.parseOptions(text);
                                                var defaultAVFormatOptions = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");

                                                if (Object.keys(options).length == Object.keys(defaultAVFormatOptions).length) {
                                                    for (var key in options) {
                                                        if (defaultAVFormatOptions[key] === undefined || String(defaultAVFormatOptions[key]) !== String(options[key])) {
                                                            Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions = options;
                                                            return;
                                                        }
                                                    }
                                                    Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions = {};
                                                } else {
                                                    Utils.currentModel().get(rootSideBar.currentViewportIndex).avFormatOptions = options;
                                                }
                                            }
                                        }

                                        function getOptionsString(options) {
                                            Object.assignDefault(options, layoutsCollectionSettings.toJSValue("defaultAVFormatOptions"));
                                            return Utils.stringifyOptions(options);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // PAGE 1: Tools & Layout Options
            ScrollView {
                id: page1ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page1Layout
                    x: 24
                    width: page1ScrollView.width - 48
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
                        palette.highlight: "#4CAF50"
                        Layout.fillWidth: true
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
                                    text: "16:9 Aspect Ratio"
                                    highlighted: Utils.currentModel() && Utils.currentModel().aspectRatio === Qt.size(16, 9)
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (Utils.currentModel()) {
                                            Utils.currentModel().aspectRatio = Qt.size(16, 9);
                                            setRootWindowRatio(Utils.currentModel().aspectRatio);
                                        }
                                    }
                                }
                                Button {
                                    text: "4:3 Aspect Ratio"
                                    highlighted: Utils.currentModel() && Utils.currentModel().aspectRatio === Qt.size(4, 3)
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (Utils.currentModel()) {
                                            Utils.currentModel().aspectRatio = Qt.size(4, 3);
                                            setRootWindowRatio(Utils.currentModel().aspectRatio);
                                        }
                                    }
                                }
                            }

                            Button {
                                text: qsTr("Toggle Full Screen")
                                highlighted: Context.config.fullScreen
                                Layout.fillWidth: true
                                onClicked: Context.config.fullScreen = !Context.config.fullScreen
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
                                text: qsTr("Merge Highlighted Cells")
                                enabled: Utils.currentLayout().mergeCells(true)
                                Layout.fillWidth: true
                                onClicked: Utils.currentLayout().mergeCells()
                            }
                        }
                    }
                }
            }

            // PAGE 2: NVR Connection Recorders List
            ScrollView {
                id: page2ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: recordersLayout
                    x: 24
                    width: page2ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("NVR / Hikvision Recorders Manager")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    NvrSettingsPanel {
                        Layout.fillWidth: true
                    }
                }
            }

            // PAGE 3: Presets & Views list
            ScrollView {
                id: page3ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: presetsLayout
                    x: 24
                    width: page3ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("Presets & Quick Layout Views")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    // Group 1: General Camera Presets
                    GroupBox {
                        title: qsTr("ONVIF and RTSP Layout settings")
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
                            anchors.margins: 4
                            spacing: 8

                            Repeater {
                                model: rootSideBar.regularIndices
                                delegate: RowLayout {
                                    id: presetRow
                                    spacing: 12
                                    Layout.fillWidth: true

                                    property var layout: layoutsCollectionModel.get(modelData)

                                    // Active preset indicator
                                    Rectangle {
                                        width: 4
                                        height: 24
                                        radius: 2
                                        color: stackLayout.currentIndex === modelData ? "#00f5d4" : "transparent"
                                    }

                                    // Editable preset name field
                                    TextField {
                                        id: nameField
                                        text: (presetRow.layout && presetRow.layout.name) ? presetRow.layout.name : ""
                                        placeholderText: qsTr("Layout %1").arg(index + 1)
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: nameField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            if (presetRow.layout) {
                                                presetRow.layout.name = text;
                                            }
                                        }
                                    }

                                    // Visible Checkbox
                                    CheckBox {
                                        text: qsTr("Visible")
                                        checked: presetRow.layout ? presetRow.layout.visible : true
                                        onCheckedChanged: {
                                            if (presetRow.layout) {
                                                presetRow.layout.visible = checked;
                                            }
                                        }
                                        palette.highlight: "#00f5d4"
                                    }

                                    // Activate button
                                    Button {
                                        id: activateBtn
                                        text: qsTr("Activate")
                                        implicitWidth: 70
                                        implicitHeight: 28
                                        highlighted: stackLayout.currentIndex === modelData
                                        onClicked: {
                                            stackLayout.currentIndex = modelData;
                                        }
                                        background: Rectangle {
                                            color: activateBtn.pressed ? "#cc121214" : (activateBtn.highlighted ? "#ff7a00" : (activateBtn.hovered ? "#3a4550" : "#1c242c"))
                                            radius: 6
                                            border.color: activateBtn.highlighted ? "#ff9e00" : (activateBtn.hovered ? "#8898a6" : "#2a3540")
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: activateBtn.text
                                            color: activateBtn.highlighted ? "#ffffff" : (activateBtn.hovered ? "#ffffff" : "#a0aec0")
                                            font.bold: activateBtn.highlighted
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    // Delete icon button
                                    Button {
                                        id: delPresetBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        visible: rootSideBar.regularIndices.length > 1
                                        icon.source: "qrc:/images/icon-trash.svg"
                                        icon.color: delPresetBtn.pressed ? "#ff4444" : (delPresetBtn.hovered ? "#ff6666" : "#ff8888")
                                        icon.width: 14
                                        icon.height: 14

                                        background: Rectangle {
                                            color: delPresetBtn.pressed ? "#40ff0000" : (delPresetBtn.hovered ? "#20ff0000" : "transparent")
                                            radius: 6
                                            border.color: delPresetBtn.hovered ? "#ff4444" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            presetDeleteDialog.index = modelData;
                                            presetDeleteDialog.open();
                                        }
                                    }
                                }
                            }

                            Button {
                                id: addPresetBtn
                                text: qsTr("Add Preset Layout")
                                Layout.fillWidth: true
                                implicitHeight: 32
                                onClicked: {
                                    var l = layoutsCollectionModel.append();
                                    l.size = Qt.size(3, 3);
                                }
                                background: Rectangle {
                                    color: addPresetBtn.pressed ? "#cc121214" : (addPresetBtn.hovered ? "#059669" : "#10b981")
                                    radius: 6
                                    border.color: addPresetBtn.hovered ? "#34d399" : "#059669"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: addPresetBtn.text
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    // Group 2: NVR Views (Only when NVR layouts configured)
                    GroupBox {
                        title: qsTr("NVR View Layouts")
                        visible: rootSideBar.nvrIndices.length > 0
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
                            anchors.margins: 4
                            spacing: 8

                            Repeater {
                                model: rootSideBar.nvrIndices
                                delegate: RowLayout {
                                    id: nvrRow
                                    spacing: 12
                                    Layout.fillWidth: true

                                    property var layout: layoutsCollectionModel.get(modelData)

                                    Rectangle {
                                        width: 4
                                        height: 24
                                        radius: 2
                                        color: stackLayout.currentIndex === modelData ? "#00f5d4" : "transparent"
                                    }

                                    TextField {
                                        id: nvrNameField
                                        text: (nvrRow.layout && nvrRow.layout.name) ? nvrRow.layout.name : ""
                                        placeholderText: (nvrRow.layout && nvrRow.layout.nvrIp) ? getRecorderName(nvrRow.layout.nvrIp) : qsTr("NVR View")
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: nvrNameField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            if (nvrRow.layout) {
                                                nvrRow.layout.name = text;
                                            }
                                        }
                                    }

                                    CheckBox {
                                        text: qsTr("Visible")
                                        checked: nvrRow.layout ? nvrRow.layout.visible : true
                                        onCheckedChanged: {
                                            if (nvrRow.layout) {
                                                nvrRow.layout.visible = checked;
                                            }
                                        }
                                        palette.highlight: "#00f5d4"
                                    }

                                    Button {
                                        id: activateBtnNvr
                                        text: qsTr("Activate")
                                        implicitWidth: 70
                                        implicitHeight: 28
                                        highlighted: stackLayout.currentIndex === modelData
                                        onClicked: {
                                            stackLayout.currentIndex = modelData;
                                        }
                                        background: Rectangle {
                                            color: activateBtnNvr.pressed ? "#cc121214" : (activateBtnNvr.highlighted ? "#ff7a00" : (activateBtnNvr.hovered ? "#3a4550" : "#1c242c"))
                                            radius: 6
                                            border.color: activateBtnNvr.highlighted ? "#ff9e00" : (activateBtnNvr.hovered ? "#8898a6" : "#2a3540")
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: activateBtnNvr.text
                                            color: activateBtnNvr.highlighted ? "#ffffff" : (activateBtnNvr.hovered ? "#ffffff" : "#a0aec0")
                                            font.bold: activateBtnNvr.highlighted
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    Button {
                                        id: delNvrBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        icon.source: "qrc:/images/icon-trash.svg"
                                        icon.color: delNvrBtn.pressed ? "#ff4444" : (delNvrBtn.hovered ? "#ff6666" : "#ff8888")
                                        icon.width: 14
                                        icon.height: 14

                                        background: Rectangle {
                                            color: delNvrBtn.pressed ? "#40ff0000" : (delNvrBtn.hovered ? "#20ff0000" : "transparent")
                                            radius: 6
                                            border.color: delNvrBtn.hovered ? "#ff4444" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            nvrPresetDeleteDialog.index = modelData;
                                            nvrPresetDeleteDialog.open();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Group 3: NVR Preset List
                    GroupBox {
                        title: qsTr("NVR Presets (Grid views)")
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
                            anchors.margins: 4
                            spacing: 8

                            Repeater {
                                model: rootSideBar.nvrPresetIndices
                                delegate: RowLayout {
                                    id: nvrPresetRow
                                    spacing: 12
                                    Layout.fillWidth: true

                                    property var layout: layoutsCollectionModel.get(modelData)

                                    Rectangle {
                                        width: 4
                                        height: 24
                                        radius: 2
                                        color: stackLayout.currentIndex === modelData ? "#00f5d4" : "transparent"
                                    }

                                    TextField {
                                        id: nvrPresetNameField
                                        text: (nvrPresetRow.layout && nvrPresetRow.layout.name) ? nvrPresetRow.layout.name : ""
                                        placeholderText: qsTr("NVR Preset #%1").arg(index + 1)
                                        selectByMouse: true
                                        Layout.fillWidth: true
                                        color: "white"
                                        background: Rectangle {
                                            color: "#0f151b"
                                            radius: 4
                                            border.color: nvrPresetNameField.activeFocus ? "#ff7a00" : "#2a3540"
                                        }
                                        onEditingFinished: {
                                            if (nvrPresetRow.layout) {
                                                nvrPresetRow.layout.name = text;
                                            }
                                        }
                                    }

                                    CheckBox {
                                        text: qsTr("Visible")
                                        checked: nvrPresetRow.layout ? nvrPresetRow.layout.visible : true
                                        onCheckedChanged: {
                                            if (nvrPresetRow.layout) {
                                                nvrPresetRow.layout.visible = checked;
                                            }
                                        }
                                        palette.highlight: "#00f5d4"
                                    }

                                    Button {
                                        id: activateBtnNvrPreset
                                        text: qsTr("Activate")
                                        implicitWidth: 70
                                        implicitHeight: 28
                                        highlighted: stackLayout.currentIndex === modelData
                                        onClicked: {
                                            stackLayout.currentIndex = modelData;
                                        }
                                        background: Rectangle {
                                            color: activateBtnNvrPreset.pressed ? "#cc121214" : (activateBtnNvrPreset.highlighted ? "#ff7a00" : (activateBtnNvrPreset.hovered ? "#3a4550" : "#1c242c"))
                                            radius: 6
                                            border.color: activateBtnNvrPreset.highlighted ? "#ff9e00" : (activateBtnNvrPreset.hovered ? "#8898a6" : "#2a3540")
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: activateBtnNvrPreset.text
                                            color: activateBtnNvrPreset.highlighted ? "#ffffff" : (activateBtnNvrPreset.hovered ? "#ffffff" : "#a0aec0")
                                            font.bold: activateBtnNvrPreset.highlighted
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    Button {
                                        id: delNvrPresetBtn
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        icon.source: "qrc:/images/icon-trash.svg"
                                        icon.color: delNvrPresetBtn.pressed ? "#ff4444" : (delNvrPresetBtn.hovered ? "#ff6666" : "#ff8888")
                                        icon.width: 14
                                        icon.height: 14

                                        background: Rectangle {
                                            color: delNvrPresetBtn.pressed ? "#40ff0000" : (delNvrPresetBtn.hovered ? "#20ff0000" : "transparent")
                                            radius: 6
                                            border.color: delNvrPresetBtn.hovered ? "#ff4444" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            nvrPresetDeleteDialog2.index = modelData;
                                            nvrPresetDeleteDialog2.open();
                                        }
                                    }
                                }
                            }

                            Button {
                                id: addNvrPresetBtn
                                text: qsTr("Add NVR Preset")
                                Layout.fillWidth: true
                                implicitHeight: 32
                                onClicked: {
                                    var l = layoutsCollectionModel.append();
                                    l.size = Qt.size(2, 2);
                                    l.isNvrPreset = true;
                                    stackLayout.currentIndex = layoutsCollectionModel.count - 1;
                                }
                                background: Rectangle {
                                    color: addNvrPresetBtn.pressed ? "#cc121214" : (addNvrPresetBtn.hovered ? "#059669" : "#10b981")
                                    radius: 6
                                    border.color: addNvrPresetBtn.hovered ? "#34d399" : "#059669"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: addNvrPresetBtn.text
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            // PAGE 4: General application settings
            ScrollView {
                id: page4ScrollView
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    id: page4Layout
                    x: 24
                    width: page4ScrollView.width - 48
                    spacing: 20

                    Text {
                        text: qsTr("System Settings")
                        color: "#00f5d4"
                        font {
                            pixelSize: 16
                            bold: true
                        }
                    }

                    GroupBox {
                        title: qsTr("General Settings")
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
                            spacing: 8

                            CheckBox {
                                text: qsTr("Allow running multiple application instances")
                                checked: !generalSettings.singleApplication
                                enabled: false
                                onCheckedChanged: generalSettings.singleApplication = !checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Automatically collapse sidebar")
                                checked: rootWindowSettings.sidebarAutoCollapse
                                onCheckedChanged: rootWindowSettings.sidebarAutoCollapse = checked
                                Layout.fillWidth: true
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Context Menu Settings")
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
                            spacing: 8

                            CheckBox {
                                text: qsTr("Enable right-click context menu")
                                checked: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableContextMenu = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Allow swapping viewport places")
                                checked: generalSettings.allowSwappingViewports
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.allowSwappingViewports = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Enable 'Remove camera' option")
                                checked: generalSettings.enableRemoveCamera
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableRemoveCamera = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Allow changing viewport settings")
                                checked: generalSettings.enableChangeViewportSettings
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableChangeViewportSettings = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Enable 'Stream selection' option")
                                checked: generalSettings.enableStreamSelection
                                enabled: generalSettings.enableContextMenu
                                onCheckedChanged: generalSettings.enableStreamSelection = checked
                                Layout.fillWidth: true
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("Interface & View Settings")
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
                            spacing: 8

                            CheckBox {
                                text: qsTr("Hide mouse cursor in Full Screen mode")
                                checked: viewSettings.hideCursorWhenFullScreen
                                onCheckedChanged: viewSettings.hideCursorWhenFullScreen = checked
                                Layout.fillWidth: true
                            }

                            CheckBox {
                                text: qsTr("Automatically unmute when entering Full Screen")
                                checked: viewportSettings.unmuteWhenFullScreen
                                onCheckedChanged: viewportSettings.unmuteWhenFullScreen = checked
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    text: qsTr("Language:")
                                    color: "white"
                                    font.pixelSize: 11
                                }

                                ComboBox {
                                    id: sidebarLanguageCombo
                                    Layout.fillWidth: true
                                    model: [
                                        { text: qsTr("System default"), value: "system" },
                                        { text: "English", value: "en" },
                                        { text: "Polski", value: "pl" }
                                    ]
                                    textRole: "text"
                                    
                                    Component.onCompleted: {
                                        var lang = Context.getLanguage();
                                        for (var i = 0; i < model.length; ++i) {
                                            if (model[i].value === lang) {
                                                currentIndex = i;
                                                break;
                                            }
                                        }
                                    }
                                    
                                    onActivated: {
                                        var selectedLang = model[currentIndex].value;
                                        Context.setLanguage(selectedLang);
                                    }

                                    Connections {
                                        target: Context
                                        onLanguageChanged: {
                                            var lang = Context.getLanguage();
                                            for (var i = 0; i < sidebarLanguageCombo.model.length; ++i) {
                                                if (sidebarLanguageCombo.model[i].value === lang) {
                                                    sidebarLanguageCombo.currentIndex = i;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: qsTr("System Media Configuration")
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

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: qsTr("Default FFmpeg command-line options")
                                    color: "white"
                                    font.pixelSize: 11
                                }

                                TextField {
                                    selectByMouse: true
                                    Layout.fillWidth: true
                                    text: {
                                        var opts = "";
                                        var options = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");
                                        for (var key in options) {
                                            if (typeof options[key] === "string" || typeof options[key] === "number") {
                                                opts += "-%1 %2 ".arg(key).arg(options[key]);
                                            }
                                        }
                                        return opts.trim();
                                    }
                                    onEditingFinished: {
                                        layoutsCollectionSettings.defaultAVFormatOptions = JSON.stringify(Utils.parseOptions(text));
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: "#2a3540"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                CheckBox {
                                    id: setCarouselCheck
                                    text: qsTr("Enable cyclic layouts carousel tour")
                                    checked: presetsSettings.carouselRunning
                                    onCheckedChanged: presetsSettings.carouselRunning = checked
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    visible: setCarouselCheck.checked

                                    Text {
                                        text: qsTr("Interval cycle (seconds):")
                                        color: "white"
                                        font.pixelSize: 11
                                    }

                                    SpinBox {
                                        id: mainCarouselIntervalSpin
                                        property int valueFactor: 1000
                                        stepSize: 100
                                        from: stepSize
                                        to: 300 * stepSize
                                        editable: true
                                        value: presetsSettings.carouselInterval
                                        onValueChanged: presetsSettings.carouselInterval = value

                                        validator: DoubleValidator {
                                            decimals: 2
                                            bottom: Math.min(mainCarouselIntervalSpin.from, mainCarouselIntervalSpin.to)
                                            top:  Math.max(mainCarouselIntervalSpin.from, mainCarouselIntervalSpin.to)
                                        }
                                        textFromValue: function(val, locale) {
                                            return Number(val / valueFactor).toLocaleString(locale, 'f', validator.decimals)
                                        }
                                        valueFromText: function(txt, locale) {
                                            return Number.fromLocaleString(locale, txt) * valueFactor
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Modal dialogs declared safely at root scope
    ConfirmDialog {
        id: presetDeleteDialog
        title: qsTr("Confirm Deletion")
        iconSource: "qrc:/images/icon-trash.svg"
        message: {
            if (index >= 0 && index < layoutsCollectionModel.count) {
                var layout = layoutsCollectionModel.get(index);
                if (layout && layout.name && layout.name.trim() !== "") {
                    return qsTr("Are you sure you want to delete preset \"%1\"? This action is completely irreversible.").arg(layout.name);
                }
            }
            return qsTr("Are you sure you want to delete preset #%1? This action is completely irreversible.").arg(index + 1);
        }
        property int index: -1
        onAccepted: layoutsCollectionModel.remove(index)
    }

    ConfirmDialog {
        id: nvrPresetDeleteDialog
        title: qsTr("Confirm Deletion")
        iconSource: "qrc:/images/icon-trash.svg"
        message: {
            if (index >= 0 && index < layoutsCollectionModel.count) {
                var layout = layoutsCollectionModel.get(index);
                if (layout && layout.name && layout.name.trim() !== "") {
                    return qsTr("Are you sure you want to delete NVR view \"%1\"? This action is completely irreversible.").arg(layout.name);
                }
            }
            return qsTr("Are you sure you want to delete this NVR view layout? This action is completely irreversible.");
        }
        property int index: -1
        onAccepted: layoutsCollectionModel.remove(index)
    }

    ConfirmDialog {
        id: nvrPresetDeleteDialog2
        title: qsTr("Confirm Deletion")
        iconSource: "qrc:/images/icon-trash.svg"
        message: {
            if (index >= 0 && index < layoutsCollectionModel.count) {
                var layout = layoutsCollectionModel.get(index);
                if (layout && layout.name && layout.name.trim() !== "") {
                    return qsTr("Are you sure you want to delete NVR Preset \"%1\"? This action is completely irreversible.").arg(layout.name);
                }
            }
            return qsTr("Are you sure you want to delete this NVR Preset? This action is completely irreversible.");
        }
        property int index: -1
        onAccepted: layoutsCollectionModel.remove(index)
    }
}
