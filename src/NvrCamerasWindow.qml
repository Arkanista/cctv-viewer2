import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Themes 1.0

Window {
    id: camerasWin

    width: 900
    height: 600
    color: "#0f151b"
    title: recorder.name ? qsTr("Cameras on %1").arg(recorder.name) : qsTr("Cameras on %1").arg(recorder.ip)

    property var recorder: ({})

    onClosing: {
        camerasWin.destroy();
    }

    // Track thumbnail refresh counters per cache key
    property var refreshCounters: ({})

    // Helper to build the RTSP sub-stream URL for thumbnails
    function subStreamUrl(rec, cam) {
        return "rtsp://" + rec.username + ":" + rec.password + "@" + rec.ip + ":554/Streaming/Channels/" + cam.channelId + "02";
    }

    // Helper to build the cache key for a camera
    function cacheKeyFor(rec, cam) {
        return rec.ip + "_" + cam.channelId;
    }

    function generateThumbnails() {
        var recMap = {
            "ip": recorder.ip,
            "port": recorder.port,
            "username": recorder.username,
            "password": recorder.password,
            "cameras": recorder.cameras || []
        };
        ThumbnailProvider.generateThumbnails(recMap);
    }

    // Listen for thumbnail ready signals
    Connections {
        target: ThumbnailProvider

        function onThumbnailReady(cacheKey) {
            var val = camerasWin.refreshCounters[cacheKey] || 0;
            var newCounters = {}
            for (var k in camerasWin.refreshCounters) {
                newCounters[k] = camerasWin.refreshCounters[k];
            }
            newCounters[cacheKey] = val + 1;
            camerasWin.refreshCounters = newCounters; // trigger binding update
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // Header Section
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "📹"
                font.pixelSize: 18
                color: "#00f5d4"
            }

            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true

                Text {
                    text: recorder.name ? recorder.name : recorder.ip
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                }

                Text {
                    text: qsTr("IP: %1 | Port: %2 | %3 channels").arg(recorder.ip).arg(recorder.port).arg(recorder.cameras ? recorder.cameras.length : 0)
                    color: "#8898a6"
                    font.pixelSize: 9
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Generate thumbnails")
                onClicked: camerasWin.generateThumbnails()
                background: Rectangle {
                    color: parent.down ? "#1a232c" : (parent.hovered ? "#2a3540" : "#1c242c")
                    border.color: "#3a86ff"
                    radius: 4
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#2a3540"
        }

        // Scrollable Tile Container
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                contentWidth: parent.width
                contentHeight: flowGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: flowGrid
                    width: parent.width
                    columns: 5
                    rowSpacing: 8
                    columnSpacing: 8

                    Repeater {
                        id: cameraRepeater
                        model: recorder.cameras || []
                        delegate: Item {
                            id: tileWrapper
                            Layout.fillWidth: true
                            height: 140

                            property string cameraUrl: "hikvision://" + recorder.username + ":" + recorder.password + "@" + recorder.ip + ":" + recorder.port + "/" + modelData.channelId
                            // Read name directly from global JSON so it stays in sync even when the
                            // Repeater reuses this delegate instead of recreating it.
                            property string cameraName: {
                                // Establish a reactive binding on the global settings string.
                                // Whenever hikvisionRecordersJson changes this expression re-evaluates.
                                var _dep = rootWindow.hikvisionRecordersJson;
                                try {
                                    var _data = JSON.parse(rootWindow.hikvisionRecordersJson || "[]");
                                    for (var _i = 0; _i < _data.length; _i++) {
                                        if (_data[_i].ip === recorder.ip) {
                                            var _cams = _data[_i].cameras || [];
                                            for (var _j = 0; _j < _cams.length; _j++) {
                                                if (String(_cams[_j].channelId) === String(modelData.channelId)) {
                                                    return _cams[_j].customName || _cams[_j].name || "";
                                                }
                                            }
                                        }
                                    }
                                } catch(_e) {}
                                return modelData.customName || modelData.name || "";
                            }
                            property string cameraCustomName: {
                                var _dep = rootWindow.hikvisionRecordersJson;
                                try {
                                    var _data = JSON.parse(rootWindow.hikvisionRecordersJson || "[]");
                                    for (var _i = 0; _i < _data.length; _i++) {
                                        if (_data[_i].ip === recorder.ip) {
                                            var _cams = _data[_i].cameras || [];
                                            for (var _j = 0; _j < _cams.length; _j++) {
                                                if (String(_cams[_j].channelId) === String(modelData.channelId)) {
                                                    return _cams[_j].customName || "";
                                                }
                                            }
                                        }
                                    }
                                } catch(_e) {}
                                return modelData.customName || "";
                            }
                            property string channelId: String(modelData.channelId)
                            property string thumbnailCacheKey: camerasWin.cacheKeyFor(recorder, modelData)

                            // React to refresh counter changes
                            property int refreshCount: camerasWin.refreshCounters[thumbnailCacheKey] || 0

                            Rectangle {
                                id: tile
                                anchors.fill: parent
                                color: tileMouseArea.containsMouse ? "#1500f5d4" : "#1c242c"
                                radius: 6
                                border.color: tileMouseArea.containsMouse ? "#00f5d4" : "#2a3540"
                                border.width: 1
                                clip: true

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                // Drag source — Drag.Automatic starts a platform-level drag
                                Drag.active: tileMouseArea.drag.active
                                Drag.dragType: Drag.Automatic
                                Drag.supportedActions: Qt.CopyAction
                                Drag.mimeData: {
                                    "text/plain": tileWrapper.cameraUrl,
                                    "application/x-cctv-camera-url": tileWrapper.cameraUrl,
                                    "application/x-cctv-channel-id": tileWrapper.channelId,
                                    "application/x-cctv-camera-name": tileWrapper.cameraName
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    // Thumbnail area
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 90

                                        // Thumbnail image from disk
                                        Image {
                                            id: thumbnailImage
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectCrop
                                            // The refreshCount in the URL forces QML to reload when thumbnail updates
                                            source: "image://thumbnail/" + tileWrapper.thumbnailCacheKey + "?v=" + tileWrapper.refreshCount
                                            cache: false
                                            asynchronous: true
                                            smooth: true
                                        }



                                        // Placeholder for missing/loading thumbnails
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: thumbnailImage.status === Image.Error || thumbnailImage.status === Image.Null
                                            color: "#151c24"

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 20
                                                height: 14
                                                color: "#2a3540"
                                                radius: 2
                                                
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 8
                                                    height: 8
                                                    radius: 4
                                                    color: "#0f151b"
                                                }
                                            }
                                        }

                                        // Gradient overlay at the bottom of thumbnail for smooth transition
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 20
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "transparent" }
                                                GradientStop { position: 1.0; color: "#1c242c" }
                                            }
                                        }

                                        // "No signal" text overlay if desired, but camera icon is enough for ungenerated.
                                        // Let's remove the old BusyIndicator and Error overlay completely
                                        // since manual generation might not have a "failed" state easily distinct from "not generated yet".
                                    }

                                    // Camera info bar at the bottom
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 50
                                        Layout.leftMargin: 8
                                        Layout.rightMargin: 8
                                        Layout.bottomMargin: 4
                                        spacing: 8

                                        // Channel Badge
                                        Rectangle {
                                            width: 24
                                            height: 24
                                            color: "#2a3540"
                                            radius: 4
                                            Layout.alignment: Qt.AlignVCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.channelId
                                                color: "#00f5d4"
                                                font.bold: true
                                                font.pixelSize: 10
                                            }
                                        }

                                        // Camera Details
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter

                                            Text {
                                                text: (recorder.name ? recorder.name : recorder.ip) + " Ch. " + modelData.channelId
                                                color: "#8898a6"
                                                font.pixelSize: 8
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: tileWrapper.cameraName || qsTr("Camera %1").arg(modelData.channelId)
                                                color: "white"
                                                font.bold: true
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }



                                Item {
                                    id: dragDummy
                                    width: 1; height: 1
                                    visible: false
                                }

                                MouseArea {
                                    id: tileMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    drag.target: dragDummy
                                    drag.threshold: 8

                                    property int pressX
                                    property int pressY

                                    onPressed: {
                                        pressX = mouse.x
                                        pressY = mouse.y
                                    }

                                    onReleased: {
                                        var dx = mouse.x - pressX
                                        var dy = mouse.y - pressY
                                        var dragged = Math.sqrt(dx*dx + dy*dy) > 8

                                        dragDummy.x = 0
                                        dragDummy.y = 0
                                    }
                                }
                                // Action buttons overlay
                                Row {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    spacing: 4
                                    visible: tileMouseArea.containsMouse || addBtn.hovered || editNameBtn.hovered || refreshBtn.hovered
                                    z: 10

                                    // Add to viewport button
                                    Button {
                                        id: addBtn
                                        width: 34
                                        height: 34

                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 18
                                            height: 18
                                            source: {
                                                var colorStr = addBtn.hovered ? "%2300ff66" : "%238898a6";
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><line x1='12' y1='5' x2='12' y2='19'></line><line x1='5' y1='12' x2='19' y2='12'></line></svg>";
                                            }
                                        }

                                        background: Rectangle {
                                            color: addBtn.pressed ? "#cc121214" : (addBtn.hovered ? "#3a4550" : "#d51c242c")
                                            radius: 17
                                            border.color: addBtn.hovered ? "#00ff66" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            var currentLayoutItem = Utils.currentLayout();
                                            var activeLayoutModel = Utils.currentModel();
                                            var focusIdx = currentLayoutItem ? currentLayoutItem.focusIndex : 0;
                                            if (focusIdx < 0) focusIdx = 0;

                                            var vp = activeLayoutModel.get(focusIdx);
                                            if (vp) {
                                                vp.url = tileWrapper.cameraUrl;
                                                vp.secondaryUrl = tileWrapper.cameraUrl;
                                                vp.streamMode = 0;
                                                Utils.log_info(qsTr("Assigned camera %1 Ch. %2 to viewport %3").arg(recorder.name || recorder.ip).arg(modelData.channelId).arg(focusIdx + 1));
                                            }
                                        }

                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: addBtn.hovered
                                        ToolTip.text: qsTr("Przypisz do aktywnego podglądu")
                                    }

                                    // Edit camera name button
                                    Button {
                                        id: editNameBtn
                                        width: 34
                                        height: 34

                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 18
                                            height: 18
                                            source: {
                                                var colorStr = editNameBtn.hovered ? "%23ff7a00" : "%238898a6";
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='16 3 21 8 8 21 3 21 3 16 16 3'></polygon></svg>";
                                            }
                                        }

                                        background: Rectangle {
                                            color: editNameBtn.pressed ? "#cc121214" : (editNameBtn.hovered ? "#3a4550" : "#d51c242c")
                                            radius: 17
                                            border.color: editNameBtn.hovered ? "#ff7a00" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            camerasWin.openEditName(modelData.channelId, modelData.name, tileWrapper.cameraCustomName);
                                        }

                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: editNameBtn.hovered
                                        ToolTip.text: qsTr("Zmień nazwę kamery")
                                    }

                                    // Refresh thumbnail button
                                    Button {
                                        id: refreshBtn
                                        width: 34
                                        height: 34

                                        contentItem: Image {
                                            anchors.centerIn: parent
                                            width: 18
                                            height: 18
                                            source: {
                                                var colorStr = refreshBtn.hovered ? "%2300c8ff" : "%238898a6";
                                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polyline points='23 4 23 10 17 10'></polyline><polyline points='1 20 1 14 7 14'></polyline><path d='M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15'></path></svg>";
                                            }
                                        }

                                        background: Rectangle {
                                            color: refreshBtn.pressed ? "#cc121214" : (refreshBtn.hovered ? "#3a4550" : "#d51c242c")
                                            radius: 17
                                            border.color: refreshBtn.hovered ? "#00c8ff" : "#2a3540"
                                            border.width: 1
                                        }

                                        onClicked: {
                                            ThumbnailProvider.generateSingleThumbnail(
                                                {
                                                    "ip": recorder.ip,
                                                    "port": recorder.port,
                                                    "username": recorder.username,
                                                    "password": recorder.password
                                                },
                                                modelData.channelId
                                            );
                                        }

                                        ToolTip.delay: Compact.toolTipDelay
                                        ToolTip.timeout: Compact.toolTipTimeout
                                        ToolTip.visible: refreshBtn.hovered
                                        ToolTip.text: qsTr("Odśwież miniaturę kamery")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function saveCustomName(channelId, newCustomName) {
        try {
            var jsonStr = rootWindow.hikvisionRecordersJson;
            if (!jsonStr) return;
            var recordersList = JSON.parse(jsonStr);
            var updatedRecorder = null;
            for (var i = 0; i < recordersList.length; ++i) {
                var rec = recordersList[i];
                if (rec.ip === recorder.ip && String(rec.port) === String(recorder.port)) {
                    if (rec.cameras) {
                        for (var j = 0; j < rec.cameras.length; ++j) {
                            if (rec.cameras[j].channelId === channelId) {
                                if (newCustomName === null || newCustomName === undefined) {
                                    delete rec.cameras[j].customName;
                                } else {
                                    rec.cameras[j].customName = newCustomName;
                                }
                                break;
                            }
                        }
                    }
                    updatedRecorder = rec;
                    break;
                }
            }
            if (updatedRecorder) {
                // Updating the JSON is enough — each tile's cameraName property has a
                // reactive binding on rootWindow.hikvisionRecordersJson and will re-read
                // the new name automatically without any Repeater model rebuild.
                //
                // Do NOT assign recorder = updatedRecorder here.  Doing so swaps the
                // model array reference and forces the Repeater to destroy every delegate
                // and recreate them from scratch.  Freshly-created delegates start with
                // containsMouse = false, so hover never fires, icons stay hidden, and the
                // tiles appear completely frozen until the mouse leaves and re-enters.
                rootWindow.hikvisionRecordersJson = JSON.stringify(recordersList);
            }
        } catch (e) {
            console.log("[saveCustomName] Exception:", e);
        }
    }

    function openEditName(channelId, origName, custName) {
        editNameDialog.targetChannelId = channelId;
        editNameDialog.originalName = origName || "";
        editNameDialog.currentCustomName = custName || "";
        customNameField.text = custName || origName || "";
        editNameDialog.open();
    }

    Dialog {
        id: editNameDialog
        modal: true
        title: qsTr("Change Camera Name")
        anchors.centerIn: parent
        width: 380

        // Restore mouse input to this window after the modal overlay is removed.
        onClosed: camerasWin.requestActivate()

        property int targetChannelId: -1
        property string originalName: ""
        property string currentCustomName: ""

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
                anchors.fill: parent
                anchors.leftMargin: 16
                text: editNameDialog.title
                color: "#00f5d4"
                font.bold: true
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: qsTr("Channel: %1").arg(editNameDialog.targetChannelId)
                color: "#8898a6"
                font.pixelSize: 11
            }

            Text {
                text: qsTr("Original name: %1").arg(editNameDialog.originalName ? editNameDialog.originalName : qsTr("None"))
                color: "#8898a6"
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            TextField {
                id: customNameField
                placeholderText: qsTr("Enter new camera name...")
                selectByMouse: true
                Layout.fillWidth: true
                color: "white"
                background: Rectangle {
                    color: "#0f151b"
                    radius: 4
                    border.color: customNameField.activeFocus ? "#00f5d4" : "#2a3540"
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
                    id: resetBtn
                    text: qsTr("Reset")
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 30

                    contentItem: Text {
                        text: resetBtn.text
                        font.bold: true
                        color: resetBtn.pressed ? "#8898a6" : "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: resetBtn.pressed ? "#2a3540" : (resetBtn.hovered ? "#3a4550" : "#222c36")
                        radius: 4
                        border.color: "#2a3540"
                    }
                    onClicked: {
                        var cid = editNameDialog.targetChannelId;
                        editNameDialog.accept(); // closes synchronously, overlay removed
                        camerasWin.saveCustomName(cid, null);
                    }
                }

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
                     onClicked: editNameDialog.reject()
                }

                Button {
                     id: saveBtn
                     text: qsTr("Save")
                     Layout.preferredWidth: 80
                     Layout.preferredHeight: 30

                     contentItem: Text {
                         text: saveBtn.text
                         font.bold: true
                         color: "white"
                         horizontalAlignment: Text.AlignHCenter
                         verticalAlignment: Text.AlignVCenter
                     }
                     background: Rectangle {
                         color: saveBtn.pressed ? "#00ccb0" : (saveBtn.hovered ? "#00ffd8" : "#00f5d4")
                         radius: 4
                     }
                     onClicked: {
                         var cid = editNameDialog.targetChannelId;
                         var val = customNameField.text.trim();
                         var orig = editNameDialog.originalName;
                         editNameDialog.accept(); // closes synchronously, overlay removed
                         camerasWin.saveCustomName(cid, (val === "" || val === orig) ? null : val);
                     }
                }
            }
        }
    }
}
