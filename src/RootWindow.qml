import QtQml 2.12
import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import QtQuick.Dialogs 1.3
import Qt.labs.settings 1.0
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Models 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Themes 1.0
import CCTV_Viewer.Hikvision 1.0
import Qt.labs.platform 1.1 as Platform

ApplicationWindow {
    id: rootWindow

    title: (Context.isAuxiliary ? qsTr("KVision - Okno pomocnicze") : qsTr("KVision")) + " " + Qt.application.version

    visible: true
    visibility: Context.config.fullScreen ? Window.FullScreen : Window.Windowed

    property bool isWindowMinimized: rootWindow.visibility === Window.Minimized
    property int lastNonMinimizedVisibility: Window.Windowed
    property bool closeAccepted: false
    property string lastLoadedModelsJson: ""
    property string lastSavedModelsJson: ""
    property bool isSyncing: false
    property bool topBarAutoCollapse: !viewSettings.showTopBarByDefault
    readonly property bool isPlaybackWindowOpen: playbackWindowLoader.active && playbackWindowLoader.item && playbackWindowLoader.item.visible

    onClosing: {
        if (!closeAccepted) {
            close.accepted = false;
            quitConfirmDialog.open();
        }
    }

    Timer {
        id: restoreVisibilityTimer
        interval: 150
        repeat: false
        property int targetVisibility: Window.Windowed
        onTriggered: {
            if (targetVisibility === Window.FullScreen) {
                rootWindow.showFullScreen();
            } else if (targetVisibility === Window.Maximized) {
                rootWindow.showMaximized();
            } else {
                rootWindow.showNormal();
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (rootWindow.isSyncing) return;
            var json = JSON.stringify(layoutsCollectionModel.toJSValue());
            rootWindow.lastSavedModelsJson = json;
            layoutsCollectionSettings.models = json;
            console.log("[Sync] Debounced layouts save completed.");
        }
    }

    Timer {
        id: syncEndTimer
        interval: 500
        repeat: false
        onTriggered: {
            rootWindow.isSyncing = false;
            console.log("[Sync] isSyncing set to false after safety delay.");
        }
    }

    onVisibilityChanged: {
        if (visibility === Window.Minimized) {
            isWindowMinimized = true;
            return;
        }

        if (isWindowMinimized) {
            return;
        }

        if (visibility === Window.FullScreen) {
            Context.config.fullScreen = true;
        } else if (visibility === Window.Windowed || visibility === Window.Maximized) {
            lastNonMinimizedVisibility = visibility;
            if (active) {
                Context.config.fullScreen = false;
            }
        }
    }

    Connections {
        target: Context.config
        function onFullScreenChanged() {
            if (Context.config.fullScreen) {
                rootWindow.visibility = Window.FullScreen;
            } else {
                rootWindow.visibility = (rootWindow.lastNonMinimizedVisibility === Window.Maximized) ? Window.Maximized : Window.Windowed;
            }
        }
    }

    width: rootWindowSettings.width
    height: rootWindowSettings.height

    // Right-to-left User Interfaces support
    LayoutMirroring.enabled: Qt.application.layoutDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    Binding {
        target: rootWindowSettings
        property: "width"
        value: rootWindow.width
        when: !Context.config.fullScreen
    }

    Binding {
        target: rootWindowSettings
        property: "height"
        value: rootWindow.height
        when: !Context.config.fullScreen
    }

    property alias hikvisionRecordersJson: hikvisionSettings.recordersJson
    property alias layoutRepeater: layoutRepeater
    property alias layoutIndex: stackLayout.currentIndex
    property alias generalSettings: generalSettings
    property alias viewSettings: viewSettings
    property var auxWindowsList: []
    property var activeLayoutWindow: rootWindow
    
    // Permanent caches for NVR searches to avoid constantly reloading from network
    property var monthAvailabilitiesCache: ({})
    property var playbackSegmentsCache: ({})

    // Multi-stage Deferred Garbage Collection and Memory Trimming to prevent memory accumulation / leaks
    Timer {
        id: gcTimer
        interval: 1000
        repeat: true
        property int tickCount: 0
        onTriggered: {
            tickCount++;
            console.log("[Root] Multi-stage deferred GC and memory trim (tick " + tickCount + "/5)...");
            gc();
            Context.trimMemory();
            if (tickCount >= 5) {
                stop();
            }
        }
        function restartGC() {
            tickCount = 0;
            restart();
        }
    }
    function triggerGcDeferred() {
        gcTimer.restartGC();
    }

    onActiveChanged: {
        if (active) {
            rootWindow.activeLayoutWindow = rootWindow;
            
            if (isWindowMinimized) {
                isWindowMinimized = false;
                if (Context.config.fullScreen) {
                    restoreVisibilityTimer.targetVisibility = Window.FullScreen;
                    restoreVisibilityTimer.start();
                }
            }
        }
    }

    Settings {
        id: generalSettings

        fileName: Context.config.fileName
        property bool singleApplication: true
        property bool allowSwappingViewports: true
        property bool enableContextMenu: true
        property bool enableRemoveCamera: true
        property bool enableChangeViewportSettings: true
        property bool enableStreamSelection: true
        property bool lockGridSize: true
        property string snapshotPath: ""
        property string videoPath: ""
        property bool disableAudio: false
        property int auxiliaryLimit: 1
    }

    Settings {
        id: hikvisionSettings
        fileName: Context.config.fileName
        category: "Hikvision"
        property string recordersJson: "[]"
        onRecordersJsonChanged: NvrStatusManager.onRecordersChanged()
    }


    function getRecorderName(ip) {
        try {
            var list = JSON.parse(hikvisionSettings.recordersJson);
            for (var i = 0; i < list.length; ++i) {
                if (list[i].ip === ip) {
                    if (list[i].name && list[i].name.trim() !== "") {
                        return list[i].name;
                    }
                    break;
                }
            }
        } catch(e) {
            console.log("[RootWindow Error] Failed to parse recorders JSON:", e);
        }
        return ip;
    }

    Timer {
        id: keepVisibleTimer
        interval: 350
        repeat: false
    }

    Settings {
        id: rootWindowSettings

        fileName: Context.config.fileName
        category: Context.isAuxiliary ? "AuxiliaryWindow_" + Context.auxiliaryId : "RootWindow"
        property int width: 1280 + 48 // SideBar compact width
        property int height: 720
        property bool fullScreen

        Component.onCompleted: {
            // Do not initialize "fullScreen" if option "-f" is set
            if (!Context.config.fullScreen) {
                Context.config.fullScreen = rootWindowSettings.fullScreen;
            }

            rootWindowSettings.fullScreen = Qt.binding(function() { return Context.config.fullScreen; });
        }
    }

    Settings {
        id: windowLayoutSettings
        fileName: Context.config.fileName
        category: Context.isAuxiliary ? "AuxiliaryLayout_" + Context.auxiliaryId : "MainLayout"
        property int currentIndex: 0
    }

    Connections {
        target: Context
        function onConfigFileChanged() {
            // 1. Check and live-reload Hikvision NVR/Cameras recorders list
            var diskRecorders = Context.readSetting("Hikvision", "recordersJson", "[]");
            if (diskRecorders !== hikvisionSettings.recordersJson) {
                console.log("[Sync] Live-reloading NVR Recorders list...");
                hikvisionSettings.recordersJson = diskRecorders;
            }

            // 2. Check and live-reload Viewport Layouts definitions
            var diskModels = Context.readSetting("ViewportsLayoutsCollection", "models", "");
            if (diskModels !== "") {
                if (diskModels === rootWindow.lastSavedModelsJson) {
                    // Disk has caught up to our latest save, or we are in sync.
                    rootWindow.lastLoadedModelsJson = diskModels;
                } else if (diskModels === rootWindow.lastLoadedModelsJson) {
                    // Disk is still showing the old state before our latest save. Ignore it.
                } else {
                    // External change!
                    console.log("[Sync] Live-reloading Viewports Layouts list due to external change...");
                    saveTimer.stop();
                    rootWindow.lastLoadedModelsJson = diskModels;
                    rootWindow.lastSavedModelsJson = diskModels;
                    rootWindow.isSyncing = true;
                    try {
                        layoutsCollectionModel.fromJSValue(JSON.parse(diskModels));
                    } catch(e) {
                        console.log("[Sync] Error parsing updated layouts:", e);
                    } finally {
                        syncEndTimer.restart();
                    }
                }
            }

            // 3. Check and live-reload General Settings
            var diskAllowSwapping = Context.readSetting("", "allowSwappingViewports", true);
            if (generalSettings.allowSwappingViewports !== diskAllowSwapping) {
                generalSettings.allowSwappingViewports = diskAllowSwapping;
            }
            var diskEnableChangeViewport = Context.readSetting("", "enableChangeViewportSettings", true);
            if (generalSettings.enableChangeViewportSettings !== diskEnableChangeViewport) {
                generalSettings.enableChangeViewportSettings = diskEnableChangeViewport;
            }
            var diskEnableStreamSel = Context.readSetting("", "enableStreamSelection", true);
            if (generalSettings.enableStreamSelection !== diskEnableStreamSel) {
                generalSettings.enableStreamSelection = diskEnableStreamSel;
            }
            var diskSnapshotPath = Context.readSetting("", "snapshotPath", "");
            if (generalSettings.snapshotPath !== diskSnapshotPath) {
                generalSettings.snapshotPath = diskSnapshotPath;
            }
            var diskVideoPath = Context.readSetting("", "videoPath", "");
            if (generalSettings.videoPath !== diskVideoPath) {
                generalSettings.videoPath = diskVideoPath;
            }
            var diskEnableContextMenu = Context.readSetting("", "enableContextMenu", true);
            if (generalSettings.enableContextMenu !== diskEnableContextMenu) {
                generalSettings.enableContextMenu = diskEnableContextMenu;
            }
            var diskEnableRemoveCamera = Context.readSetting("", "enableRemoveCamera", true);
            if (generalSettings.enableRemoveCamera !== diskEnableRemoveCamera) {
                generalSettings.enableRemoveCamera = diskEnableRemoveCamera;
            }
            var diskLockGridSize = Context.readSetting("", "lockGridSize", true);
            if (generalSettings.lockGridSize !== diskLockGridSize) {
                generalSettings.lockGridSize = diskLockGridSize;
            }
            var diskAuxiliaryLimit = Context.readSetting("", "auxiliaryLimit", 1);
            if (diskAuxiliaryLimit < 0) diskAuxiliaryLimit = 0;
            if (diskAuxiliaryLimit > 3) diskAuxiliaryLimit = 3;
            if (generalSettings.auxiliaryLimit !== diskAuxiliaryLimit) {
                generalSettings.auxiliaryLimit = diskAuxiliaryLimit;
            }

            // 4. Check and live-reload View Settings
            var diskHideCursor = Context.readSetting("View", "hideCursorWhenFullScreen", true);
            if (viewSettings.hideCursorWhenFullScreen !== diskHideCursor) {
                viewSettings.hideCursorWhenFullScreen = diskHideCursor;
            }
            var diskShowChannelStatus = Context.readSetting("View", "showChannelStatus", true);
            if (viewSettings.showChannelStatus !== diskShowChannelStatus) {
                viewSettings.showChannelStatus = diskShowChannelStatus;
            }
            var diskShowCameraInfo = Context.readSetting("View", "showCameraInfo", true);
            if (viewSettings.showCameraInfo !== diskShowCameraInfo) {
                viewSettings.showCameraInfo = diskShowCameraInfo;
            }
            var diskHoverControlIcons = Context.readSetting("View", "hoverControlIcons", true);
            if (viewSettings.hoverControlIcons !== diskHoverControlIcons) {
                viewSettings.hoverControlIcons = diskHoverControlIcons;
            }
            var diskShowInfoOnHoverOnly = Context.readSetting("View", "showInfoOnHoverOnly", false);
            if (viewSettings.showInfoOnHoverOnly !== diskShowInfoOnHoverOnly) {
                viewSettings.showInfoOnHoverOnly = diskShowInfoOnHoverOnly;
            }
            var diskShowTopBarByDefault = Context.readSetting("View", "showTopBarByDefault", true);
            if (viewSettings.showTopBarByDefault !== diskShowTopBarByDefault) {
                viewSettings.showTopBarByDefault = diskShowTopBarByDefault;
            }
            var diskNoUnmuteWhenFullScreen = Context.readSetting("Viewport", "noUnmuteWhenFullScreen", false);
            if (viewportSettings.noUnmuteWhenFullScreen !== diskNoUnmuteWhenFullScreen) {
                viewportSettings.noUnmuteWhenFullScreen = diskNoUnmuteWhenFullScreen;
            }
            var diskDefaultAVFormatOptions = Context.readSetting("ViewportsLayoutsCollection", "defaultAVFormatOptions", "{\"analyzeduration\":0,\"probesize\":500000}");
            if (layoutsCollectionSettings.defaultAVFormatOptions !== diskDefaultAVFormatOptions) {
                layoutsCollectionSettings.defaultAVFormatOptions = diskDefaultAVFormatOptions;
            }


            // 6. Check and live-reload Application Language
            var diskLang = Context.readSetting("", "language", "system");
            if (Context.getLanguage() !== diskLang) {
                console.log("[Sync] Live-reloading language to:", diskLang);
                Context.setLanguage(diskLang);
            }
        }
    }

    Settings {
        id: layoutsCollectionSettings

        fileName: Context.config.fileName
        category: "ViewportsLayoutsCollection"

        property string models
        property string defaultAVFormatOptions: "{\"analyzeduration\":0,\"probesize\":500000}"

        function toJSValue(key) {
            var obj = {};

            try {
                obj = JSON.parse(layoutsCollectionSettings[String(key)]);
            } catch(err) {
                Utils.log_error(qsTr("Error reading configuration!"));
            }

            return obj;
        }
    }

    Settings {
        id: viewSettings

        fileName: Context.config.fileName
        category: "View"

        property bool hideCursorWhenFullScreen: true
        property bool showChannelStatus: true
        property bool showCameraInfo: true
        property bool hoverControlIcons: true
        property bool showInfoOnHoverOnly: false
        property bool showTopBarByDefault: true
    }

    Settings {
        id: viewportSettings

        fileName: Context.config.fileName
        category: "Viewport"

        property bool noUnmuteWhenFullScreen: false
    }

    Shortcut {
        sequence: "M"
        onActivated: {
            if (Utils.currentLayout().focusIndex >= 0) {
                var item = Utils.currentModel().get(Utils.currentLayout().focusIndex);
                var viewport = Utils.currentLayout().get(Utils.currentLayout().focusIndex);

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
        sequence: "Alt+Right"
        onActivated: stackLayout.currentIndex = Math.min(stackLayout.currentIndex + 1, stackLayout.count - 1)
    }
    Shortcut {
        sequence: "Alt+Left"
        onActivated: stackLayout.currentIndex = Math.max(stackLayout.currentIndex - 1, 0)
    }
    // Shortcuts for the first 9 presets (Alt + 1, Alt + 2, ..., Alt + 9)
    Repeater {
        model: Context.config.kioskMode ? 0 : Math.min(stackLayout.count, 9)

        Item {
            Shortcut {
                sequence: "Alt+" + (index + 1)
                onActivated: stackLayout.currentIndex = index
            }
        }
    }
    Shortcut {
        sequences: ["F11", StandardKey.FullScreen]
        onActivated: toggleFullScreen()
        onActivatedAmbiguously: toggleFullScreen()

        function toggleFullScreen() {
            Context.config.fullScreen = !Context.config.fullScreen;
        }
    }
    Shortcut {
        sequence: StandardKey.Quit
        onActivated: Qt.quit()
    }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: rootWindow.openAuxiliaryWindow()
    }

    function setRootWindowRatio(ratio) {
        var horzRatio = Utils.currentModel().size.width * ratio.width;
        var vertRatio = Utils.currentModel().size.height * ratio.height;
        var pixels = Math.round(rootWindow.width / horzRatio);

        if (!Context.config.fullScreen) {
            rootWindow.width = horzRatio * pixels;
            rootWindow.height = vertRatio * pixels;
        }
    }

    function openAuxiliaryWindow(initialState) {
        loadingTimer.start();
        Context.startAuxiliaryProcess();
    }

    function openPlaybackWindow(recInfo, channelId, cameraName) {
        if (playbackWindowLoader.active) {
            if (playbackWindowLoader.item) {
                playbackWindowLoader.item.recorderInfo = recInfo;
                playbackWindowLoader.item.channelId = channelId;
                playbackWindowLoader.item.cameraName = cameraName;
                playbackWindowLoader.item.show();
                playbackWindowLoader.item.raise();
            }
        } else {
            playbackWindowLoader.setSource("qrc:/src/PlaybackWindow.qml", {
                "recorderInfo": recInfo,
                "channelId": channelId,
                "cameraName": cameraName,
                "width": rootWindow.width * 0.9,
                "height": rootWindow.height * 0.9
            });
            playbackWindowLoader.active = true;
        }
    }

    function openPlaybackWindowEmpty() {
        openPlaybackWindow(null, -1, "");
    }



    ViewportsLayoutsCollectionModel {
        id: layoutsCollectionModel

        // Demo group
        ViewportsLayoutModel {
            size: Qt.size(2, 2)
        }
        ViewportsLayoutModel {
            size: Qt.size(3, 3)
        }
        ViewportsLayoutModel {
            size: Qt.size(1, 1)
        }

        onCountChanged: stackLayout.currentIndex = stackLayout.currentIndex.clamp(0, layoutsCollectionModel.count - 1)
        Component.onCompleted: {
            // Demo streams
            get(0).get(0).url = "rtmp://live.a71.ru/demo/0";
            get(0).get(1).url = "rtmp://live.a71.ru/demo/1";

            var initialModels = "";
            rootWindow.isSyncing = true;
            try {
                if (!layoutsCollectionSettings.models.isEmpty()) {
                    initialModels = layoutsCollectionSettings.models;
                    fromJSValue(JSON.parse(initialModels));
                }
            } catch(err) {
                Utils.log_error(qsTr("Error reading configuration!"));
            } finally {
                rootWindow.isSyncing = false;
            }
            rootWindow.lastLoadedModelsJson = initialModels;
            rootWindow.lastSavedModelsJson = initialModels;

            layoutsCollectionModel.changed.connect(function () {
                if (rootWindow.isSyncing) return;
                saveTimer.restart();
            });

            if (Context.isAuxiliary) {
                stackLayout.currentIndex = -1;
            } else {
                // Force initialize "currentIndex" if option "-p" is set
                var currentIndex = (Context.config.currentIndex >= 0) ? Context.config.currentIndex : windowLayoutSettings.currentIndex;
                stackLayout.currentIndex = currentIndex.clamp(0, layoutsCollectionModel.count - 1);
            }
        }
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

    // Sleek premium horizontal top bar for settings and grid layout options (DOCK)
    Rectangle {
        id: topToolBar
        height: 56
        width: topRowLayout.implicitWidth + 24
        anchors.horizontalCenter: parent.horizontalCenter
        color: (rootWindow.visibility === Window.FullScreen) ? "#44121214" : "#99121214"
        z: 9999
        radius: 12

        // Slides down to y: -12 so that the top 12px (containing top rounded corners) is off-screen,
        // leaving only the bottom rounded corners visible at the top edge of the window.
        y: (!rootWindow.topBarAutoCollapse || hoverArea.containsMouse || topToolBarMouseArea.containsMouse || keepVisibleTimer.running) ? -12 : -height

        Behavior on y {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            id: topToolBarMouseArea
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 44
            hoverEnabled: true
            onContainsMouseChanged: {
                if (containsMouse) {
                    keepVisibleTimer.stop();
                } else if (!hoverArea.containsMouse) {
                    keepVisibleTimer.start();
                }
            }

            RowLayout {
                id: topRowLayout
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 44
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
                id: pinButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                property bool isPinned: !rootWindow.topBarAutoCollapse

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    rotation: pinButton.isPinned ? 0 : -45

                    Behavior on rotation {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                    }

                    source: {
                        var colorStr = pinButton.hovered ? "white" : "%238898a6";
                        if (pinButton.isPinned) {
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='" + colorStr + "' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='12' x2='12' y1='17' y2='22'></line><path d='M5 17h14v-1.76a2 2 0 0 0-.44-1.24l-2.78-3.56A2 2 0 0 1 15 9.2V5a2 2 0 0 0-2-2h-2a2 2 0 0 0-2 2v4.2a2 2 0 0 1-.78 1.24L5.44 14a2 2 0 0 0-.44 1.24Z'></path></svg>";
                        } else {
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='12' x2='12' y1='17' y2='22'></line><path d='M5 17h14v-1.76a2 2 0 0 0-.44-1.24l-2.78-3.56A2 2 0 0 1 15 9.2V5a2 2 0 0 0-2-2h-2a2 2 0 0 0-2 2v4.2a2 2 0 0 1-.78 1.24L5.44 14a2 2 0 0 0-.44 1.24Z'></path></svg>";
                        }
                    }
                }

                background: Rectangle {
                    color: pinButton.pressed ? "#cc121214" : (pinButton.hovered ? "#3a4550" : "#1c242c")
                    radius: 15
                    border.color: pinButton.hovered ? "#8898a6" : "#2a3540"
                    border.width: 1
                }

                onClicked: {
                    rootWindow.topBarAutoCollapse = !rootWindow.topBarAutoCollapse;
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: pinButton.hovered
                ToolTip.text: pinButton.isPinned ? qsTr("Odepnij pasek górny") : qsTr("Przypnij pasek górny")
            }

            Button {
                id: fullScreenBtn
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                property bool isActive: Context.config.fullScreen

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: {
                        var colorStr = fullScreenBtn.hovered ? "%2300ff66" : (fullScreenBtn.isActive ? "%2300ff66" : "%2300cc52");
                        if (fullScreenBtn.isActive) {
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='m14 10 7-7m-7 7h6m-6 0V4M10 14 3 21m7-7H4m6 0v6M14 14l7 7m-7-7v6m0-6h6M10 10 3 3m7 7V4m0 6H4'></path></svg>";
                        } else {
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='m21 21-6-6m6 6V15m0 6h-6M3 3l6 6M3 3v6M3 3h6M3 21l6-6M3 21v-6M3 21h6M21 3l-6 6M21 3v6M21 3h-6'></path></svg>";
                        }
                    }
                }

                background: Rectangle {
                    color: fullScreenBtn.pressed ? "#cc121214" : (fullScreenBtn.hovered ? "#3a4550" : "#1c242c")
                    radius: 15
                    border.color: fullScreenBtn.hovered ? "#00ff66" : "#2a3540"
                    border.width: 1
                }

                onClicked: {
                    Context.config.fullScreen = !Context.config.fullScreen;
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: fullScreenBtn.hovered
                ToolTip.text: qsTr("Toggle Full Screen")
            }

            Button {
                id: minimizeButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: {
                        var colorStr = minimizeButton.hovered ? "%2333ccff" : "%2300c8ff";
                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><line x1='5' y1='19' x2='19' y2='19'></line><line x1='12' y1='5' x2='12' y2='14'></line><polyline points='7 10 12 15 17 10'></polyline></svg>";
                    }
                }

                background: Rectangle {
                    color: minimizeButton.pressed ? "#cc121214" : (minimizeButton.hovered ? "#3a4550" : "#1c242c")
                    radius: 15
                    border.color: minimizeButton.hovered ? "#00c8ff" : "#2a3540"
                    border.width: 1
                }

                onClicked: {
                    rootWindow.showMinimized();
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: minimizeButton.hovered
                ToolTip.text: qsTr("Minimalizuj okno")
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
                    sidebarWindow.visible = !sidebarWindow.visible;
                    if (sidebarWindow.visible) {
                        sidebarWindow.raise();
                        sidebarWindow.requestActivate();
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
                id: archiveButton
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
                        var colorStr = "%23121214";
                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><ellipse cx='12' cy='5' rx='9' ry='3'></ellipse><path d='M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5'></path><path d='M3 12c0 1.66 4 3 9 3s9-1.34 9-3'></path></svg>";
                    }
                }

                background: Rectangle {
                    color: archiveButton.pressed ? "#00ccb0" : (archiveButton.hovered ? "#00ffd8" : "#00f5d4")
                    radius: 15
                    border.color: archiveButton.pressed ? "#00ccb0" : (archiveButton.hovered ? "#00ffd8" : "#00f5d4")
                    border.width: 1
                }

                onClicked: {
                    rootWindow.openPlaybackWindowEmpty();
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: archiveButton.hovered
                ToolTip.text: qsTr("Archiwum nagrań i odtwarzacz")
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
                    instructionsWindow.raise();
                    instructionsWindow.requestActivate();
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: instructionsButton.hovered
                ToolTip.text: qsTr("Instrukcja obsługi programu")
            }

            Button {
                id: systemStatsSwitch
                checkable: true
                checked: false
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: {
                        var colorStr = systemStatsSwitch.pressed ? "%23ffffff" : (systemStatsSwitch.checked ? "%2300ff66" : (systemStatsSwitch.hovered ? "%23ffffff" : "%238898a6"));
                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><line x1='18' y1='20' x2='18' y2='10'></line><line x1='12' y1='20' x2='12' y2='4'></line><line x1='6' y1='20' x2='6' y2='14'></line></svg>";
                    }
                }

                background: Rectangle {
                    color: systemStatsSwitch.pressed ? "#cc121214" : (systemStatsSwitch.checked ? "#cc004d1a" : (systemStatsSwitch.hovered ? "#3a4550" : "#1c242c"))
                    radius: 15
                    border.color: systemStatsSwitch.checked ? "#00ff66" : (systemStatsSwitch.hovered ? "#8898a6" : "#2a3540")
                    border.width: 1
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: systemStatsSwitch.hovered
                ToolTip.text: systemStatsSwitch.checked ? qsTr("Wyłącz statystyki zużycia zasobów") : qsTr("Włącz statystyki zużycia zasobów")
            }

            Button {
                id: nvrStatusButton
                visible: NvrStatusManager.monitoringEnabled && NvrStatusManager.hasConfiguredRecorders
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                contentItem: Item {
                    anchors.fill: parent

                    // Pulsing glow background when there are errors (Outer large wave)
                    Rectangle {
                        id: pulseGlow
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: "#ef4444"
                        opacity: 0.0
                        visible: NvrStatusManager.hasErrors

                        SequentialAnimation on scale {
                            running: NvrStatusManager.hasErrors
                            loops: Animation.Infinite
                            PropertyAnimation { from: 1.0; to: 2.3; duration: 800; easing.type: Easing.OutQuad }
                            PropertyAnimation { from: 2.3; to: 1.0; duration: 800; easing.type: Easing.InQuad }
                        }

                        SequentialAnimation on opacity {
                            running: NvrStatusManager.hasErrors
                            loops: Animation.Infinite
                            PropertyAnimation { from: 0.85; to: 0.0; duration: 800; easing.type: Easing.OutQuad }
                            PropertyAnimation { from: 0.0; to: 0.85; duration: 800; easing.type: Easing.InQuad }
                        }
                    }

                    // Secondary pulsing glow (Inner fast ripple)
                    Rectangle {
                        id: pulseGlowInner
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: "#ef4444"
                        opacity: 0.0
                        visible: NvrStatusManager.hasErrors

                        SequentialAnimation on scale {
                            running: NvrStatusManager.hasErrors
                            loops: Animation.Infinite
                            PropertyAnimation { from: 1.0; to: 1.6; duration: 600; easing.type: Easing.OutQuad }
                            PropertyAnimation { from: 1.6; to: 1.0; duration: 600; easing.type: Easing.InQuad }
                        }

                        SequentialAnimation on opacity {
                            running: NvrStatusManager.hasErrors
                            loops: Animation.Infinite
                            PropertyAnimation { from: 0.6; to: 0.1; duration: 600; easing.type: Easing.OutQuad }
                            PropertyAnimation { from: 0.1; to: 0.6; duration: 600; easing.type: Easing.InQuad }
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var colorStr = "%23121214";
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='2' width='20' height='8' rx='2' ry='2'></rect><rect x='2' y='14' width='20' height='8' rx='2' ry='2'></rect><line x1='6' y1='6' x2='6.01' y2='6'></line><line x1='6' y1='18' x2='6.01' y2='18'></line></svg>";
                        }
                    }
                }

                background: Rectangle {
                    color: {
                        if (NvrStatusManager.hasErrors) {
                            return nvrStatusButton.pressed ? "#b91c1c" : (nvrStatusButton.hovered ? "#ef4444" : "#dc2626");
                        } else {
                            return nvrStatusButton.pressed ? "#15803d" : (nvrStatusButton.hovered ? "#22c55e" : "#16a34a");
                        }
                    }
                    radius: 15
                    border.color: NvrStatusManager.hasErrors ? "#ef4444" : "#22c55e"
                    border.width: 1
                }

                onClicked: {
                    nvrStatusDialog.open();
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: nvrStatusButton.hovered
                ToolTip.text: NvrStatusManager.hasErrors ? qsTr("Wykryto błędy rejestratorów!") : qsTr("Status rejestratorów: OK")
            }

            Rectangle {
                width: 1
                height: 20
                color: "#2a3540"
                Layout.alignment: Qt.AlignVCenter
                visible: nvrStatusButton.visible
            }

            RowLayout {
                spacing: 4

                Switch {
                    id: lockGridSwitch
                    checked: generalSettings.lockGridSize

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

                    onCheckedChanged: {
                        generalSettings.lockGridSize = checked;
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: lockGridSwitch.hovered
                    ToolTip.text: qsTr("Zablokuj zmianę rozmiaru siatki")
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
                        enabled: !generalSettings.lockGridSize

                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30

                        // Highlight if this is the current active size!
                        property bool isActive: {
                            try {
                                var curr = Utils.currentModel();
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
                            try {
                                var curr = Utils.currentModel();
                                if (curr) {
                                    curr.size = Qt.size(gridSize, gridSize);
                                }
                            } catch(e) {
                                console.log("[Grid Selector Error] Failed to change grid size:", e);
                            }
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
                        toolsWindow.visible = !toolsWindow.visible;
                        if (toolsWindow.visible) {
                            toolsWindow.raise();
                            toolsWindow.requestActivate();
                        }
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: moreOptionsButton.hovered
                    ToolTip.text: qsTr("Więcej opcji")
                }
            }

            Rectangle {
                width: 1
                height: 20
                color: "#2a3540"
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                Layout.rightMargin: 6
            }

            RowLayout {
                spacing: 4

                Repeater {
                    model: layoutsCollectionModel
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
                                        return "📹 " + getRecorderName(layout.nvrIp);
                                    } else {
                                        var count = 1;
                                        for (var i = 0; i < layoutIndex; ++i) {
                                            var l = layoutsCollectionModel.get(i);
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
                        property bool isActive: stackLayout.currentIndex === layoutIndex

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
                            if (stackLayout.currentIndex === layoutIndex) {
                                stackLayout.currentIndex = -1;
                            }
                            stackLayout.currentIndex = layoutIndex;
                        }
                    }
                }
            }
        }
    }
    }

    // Protruding error indicator at the top edge of the window when top bar is hidden
    Rectangle {
        id: topEdgeErrorIndicator
        width: 48
        height: 24
        x: topToolBar.x + 12 + nvrStatusButton.x + nvrStatusButton.width / 2 - width / 2
        anchors.top: parent.top
        color: "transparent"
        z: 100000 // On top of everything

        visible: NvrStatusManager.monitoringEnabled && NvrStatusManager.hasConfiguredRecorders && NvrStatusManager.hasErrors
        opacity: (topToolBar.y < -12) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        Rectangle {
            id: indicatorCircle
            width: 48
            height: 48
            radius: 24
            color: "#dc2626"
            border.color: "#ef4444"
            border.width: 1.5
            anchors.horizontalCenter: parent.horizontalCenter
            y: -28 // Leaves exactly 20px visible inside the screen

            // Dual pulsing glows
            Rectangle {
                id: indicatorGlow1
                width: 48
                height: 48
                radius: 24
                color: "#ef4444"
                anchors.centerIn: parent
                z: -1

                SequentialAnimation on scale {
                    running: topEdgeErrorIndicator.visible && (topToolBar.y < -12)
                    loops: Animation.Infinite
                    PropertyAnimation { from: 1.0; to: 2.3; duration: 800; easing.type: Easing.OutQuad }
                    PropertyAnimation { from: 2.3; to: 1.0; duration: 800; easing.type: Easing.InQuad }
                }

                SequentialAnimation on opacity {
                    running: topEdgeErrorIndicator.visible && (topToolBar.y < -12)
                    loops: Animation.Infinite
                    PropertyAnimation { from: 0.85; to: 0.0; duration: 800; easing.type: Easing.OutQuad }
                    PropertyAnimation { from: 0.0; to: 0.85; duration: 800; easing.type: Easing.InQuad }
                }
            }

            Rectangle {
                id: indicatorGlow2
                width: 48
                height: 48
                radius: 24
                color: "#ef4444"
                anchors.centerIn: parent
                z: -2

                SequentialAnimation on scale {
                    running: topEdgeErrorIndicator.visible && (topToolBar.y < -12)
                    loops: Animation.Infinite
                    PropertyAnimation { from: 1.0; to: 1.6; duration: 600; easing.type: Easing.OutQuad }
                    PropertyAnimation { from: 1.6; to: 1.0; duration: 600; easing.type: Easing.InQuad }
                }

                SequentialAnimation on opacity {
                    running: topEdgeErrorIndicator.visible && (topToolBar.y < -12)
                    loops: Animation.Infinite
                    PropertyAnimation { from: 0.6; to: 0.1; duration: 600; easing.type: Easing.OutQuad }
                    PropertyAnimation { from: 0.1; to: 0.6; duration: 600; easing.type: Easing.InQuad }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                text: "!"
                color: "white"
                font.bold: true
                font.pixelSize: 13
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    nvrStatusDialog.open();
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: containsMouse
                ToolTip.text: qsTr("Wykryto błędy rejestratorów! Kliknij, aby zobaczyć szczegóły.")
            }
        }
    }

    Item {
        anchors.fill: parent

        // Placeholder when no view is selected in auxiliary window
        Rectangle {
            anchors.fill: parent
            color: "#0f151b"
            visible: Context.isAuxiliary && stackLayout.currentIndex === -1

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

        StackLayout {
            id: stackLayout

            visible: false
            currentIndex: -1
            anchors.fill: parent

            onCurrentIndexChanged: {
                windowLayoutSettings.currentIndex = currentIndex;
                rootWindow.triggerGcDeferred();
            }

            Repeater {
                id: layoutRepeater
                model: layoutsCollectionModel

                ViewportsLayout {
                    model: layoutModel
                    focus: true
                }
            }
        }
    }

    // Separate utility Window for options (SideBar contents)
    Window {
        id: sidebarWindow
        title: qsTr("KVision - Panel")
        width: Math.round(rootWindow.width * 0.85)
        height: Math.round(rootWindow.height * 0.85)
        visible: false
        color: "#0f151b"

        onVisibleChanged: {
            if (sideBarLoader.item) {
                try {
                    sideBarLoader.item.resetPathChangesCheckbox();
                } catch(e) {}
            }
            if (visible) {
                if (sideBarLoader.source == "" && !Context.config.kioskMode) {
                    sideBarLoader.source = "SideBar.qml";
                }
                var defaultWidth = Math.round(rootWindow.width * 0.85);
                var defaultHeight = Math.round(rootWindow.height * 0.85);
                if (sidebarWindow.width === 320 || sidebarWindow.width <= 0) {
                    sidebarWindow.width = defaultWidth;
                }
                if (sidebarWindow.height === 750 || sidebarWindow.height <= 0) {
                    sidebarWindow.height = defaultHeight;
                }
                sidebarWindow.x = Math.round(rootWindow.x + (rootWindow.width - sidebarWindow.width) / 2);
                sidebarWindow.y = Math.round(rootWindow.y + (rootWindow.height - sidebarWindow.height) / 2);
            }
        }

        Settings {
            id: sidebarWindowSettings
            fileName: Context.config.fileName
            category: "SidebarWindow"
            property int x: -1
            property int y: -1
            property int width: -1
            property int height: -1
            property bool visible: false
        }

        Component.onCompleted: {
            var defaultWidth = Math.round(rootWindow.width * 0.85);
            var defaultHeight = Math.round(rootWindow.height * 0.85);
            var defaultX = Math.round(rootWindow.x + (rootWindow.width - defaultWidth) / 2);
            var defaultY = Math.round(rootWindow.y + (rootWindow.height - defaultHeight) / 2);

            sidebarWindow.width = (sidebarWindowSettings.width > 0 && sidebarWindowSettings.width !== 320) ? sidebarWindowSettings.width : defaultWidth;
            sidebarWindow.height = (sidebarWindowSettings.height > 0 && sidebarWindowSettings.height !== 750) ? sidebarWindowSettings.height : defaultHeight;
            sidebarWindow.x = (sidebarWindowSettings.x >= 0 && sidebarWindowSettings.x !== 100) ? sidebarWindowSettings.x : defaultX;
            sidebarWindow.y = (sidebarWindowSettings.y >= 0 && sidebarWindowSettings.y !== 100) ? sidebarWindowSettings.y : defaultY;

            if (Context.isAuxiliary) {
                sidebarWindow.visible = false;
            } else {
                sidebarWindow.visible = sidebarWindowSettings.visible;

                sidebarWindow.xChanged.connect(saveGeometry);
                sidebarWindow.yChanged.connect(saveGeometry);
                sidebarWindow.widthChanged.connect(saveGeometry);
                sidebarWindow.heightChanged.connect(saveGeometry);
                sidebarWindow.visibleChanged.connect(saveGeometry);
            }
        }



        function saveGeometry() {
            sidebarWindowSettings.x = sidebarWindow.x;
            sidebarWindowSettings.y = sidebarWindow.y;
            sidebarWindowSettings.width = sidebarWindow.width;
            sidebarWindowSettings.height = sidebarWindow.height;
            sidebarWindowSettings.visible = sidebarWindow.visible;
        }

        Loader {
            id: sideBarLoader
            anchors.fill: parent
        }
    }

    Connections {
        target: SingleApplication
        function onMessageReceived(message) {
            if (message === "openNewWindow") {
                rootWindow.openAuxiliaryWindow();
            }
        }
    }

    Component.onCompleted: {
        stackLayout.visible = true;

        var snapPath = generalSettings.snapshotPath;
        if (snapPath === "") {
            var picLoc = Platform.StandardPaths.writableLocation(Platform.StandardPaths.PicturesLocation).toString();
            if (picLoc.indexOf("file://") === 0) picLoc = picLoc.substring(7);
            snapPath = picLoc + "/CCTV";
            generalSettings.snapshotPath = snapPath;
        }
        Context.mkpath(snapPath);

        var vidPath = generalSettings.videoPath;
        if (vidPath === "") {
            var movLoc = Platform.StandardPaths.writableLocation(Platform.StandardPaths.MoviesLocation).toString();
            if (movLoc.indexOf("file://") === 0) movLoc = movLoc.substring(7);
            vidPath = movLoc + "/CCTV";
            generalSettings.videoPath = vidPath;
        }
        Context.mkpath(vidPath);

        if (Context.isFirstRun && !Context.isAuxiliary) {
            firstRunHelpTimer.start();
        }
    }


    InstructionsWindow {
        id: instructionsWindow
        visible: false
    }

    Timer {
        id: firstRunHelpTimer
        interval: 350
        repeat: false
        onTriggered: {
            instructionsWindow.show();
            instructionsWindow.raise();
            instructionsWindow.requestActivate();
        }
    }

    ConfirmDialog {
        id: quitConfirmDialog
        title: Context.isAuxiliary ? qsTr("Zamknij okno") : qsTr("Zamknij program")
        message: Context.isAuxiliary ? qsTr("Czy na pewno zamknąć to okno?") : qsTr("Czy na pewno zamknąć program?")
        confirmButtonText: qsTr("TAK")
        cancelButtonText: qsTr("NIE")
        isDanger: true
        onAccepted: {
            if (saveTimer.running) {
                saveTimer.stop();
                if (!rootWindow.isSyncing) {
                    var json = JSON.stringify(layoutsCollectionModel.toJSValue());
                    rootWindow.lastSavedModelsJson = json;
                    layoutsCollectionSettings.models = json;
                    console.log("[Sync] Emergency immediate layouts save completed on close.");
                }
            }
            rootWindow.closeAccepted = true;
            rootWindow.hide();
            Qt.quit();
        }
    }

    NvrStatusDialog {
        id: nvrStatusDialog
    }

    ToolsWindow {
        id: toolsWindow
        visible: false
    }

    // Premium semi-transparent draggable panel for system stats
    Rectangle {
        id: statsPanel
        width: 400
        height: 310
        x: 20
        y: 60
        color: "#59121214" // 35% opacity dark background for better readability
        border.color: "#00ff66"
        border.width: 1
        radius: 8
        z: 99999
        visible: systemStatsSwitch.checked

        property int minWidth: 250
        property int minHeight: 220

        property var cpuHistory: []
        property var gpuHistory: []
        property var netHistory: []

        function resetData() {
            var arr = [];
            for (var i = 0; i < 360; ++i) arr.push(0);
            statsPanel.cpuHistory = arr;
            statsPanel.gpuHistory = arr;
            statsPanel.netHistory = arr;
            cpuCanvas.requestPaint();
            gpuCanvas.requestPaint();
            netCanvas.requestPaint();
        }

        Component.onCompleted: {
            resetData();
            SystemStats.active = visible;
        }

        onVisibleChanged: {
            SystemStats.active = visible;
            if (!visible) {
                resetData();
                gc(); // Optionally trigger garbage collection to free memory immediately
            }
        }

        Connections {
            target: SystemStats
            function onStatsChanged() {
                var cpu = SystemStats.cpuUsage;
                var gpu = SystemStats.gpuUsage;
                var net = SystemStats.netUsage;

                var newCpu = statsPanel.cpuHistory.slice();
                newCpu.push(cpu);
                if (newCpu.length > 360) newCpu.shift();
                statsPanel.cpuHistory = newCpu;

                var newGpu = statsPanel.gpuHistory.slice();
                newGpu.push(gpu);
                if (newGpu.length > 360) newGpu.shift();
                statsPanel.gpuHistory = newGpu;

                var newNet = statsPanel.netHistory.slice();
                newNet.push(net);
                if (newNet.length > 360) newNet.shift();
                statsPanel.netHistory = newNet;

                cpuCanvas.requestPaint();
                gpuCanvas.requestPaint();
                netCanvas.requestPaint();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                
                Text {
                    text: qsTr("📊 SYSTEM STATS")
                    color: "#00ff66"
                    font.bold: true
                    font.pixelSize: 13
                    Layout.fillWidth: true
                }

                Image {
                    id: dragHandle
                    width: 24
                    height: 24
                    sourceSize.width: 24
                    sourceSize.height: 24
                    fillMode: Image.PreserveAspectFit
                    source: {
                        var colorStr = dragArea.pressed ? "%23ffffff" : (dragArea.hovered ? "%2300ffd8" : "%2300ff66");
                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><circle cx='9' cy='5' r='1.5'></circle><circle cx='9' cy='12' r='1.5'></circle><circle cx='9' cy='19' r='1.5'></circle><circle cx='15' cy='5' r='1.5'></circle><circle cx='15' cy='12' r='1.5'></circle><circle cx='15' cy='19' r='1.5'></circle></svg>";
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor

                        property point clickPos: "0,0"
                        onPressed: {
                            clickPos = Qt.point(mouse.x, mouse.y)
                        }
                        onPositionChanged: {
                            if (pressed) {
                                var delta = Qt.point(mouse.x - clickPos.x, mouse.y - clickPos.y)
                                statsPanel.x = Math.max(0, Math.min(rootWindow.width - statsPanel.width, statsPanel.x + delta.x))
                                statsPanel.y = Math.max(50, Math.min(rootWindow.height - statsPanel.height, statsPanel.y + delta.y))
                            }
                        }
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: dragArea.hovered
                    ToolTip.text: qsTr("Przeciągnij panel statystyk")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                Text {
                    text: qsTr("RAM: ") + SystemStats.ramUsage.toFixed(1) + " MB"
                    color: "#00ff66"
                    font.pixelSize: 11
                    font.bold: true
                }

                Text {
                    text: qsTr("VRAM: ") + SystemStats.vramUsage.toFixed(1) + " MB"
                    color: "#00ff66"
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Text {
                text: qsTr("CPU: ") + SystemStats.cpuUsage.toFixed(1) + "%"
                color: "#00ff66"
                font.pixelSize: 11
                font.bold: true
            }

            Canvas {
                id: cpuCanvas
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 28
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    // Draw bright and thin background border
                    ctx.strokeStyle = "rgba(0, 255, 102, 0.7)";
                    ctx.lineWidth = 0.8;
                    ctx.strokeRect(0, 0, width, height);

                    // Draw faint gridlines
                    ctx.beginPath();
                    ctx.strokeStyle = "rgba(0, 255, 102, 0.15)";
                    ctx.lineWidth = 0.8;
                    // Horizontal gridlines
                    var hStep = height / 4;
                    for (var y = hStep; y < height; y += hStep) {
                        ctx.moveTo(0, y);
                        ctx.lineTo(width, y);
                    }
                    // Vertical gridlines every 1 minute (60 seconds / 60 points)
                    var colWidth = width / 6;
                    for (var col = 1; col < 6; ++col) {
                        var xv = col * colWidth;
                        ctx.moveTo(xv, 0);
                        ctx.lineTo(xv, height);
                    }
                    ctx.stroke();

                    // Draw CPU line & fill
                    if (statsPanel.cpuHistory && statsPanel.cpuHistory.length > 1) {
                        var step = width / (360 - 1);
                        var startX = width - (statsPanel.cpuHistory.length - 1) * step;

                        // 1. Draw gradient area under the curve
                        ctx.beginPath();
                        ctx.moveTo(startX, height);
                        for (var i = 0; i < statsPanel.cpuHistory.length; i++) {
                            var x = startX + i * step;
                            var yVal = height - (statsPanel.cpuHistory[i] / 100.0) * height;
                            yVal = Math.max(1, Math.min(height - 1, yVal));
                            ctx.lineTo(x, yVal);
                        }
                        ctx.lineTo(width, height);
                        ctx.closePath();
                        
                        var gradient = ctx.createLinearGradient(0, 0, 0, height);
                        gradient.addColorStop(0, "rgba(0, 255, 102, 0.35)");
                        gradient.addColorStop(1, "rgba(0, 255, 102, 0.03)");
                        ctx.fillStyle = gradient;
                        ctx.fill();

                        // 2. Stroke graph line on top
                        ctx.beginPath();
                        ctx.strokeStyle = "#00ff66";
                        ctx.lineWidth = 1.8; // thicker line for visibility
                        ctx.moveTo(startX, height - (statsPanel.cpuHistory[0] / 100.0) * height);
                        for (var i = 1; i < statsPanel.cpuHistory.length; i++) {
                            var x = startX + i * step;
                            var yVal = height - (statsPanel.cpuHistory[i] / 100.0) * height;
                            yVal = Math.max(1, Math.min(height - 1, yVal));
                            ctx.lineTo(x, yVal);
                        }
                        ctx.stroke();
                    }
                }
            }

            Text {
                text: qsTr("GPU: ") + SystemStats.gpuUsage.toFixed(1) + "%"
                color: "#00ff66"
                font.pixelSize: 11
                font.bold: true
            }

            Canvas {
                id: gpuCanvas
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 28
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    // Draw bright and thin background border
                    ctx.strokeStyle = "rgba(0, 255, 102, 0.7)";
                    ctx.lineWidth = 0.8;
                    ctx.strokeRect(0, 0, width, height);

                    // Draw faint gridlines
                    ctx.beginPath();
                    ctx.strokeStyle = "rgba(0, 255, 102, 0.15)";
                    ctx.lineWidth = 0.8;
                    // Horizontal gridlines
                    var hStep = height / 4;
                    for (var y = hStep; y < height; y += hStep) {
                        ctx.moveTo(0, y);
                        ctx.lineTo(width, y);
                    }
                    // Vertical gridlines every 1 minute (60 seconds / 60 points)
                    var colWidth = width / 6;
                    for (var col = 1; col < 6; ++col) {
                        var xv = col * colWidth;
                        ctx.moveTo(xv, 0);
                        ctx.lineTo(xv, height);
                    }
                    ctx.stroke();

                    // Draw GPU line & fill
                    if (statsPanel.gpuHistory && statsPanel.gpuHistory.length > 1) {
                        var step = width / (360 - 1);
                        var startX = width - (statsPanel.gpuHistory.length - 1) * step;

                        // 1. Draw gradient area under the curve
                        ctx.beginPath();
                        ctx.moveTo(startX, height);
                        for (var i = 0; i < statsPanel.gpuHistory.length; i++) {
                            var x = startX + i * step;
                            var yVal = height - (statsPanel.gpuHistory[i] / 100.0) * height;
                            yVal = Math.max(1, Math.min(height - 1, yVal));
                            ctx.lineTo(x, yVal);
                        }
                        ctx.lineTo(width, height);
                        ctx.closePath();
                        
                        var gradient = ctx.createLinearGradient(0, 0, 0, height);
                        gradient.addColorStop(0, "rgba(0, 255, 102, 0.35)");
                        gradient.addColorStop(1, "rgba(0, 255, 102, 0.03)");
                        ctx.fillStyle = gradient;
                        ctx.fill();

                        // 2. Stroke graph line on top
                        ctx.beginPath();
                        ctx.strokeStyle = "#00ff66";
                        ctx.lineWidth = 1.8; // thicker line for visibility
                        ctx.moveTo(startX, height - (statsPanel.gpuHistory[0] / 100.0) * height);
                        for (var i = 1; i < statsPanel.gpuHistory.length; i++) {
                            var x = startX + i * step;
                            var yVal = height - (statsPanel.gpuHistory[i] / 100.0) * height;
                            yVal = Math.max(1, Math.min(height - 1, yVal));
                            ctx.lineTo(x, yVal);
                        }
                        ctx.stroke();
                    }
                }
            }

            Text {
                text: qsTr("NET: ") + (SystemStats.netUsage >= 1.0 ? SystemStats.netUsage.toFixed(1) + " Mbps" : (SystemStats.netUsage * 1000.0).toFixed(0) + " kbps")
                color: "#00ff66"
                font.pixelSize: 11
                font.bold: true
            }

            Canvas {
                id: netCanvas
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 28
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    // Draw bright and thin background border
                    ctx.strokeStyle = "rgba(0, 255, 102, 0.7)";
                    ctx.lineWidth = 0.8;
                    ctx.strokeRect(0, 0, width, height);

                    // Draw faint gridlines
                    ctx.beginPath();
                    ctx.strokeStyle = "rgba(0, 255, 102, 0.15)";
                    ctx.lineWidth = 0.8;
                    // Horizontal gridlines
                    var hStep = height / 4;
                    for (var y = hStep; y < height; y += hStep) {
                        ctx.moveTo(0, y);
                        ctx.lineTo(width, y);
                    }
                    // Vertical gridlines every 1 minute
                    var colWidth = width / 6;
                    for (var col = 1; col < 6; ++col) {
                        var xv = col * colWidth;
                        ctx.moveTo(xv, 0);
                        ctx.lineTo(xv, height);
                    }
                    ctx.stroke();

                    // Find max value in history to scale Y-axis
                    var maxVal = 4.0; // minimum scale is 4.0 Mbps
                    if (statsPanel.netHistory) {
                        for (var i = 0; i < statsPanel.netHistory.length; i++) {
                            if (statsPanel.netHistory[i] > maxVal) {
                                maxVal = statsPanel.netHistory[i];
                            }
                        }
                    }

                    // Draw Network line & fill
                    if (statsPanel.netHistory && statsPanel.netHistory.length > 1) {
                        var step = width / (360 - 1);
                        var startX = width - (statsPanel.netHistory.length - 1) * step;

                        // 1. Draw gradient area under the curve
                        ctx.beginPath();
                        ctx.moveTo(startX, height);
                        for (var i = 0; i < statsPanel.netHistory.length; i++) {
                            var x = startX + i * step;
                            var yVal = height - (statsPanel.netHistory[i] / maxVal) * height;
                            yVal = Math.max(1, Math.min(height - 1, yVal));
                            ctx.lineTo(x, yVal);
                        }
                        ctx.lineTo(width, height);
                        ctx.closePath();
                        
                        var gradient = ctx.createLinearGradient(0, 0, 0, height);
                        gradient.addColorStop(0, "rgba(0, 255, 102, 0.35)");
                        gradient.addColorStop(1, "rgba(0, 255, 102, 0.03)");
                        ctx.fillStyle = gradient;
                        ctx.fill();

                        // 2. Stroke graph line on top
                        ctx.beginPath();
                        ctx.strokeStyle = "#00ff66";
                        ctx.lineWidth = 1.8; // thicker line for visibility
                        ctx.moveTo(startX, height - (statsPanel.netHistory[0] / maxVal) * height);
                        for (var i = 1; i < statsPanel.netHistory.length; i++) {
                            var x = startX + i * step;
                            var yVal = height - (statsPanel.netHistory[i] / maxVal) * height;
                            yVal = Math.max(1, Math.min(height - 1, yVal));
                            ctx.lineTo(x, yVal);
                        }
                        ctx.stroke();
                    }
                }
            }
        }

        // Resize Handlers (Self-contained self-mapping MouseAreas)
        MouseArea {
            id: resizeLeft
            width: 6
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            cursorShape: Qt.SizeHorCursor
            z: 10
            property real clickX: 0
            property real initX: 0
            property real initW: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickX = p.x
                initX = statsPanel.x
                initW = statsPanel.width
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaX = p.x - clickX
                    var newWidth = initW - deltaX
                    if (newWidth >= statsPanel.minWidth) {
                        statsPanel.x = initX + deltaX
                        statsPanel.width = newWidth
                    }
                }
            }
        }

        MouseArea {
            id: resizeRight
            width: 6
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            cursorShape: Qt.SizeHorCursor
            z: 10
            property real clickX: 0
            property real initW: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickX = p.x
                initW = statsPanel.width
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaX = p.x - clickX
                    var newWidth = initW + deltaX
                    if (newWidth >= statsPanel.minWidth) {
                        statsPanel.width = newWidth
                    }
                }
            }
        }

        MouseArea {
            id: resizeTop
            height: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            cursorShape: Qt.SizeVerCursor
            z: 10
            property real clickY: 0
            property real initY: 0
            property real initH: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickY = p.y
                initY = statsPanel.y
                initH = statsPanel.height
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaY = p.y - clickY
                    var newHeight = initH - deltaY
                    if (newHeight >= statsPanel.minHeight) {
                        statsPanel.y = initY + deltaY
                        statsPanel.height = newHeight
                    }
                }
            }
        }

        MouseArea {
            id: resizeBottom
            height: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            cursorShape: Qt.SizeVerCursor
            z: 10
            property real clickY: 0
            property real initH: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickY = p.y
                initH = statsPanel.height
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaY = p.y - clickY
                    var newHeight = initH + deltaY
                    if (newHeight >= statsPanel.minHeight) {
                        statsPanel.height = newHeight
                    }
                }
            }
        }

        MouseArea {
            id: resizeTopLeft
            width: 8
            height: 8
            anchors.left: parent.left
            anchors.top: parent.top
            cursorShape: Qt.SizeFDiagCursor
            z: 10
            property real clickX: 0
            property real clickY: 0
            property real initX: 0
            property real initY: 0
            property real initW: 0
            property real initH: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickX = p.x
                clickY = p.y
                initX = statsPanel.x
                initY = statsPanel.y
                initW = statsPanel.width
                initH = statsPanel.height
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaX = p.x - clickX
                    var deltaY = p.y - clickY
                    var newWidth = initW - deltaX
                    var newHeight = initH - deltaY
                    if (newWidth >= statsPanel.minWidth) {
                        statsPanel.x = initX + deltaX
                        statsPanel.width = newWidth
                    }
                    if (newHeight >= statsPanel.minHeight) {
                        statsPanel.y = initY + deltaY
                        statsPanel.height = newHeight
                    }
                }
            }
        }

        MouseArea {
            id: resizeTopRight
            width: 8
            height: 8
            anchors.right: parent.right
            anchors.top: parent.top
            cursorShape: Qt.SizeBDiagCursor
            z: 10
            property real clickX: 0
            property real clickY: 0
            property real initY: 0
            property real initW: 0
            property real initH: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickX = p.x
                clickY = p.y
                initY = statsPanel.y
                initW = statsPanel.width
                initH = statsPanel.height
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaX = p.x - clickX
                    var deltaY = p.y - clickY
                    var newWidth = initW + deltaX
                    var newHeight = initH - deltaY
                    if (newWidth >= statsPanel.minWidth) {
                        statsPanel.width = newWidth
                    }
                    if (newHeight >= statsPanel.minHeight) {
                        statsPanel.y = initY + deltaY
                        statsPanel.height = newHeight
                    }
                }
            }
        }

        MouseArea {
            id: resizeBottomLeft
            width: 8
            height: 8
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            cursorShape: Qt.SizeBDiagCursor
            z: 10
            property real clickX: 0
            property real clickY: 0
            property real initX: 0
            property real initW: 0
            property real initH: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickX = p.x
                clickY = p.y
                initX = statsPanel.x
                initW = statsPanel.width
                initH = statsPanel.height
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaX = p.x - clickX
                    var deltaY = p.y - clickY
                    var newWidth = initW - deltaX
                    var newHeight = initH + deltaY
                    if (newWidth >= statsPanel.minWidth) {
                        statsPanel.x = initX + deltaX
                        statsPanel.width = newWidth
                    }
                    if (newHeight >= statsPanel.minHeight) {
                        statsPanel.height = newHeight
                    }
                }
            }
        }

        MouseArea {
            id: resizeBottomRight
            width: 8
            height: 8
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            cursorShape: Qt.SizeFDiagCursor
            z: 10
            property real clickX: 0
            property real clickY: 0
            property real initW: 0
            property real initH: 0
            onPressed: {
                var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                clickX = p.x
                clickY = p.y
                initW = statsPanel.width
                initH = statsPanel.height
            }
            onPositionChanged: {
                if (pressed) {
                    var p = mapToItem(statsPanel.parent, mouse.x, mouse.y)
                    var deltaX = p.x - clickX
                    var deltaY = p.y - clickY
                    var newWidth = initW + deltaX
                    var newHeight = initH + deltaY
                    if (newWidth >= statsPanel.minWidth) {
                        statsPanel.width = newWidth
                    }
                    if (newHeight >= statsPanel.minHeight) {
                        statsPanel.height = newHeight
                    }
                }
            }
        }
    }

    // Loading overlay for auxiliary window
    Rectangle {
        id: loadingOverlay
        anchors.centerIn: parent
        width: loadingRow.implicitWidth + 40
        height: loadingRow.implicitHeight + 24
        color: "#cc121214"
        border.color: "#00f5d4"
        border.width: 1.5
        radius: 8
        z: 999999
        visible: loadingTimer.running

        RowLayout {
            id: loadingRow
            anchors.centerIn: parent
            spacing: 16

            Image {
                source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2.5' stroke-linecap='round'><path d='M12 2a10 10 0 1 0 10 10'></path></svg>"
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                fillMode: Image.PreserveAspectFit

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: loadingOverlay.visible
                }
            }

            Text {
                text: qsTr("Ładowanie nowego okna...")
                color: "white"
                font.bold: true
                font.pixelSize: 13
            }
        }
    }

    Timer {
        id: loadingTimer
        interval: 2000
        repeat: false
    }

    Loader {
        id: playbackWindowLoader
        active: false
        onLoaded: {
            item.show();
            item.raise();
        }
    }

    CursorShape {
        id: cursorShape

        autoHide: rootWindow.activeFocusItem != null && // Disabled when ApplicationWindow is't active
                  Context.config.fullScreen && viewSettings.hideCursorWhenFullScreen
        autoHideTimeout: 3000
        anchors.fill: parent
    }

}
