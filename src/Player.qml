import QtQml 2.12
import QtQuick 2.12
import QtQuick.Controls 2.12
import QtMultimedia 5.12
import Qt.labs.settings 1.0
import CCTV_Viewer.Multimedia 1.0
import CCTV_Viewer.Hikvision 1.0
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Themes 1.0
import Qt.labs.platform 1.1 as Platform

FocusScope {
    id: root

    property string color: "black"
    property bool isSubStream: false
    property bool isOneToOne: false
    property real oneToOneX: 0
    property real oneToOneY: 0

    onIsOneToOneChanged: {
        if (isOneToOne) {
            var activeOutput = activePlayerIndex === 1 ? videoOutput1 : videoOutput2;
            var videoW = activeOutput.sourceRect.width > 0 ? activeOutput.sourceRect.width : 1280;
            var videoH = activeOutput.sourceRect.height > 0 ? activeOutput.sourceRect.height : 720;
            oneToOneX = Math.min(0, (videoContainer.width - videoW) / 2);
            oneToOneY = Math.min(0, (videoContainer.height - videoH) / 2);
        } else {
            oneToOneX = 0;
            oneToOneY = 0;
        }
    }

    property var avOptions: ({})
    property int index: -1

    property int loops: 1
    onLoopsChanged: {
        qmlAvPlayer1.loops = loops;
        qmlAvPlayer2.loops = loops;
    }
    
    property int activePlayerIndex: 1
    property string activeCameraId: ""
    property string activeStreamUrl: ""
    
    readonly property var playbackState: activePlayerIndex === 1 ? qmlAvPlayer1.playbackState : qmlAvPlayer2.playbackState
    readonly property var status: activePlayerIndex === 1 ? qmlAvPlayer1.status : qmlAvPlayer2.status
    property string source: ""
    
    readonly property bool isHikvision: String(source).indexOf("hikvision://") !== -1
    property string recorderIp: ""
    property int recorderPort: 8000
    property string username: ""
    property string password: ""
    property int channelId: 1

    property bool isZoomed: false
    property bool isZoomSelectionMode: false
    property real zoomX: 0
    property real zoomY: 0
    property real zoomWidth: 1
    property real zoomHeight: 1

    // Lookup names from the globally saved recorders JSON
    property string cameraNameInfo: {
        if (!isHikvision || !recorderIp) return "";
        try {
            var jsonStr = rootWindow.hikvisionRecordersJson;
            if (!jsonStr) return "";
            var recordersList = JSON.parse(jsonStr);
            for (var i = 0; i < recordersList.length; ++i) {
                var rec = recordersList[i];
                if (rec.ip === recorderIp) {
                    var recName = rec.name ? rec.name : rec.ip;
                    var camName = "";
                    if (rec.cameras) {
                        for (var j = 0; j < rec.cameras.length; ++j) {
                            if (parseInt(rec.cameras[j].channelId) === channelId) {
                                camName = rec.cameras[j].name || "";
                                break;
                            }
                        }
                    }
                    if (!camName) {
                        camName = "Camera " + channelId;
                    }
                    return recName + " Ch. " + channelId + " " + camName;
                }
            }
        } catch (e) {
            console.log("Error looking up camera names:", e);
        }
        return recorderIp + " Ch. " + channelId;
    }
    
    onSourceChanged: {
        updateSource();
    }

    onIsSubStreamChanged: {
        updateSource();
    }

    // Shared Hikvision Settings to sync real/mock stream toggle in real-time
    Settings {
        id: hikPlayerSettings
        fileName: Context.config.fileName
        category: "Hikvision"
        property bool useRealStreams: true
        
        onUseRealStreamsChanged: {
            updateSource();
        }
    }

    function updateSource() {
        if (!root.visible) {
            qmlAvPlayer1.source = "";
            qmlAvPlayer2.source = "";
            activeStreamUrl = "";
            activeCameraId = "";
            return;
        }

        var newUrl = "";
        var newCameraId = "";

        parseUri(source);

        if (!isHikvision) {
            newUrl = source;
            newCameraId = source;
        } else {
            if (hikPlayerSettings.useRealStreams) {
                var streamSuffix = isSubStream ? "02" : "01";
                newUrl = "rtsp://" + username + ":" + password + "@" + recorderIp + ":554/Streaming/Channels/" + channelId + streamSuffix;
                newCameraId = recorderIp + "_" + channelId;
            }
        }

        if (newUrl === "") {
            qmlAvPlayer1.stop();
            qmlAvPlayer2.stop();
            qmlAvPlayer1.source = "";
            qmlAvPlayer2.source = "";
            activeStreamUrl = "";
            activeCameraId = "";
            return;
        }

        var activePlayer = activePlayerIndex === 1 ? qmlAvPlayer1 : qmlAvPlayer2;
        var inactivePlayer = activePlayerIndex === 1 ? qmlAvPlayer2 : qmlAvPlayer1;

        if (activeStreamUrl === newUrl) {
            if (activePlayer.source === newUrl) {
                activePlayer.play();
            }
            return;
        }

        var isSameCamera = (newCameraId !== "" && newCameraId === activeCameraId && playbackState === MediaPlayer.PlayingState && status === MediaPlayer.Buffered);

        if (isSameCamera) {
            console.log("[Player] Seamless switch quality of camera " + newCameraId + " to URL: " + newUrl);
            inactivePlayer.muted = true; // Keep inactive player muted during loading
            inactivePlayer.source = newUrl;
            inactivePlayer.play();
            activeStreamUrl = newUrl;
        } else {
            console.log("[Player] Different camera: switching immediately to URL: " + newUrl);
            activePlayerIndex = 1;
            qmlAvPlayer2.source = "";
            qmlAvPlayer1.source = newUrl;
            qmlAvPlayer1.play();
            activeStreamUrl = newUrl;
            activeCameraId = newCameraId;
        }
    }

    function handlePlayerStatus(playerIndex, status) {
        if (status === MediaPlayer.InvalidMedia) {
            root.mediaError(String(playerIndex === 1 ? qmlAvPlayer1.source : qmlAvPlayer2.source));
        }

        if (playerIndex === activePlayerIndex) {
            return;
        }
        
        if (status === MediaPlayer.Buffered) {
            console.log("[Player] Seamless switch: Inactive player " + playerIndex + " is now Buffered. Switching.");
            var activePlayer = playerIndex === 1 ? qmlAvPlayer1 : qmlAvPlayer2;
            activePlayer.muted = root.muted; // Restore user's mute settings for the now-active player
            
            activePlayerIndex = playerIndex;
            
            var otherPlayer = playerIndex === 1 ? qmlAvPlayer2 : qmlAvPlayer1;
            otherPlayer.source = "";
        }
        else if (status === MediaPlayer.InvalidMedia) {
            console.log("[Player] Seamless switch failed: Inactive player " + playerIndex + " failed to load. Switching to show error.");
            activePlayerIndex = playerIndex;
            
            var otherPlayer = playerIndex === 1 ? qmlAvPlayer2 : qmlAvPlayer1;
            otherPlayer.source = "";
        }
    }

    function updateMessageText() {
        var activePlayer = activePlayerIndex === 1 ? qmlAvPlayer1 : qmlAvPlayer2;
        switch (activePlayer.status) {
        case MediaPlayer.NoMedia:
            message.text = qsTr("No media");
            break;
        case MediaPlayer.Loading:
            message.text = qsTr("Loading...");
            break;
        case MediaPlayer.Loaded:
            message.text = qsTr("Loaded");
            break;
        case MediaPlayer.Stalled:
            message.text = qsTr("Stalled");
            break;
        case MediaPlayer.Buffering:
            message.text = qsTr("Buffering %1\%").arg(Math.round(activePlayer.bufferProgress * 100));
            break;
        case MediaPlayer.Buffered:
            message.text = "";
            break;
        case MediaPlayer.EndOfMedia:
            message.text = qsTr("End of media");
            break;
        case MediaPlayer.InvalidMedia:
            message.text = qsTr("Error!");
            break;
        default:
            message.text = "";
            break;
        }
    }

    property bool muted: false
    property double volume: 1.0
    readonly property bool hasAudio: activePlayerIndex === 1 ? qmlAvPlayer1.hasAudio : qmlAvPlayer2.hasAudio

    onMutedChanged: {
        if (activePlayerIndex === 1) {
            qmlAvPlayer1.muted = muted;
            qmlAvPlayer2.muted = true;
        } else {
            qmlAvPlayer2.muted = muted;
            qmlAvPlayer1.muted = true;
        }
    }

    onVolumeChanged: {
        qmlAvPlayer1.volume = volume;
        qmlAvPlayer2.volume = volume;
    }

    onVisibleChanged: {
        if (visible) {
            updateSource();
            if (!timer.running) {
                timer.start();
            }
        } else {
            timer.stop();
            qmlAvPlayer1.autoPlay = false;
            qmlAvPlayer2.autoPlay = false;
            qmlAvPlayer1.stop();
            qmlAvPlayer2.stop();
            qmlAvPlayer1.source = "";
            qmlAvPlayer2.source = "";
            activeStreamUrl = "";
            activeCameraId = "";
        }
    }
    Component.onCompleted: {
        if (visible) {
            timer.start();
        }
        updateSource();
    }

    signal mediaError(string errorSource)

    Timer {
        id: timer

        interval: 50

        onTriggered: {
            if (root.visible) {
                qmlAvPlayer1.autoPlay = true;
                qmlAvPlayer2.autoPlay = true;
            }
        }
    }

    Rectangle {
        color: root.color
        border.color: "#101010"
        anchors.fill: parent

        Item {
            id: videoContainer
            anchors.fill: parent
            clip: true

            // VideoOutput handles either regular RTSP or Hikvision RTSP Fallback
            VideoOutput {
                id: videoOutput1
                source: qmlAvPlayer1
                x: root.isOneToOne ? root.oneToOneX : -root.zoomX * width
                y: root.isOneToOne ? root.oneToOneY : -root.zoomY * height
                width: root.isOneToOne ? (sourceRect.width > 0 ? sourceRect.width : parent.width) : (parent.width / Math.max(0.001, root.zoomWidth))
                height: root.isOneToOne ? (sourceRect.height > 0 ? sourceRect.height : parent.height) : (parent.height / Math.max(0.001, root.zoomHeight))
                fillMode: VideoOutput.Stretch
                visible: (!root.isHikvision || hikPlayerSettings.useRealStreams) && activePlayerIndex === 1

                onSourceRectChanged: {
                    if (root.isOneToOne && root.activePlayerIndex === 1) {
                        root.oneToOneX = Math.min(0, (videoContainer.width - sourceRect.width) / 2);
                        root.oneToOneY = Math.min(0, (videoContainer.height - sourceRect.height) / 2);
                    }
                }
            }

            VideoOutput {
                id: videoOutput2
                source: qmlAvPlayer2
                x: root.isOneToOne ? root.oneToOneX : -root.zoomX * width
                y: root.isOneToOne ? root.oneToOneY : -root.zoomY * height
                width: root.isOneToOne ? (sourceRect.width > 0 ? sourceRect.width : parent.width) : (parent.width / Math.max(0.001, root.zoomWidth))
                height: root.isOneToOne ? (sourceRect.height > 0 ? sourceRect.height : parent.height) : (parent.height / Math.max(0.001, root.zoomHeight))
                fillMode: VideoOutput.Stretch
                visible: (!root.isHikvision || hikPlayerSettings.useRealStreams) && activePlayerIndex === 2

                onSourceRectChanged: {
                    if (root.isOneToOne && root.activePlayerIndex === 2) {
                        root.oneToOneX = Math.min(0, (videoContainer.width - sourceRect.width) / 2);
                        root.oneToOneY = Math.min(0, (videoContainer.height - sourceRect.height) / 2);
                    }
                }
            }

            // Hikvision C++ Painted Player renders high-tech mock layout if fallback is disabled
            HikvisionPlayer {
                id: hikPlayer
                visible: root.isHikvision && !hikPlayerSettings.useRealStreams
                x: -root.zoomX * width
                y: -root.zoomY * height
                width: parent.width / Math.max(0.001, root.zoomWidth)
                height: parent.height / Math.max(0.001, root.zoomHeight)
                recorderIp: root.recorderIp
                recorderPort: root.recorderPort
                username: root.username
                password: root.password
                channelId: root.channelId
                streamType: root.isSubStream ? 1 : 0
            }
        }

        Text {
            id: message

            color: "white"
            visible: !root.isHikvision && (activePlayerIndex === 1 ? qmlAvPlayer1.status : qmlAvPlayer2.status) !== MediaPlayer.Buffered
            anchors.centerIn: parent
        }

        QmlAVPlayer {
            id: qmlAvPlayer1

            autoLoad: false

            avOptions: {
                var avOptions = root.avOptions;
                Object.assignDefault(avOptions, layoutsCollectionSettings.toJSValue("defaultAVFormatOptions"));
                return avOptions;
            }

            onStatusChanged: {
                handlePlayerStatus(1, status);
                updateMessageText();
            }

            onBufferProgressChanged: {
                updateMessageText();
            }
        }

        QmlAVPlayer {
            id: qmlAvPlayer2

            autoLoad: false

            avOptions: {
                var avOptions = root.avOptions;
                Object.assignDefault(avOptions, layoutsCollectionSettings.toJSValue("defaultAVFormatOptions"));
                return avOptions;
            }

            onStatusChanged: {
                handlePlayerStatus(2, status);
                updateMessageText();
            }

            onBufferProgressChanged: {
                updateMessageText();
            }
        }

        Timer {
            id: bitrateTimer
            interval: 1000
            running: (!root.isHikvision || hikPlayerSettings.useRealStreams) && root.visible && (playbackState === MediaPlayer.PlayingState)
            repeat: true
            
            property var lastBytes: 0
            property string bitrateText: "0 kbps"

            onTriggered: {
                var activePlayer = activePlayerIndex === 1 ? qmlAvPlayer1 : qmlAvPlayer2;
                var currentBytes = activePlayer.bytesRead();
                var diffBytes = currentBytes - lastBytes;
                if (diffBytes < 0) {
                    diffBytes = currentBytes; // handle player restart / reset
                }
                lastBytes = currentBytes;
                
                var bps = diffBytes * 8;
                if (bps >= 1000000) {
                    bitrateText = (bps / 1000000).toFixed(2) + " Mbps";
                } else if (bps >= 1000) {
                    bitrateText = Math.round(bps / 1000) + " kbps";
                } else {
                    bitrateText = bps + " bps";
                }
            }
            
            onRunningChanged: {
                if (!running) {
                    bitrateText = "0 kbps";
                    lastBytes = 0;
                }
            }
        }

        Rectangle {
            id: streamInfoBadge
            
            anchors {
                left: parent.left
                top: parent.top
                margins: 6
            }
            
            visible: (root.source !== "") && (root.isHikvision ? (root.recorderIp !== "") : (playbackState === MediaPlayer.PlayingState || status === MediaPlayer.Buffered || status === MediaPlayer.Buffering || status === MediaPlayer.Loading))
            
            color: "#66121214"
            border {
                color: root.isSubStream ? "#ff7a00" : "#00f5d4"
                width: 1
            }
            radius: 4
            
            implicitWidth: contentLayout.width + 8
            implicitHeight: contentLayout.height + 4
            
            Row {
                id: contentLayout
                anchors.centerIn: parent
                spacing: 4
                
                Text {
                    text: root.isSubStream ? "SUB" : "MAIN"
                    color: root.isSubStream ? "#ff7a00" : "#00f5d4"
                    font {
                        pixelSize: 8
                        bold: true
                    }
                }
                
                Rectangle {
                    width: 1
                    height: 7
                    color: root.isSubStream ? "#44ff7a00" : "#4400f5d4"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.isHikvision || hikPlayerSettings.useRealStreams
                }
                
                Text {
                    text: bitrateTimer.bitrateText
                    color: "#eeeeee"
                    font {
                        pixelSize: 8
                    }
                    visible: !root.isHikvision || hikPlayerSettings.useRealStreams
                }
            }
        }



        Rectangle {
            id: cameraInfoBadge
            
            anchors {
                left: parent.left
                bottom: parent.bottom
                margins: 6
            }
            
            visible: root.isHikvision && root.cameraNameInfo !== ""
            
            color: "#66121214"
            border {
                color: "#ff7a00"
                width: 1
            }
            radius: 4
            
            implicitWidth: cameraInfoText.implicitWidth + 8
            implicitHeight: cameraInfoText.implicitHeight + 4
            
            Text {
                id: cameraInfoText
                anchors.centerIn: parent
                text: root.cameraNameInfo
                color: "#eeeeee"
                font {
                    pixelSize: 8
                    bold: true
                }
            }
        }

        // MouseArea to handle mouse click-and-drag for ROI Zoom selection
        MouseArea {
            id: zoomMouseArea
            anchors.fill: parent
            enabled: root.isZoomSelectionMode
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            property real startX: 0
            property real startY: 0
            property real currentX: 0
            property real currentY: 0
            property bool isDragging: false

            onPressed: {
                startX = mouse.x;
                startY = mouse.y;
                currentX = mouse.x;
                currentY = mouse.y;
                isDragging = true;
            }

            onPositionChanged: {
                if (isDragging) {
                    currentX = Math.max(0, Math.min(mouse.x, parent.width));
                    currentY = Math.max(0, Math.min(mouse.y, parent.height));
                }
            }

            onReleased: {
                if (isDragging) {
                    isDragging = false;
                    var x1 = Math.min(startX, currentX);
                    var y1 = Math.min(startY, currentY);
                    var w = Math.abs(startX - currentX);
                    var h = Math.abs(startY - currentY);

                    // Ignore very small clicks/drags to avoid accidental zoom on clicks
                    if (w > 10 && h > 10) {
                        root.zoomX = x1 / parent.width;
                        root.zoomY = y1 / parent.height;
                        root.zoomWidth = w / parent.width;
                        root.zoomHeight = h / parent.height;
                        root.isZoomed = true;
                    }
                    root.isZoomSelectionMode = false;
                }
            }
        }

        // MouseArea to handle middle-click drag (wheel click and drag) for panning in 1:1 mode
        MouseArea {
            id: middleDragMouseArea
            anchors.fill: parent
            acceptedButtons: Qt.MiddleButton
            enabled: root.isOneToOne
            cursorShape: containsPress ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            property real lastX: 0
            property real lastY: 0

            onPressed: {
                lastX = mouse.x;
                lastY = mouse.y;
            }

            onPositionChanged: {
                if (pressed) {
                    var dx = mouse.x - lastX;
                    var dy = mouse.y - lastY;

                    var activeOutput = root.activePlayerIndex === 1 ? videoOutput1 : videoOutput2;
                    var videoW = activeOutput.width;
                    var videoH = activeOutput.height;

                    root.oneToOneX = Math.min(0, Math.max(parent.width - videoW, root.oneToOneX + dx));
                    root.oneToOneY = Math.min(0, Math.max(parent.height - videoH, root.oneToOneY + dy));

                    lastX = mouse.x;
                    lastY = mouse.y;
                }
            }
        }

        // Selection rectangle outline
        Rectangle {
            id: selectionRect
            visible: zoomMouseArea.isDragging
            x: Math.min(zoomMouseArea.startX, zoomMouseArea.currentX)
            y: Math.min(zoomMouseArea.startY, zoomMouseArea.currentY)
            width: Math.abs(zoomMouseArea.startX - zoomMouseArea.currentX)
            height: Math.abs(zoomMouseArea.startY - zoomMouseArea.currentY)
            color: "#3300f5d4" // translucent cyan
            border.color: "#00f5d4" // solid cyan border
            border.width: 1
        }

        // Symmetrically placed magnifying glass button overlay on the bottom right (no fill tło, gray border, white icon by default, color-coded modes)
        Row {
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: 6
            }
            spacing: 6

            Control {
                id: snapshotBadge

                property bool isSavingSnapshot: false

                Timer {
                    id: snapshotBadgeTimer
                    interval: 1000
                    onTriggered: snapshotBadge.isSavingSnapshot = false
                }

                implicitWidth: 16
                implicitHeight: 16
                visible: root.source !== ""

                background: Rectangle {
                    radius: 2
                    color: snapshotMouseAreaBtn.pressed ? "#22ffffff" : (snapshotMouseAreaBtn.containsMouse ? "#11ffffff" : "transparent")
                }

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    source: snapshotBadge.isSavingSnapshot ?
                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ff7a00' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'></path><circle cx='12' cy='13' r='4'></circle></svg>" :
                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'></path><circle cx='12' cy='13' r='4'></circle></svg>"
                }

                MouseArea {
                    id: snapshotMouseAreaBtn
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var d = new Date();
                        var dateStr = Qt.formatDateTime(d, "yyyy-MM-dd_HH-mm-ss");
                        var activeOutput = null;
                        var nativeWidth = 1920;
                        var nativeHeight = 1080;
                        var camName = root.cameraNameInfo ? root.cameraNameInfo.replace(/ /g, "_").replace(/[^a-zA-Z0-9_\-\.]/g, "") : "Camera";

                        if (root.isHikvision && !hikPlayerSettings.useRealStreams) {
                            activeOutput = hikPlayer;
                        } else if (activePlayerIndex === 1) {
                            activeOutput = videoOutput1;
                            nativeWidth = videoOutput1.sourceRect.width > 0 ? videoOutput1.sourceRect.width : 1920;
                            nativeHeight = videoOutput1.sourceRect.height > 0 ? videoOutput1.sourceRect.height : 1080;
                        } else {
                            activeOutput = videoOutput2;
                            nativeWidth = videoOutput2.sourceRect.width > 0 ? videoOutput2.sourceRect.width : 1920;
                            nativeHeight = videoOutput2.sourceRect.height > 0 ? videoOutput2.sourceRect.height : 1080;
                        }

                        var path = "";
                        if (typeof generalSettings !== "undefined" && generalSettings.snapshotPath !== "") {
                            path = generalSettings.snapshotPath;
                        } else {
                            path = Platform.StandardPaths.writableLocation(Platform.StandardPaths.PicturesLocation).toString();
                            if (path.indexOf("file://") === 0) path = path.substring(7);
                            path = path + "/CCTV";
                        }
                        Context.mkpath(path);
                        path = path + "/" + camName + "_LIVE_" + dateStr + ".jpg";

                        snapshotBadge.isSavingSnapshot = true;
                        snapshotBadgeTimer.restart();
                        activeOutput.grabToImage(function(result) {
                            result.saveToFile(path);
                            console.log("Saved snapshot to", path);
                        }, Qt.size(nativeWidth, nativeHeight));
                    }
                }

                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: snapshotMouseAreaBtn.containsMouse
                ToolTip.text: qsTr("Wykonaj stopklatkę w pełnej rozdzielczości")
            }

            Control {
                id: playbackBadge
                
                implicitWidth: 16
                implicitHeight: 16
                visible: root.source !== "" && root.isHikvision
                
                background: Rectangle {
                    radius: 2
                    color: playbackMouseAreaBtn.pressed ? "#22ffffff" : (playbackMouseAreaBtn.containsMouse ? "#11ffffff" : "transparent")
                }
                
                contentItem: Image {
                    anchors.centerIn: parent
                    source: "qrc:/images/play.svg"
                    width: 10
                    height: 10
                    sourceSize: Qt.size(10, 10)
                }
                
                MouseArea {
                    id: playbackMouseAreaBtn
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var recInfo = {
                            "ip": root.recorderIp,
                            "port": root.recorderPort,
                            "username": root.username,
                            "password": root.password
                        };
                        var camName = root.cameraNameInfo || ("Camera " + root.channelId);
                        
                        var component = Qt.createComponent("qrc:/src/PlaybackWindow.qml");
                        if (component.status === Component.Ready) {
                            var win = component.createObject(rootWindow, {
                                "recorderInfo": recInfo,
                                "channelId": root.channelId,
                                "cameraName": camName,
                                "width": rootWindow.width * 0.9,
                                "height": rootWindow.height * 0.9
                            });
                            win.show();
                        } else if (component.status === Component.Error) {
                            console.log("Error creating PlaybackWindow:", component.errorString());
                        } else {
                            component.statusChanged.connect(function() {
                                if (component.status === Component.Ready) {
                                    var win = component.createObject(rootWindow, {
                                        "recorderInfo": recInfo,
                                        "channelId": root.channelId,
                                        "cameraName": camName,
                                        "width": rootWindow.width * 0.9,
                                        "height": rootWindow.height * 0.9
                                    });
                                    win.show();
                                } else if (component.status === Component.Error) {
                                    console.log("Error creating PlaybackWindow async:", component.errorString());
                                }
                            });
                        }
                    }
                }
                
                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: playbackMouseAreaBtn.containsMouse
                ToolTip.text: qsTr("Archiwum nagrań")
            }

            Control {
                id: oneToOneBadge
                
                implicitWidth: 16
                implicitHeight: 16
                visible: root.source !== ""
                
                background: Rectangle {
                    radius: 2
                    color: root.isOneToOne ? "#3300f5d4" : (oneToOneMouseAreaBtn.pressed ? "#22ffffff" : (oneToOneMouseAreaBtn.containsMouse ? "#11ffffff" : "transparent"))
                }
                
                contentItem: Image {
                    id: oneToOneIcon
                    anchors.centerIn: parent
                    width: 15
                    height: 15
                    source: root.isOneToOne ?
                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><text x='8' y='12.5' font-family='sans-serif' font-size='12' font-weight='900' text-anchor='middle' fill='%2300f5d4'>1:1</text></svg>" :
                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><text x='8' y='12.5' font-family='sans-serif' font-size='12' font-weight='900' text-anchor='middle' fill='%23ffffff'>1:1</text></svg>"
                }
                
                MouseArea {
                    id: oneToOneMouseAreaBtn
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.isOneToOne = !root.isOneToOne;
                    }
                }
                
                ToolTip.delay: Compact.toolTipDelay
                ToolTip.timeout: Compact.toolTipTimeout
                ToolTip.visible: oneToOneMouseAreaBtn.containsMouse
                ToolTip.text: root.isOneToOne ? qsTr("Wyłącz tryb 1:1") : qsTr("Włącz tryb 1:1 (piksel w piksel)")
            }

            Control {
                id: zoomBadge
                
                implicitWidth: 16
                implicitHeight: 16
                visible: root.source !== ""
            
            font.pixelSize: 9
            
            background: Rectangle {
                radius: 2
                color: root.isZoomSelectionMode ? "#3300f5d4" : (zoomMouseAreaBtn.pressed ? "#22ffffff" : (zoomMouseAreaBtn.containsMouse ? "#11ffffff" : "transparent"))
            }
            
            contentItem: Image {
                id: zoomIcon
                anchors.centerIn: parent
                width: 10
                height: 10
                source: root.isZoomed ? 
                    "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ff3333' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>" :
                    (root.isZoomSelectionMode ?
                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='11' y1='8' x2='11' y2='14'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>" :
                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='11' y1='8' x2='11' y2='14'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>"
                    )
            }
            
            MouseArea {
                id: zoomMouseAreaBtn
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.isZoomed) {
                        // Reset zoom
                        root.zoomX = 0;
                        root.zoomY = 0;
                        root.zoomWidth = 1;
                        root.zoomHeight = 1;
                        root.isZoomed = false;
                        root.isZoomSelectionMode = false;
                    } else {
                        // Toggle selection mode
                        root.isZoomSelectionMode = !root.isZoomSelectionMode;
                    }
                }
            }
            
            ToolTip.delay: Compact.toolTipDelay
            ToolTip.timeout: Compact.toolTipTimeout
            ToolTip.visible: zoomMouseAreaBtn.containsMouse
            ToolTip.text: root.isZoomed ? qsTr("Reset Zoom") : (root.isZoomSelectionMode ? qsTr("Click and drag on camera feed to zoom") : qsTr("Select region to zoom"))
        }
        }
    }

    function play() {
        if (activePlayerIndex === 1) qmlAvPlayer1.play();
        else qmlAvPlayer2.play();
    }
