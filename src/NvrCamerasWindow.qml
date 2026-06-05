import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Utils 1.0

Window {
    id: camerasWin

    width: 900
    height: 600
    color: "#0f151b"
    title: recorder.name ? qsTr("Cameras on %1").arg(recorder.name) : qsTr("Cameras on %1").arg(recorder.ip)

    property var recorder: ({})

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
                        model: recorder.cameras || []
                        delegate: Item {
                            id: tileWrapper
                            Layout.fillWidth: true
                            height: 140

                            property string cameraUrl: "hikvision://" + recorder.username + ":" + recorder.password + "@" + recorder.ip + ":" + recorder.port + "/" + modelData.channelId
                            property string cameraName: modelData.name || ""
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
                                                text: modelData.name || qsTr("Camera %1").arg(modelData.channelId)
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
                                    visible: tileMouseArea.containsMouse || addMouse.containsMouse || singleRefreshMouse.containsMouse // Show when hovering the tile or buttons
                                    z: 10

                                    // Add to viewport button
                                    Rectangle {
                                        width: 32
                                        height: 32
                                        color: addMouse.containsMouse ? "#aa1c242c" : "#551c242c"
                                        radius: 4

                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            font.pixelSize: 18
                                            font.bold: true
                                            color: "white"
                                        }

                                        MouseArea {
                                            id: addMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
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
                                        }
                                    }

                                    // Refresh thumbnail button
                                    Rectangle {
                                        width: 32
                                        height: 32
                                        color: singleRefreshMouse.containsMouse ? "#aa1c242c" : "#551c242c"
                                        radius: 4

                                        Text {
                                            anchors.centerIn: parent
                                            text: "🔄"
                                            font.pixelSize: 16
                                            color: "white"
                                        }

                                        MouseArea {
                                            id: singleRefreshMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
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
}
