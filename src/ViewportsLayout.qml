import QtQml 2.12
import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtMultimedia 5.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Models 1.0
import CCTV_Viewer.Hikvision 1.0
import QtQuick.Controls 2.12

FocusScope {
    id: root

    property var size: model.size
    property var model: ViewportsLayoutModel {}
    property string color: "black"
    property int pendingSwapSourceIndex: -1

    readonly property alias fullScreenIndex: d.fullScreenIndex
    readonly property alias focusIndex: d.focusIndex
    readonly property alias activeFocusIndex: d.activeFocusIndex
    readonly property alias pressAndHoldIndex: d.pressAndHoldIndex
    readonly property alias multiselect: d.multiselect

    onVisibleChanged: d.selectionReset()

    QtObject {
        id: d

        property real layoutRatio: (model.aspectRatio.width * model.size.width) / (model.aspectRatio.height * model.size.height);
        property int fullScreenIndex: -1
        property int focusIndex: -1
        property int activeFocusIndex: -1
        property int pressAndHoldIndex: -1
        property int selectionIndex1: focusIndex
        property int selectionIndex2
        property bool multiselect: selectionIndex2 != selectionIndex1
        property int keyModifiers: 0

        onLayoutRatioChanged: selectionReset()
        onSelectionIndex1Changed: selectionReset()

        function columnFromIndex(index) {
            return index % root.size.width;
        }

        function rowFromIndex(index) {
            return Math.floor(index / root.size.width);
        }

        function indexFromAddress(column, row) {
            return row * root.size.width + column;
        }

        function selectionTop() {
            var top1 = rowFromIndex(selectionIndex1);
            var top2 = rowFromIndex(selectionIndex2);

            return Math.min(top1, top2);
        }

        function selectionRight() {
            var item1 = root.get(selectionIndex1);
            var item2 = root.get(selectionIndex2);
            var right1 = columnFromIndex(selectionIndex1);
            var right2 = columnFromIndex(selectionIndex2);

            if (item1 !== undefined) {
                right1 += root.get(selectionIndex1).columnSpan;
            }
            if (item2 !== undefined) {
                right2 += root.get(selectionIndex2).columnSpan;
            }

            return Math.max(right1, right2);
        }

        function selectionBottom() {
            var item1 = root.get(selectionIndex1);
            var item2 = root.get(selectionIndex2);
            var bottom1 = rowFromIndex(selectionIndex1);
            var bottom2 = rowFromIndex(selectionIndex2);

            if (item1 !== undefined) {
                bottom1 += root.get(selectionIndex1).rowSpan;
            }
            if (item2 !== undefined) {
                bottom2 += root.get(selectionIndex2).rowSpan;
            }

            return Math.max(bottom1, bottom2);
        }

        function selectionLeft() {
            var left1 = columnFromIndex(selectionIndex1);
            var left2 = columnFromIndex(selectionIndex2);

            return Math.min(left1, left2);
        }

        function selectionWidth() {
            return selectionRight() - selectionLeft();
        }

        function selectionHeight() {
            return selectionBottom() - selectionTop();
        }

        function selectionContains(index) {
            var column = columnFromIndex(index);
            var row = rowFromIndex(index);

            if (get(index) !== undefined && get(index).visible &&
                    column >= selectionLeft() && column < selectionRight() &&
                    row >= selectionTop() && row < selectionBottom()) {
                return true;
            }

            return false;
        }

        function selectionReset() {
            selectionIndex2 = selectionIndex1;
        }
    }

    Rectangle {
        color: root.color
        anchors.fill: parent
    }

    GridLayout {
        id: layout

        width: (root.width / root.height <= d.layoutRatio) ? root.width : root.height * d.layoutRatio;
        height: (root.width / root.height < d.layoutRatio) ? root.width / d.layoutRatio : root.height;
        columns: root.size.width
        rows: root.size.height
        columnSpacing: 0
        rowSpacing: 0
        anchors.centerIn: parent

        Repeater {
            id: repeater

            model: root.model

            onCountChanged: {
                if (d.fullScreenIndex >= count) {
                    d.fullScreenIndex = -1;
                }
                if (d.focusIndex) {
                    if (count == 1) {
                        d.focusIndex = 0;
                    } else {
                        d.focusIndex = -1;
                    }
                }
                if (d.activeFocusIndex) {
                    d.activeFocusIndex = -1;
                }
                if (d.pressAndHoldIndex) {
                    d.pressAndHoldIndex = -1;
                }
            }

            delegate: Item {
                id: container

                implicitWidth: (layout.width / root.size.width) * Math.max(viewport.columnSpan, 0)
                implicitHeight: (layout.height / root.size.height) * Math.max(viewport.rowSpan, 0)
                visible: root.visible && ((model.visible === ViewportsLayoutItem.Visible) ? true : false)

                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.columnSpan: Math.max(viewport.columnSpan, 1);
                Layout.rowSpan: Math.max(viewport.rowSpan, 1);

                Item {
                    id: viewport

                    x: 0
                    y: 0
                    width: parent.width
                    height: parent.height
                    activeFocusOnTab: d.fullScreenIndex < 0 || d.fullScreenIndex === model.index

                    // Drag source on the visible viewport itself!
                    Drag.active: viewportMouseArea.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.MoveAction
                    Drag.mimeData: {
                        "application/x-cctv-viewport-index": String(model.index)
                    }

                    property int cursorColumnOffset: 0
                    property int cursorRowOffset: 0
                    property bool fullScreen: false
                    
                    // Zoom properties
                    property real zoomScale: 1.0
                    property real panX: 0
                    property real panY: 0
                    readonly property bool zoomEnabled: fullScreen || (root.size.width === 1 && root.size.height === 1)

                    readonly property alias selected: d2.selected

                    readonly property alias url: d2.url
                    readonly property alias secondaryUrl: d2.secondaryUrl
                    readonly property alias column: d2.column
                    readonly property alias row: d2.row
                    readonly property alias columnSpan: d2.columnSpan
                    readonly property alias rowSpan: d2.rowSpan
                    readonly property alias volume: d2.volume
                    readonly property alias avFormatOptions: d2.avFormatOptions
                    readonly property alias streamMode: d2.streamMode

                    readonly property alias topIndex: d2.topIndex
                    readonly property alias rightIndex: d2.rightIndex
                    readonly property alias bottomIndex: d2.bottomIndex
                    readonly property alias leftIndex: d2.leftIndex

                    readonly property alias hasAudio: player.hasAudio

                    states: [
                        State {
                            name: "fullScreen"
                            when: viewport.fullScreen

                            PropertyChanges {
                                target: viewport
                                // HACK: Вводим зависимость от размера container для того,
                                // чтобы инициировать пересчет позиции viewport при изменении размера GridLayout.
                                x: container.width ? -container.mapToItem(layout, 0, 0).x : 0
                                y: container.height ? -container.mapToItem(layout, 0, 0).y : 0
                                width: layout.width
                                height: layout.height
                            }
                            PropertyChanges {
                                target: viewport.parent
                                z: 1
                            }
                        }
                    ]

                    transitions: [
                        Transition {
                            ParallelAnimation {
                                PropertyAnimation {
                                    properties: "x, y, z, width, height"
                                    easing.type: Easing.Linear
                                    duration: 250
                                }
                            }
                        }
                    ]

                    onVisibleChanged: {
                        fullScreen = false;
                        resetZoom();
                    }
                    onFullScreenChanged: {
                        d2.setCurrentIndex("fullScreenIndex", fullScreen)
                        if (!fullScreen) {
                            resetZoom();
                        }
                    }
                    onZoomEnabledChanged: {
                        if (!zoomEnabled) {
                            resetZoom();
                        }
                    }
                    onFocusChanged: {
                        d2.setCurrentIndex("focusIndex", focus);
                        d2.setCurrentIndex("pressAndHoldIndex", false);
                        fullScreen = false;
                    }
                    onActiveFocusChanged: d2.setCurrentIndex("activeFocusIndex", activeFocus)
                    onSelectedChanged: {
                        if (!selected) {
                            cursorColumnOffset = 0;
                            cursorRowOffset = 0;
                        }
                    }

                    function resetZoom() {
                        zoomScale = 1.0;
                        panX = 0;
                        panY = 0;
                    }

                    Keys.onPressed: {
                        var fullScreenKey = QT_TR_NOOP("F", "Shortcut");
                        if (event.text.toUpperCase() === fullScreenKey ||
                            event.text.toUpperCase() === qsTr(fullScreenKey)) {
                            fullScreen = (root.size.width > 1 && root.size.height > 1) ? !fullScreen : false;
                            d.selectionReset();
                        }

                        function keyNavigationHandler(keyNavigationCallback) {
                            if (!fullScreen) {
                                if (d.activeFocusIndex >= 0 && d.keyModifiers & Qt.ShiftModifier) {
                                    d.selectionIndex2 = keyNavigationCallback(d.selectionIndex2);
                                } else {
                                    root.get(keyNavigationCallback(model.index)).forceActiveFocus();
                                }
                            }
                        }

                        switch (event.key) {
                        case Qt.Key_Escape:
                            focus = false;
                            fullScreen = false;
                            break;
                        case Qt.Key_Up:
                            function keyUpCallback(index) {
                                var topIndex = root.get(index).topIndex;

                                if (topIndex !== index) {
                                    root.get(topIndex).cursorColumnOffset =
                                            d.columnFromIndex(index) + root.get(index).cursorColumnOffset - d.columnFromIndex(topIndex);
                                } else {
                                    root.get(index).cursorRowOffset = Math.max(root.get(index).cursorRowOffset - 1, 0);
                                }

                                return topIndex;
                            }

                            keyNavigationHandler(keyUpCallback);
                            break;
                        case Qt.Key_Down:
                            function keyDownCallback(index) {
                                var bottomIndex = root.get(index).bottomIndex;

                                if (bottomIndex !== index) {
                                    root.get(bottomIndex).cursorColumnOffset =
                                            d.columnFromIndex(index) + root.get(index).cursorColumnOffset - d.columnFromIndex(bottomIndex);
                                } else {
                                    root.get(index).cursorRowOffset = Math.min(root.get(index).cursorRowOffset + 1, root.get(index).rowSpan - 1);
                                }

                                return bottomIndex;
                            }

                            keyNavigationHandler(keyDownCallback);
                            break;
                        case Qt.Key_Right:
                            function keyRightCallback(index) {
                                var rightIndex = root.get(index).rightIndex;

                                if (rightIndex !== index) {
                                    root.get(rightIndex).cursorRowOffset =
                                            d.rowFromIndex(index) + root.get(index).cursorRowOffset - d.rowFromIndex(rightIndex);
                                } else {
                                    root.get(index).cursorColumnOffset = Math.min(root.get(index).cursorColumnOffset + 1, root.get(index).columnSpan - 1);
                                }

                                return rightIndex;
                            }

                            keyNavigationHandler(keyRightCallback);
                            break;
                        case Qt.Key_Left:
                            function keyLeftCallback(index) {
                                var leftIndex = root.get(index).leftIndex;

                                if (leftIndex !== index) {
                                    root.get(leftIndex).cursorRowOffset =
                                            d.rowFromIndex(index) + root.get(index).cursorRowOffset - d.rowFromIndex(leftIndex);
                                } else {
                                    root.get(index).cursorColumnOffset = Math.max(root.get(index).cursorColumnOffset - 1, 0);
                                }

                                return leftIndex;
                            }

                            keyNavigationHandler(keyLeftCallback);
                            break;
                        case Qt.Key_Plus:
                        case Qt.Key_Equal:
                            if (event.text === "+" || event.key === Qt.Key_Plus) {
                                if (player.recorderIp !== "") {
                                    if (!event.isAutoRepeat) {
                                        HikvisionManager.ptzZoom(player.recorderIp, player.recorderPort, player.username, player.password, player.channelId, 11, false);
                                    }
                                    event.accepted = true;
                                }
                            }
                            break;
                        case Qt.Key_Minus:
                            if (event.text === "-" || event.key === Qt.Key_Minus) {
                                if (player.recorderIp !== "") {
                                    if (!event.isAutoRepeat) {
                                        HikvisionManager.ptzZoom(player.recorderIp, player.recorderPort, player.username, player.password, player.channelId, 12, false);
                                    }
                                    event.accepted = true;
                                }
                            }
                            break;
                        }
                    }

                    Keys.onReleased: {
                        if (event.isAutoRepeat) {
                            return;
                        }
                        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+") {
                            if (player.recorderIp !== "") {
                                HikvisionManager.ptzZoom(player.recorderIp, player.recorderPort, player.username, player.password, player.channelId, 11, true);
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Minus || event.text === "-") {
                            if (player.recorderIp !== "") {
                                HikvisionManager.ptzZoom(player.recorderIp, player.recorderPort, player.username, player.password, player.channelId, 12, true);
                                event.accepted = true;
                            }
                        }
                    }

                    QtObject {
                        id: d2

                        property bool selected: d.selectionContains(model.index)

                        property string url: model.url
                        property string secondaryUrl: model.secondaryUrl
                        property bool secondaryUrlFailed: false
                        property int column: d.columnFromIndex(model.index)
                        property int row: d.rowFromIndex(model.index)
                        property int columnSpan: model.columnSpan
                        property int rowSpan: model.rowSpan
                        property real volume: model.volume
                        property var avFormatOptions: model.avFormatOptions
                        property int streamMode: model.streamMode

                        onSecondaryUrlChanged: secondaryUrlFailed = false

                        property int topIndex: spanningIndex(viewport.column + viewport.cursorColumnOffset,
                                                             Number(viewport.row - 1).clamp(0, root.size.height - 1))

                        property int bottomIndex: spanningIndex(viewport.column + viewport.cursorColumnOffset,
                                                                Number(viewport.row + viewport.rowSpan).clamp(0, root.size.height - 1))

                        property int rightIndex: spanningIndex(Utils.ifLeftToRight(
                                                               Number(viewport.column + viewport.columnSpan).clamp(0, root.size.width - 1),
                                                               Number(viewport.column - 1).clamp(0, root.size.width - 1)),
                                                               viewport.row + viewport.cursorRowOffset)

                        property int leftIndex: spanningIndex(Utils.ifLeftToRight(
                                                              Number(viewport.column - 1).clamp(0, root.size.width - 1),
                                                              Number(viewport.column + viewport.columnSpan).clamp(0, root.size.width - 1)),
                                                              viewport.row + viewport.cursorRowOffset)

                        function setCurrentIndex(key, current) {
                            if (current === true) {
                                d[key] = model.index;
                            } else if (d[key] === model.index) {
                                d[key] = -1;
                            }
                        }

                        function spanningIndex(column, row) {
                            var spanningIndex = d.indexFromAddress(column, row);

                            if (spanningIndex !== model.index) {
                                var spanningItem = root.get(spanningIndex);

                                if (spanningItem !== undefined && !spanningItem.visible) {
                                    spanningIndex = d.indexFromAddress(d.columnFromIndex(spanningIndex) + spanningItem.columnSpan,
                                                                       d.rowFromIndex(spanningIndex) + spanningItem.rowSpan);
                                }
                            }

                            return spanningIndex;
                        }
                    }

                    Rectangle {
                        id: playerContainer

                        color: root.color
                        anchors.fill: parent
                        clip: true
                        Player {
                            id: player
                            visible: root.visible
                            index: model.index

                            color: root.color
                            source: {
                                if (viewport.streamMode === 1) {
                                    return viewport.url;
                                } else if (viewport.streamMode === 2) {
                                    return (String(viewport.secondaryUrl) !== "" && !d2.secondaryUrlFailed) ? viewport.secondaryUrl : viewport.url;
                                } else { // Auto (0)
                                    if ((root.size.width > 1 || root.size.height > 1) && !viewport.fullScreen && String(viewport.secondaryUrl) !== "" && !d2.secondaryUrlFailed) {
                                        return viewport.secondaryUrl;
                                    }
                                    return viewport.url;
                                }
                            }
                            volume: Math.max(viewport.volume, root.fullScreenIndex === model.index && viewportSettings.unmuteWhenFullScreen)
                            avOptions: viewport.avFormatOptions
                            loops: MediaPlayer.Infinite
                            isSubStream: {
                                if (player.isOneToOne) {
                                    return false;
                                }
                                if (viewport.streamMode === 1) {
                                    return false;
                                } else if (viewport.streamMode === 2) {
                                    return String(viewport.secondaryUrl) !== "" && !d2.secondaryUrlFailed;
                                } else { // Auto (0)
                                    return (root.size.width > 1 || root.size.height > 1) && !viewport.fullScreen && String(viewport.secondaryUrl) !== "" && !d2.secondaryUrlFailed;
                                }
                            }

                            onMediaError: {
                                if (errorSource === String(viewport.secondaryUrl)) {
                                    d2.secondaryUrlFailed = true;
                                }
                            }
                            
                            // Apply zoom transformation when zoom is enabled
                            scale: viewport.zoomEnabled ? viewport.zoomScale : 1.0
                            transformOrigin: Item.TopLeft
                            
                            x: viewport.zoomEnabled ? viewport.panX : 0
                            y: viewport.zoomEnabled ? viewport.panY : 0
                            
                            width: parent.width
                            height: parent.height
                            
                            Behavior on scale {
                                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                            }
                            Behavior on x {
                                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                            }
                            Behavior on y {
                                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                            }
                        }
                    }

                    Rectangle {
                        id: selectionRect

                        color: "transparent"
                        anchors.fill: parent

                        states: [
                            State {
                                name: "multiselect"
                                when: root.multiselect && viewport.selected

                                PropertyChanges {
                                    target: selectionRect
                                    color: "#4000a8ff"
                                }
                            }
                        ]
                    }

                    Rectangle {
                        id: selectionFrame

                        color: "transparent"
                        border.color: "transparent"
                        anchors.fill: parent

                        states: [
                            State {
                                name: "active"
                                when: viewport.activeFocus && !Context.config.kioskMode

                                PropertyChanges {
                                    target: selectionFrame
                                    border.width: 1
                                    border.color: "#00dd00"
                                }
                            },
                            State {
                                name: "swapSource"
                                when: root.pendingSwapSourceIndex === model.index

                                PropertyChanges {
                                    target: selectionFrame
                                    border.width: 2
                                    border.color: "#00f5d4"
                                }
                            }
                        ]
                    }

                    Item {
                        id: dragDummyViewport
                        width: 1; height: 1
                        visible: false
                    }
                    MouseArea {
                        id: viewportMouseArea
                        z: -1
                        anchors.fill: parent
                        
                        // Enable wheel events for zooming
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: dragDummyViewport
                        drag.threshold: 15
                        cursorShape: root.pendingSwapSourceIndex >= 0 ? Qt.DragMoveCursor : Qt.ArrowCursor

                        onPressed: {
                            if (mouse.button === Qt.RightButton) {
                                if (generalSettings.enableContextMenu) {
                                    root.pendingSwapSourceIndex = -1;
                                    contextMenu.popup();
                                }
                                return;
                            }
                            console.log("[CCTV Viewer Debug] Pressed viewport. index =", model.index, "pendingSwapSourceIndex =", root.pendingSwapSourceIndex);
                            if (root.pendingSwapSourceIndex >= 0 && generalSettings.allowSwappingViewports) {
                                var sourceIndex = root.pendingSwapSourceIndex;
                                var targetIndex = model.index;
                                if (sourceIndex !== targetIndex) {
                                    var sourceItem = root.model.get(sourceIndex);
                                    var targetItem = root.model.get(targetIndex);
                                    if (sourceItem && targetItem) {
                                        var tempUrl = sourceItem.url;
                                        var tempSecUrl = sourceItem.secondaryUrl;
                                        var tempVol = sourceItem.volume;
                                        var tempOpts = sourceItem.avFormatOptions;
                                        var tempStreamMode = sourceItem.streamMode;

                                        sourceItem.url = targetItem.url;
                                        sourceItem.secondaryUrl = targetItem.secondaryUrl;
                                        sourceItem.volume = targetItem.volume;
                                        sourceItem.avFormatOptions = targetItem.avFormatOptions;
                                        sourceItem.streamMode = targetItem.streamMode;

                                        targetItem.url = tempUrl;
                                        targetItem.secondaryUrl = tempSecUrl;
                                        targetItem.volume = tempVol;
                                        targetItem.avFormatOptions = tempOpts;
                                        targetItem.streamMode = tempStreamMode;

                                        Utils.log_info("Swapped viewport " + (sourceIndex + 1) + " with " + (targetIndex + 1));
                                    }
                                }
                                root.pendingSwapSourceIndex = -1;
                            } else {
                                if (d.activeFocusIndex >= 0 && d.keyModifiers & Qt.ShiftModifier) {
                                    d.selectionIndex2 = model.index;
                                } else {
                                    viewport.forceActiveFocus();
                                    d.selectionReset();
                                }
                            }
                        }
                        onReleased: {
                            dragDummyViewport.x = 0;
                            dragDummyViewport.y = 0;
                        }
                        onPressAndHold: d2.setCurrentIndex("pressAndHoldIndex", true)
                        onDoubleClicked: {
                            viewport.fullScreen = (root.size.width > 1 && root.size.height > 1) ? !viewport.fullScreen : false;
                            d.selectionReset();
                        }

                        onMouseXChanged: mouseMoveHandler()
                        onMouseYChanged: mouseMoveHandler()
                        
                        // Handle mousewheel zoom when in fullscreen (requires CTRL modifier)
                        onWheel: {
                            if (wheel.modifiers & Qt.ControlModifier) {
                                if (!viewport.fullScreen && root.size.width > 1 && root.size.height > 1) {
                                    viewport.fullScreen = true;
                                    viewport.forceActiveFocus();
                                    d.selectionReset();
                                }

                                if (viewport.zoomEnabled) {
                                    var delta = wheel.angleDelta.y / 120;
                                    var zoomFactor = 1 + (delta * 0.1);

                                    var newScale = viewport.zoomScale * zoomFactor;
                                    newScale = Number(newScale).clamp(1.0, 10.0);

                                    if (newScale !== viewport.zoomScale) {
                                        var mouseX = wheel.x;
                                        var mouseY = wheel.y;

                                        var imageX = (mouseX - viewport.panX) / viewport.zoomScale;
                                        var imageY = (mouseY - viewport.panY) / viewport.zoomScale;

                                        viewport.zoomScale = newScale;

                                        viewport.panX = mouseX - imageX * newScale;
                                        viewport.panY = mouseY - imageY * newScale;

                                        var minPanX = viewport.width - (viewport.width * newScale);
                                        var maxPanX = 0;
                                        var minPanY = viewport.height - (viewport.height * newScale);
                                        var maxPanY = 0;

                                        viewport.panX = Number(viewport.panX).clamp(minPanX, maxPanX);
                                        viewport.panY = Number(viewport.panY).clamp(minPanY, maxPanY);
                                    }
                                }

                                wheel.accepted = true;
                            }
                        }

                        function mouseMoveHandler() {
                            if (!containsMouse) {
                                var selectionIndex2 = viewport.indexAt(mouseX, mouseY);

                                if (selectionIndex2 >= 0) {
                                    d.selectionIndex2 = selectionIndex2;
                                }
                            } else {
                                if (!(d.keyModifiers & Qt.ShiftModifier)) {
                                    d.selectionReset();
                                }
                            }
                        }
                    }

                    Menu {
                        id: contextMenu
                        
                        topPadding: 5
                        bottomPadding: 5
                        
                        onClosed: {
                            streamSubMenu.close();
                        }
                        
                        enter: Transition {
                            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                        }
                        exit: Transition {
                            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 100; easing.type: Easing.InQuad }
                            NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 100; easing.type: Easing.InQuad }
                        }
                        
                        background: Rectangle {
                            implicitWidth: 160
                            color: "#151d24"
                            border.color: "#ff7a00"
                            border.width: 1
                            radius: 6
                        }
                        
                        MenuItem {
                            text: qsTr("Zamień miejscami")
                            visible: generalSettings.allowSwappingViewports
                            enabled: model.url !== ""
                            leftPadding: 12
                            
                            contentItem: Text {
                                text: parent.text
                                font {
                                    pixelSize: 11
                                    bold: true
                                }
                                color: parent.enabled ? (parent.hovered ? "#00f5d4" : "#eeeeee") : "#555555"
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: parent.hovered ? "#2a3540" : "transparent"
                                border.color: parent.hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onHoveredChanged: {
                                if (hovered) {
                                    streamSubMenu.close();
                                }
                            }
                            
                            onTriggered: {
                                console.log("[CCTV Viewer Debug] Triggered context menu Zamień miejscami on index =", model.index);
                                root.pendingSwapSourceIndex = model.index;
                            }
                        }

                        MenuItem {
                            id: streamSelectMenuItem
                            text: qsTr("Wybór streamu")
                            visible: generalSettings.enableStreamSelection
                            enabled: model.url !== ""
                            leftPadding: 12
                            
                            contentItem: RowLayout {
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: streamSelectMenuItem.text
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: streamSelectMenuItem.enabled ? (streamSelectMenuItem.hovered ? "#00f5d4" : "#eeeeee") : "#555555"
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: "▶"
                                    font {
                                        pixelSize: 9
                                        bold: true
                                    }
                                    color: streamSelectMenuItem.enabled ? (streamSelectMenuItem.hovered ? "#00f5d4" : "#eeeeee") : "#555555"
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    rightPadding: 8
                                }
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: streamSelectMenuItem.hovered ? "#2a3540" : "transparent"
                                border.color: streamSelectMenuItem.hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onHoveredChanged: {
                                if (hovered && enabled) {
                                    streamSubMenu.popup(streamSelectMenuItem, streamSelectMenuItem.width, 0);
                                }
                            }
                            
                            onTriggered: {
                                streamSubMenu.popup(streamSelectMenuItem, streamSelectMenuItem.width, 0);
                            }
                        }

                        MenuItem {
                            id: removeCameraMenuItem
                            text: qsTr("Usuń kamerę")
                            visible: generalSettings.enableRemoveCamera
                            enabled: model.url !== ""
                            leftPadding: 12
                            
                            contentItem: Text {
                                text: removeCameraMenuItem.text
                                font {
                                    pixelSize: 11
                                    bold: true
                                }
                                color: removeCameraMenuItem.enabled ? (removeCameraMenuItem.hovered ? "#ff3333" : "#eeeeee") : "#555555"
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: removeCameraMenuItem.hovered ? "#2a3540" : "transparent"
                                border.color: removeCameraMenuItem.hovered ? "#ff3333" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onHoveredChanged: {
                                if (hovered) {
                                    streamSubMenu.close();
                                }
                            }
                            
                            onTriggered: {
                                removeCameraConfirmDialog.index = model.index;
                                removeCameraConfirmDialog.open();
                            }
                        }

                        MenuItem {
                            id: changeSettingsMenuItem
                            text: qsTr("Zmień ustawienia")
                            visible: generalSettings.enableChangeViewportSettings
                            enabled: model.url !== "" && model.url.indexOf("hikvision://") !== 0
                            leftPadding: 12
                            
                            contentItem: Text {
                                text: changeSettingsMenuItem.text
                                font {
                                    pixelSize: 11
                                    bold: true
                                }
                                color: changeSettingsMenuItem.enabled ? (changeSettingsMenuItem.hovered ? "#00f5d4" : "#eeeeee") : "#555555"
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: changeSettingsMenuItem.hovered ? "#2a3540" : "transparent"
                                border.color: changeSettingsMenuItem.hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onHoveredChanged: {
                                if (hovered) {
                                    streamSubMenu.close();
                                }
                            }
                            
                            onTriggered: {
                                viewportSettingsDialog.index = model.index;
                                viewportSettingsDialog.open();
                            }
                        }
                    }

                    Menu {
                        id: streamSubMenu
                        
                        topPadding: 5
                        bottomPadding: 5
                        
                        enter: Transition {
                            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                        }
                        exit: Transition {
                            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 100; easing.type: Easing.InQuad }
                            NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 100; easing.type: Easing.InQuad }
                        }
                        
                        background: Rectangle {
                            implicitWidth: 160
                            color: "#151d24"
                            border.color: "#ff7a00"
                            border.width: 1
                            radius: 6
                        }
                        
                        MenuItem {
                            id: streamAutoItem
                            text: qsTr("Automatycznie")
                            leftPadding: 12
                            
                            contentItem: RowLayout {
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: streamAutoItem.text
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: streamAutoItem.hovered ? "#00f5d4" : (viewport.streamMode === 0 ? "#00f5d4" : "#eeeeee")
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: "✓"
                                    visible: viewport.streamMode === 0
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: "#00f5d4"
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    rightPadding: 8
                                }
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: streamAutoItem.hovered ? "#2a3540" : "transparent"
                                border.color: streamAutoItem.hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onTriggered: {
                                var item = root.model.get(model.index);
                                if (item) {
                                    item.streamMode = 0;
                                }
                            }
                        }
                        
                        MenuItem {
                            id: streamMainItem
                            text: qsTr("Tylko MAIN")
                            leftPadding: 12
                            
                            contentItem: RowLayout {
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: streamMainItem.text
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: streamMainItem.hovered ? "#00f5d4" : (viewport.streamMode === 1 ? "#00f5d4" : "#eeeeee")
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: "✓"
                                    visible: viewport.streamMode === 1
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: "#00f5d4"
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    rightPadding: 8
                                }
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: streamMainItem.hovered ? "#2a3540" : "transparent"
                                border.color: streamMainItem.hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onTriggered: {
                                var item = root.model.get(model.index);
                                if (item) {
                                    item.streamMode = 1;
                                }
                            }
                        }
                        
                        MenuItem {
                            id: streamSubItem
                            text: qsTr("Tylko SUB")
                            leftPadding: 12
                            
                            contentItem: RowLayout {
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: streamSubItem.text
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: streamSubItem.hovered ? "#00f5d4" : (viewport.streamMode === 2 ? "#00f5d4" : "#eeeeee")
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: "✓"
                                    visible: viewport.streamMode === 2
                                    font {
                                        pixelSize: 11
                                        bold: true
                                    }
                                    color: "#00f5d4"
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                    rightPadding: 8
                                }
                            }
                            
                            background: Rectangle {
                                implicitWidth: 150
                                implicitHeight: 32
                                color: streamSubItem.hovered ? "#2a3540" : "transparent"
                                border.color: streamSubItem.hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                            
                            onTriggered: {
                                var item = root.model.get(model.index);
                                if (item) {
                                    item.streamMode = 2;
                                }
                            }
                        }
                    }

                    // DropArea ON TOP of everything — accepts both camera and viewport drops
                    DropArea {
                        id: dropArea
                        anchors.fill: parent

                        // Highlight on drag hover
                        Rectangle {
                            anchors.fill: parent
                            color: dropArea.containsDrag ? "#3000f5d4" : "transparent"
                            border.color: dropArea.containsDrag ? "#00f5d4" : "transparent"
                            border.width: 2
                            z: 100

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        onEntered: {
                            if (drag.hasFormat("application/x-cctv-viewport-index") || drag.hasFormat("application/x-cctv-camera-url") || drag.hasText) {
                                drag.accept();
                            } else {
                                drag.accepted = false;
                            }
                        }

                        onPositionChanged: {
                            if (drag.hasFormat("application/x-cctv-viewport-index") || drag.hasFormat("application/x-cctv-camera-url") || drag.hasText) {
                                drag.accept();
                            } else {
                                drag.accepted = false;
                            }
                        }

                        onDropped: {
                            // Camera drop from NvrCamerasWindow
                            if (drop.hasText) {
                                var url = "";
                                // Try custom MIME type first
                                if (drop.hasFormat("application/x-cctv-camera-url")) {
                                    url = drop.getDataAsString("application/x-cctv-camera-url");
                                } else {
                                    url = drop.text;
                                }

                                if (url && url.indexOf("hikvision://") === 0) {
                                    root.model.get(model.index).url = url;
                                    root.model.get(model.index).secondaryUrl = url;
                                    root.model.get(model.index).streamMode = 0;
                                    drop.accept(Qt.CopyAction);
                                    Utils.log_info("Dropped camera on viewport " + (model.index + 1));
                                    return;
                                }
                            }

                            // Viewport swap
                            if (drop.hasFormat("application/x-cctv-viewport-index")) {
                                var sourceIndex = parseInt(drop.getDataAsString("application/x-cctv-viewport-index"));
                                if (sourceIndex !== model.index && sourceIndex >= 0 && sourceIndex < root.model.count) {
                                    var sourceItem = root.model.get(sourceIndex);
                                    var targetItem = root.model.get(model.index);
                                    if (sourceItem && targetItem) {
                                        var tempUrl = sourceItem.url;
                                        var tempSecUrl = sourceItem.secondaryUrl;
                                        var tempVol = sourceItem.volume;
                                        var tempOpts = sourceItem.avFormatOptions;
                                        var tempStreamMode = sourceItem.streamMode;

                                        sourceItem.url = targetItem.url;
                                        sourceItem.secondaryUrl = targetItem.secondaryUrl;
                                        sourceItem.volume = targetItem.volume;
                                        sourceItem.avFormatOptions = targetItem.avFormatOptions;
                                        sourceItem.streamMode = targetItem.streamMode;

                                        targetItem.url = tempUrl;
                                        targetItem.secondaryUrl = tempSecUrl;
                                        targetItem.volume = tempVol;
                                        targetItem.avFormatOptions = tempOpts;
                                        targetItem.streamMode = tempStreamMode;

                                        drop.accept(Qt.MoveAction);
                                        Utils.log_info("Swapped viewport " + (sourceIndex + 1) + " with " + (model.index + 1));
                                    }
                                }
                                return;
                            }
                        }
                    }

                    function indexAt(x, y) {
                        for (var i = 0; i < repeater.count; ++i) {
                            var itemTo = repeater.itemAt(i);

                            if (i === model.index) {
                                if (contains(Qt.point(x, y))) {
                                    return i;
                                }
                            } else {
                                var mappedPoint = mapToItem(itemTo, x, y);

                                if (itemTo.contains(mappedPoint)) {
                                    return i;
                                }
                            }
                        }

                        return -1;
                    }
                }
            }
        }
    }

    Keys.onPressed: {
        d.keyModifiers = event.modifiers;

        switch (event.key) {
        case Qt.Key_Delete:
            for (var i = 0; i < root.size.width * root.size.height; ++i) {
                if (root.get(i).selected) {
                    model.get(i).url = "";
                    model.get(i).secondaryUrl = "";
                    model.get(i).volume = 0;
                    model.get(i).avFormatOptions = layoutsCollectionSettings.toJSValue("defaultAVFormatOptions");
                    model.get(i).streamMode = 0;
                }
            }
            break;
        }
    }
    Keys.onReleased: d.keyModifiers = event.modifiers

    function get(index) {
        if (index >= 0 && index < repeater.count) {
            var item = repeater.itemAt(index);
            if (item === null) {
                return undefined;
            }

            return item.children[0];
        }

        return;
    }

    function indexAt(x, y) {
        for (var i = 0; i < repeater.count; ++i) {
            var itemTo = repeater.itemAt(i);
            var mappedPoint = mapToItem(itemTo, x, y);

            if (itemTo.contains(mappedPoint)) {
                return i;
            }
        }

        return -1;
    }

    function mergeCells(testMode) {
        var topLeftIndex = d.indexFromAddress(d.selectionLeft(), d.selectionTop());
        if (topLeftIndex < 0 || topLeftIndex >= model.count) {
            return false;
        }
        var topLeftElement = model.get(topLeftIndex);

        if (d.selectionWidth() !== d.selectionHeight() ||
            d.selectionWidth() <= 0 || d.selectionHeight() <= 0 ||
            (d.selectionWidth() >= root.size.width && d.selectionHeight() >= root.size.height)) {
            return false;
        }

        if (!testMode) {
            if (topLeftElement.columnSpan > 1 || topLeftElement.rowSpan > 1) {
                topLeftElement.columnSpan = 1;
                topLeftElement.rowSpan = 1;
            } else {
                topLeftElement.columnSpan = d.selectionWidth();
                topLeftElement.rowSpan = d.selectionHeight();
            }

            d.selectionReset();
            model.normalize();
        }

        return true;
    }

    ConfirmDialog {
        id: removeCameraConfirmDialog
        title: qsTr("Confirm Camera Removal")
        iconSource: "qrc:/images/icon-trash.svg"
        message: qsTr("Are you sure you want to remove the camera from this viewport?")
        property int index: -1
        
        onAccepted: {
            if (index >= 0 && index < root.model.count) {
                var item = root.model.get(index);
                if (item) {
                    item.url = "";
                    item.secondaryUrl = "";
                    item.volume = 0.0;
                    item.avFormatOptions = {};
                    item.streamMode = 0;
                }
            }
        }
    }

    ViewportSettingsDialog {
        id: viewportSettingsDialog
    }
}