//    function pause() { mediaPlayer.pause(); }
//    function seek(position) { mediaPlayer.seek(position); }
    function stop() {
        qmlAvPlayer1.stop();
        qmlAvPlayer2.stop();
        qmlAvPlayer1.source = "";
        qmlAvPlayer2.source = "";
        activeStreamUrl = "";
        activeCameraId = "";
    }

    function parseUri(uri) {
        var s = String(uri);
        if (s.indexOf("hikvision://") !== -1) {
            parseHikvisionUri(uri);
        } else if (s.indexOf("rtsp://") !== -1) {
            parseRtspUri(uri);
        }
    }

    function parseRtspUri(uri) {
        var s = String(uri);
        var idx = s.indexOf("rtsp://");
        if (idx === -1) return;

        var content = s.substring(idx + 7); // after "rtsp://"

        // Split at "/" for path
        var parts = content.split("/");
        if (parts.length > 1) {
            // Find channel ID from path, e.g. "Streaming/Channels/401"
            var channelMatch = parts[parts.length - 1].match(/(\d+)/);
            if (channelMatch) {
                var chanNum = parseInt(channelMatch[1]);
                if (chanNum >= 100) {
                    channelId = Math.floor(chanNum / 100);
                } else {
                    channelId = chanNum;
                }
            } else {
                channelId = 1;
            }
        }

        var mainPart = parts[0]; // "username:password@ip:port"

        // Split at "@" for credentials and address
        var addrParts = mainPart.split("@");
        var addrPort = "";
        if (addrParts.length > 1) {
            var creds = addrParts[0].split(":");
            username = creds[0] || "";
            password = creds[1] || "";
            addrPort = addrParts[1];
        } else {
            addrPort = addrParts[0];
            username = "";
            password = "";
        }

        // Split at ":" for ip and port
        var ipPort = addrPort.split(":");
        recorderIp = ipPort[0] || "";

        // Resolve SDK port by searching in configured recorders
        recorderPort = 8000; // Default
        try {
            var jsonStr = rootWindow.hikvisionRecordersJson;
            if (jsonStr) {
                var recordersList = JSON.parse(jsonStr);
                for (var i = 0; i < recordersList.length; ++i) {
                    var rec = recordersList[i];
                    if (rec.ip === recorderIp) {
                        recorderPort = parseInt(rec.port) || 8000;
                        if (!username && rec.username) username = rec.username;
                        if (!password && rec.password) password = rec.password;
                        break;
                    }
                }
            }
        } catch (e) {
            console.log("[Player QML Error] Failed to resolve recorder port from JSON:", e);
        }
    }

    function parseHikvisionUri(uri) {
        var s = String(uri);
        var idx = s.indexOf("hikvision://");
        if (idx === -1) return;
        
        var content = s.substring(idx + 12); // after "hikvision://"
        
        // Split at "/" for channel
        var parts = content.split("/");
        if (parts.length > 1) {
            channelId = parseInt(parts[1]) || 1;
        }
        
        var mainPart = parts[0]; // "username:password@ip:port"
        
        // Split at "@" for credentials and address
        var addrParts = mainPart.split("@");
        var addrPort = "";
        if (addrParts.length > 1) {
            var creds = addrParts[0].split(":");
            username = creds[0] || "";
            password = creds[1] || "";
            addrPort = addrParts[1];
        } else {
            addrPort = addrParts[0];
            username = "";
            password = "";
        }
        
        // Split at ":" for ip and port
        var ipPort = addrPort.split(":");
        recorderIp = ipPort[0] || "";
        if (ipPort.length > 1) {
            recorderPort = parseInt(ipPort[1]) || 8000;
        } else {
            recorderPort = 8000;
        }
    }
}
