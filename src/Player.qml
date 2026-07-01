import QtQml 2.12
import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import QtMultimedia 5.12
import Qt.labs.settings 1.0
import CCTV_Viewer.Multimedia 1.0
import CCTV_Viewer.Hikvision 1.0
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Themes 1.0
import Qt.labs.platform 1.1 as Platform
import QtGraphicalEffects 1.12

FocusScope {
    id: root

    Behavior on scale {
        enabled: typeof viewSettings !== "undefined" ? !viewSettings.disableViewportZoomAnimation : true
        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
    }
    Behavior on x {
        enabled: typeof viewSettings !== "undefined" ? !viewSettings.disableViewportZoomAnimation : true
        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
    }
    Behavior on y {
        enabled: typeof viewSettings !== "undefined" ? !viewSettings.disableViewportZoomAnimation : true
        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
    }

    property string color: "black"
    property bool isSubStream: false
    property bool isOneToOne: false
    property real oneToOneX: 0
    property real oneToOneY: 0

    onIsOneToOneChanged: {
        if (isOneToOne) {
            var videoW = 1280;
            var videoH = 720;
            if (isQuickPlayback && quickPlaybackPlayerLoader.item) {
                videoW = quickPlaybackPlayerLoader.item.videoWidth > 0 ? quickPlaybackPlayerLoader.item.videoWidth : 1280;
                videoH = quickPlaybackPlayerLoader.item.videoHeight > 0 ? quickPlaybackPlayerLoader.item.videoHeight : 720;
            } else {
                var activeOutput = activePlayerIndex === 1 ? videoOutput1 : videoOutput2;
                videoW = activeOutput.sourceRect.width > 0 ? activeOutput.sourceRect.width : 1280;
                videoH = activeOutput.sourceRect.height > 0 ? activeOutput.sourceRect.height : 720;
            }
            oneToOneX = Math.min(0, (videoContainer.width - videoW) / 2);
            oneToOneY = Math.min(0, (videoContainer.height - videoH) / 2);
        } else {
            oneToOneX = 0;
            oneToOneY = 0;
        }
    }

    property var avOptions: ({})
    property bool ignoreGlobalAVFormatOptions: false
    property int index: -1
    property bool isFullScreen: false
    property var layoutModel: null

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
    readonly property bool activeIsSubStream: activePlayerIndex === 1 ? qmlAvPlayer1.isSubStreamOfPlayer : qmlAvPlayer2.isSubStreamOfPlayer
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

    property bool isQuickPlayback: false
    property var quickPlaybackActivationTime: null
    property int quickPlaybackOffset: 1740
    property int quickPlaybackSpeed: 1
    property bool isQuickPlaybackPaused: false
    property var quickPlaybackSegments: []
    property bool pendingQuickPlaybackSeek: false
    property bool isRestoringLiveView: false

    Timer {
        id: restoringLiveViewTimer
        interval: 3000
        repeat: false
        onTriggered: root.isRestoringLiveView = false
    }

    Timer {
        id: seamlessSwitchTimer
        interval: 100
        repeat: false
        property int targetPlayerIndex: -1
        onTriggered: {
            if (targetPlayerIndex === -1 || targetPlayerIndex === activePlayerIndex) return;
            var player = targetPlayerIndex === 1 ? qmlAvPlayer1 : qmlAvPlayer2;
            var oldPlayer = targetPlayerIndex === 1 ? qmlAvPlayer2 : qmlAvPlayer1;
            
            // Sanity check: Ensure target player is still healthy and matches activeStreamUrl
            if (String(player.source) !== activeStreamUrl || player.playbackState !== MediaPlayer.PlayingState) {
                console.log("[Player] Seamless switch aborted: Target player " + targetPlayerIndex + " is no longer valid or matches target URL.");
                return;
            }
            
            console.log("[Player] Seamless switch timer triggered: Switching activePlayerIndex from " + activePlayerIndex + " to " + targetPlayerIndex);
            
            oldPlayer.muted = true;
            player.muted = root.muted;
            activePlayerIndex = targetPlayerIndex;
            
            var targetIndex = targetPlayerIndex;
            Qt.callLater(function() {
                if (activePlayerIndex === targetIndex) {
                    console.log("[Player] Post-switch (timer): stopping and clearing old player source");
                    oldPlayer.source = "";
                    oldPlayer.isSubStreamOfPlayer = false;
                }
            });
        }
    }

    function getDateKey(d) {
        if (!d) return "";
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function formatTime(date) {
        if (!date) return "--:--:--";
        return Qt.formatTime(date, "HH:mm:ss");
    }

    function formatRelativeTime(offsetSeconds) {
        var diff = 1800 - offsetSeconds;
        if (diff === 0) return "now";
        var m = Math.floor(diff / 60);
        var s = diff % 60;
        return "-" + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
    }

    function updateQuickPlaybackSegments() {
        if (!isQuickPlayback || !quickPlaybackActivationTime || !rootWindow) return;
        var dateKey = getDateKey(quickPlaybackActivationTime);
        var cacheKey = recorderIp + "_" + channelId + "_" + dateKey;
        var segments = rootWindow.playbackSegmentsCache[cacheKey];
        if (segments) {
            quickPlaybackSegments = segments;
        } else {
            quickPlaybackSegments = [];
        }
    }

    onIsQuickPlaybackChanged: {
        if (isQuickPlayback) {
            quickPlaybackActivationTime = new Date();
            quickPlaybackOffset = 1740;
            quickPlaybackSpeed = 1;
            isQuickPlaybackPaused = false;
            pendingQuickPlaybackSeek = true;
            
            var recorderInfoForCam = {
                "ip": recorderIp,
                "port": recorderPort || 8000,
                "username": username,
                "password": password
            };
            var start = new Date(quickPlaybackActivationTime);
            start.setHours(0,0,0,0);
            start.setDate(start.getDate() - 1);
            var end = new Date(quickPlaybackActivationTime);
            end.setHours(23,59,59,999);
            end.setDate(end.getDate() + 1);
            
            updateQuickPlaybackSegments();
            HikvisionISAPI.searchRecordings(recorderInfoForCam, channelId, start, end);
            
            // Playback will start in quickPlaybackPlayerLoader.onLoaded
            quickPlaybackTimer.start();
        } else {
            pendingQuickPlaybackSeek = false;
            quickPlaybackTimer.stop();
            isRestoringLiveView = true;
            restoringLiveViewTimer.restart();
        }
        updateSource();
    }

    Connections {
        target: HikvisionISAPI
        function onSearchFinished(searchRecorderIp, searchChannelId, startTime, segments) {
            if (root.isQuickPlayback && searchRecorderIp === root.recorderIp && searchChannelId === root.channelId) {
                var targetDate = new Date(startTime);
                targetDate.setDate(targetDate.getDate() + 1);
                var dateKey = root.getDateKey(targetDate);
                var cacheKey = searchRecorderIp + "_" + searchChannelId + "_" + dateKey;

                var adjustedSegments = [];
                if (segments) {
                    for (var i = 0; i < segments.length; i++) {
                        var seg = segments[i];
                        var localOffsetMs = new Date(seg.startTime).getTimezoneOffset() * 60000;
                        adjustedSegments.push({
                            "startTime": seg.startTime + localOffsetMs,
                            "endTime": seg.endTime + localOffsetMs
                        });
                    }
                }
                
                if (typeof rootWindow !== "undefined" && rootWindow) {
                    var tempSegments = Object.assign({}, rootWindow.playbackSegmentsCache);
                    tempSegments[cacheKey] = adjustedSegments;
                    rootWindow.playbackSegmentsCache = tempSegments;
                }
                root.updateQuickPlaybackSegments();

                if (root.pendingQuickPlaybackSeek) {
                    root.pendingQuickPlaybackSeek = false;
                    if (adjustedSegments.length > 0 && root.quickPlaybackActivationTime) {
                        var windowEnd = root.quickPlaybackActivationTime.getTime();
                        var windowStart = windowEnd - 1800000;
                        var maxEndTime = 0;
                        for (var i = 0; i < adjustedSegments.length; i++) {
                            var seg = adjustedSegments[i];
                            if (seg.startTime < windowEnd && seg.endTime > windowStart) {
                                var overlapEnd = Math.min(windowEnd, seg.endTime);
                                if (overlapEnd > maxEndTime) {
                                    maxEndTime = overlapEnd;
                                }
                            }
                        }
                        if (maxEndTime > 0) {
                            var targetPlayTime = maxEndTime - 60 * 1000; // 60 seconds before latest record
                            if (targetPlayTime < windowStart) {
                                targetPlayTime = windowStart;
                            }
                            var newOffset = Math.floor((targetPlayTime - windowStart) / 1000);
                            root.quickPlaybackOffset = newOffset;
                            console.log("[Player QML] Aligning quick playback start time to:", new Date(targetPlayTime), "with offset:", newOffset);
                            if (quickPlaybackPlayerLoader.item) {
                                quickPlaybackPlayerLoader.item.playAtTime(new Date(targetPlayTime));
                            }
                        } else {
                            console.log("[Player QML] No overlapping segments found in the 30-minute window.");
                        }
                    } else {
                        console.log("[Player QML] Search completed but no segments found for channel:", root.channelId);
                    }
                }
            }
        }
    }

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
                                camName = rec.cameras[j].customName || rec.cameras[j].name || "";
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
        Qt.callLater(updateSource);
    }

    onIsSubStreamChanged: {
        Qt.callLater(updateSource);
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
        if (!root.visible || root.isQuickPlayback) {
            qmlAvPlayer1.source = "";
            qmlAvPlayer1.isSubStreamOfPlayer = false;
            qmlAvPlayer2.source = "";
            qmlAvPlayer2.isSubStreamOfPlayer = false;
            activeStreamUrl = "";
            activeCameraId = "";
            return;
        }

        var newUrl = "";
        var newCameraId = "";

        parseUri(source);

        if (root.isQuickPlayback) {
            newUrl = "";
            newCameraId = "";
        } else if (!isHikvision) {
            newUrl = source;
            newCameraId = "viewport_" + root.index;
        } else {
            if (hikPlayerSettings.useRealStreams) {
                var streamSuffix = isSubStream ? "02" : "01";
                newUrl = "rtsp://" + username + ":" + password + "@" + recorderIp + ":554/Streaming/Channels/" + channelId + streamSuffix;
                newCameraId = recorderIp + "_" + channelId;
            }
        }

        if (newUrl === "") {
            qmlAvPlayer1.source = "";
            qmlAvPlayer1.isSubStreamOfPlayer = false;
            qmlAvPlayer2.source = "";
            qmlAvPlayer2.isSubStreamOfPlayer = false;
            activeStreamUrl = "";
            activeCameraId = "";
            seamlessSwitchTimer.stop();
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

        var isSameCamera = (newCameraId !== "" && newCameraId === activeCameraId && playbackState === MediaPlayer.PlayingState);

        if (isSameCamera) {
            console.log("[Player] Seamless switch quality of camera " + newCameraId + " to URL: " + newUrl);
            inactivePlayer.muted = true; // Keep inactive player muted during loading
            inactivePlayer.isSubStreamOfPlayer = root.isSubStream;
            inactivePlayer.source = newUrl;
            inactivePlayer.play();
            activeStreamUrl = newUrl;
        } else {
            console.log("[Player] Different camera: switching immediately to URL: " + newUrl);
            seamlessSwitchTimer.stop();
            activePlayerIndex = 1;
            qmlAvPlayer2.source = "";
            qmlAvPlayer2.isSubStreamOfPlayer = false;
            qmlAvPlayer1.isSubStreamOfPlayer = root.isSubStream;
            qmlAvPlayer1.source = newUrl;
            qmlAvPlayer1.play();
            activeStreamUrl = newUrl;
            activeCameraId = newCameraId;
        }
    }

    function checkSeamlessSwitch(playerIndex) {
        if (playerIndex === activePlayerIndex) {
            return;
        }
        
        var player = playerIndex === 1 ? qmlAvPlayer1 : qmlAvPlayer2;
        if (String(player.source) !== activeStreamUrl) {
            console.log("[Player] checkSeamlessSwitch rejecting inactive player " + playerIndex + " due to source mismatch. Source: '" + player.source + "', Target: '" + activeStreamUrl + "'");
            return;
        }
        console.log("[Player] checkSeamlessSwitch checking inactive player " + playerIndex + " status: " + player.status + " hasVideo: " + player.hasVideo + " hasAudio: " + player.hasAudio + " framePresented: " + player.framePresented);
        if (player.playbackState === MediaPlayer.PlayingState && player.status === MediaPlayer.Buffered && player.hasVideo && player.framePresented) {
            if (seamlessSwitchTimer.running) {
                if (seamlessSwitchTimer.targetPlayerIndex === playerIndex) return;
                seamlessSwitchTimer.stop();
            }
            console.log("[Player] Inactive player " + playerIndex + " is ready. Starting 100ms seamless switch timer.");
            seamlessSwitchTimer.targetPlayerIndex = playerIndex;
            seamlessSwitchTimer.start();
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
            checkSeamlessSwitch(playerIndex);
        }
        else if (status === MediaPlayer.InvalidMedia) {
            console.log("[Player] Seamless switch failed: Inactive player " + playerIndex + " failed to load. Switching to show error.");
            activePlayerIndex = playerIndex;
            
            var targetIndex = playerIndex;
            Qt.callLater(function() {
                if (activePlayerIndex === targetIndex) {
                    var oldPlayer = targetIndex === 1 ? qmlAvPlayer2 : qmlAvPlayer1;
                    oldPlayer.source = "";
                    oldPlayer.isSubStreamOfPlayer = false;
                }
            });
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
            root.isRestoringLiveView = false;
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
    readonly property bool hasAudio: (typeof generalSettings !== "undefined" && generalSettings.disableAudio) ? false : (activePlayerIndex === 1 ? qmlAvPlayer1.hasAudio : qmlAvPlayer2.hasAudio)

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

    onActivePlayerIndexChanged: {
        if (activePlayerIndex === 1) {
            qmlAvPlayer1.muted = muted;
            qmlAvPlayer2.muted = true;
        } else {
            qmlAvPlayer2.muted = muted;
            qmlAvPlayer1.muted = true;
        }
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
            qmlAvPlayer1.source = "";
            qmlAvPlayer1.isSubStreamOfPlayer = false;
            qmlAvPlayer2.source = "";
            qmlAvPlayer2.isSubStreamOfPlayer = false;
            activeStreamUrl = "";
            activeCameraId = "";
        }
    }
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--debug-memory") !== -1) {
            console.log("[MEM-TRACK] Created Player.qml component (index: " + index + ")");
        }
        if (visible) {
            timer.start();
        }
        updateSource();
    }

    function showSnapshotDialog(path) {
        localSnapshotSavedDialog.filePath = path;
        localSnapshotSavedDialog.open();
    }

    function takeSnapshot(forceHD) {
        var typeStr = root.isQuickPlayback ? "QUICK_PLAYBACK" : "LIVE";
        captureCurrentFrameAndNotify(typeStr);
    }

    function captureCurrentFrameAndNotify(typeStr) {
        var d = new Date();
        var dateStr = Qt.formatDateTime(d, "yyyy-MM-dd_HH-mm-ss");
        var activeOutput = null;
        var nativeWidth = 1920;
        var nativeHeight = 1080;
        var rawCamName = root.cameraNameInfo || "Camera";
        rawCamName = rawCamName.replace(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/g, "");
        rawCamName = rawCamName.replace(/([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}/g, "");
        rawCamName = rawCamName.trim().replace(/^[_-\s]+|[_-\s]+$/g, "");
        var camName = rawCamName.replace(/ /g, "_").replace(/[^a-zA-Z0-9_\-\.]/g, "");

        var path = "";
        if (typeof generalSettings !== "undefined" && generalSettings.snapshotPath !== "") {
            path = generalSettings.snapshotPath;
        } else {
            path = Platform.StandardPaths.writableLocation(Platform.StandardPaths.PicturesLocation).toString();
            if (path.indexOf("file://") === 0) path = path.substring(7);
            path = path + "/CCTV";
        }
        Context.mkpath(path);
        path = path + "/" + camName + "_" + typeStr + "_" + dateStr + ".jpg";

        snapshotBadge.isSavingSnapshot = true;
        snapshotBadgeTimer.restart();

        if (root.isQuickPlayback && quickPlaybackPlayerLoader.item) {
            var saved = quickPlaybackPlayerLoader.item.saveCurrentFrame(path);
            if (saved) {
                console.log("Saved snapshot (" + typeStr + ") to", path);
                showSnapshotDialog(path);
            } else {
                console.log("Failed to save snapshot (" + typeStr + ") via C++ saveCurrentFrame");
            }
            return;
        }

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

        activeOutput.grabToImage(function(result) {
            result.saveToFile(path);
            console.log("Saved snapshot (" + typeStr + ") to", path);
            showSnapshotDialog(path);
        }, Qt.size(nativeWidth, nativeHeight));
    }

    function openPlayback() {
        var recInfo = {
            "ip": root.recorderIp,
            "port": root.recorderPort,
            "username": root.username,
            "password": root.password
        };
        var camName = root.cameraNameInfo || ("Camera " + root.channelId);

        if (typeof rootWindow !== "undefined" && rootWindow) {
            rootWindow.openPlaybackWindow(recInfo, root.channelId, camName);
        }
    }

    Component.onDestruction: {
        if (Qt.application.arguments.indexOf("--debug-memory") !== -1) {
            console.log("[MEM-TRACK] Destroyed Player.qml component (index: " + index + ")");
        }
        timer.stop();
        qmlAvPlayer1.autoPlay = false;
        qmlAvPlayer2.autoPlay = false;
        qmlAvPlayer1.source = "";
        qmlAvPlayer1.isSubStreamOfPlayer = false;
        qmlAvPlayer2.source = "";
        qmlAvPlayer2.isSubStreamOfPlayer = false;
        activeStreamUrl = "";
        activeCameraId = "";
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
                visible: (!root.isHikvision || hikPlayerSettings.useRealStreams)
                opacity: activePlayerIndex === 1 ? 1.0 : 0.0
                z: activePlayerIndex === 1 ? 2 : 1

                onSourceRectChanged: {
                    if (root.isOneToOne && root.activePlayerIndex === 1) {
                        root.oneToOneX = Math.min(0, (videoContainer.width - sourceRect.width) / 2);
                        root.oneToOneY = Math.min(0, (videoContainer.height - sourceRect.height) / 2);
                    }
                    if (root.activePlayerIndex !== 1 && sourceRect.width > 0) {
                        checkSeamlessSwitch(1);
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
                visible: (!root.isHikvision || hikPlayerSettings.useRealStreams)
                opacity: activePlayerIndex === 2 ? 1.0 : 0.0
                z: activePlayerIndex === 2 ? 2 : 1

                onSourceRectChanged: {
                    if (root.isOneToOne && root.activePlayerIndex === 2) {
                        root.oneToOneX = Math.min(0, (videoContainer.width - sourceRect.width) / 2);
                        root.oneToOneY = Math.min(0, (videoContainer.height - sourceRect.height) / 2);
                    }
                    if (root.activePlayerIndex !== 2 && sourceRect.width > 0) {
                        checkSeamlessSwitch(2);
                    }
                }
            }

            // Hikvision C++ Painted Player renders high-tech mock layout if fallback is disabled
            HikvisionPlayer {
                id: hikPlayer
                visible: root.isHikvision && !hikPlayerSettings.useRealStreams && root.visible && !root.isQuickPlayback
                x: -root.zoomX * width
                y: -root.zoomY * height
                width: parent.width / Math.max(0.001, root.zoomWidth)
                height: parent.height / Math.max(0.001, root.zoomHeight)
                recorderIp: (root.visible && root.isHikvision && !hikPlayerSettings.useRealStreams && !root.isQuickPlayback) ? root.recorderIp : ""
                recorderPort: root.recorderPort
                username: root.username
                password: root.password
                channelId: root.channelId
                streamType: root.isSubStream ? 1 : 0
            }

            Component {
                id: quickPlaybackPlayerComponent
                HikvisionArchivePlayer {
                    recorderIp: root.recorderIp
                    username: root.username
                    password: root.password
                    channelId: root.channelId
                    port: root.recorderPort
                    muted: root.muted
                    volume: root.volume

                    onVideoSizeChanged: {
                        if (root.isOneToOne && root.isQuickPlayback) {
                            root.oneToOneX = Math.min(0, (videoContainer.width - videoWidth) / 2);
                            root.oneToOneY = Math.min(0, (videoContainer.height - videoHeight) / 2);
                        }
                    }
                }
            }

            Loader {
                id: quickPlaybackPlayerLoader
                z: 3
                active: root.isQuickPlayback
                visible: root.isQuickPlayback
                x: root.isOneToOne ? root.oneToOneX : -root.zoomX * width
                y: root.isOneToOne ? root.oneToOneY : -root.zoomY * height
                width: root.isOneToOne ? ((item && item.videoWidth > 0) ? item.videoWidth : videoContainer.width) : (videoContainer.width / Math.max(0.001, root.zoomWidth))
                height: root.isOneToOne ? ((item && item.videoHeight > 0) ? item.videoHeight : videoContainer.height) : (videoContainer.height / Math.max(0.001, root.zoomHeight))
                sourceComponent: quickPlaybackPlayerComponent

                onLoaded: {
                    var playStart = new Date(root.quickPlaybackActivationTime.getTime() - (1800 - root.quickPlaybackOffset) * 1000);
                    item.playAtTime(playStart);
                }
            }
        }

        Text {
            id: message

            color: "white"
            visible: !root.isHikvision && (activePlayerIndex === 1 ? qmlAvPlayer1.status : qmlAvPlayer2.status) !== MediaPlayer.Buffered
            anchors.centerIn: parent
        }

        Rectangle {
            id: restoringLiveOverlay
            anchors.fill: parent
            z: 10
            color: "black"
            visible: root.isRestoringLiveView && !root.isQuickPlayback

            Text {
                anchors.centerIn: parent
                text: qsTr("Przywracam widok live...")
                color: "white"
            }
        }

        QmlAVPlayer {
            id: qmlAvPlayer1

            autoLoad: false
            property bool isSubStreamOfPlayer: false

            avOptions: {
                var avOptions = root.avOptions;
                if (!root.ignoreGlobalAVFormatOptions) {
                    Object.assignDefault(avOptions, layoutsCollectionSettings.toJSValue("defaultAVFormatOptions"));
                }
                if (typeof generalSettings !== "undefined" && generalSettings.disableAudio) {
                    avOptions["an"] = true;
                }
                return avOptions;
            }

            onStatusChanged: {
                handlePlayerStatus(1, status);
                updateMessageText();
            }

            onHasVideoChanged: {
                checkSeamlessSwitch(1);
            }

            onHasAudioChanged: {
                checkSeamlessSwitch(1);
            }

            onFramePresentedChanged: {
                if (framePresented) {
                    checkSeamlessSwitch(1);
                }
            }

            onBufferProgressChanged: {
                updateMessageText();
            }
        }

        QmlAVPlayer {
            id: qmlAvPlayer2

            autoLoad: false
            property bool isSubStreamOfPlayer: false

            avOptions: {
                var avOptions = root.avOptions;
                if (!root.ignoreGlobalAVFormatOptions) {
                    Object.assignDefault(avOptions, layoutsCollectionSettings.toJSValue("defaultAVFormatOptions"));
                }
                if (typeof generalSettings !== "undefined" && generalSettings.disableAudio) {
                    avOptions["an"] = true;
                }
                return avOptions;
            }

            onStatusChanged: {
                handlePlayerStatus(2, status);
                updateMessageText();
            }

            onHasVideoChanged: {
                checkSeamlessSwitch(2);
            }

            onHasAudioChanged: {
                checkSeamlessSwitch(2);
            }

            onFramePresentedChanged: {
                if (framePresented) {
                    checkSeamlessSwitch(2);
                }
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
            
            visible: (!viewSettings.showInfoOnHoverOnly || playerHoverArea.containsMouse) && viewSettings.showChannelStatus && (root.isQuickPlayback ? true : ((root.source !== "") && (root.isHikvision ? (root.recorderIp !== "") : (playbackState === MediaPlayer.PlayingState || status === MediaPlayer.Buffered || status === MediaPlayer.Buffering || status === MediaPlayer.Loading))))
            
            color: "#66121214"
            border {
                color: root.isQuickPlayback ? "#00f5d4" : (root.activeIsSubStream ? "#ff7a00" : "#00f5d4")
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
                    text: root.isQuickPlayback ? "MAIN" : (root.activeIsSubStream ? "SUB" : "MAIN")
                    color: root.activeIsSubStream && !root.isQuickPlayback ? "#ff7a00" : "#00f5d4"
                    font {
                        pixelSize: 8
                        bold: true
                    }
                }
                
                Rectangle {
                    width: 1
                    height: 7
                    color: root.activeIsSubStream && !root.isQuickPlayback ? "#44ff7a00" : "#4400f5d4"
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Text {
                    visible: root.isQuickPlayback
                    text: root.quickPlaybackSpeed + "x"
                    color: "#ff7a00"
                    font {
                        pixelSize: 8
                        bold: true
                    }
                }

                Rectangle {
                    visible: root.isQuickPlayback
                    width: 1
                    height: 7
                    color: "#44ff7a00"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: {
                        var fpsVal = 0;
                        if (root.isQuickPlayback && quickPlaybackPlayerLoader.item) {
                            fpsVal = quickPlaybackPlayerLoader.item.fps;
                        } else if (root.isHikvision) {
                            if (hikPlayerSettings.useRealStreams) {
                                fpsVal = (root.activePlayerIndex === 1 ? qmlAvPlayer1.fps : qmlAvPlayer2.fps);
                            } else {
                                fpsVal = hikPlayer.fps;
                            }
                        } else {
                            fpsVal = (root.activePlayerIndex === 1 ? qmlAvPlayer1.fps : qmlAvPlayer2.fps);
                        }
                        return fpsVal + " FPS";
                    }
                    color: "#eeeeee"
                    font {
                        pixelSize: 8
                        bold: true
                    }
                }
                
                Rectangle {
                    width: 1
                    height: 7
                    color: root.activeIsSubStream && !root.isQuickPlayback ? "#44ff7a00" : "#4400f5d4"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isQuickPlayback ? false : (!root.isHikvision || hikPlayerSettings.useRealStreams)
                }
                
                Text {
                    text: bitrateTimer.bitrateText
                    color: "#eeeeee"
                    font {
                        pixelSize: 8
                    }
                    visible: root.isQuickPlayback ? false : (!root.isHikvision || hikPlayerSettings.useRealStreams)
                }
            }
        }



        Rectangle {
            id: cameraInfoBadge
            
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: 6
                bottomMargin: root.isQuickPlayback ? (quickPlaybackControlsPanel.height + 12) : 6
            }
            
            visible: (!viewSettings.showInfoOnHoverOnly || playerHoverArea.containsMouse) && viewSettings.showCameraInfo && root.isHikvision && root.cameraNameInfo !== ""
            
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

                    var videoW;
                    var videoH;
                    if (root.isQuickPlayback) {
                        videoW = quickPlaybackPlayerLoader.width;
                        videoH = quickPlaybackPlayerLoader.height;
                    } else {
                        var activeOutput = root.activePlayerIndex === 1 ? videoOutput1 : videoOutput2;
                        videoW = activeOutput.width;
                        videoH = activeOutput.height;
                    }

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

        MouseArea {
            id: playerHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton

            property bool isHovered: false

            function updateHoverState() {
                isHovered = containsMouse ||
                            snapshotMouseAreaBtn.containsMouse ||
                            (playbackBadge.visible && playbackMouseAreaBtn.containsMouse) ||
                            oneToOneMouseAreaBtn.containsMouse ||
                            zoomMouseAreaBtn.containsMouse ||
                            (volumeControl.visible && (muteMouseArea.containsMouse || sliderMouseArea.containsMouse || maxVolMouseArea.containsMouse || volumeSlider.pressed));
            }

            onContainsMouseChanged: updateHoverState()
            Component.onCompleted: updateHoverState()

            // Symmetrically placed magnifying glass button overlay on the bottom right
            Row {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: 6
                    bottomMargin: root.isQuickPlayback ? (quickPlaybackControlsPanel.height + 12) : 6
                }
                spacing: 6
                visible: (root.source !== "") && (!viewSettings.hoverControlIcons || playerHoverArea.isHovered)

                Row {
                    id: volumeControl
                    spacing: 4
                    visible: root.isFullScreen && root.hasAudio

                    Control {
                        id: muteButton
                        implicitWidth: 24
                        implicitHeight: 24
                        padding: 5
                        focusPolicy: Qt.NoFocus

                        background: Rectangle {
                            radius: 12
                            color: muteMouseArea.pressed ? "#4a5560" : (muteMouseArea.containsMouse ? "#3a4550" : "#cc121214")
                            border.color: (muteMouseArea.containsMouse || muteMouseArea.pressed) ? "#cc8898a6" : "#802a3540"
                            border.width: 1
                        }

                        contentItem: Image {
                            sourceSize: Qt.size(32, 32)
                            fillMode: Image.PreserveAspectFit
                            source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ff3333' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='11 5 6 9 2 9 2 15 6 15 11 19 11 5'></polygon><line x1='23' y1='9' x2='17' y2='15'></line><line x1='17' y1='9' x2='23' y2='15'></line></svg>"
                        }

                        MouseArea {
                            id: muteMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: playerHoverArea.updateHoverState()
                            onClicked: {
                                if (root.layoutModel && root.index !== -1) {
                                    var vItem = root.layoutModel.get(root.index);
                                    if (vItem) vItem.volume = 0.0;
                                } else {
                                    root.volume = 0.0;
                                }
                            }
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: muteMouseArea.containsMouse
                        ToolTip.text: qsTr("Wycisz")
                    }

                    Slider {
                        id: volumeSlider
                        width: 110
                        height: 24
                        padding: 0
                        from: 0.0
                        to: 1.0
                        value: root.volume
                        focusPolicy: Qt.NoFocus
                        onMoved: {
                            if (root.layoutModel && root.index !== -1) {
                                var vItem = root.layoutModel.get(root.index);
                                if (vItem) vItem.volume = value;
                            } else {
                                root.volume = value;
                            }
                        }

                        background: Rectangle {
                            x: volumeSlider.leftPadding
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            implicitWidth: 110
                            implicitHeight: 4
                            width: volumeSlider.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: "#1c242c"

                            Rectangle {
                                width: volumeSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#00f5d4"
                                radius: 2
                                layer.enabled: true
                                layer.effect: Glow {
                                    radius: 4
                                    samples: 8
                                    color: "#00f5d4"
                                    transparentBorder: true
                                }
                            }
                        }

                        handle: Rectangle {
                            x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                            implicitWidth: 12
                            implicitHeight: 12
                            radius: 6
                            color: volumeSlider.pressed ? "#ff9a00" : (sliderMouseArea.containsMouse ? "#ffaa00" : "#ff7a00")
                            border.color: "#ffffff"
                            border.width: volumeSlider.pressed ? 2 : 1
                        }

                        MouseArea {
                            id: sliderMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            onContainsMouseChanged: playerHoverArea.updateHoverState()
                        }

                        Connections {
                            target: volumeSlider
                            function onPressedChanged() { playerHoverArea.updateHoverState() }
                        }
                    }

                    Control {
                        id: maxVolButton
                        implicitWidth: 24
                        implicitHeight: 24
                        padding: 5
                        focusPolicy: Qt.NoFocus

                        background: Rectangle {
                            radius: 12
                            color: maxVolMouseArea.pressed ? "#4a5560" : (maxVolMouseArea.containsMouse ? "#3a4550" : "#cc121214")
                            border.color: (maxVolMouseArea.containsMouse || maxVolMouseArea.pressed) ? "#cc8898a6" : "#802a3540"
                            border.width: 1
                        }

                        contentItem: Image {
                            sourceSize: Qt.size(32, 32)
                            fillMode: Image.PreserveAspectFit
                            source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='11 5 6 9 2 9 2 15 6 15 11 19 11 5'></polygon><path d='M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07'></path></svg>"
                        }

                        MouseArea {
                            id: maxVolMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: playerHoverArea.updateHoverState()
                            onClicked: {
                                if (root.layoutModel && root.index !== -1) {
                                    var vItem = root.layoutModel.get(root.index);
                                    if (vItem) vItem.volume = 1.0;
                                } else {
                                    root.volume = 1.0;
                                }
                            }
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: maxVolMouseArea.containsMouse
                        ToolTip.text: qsTr("Maksymalna głośność")
                    }
                }

                Control {
                    id: snapshotBadge

                    property bool isSavingSnapshot: false

                    Timer {
                        id: snapshotBadgeTimer
                        interval: 1000
                        onTriggered: snapshotBadge.isSavingSnapshot = false
                    }

                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 5
                    visible: root.source !== ""

                    background: Rectangle {
                        radius: 12
                        color: snapshotBadge.isSavingSnapshot ?
                            (snapshotMouseAreaBtn.pressed ? "#44ff7a00" : (snapshotMouseAreaBtn.containsMouse ? "#33ff7a00" : "#22ff7a00")) :
                            (snapshotMouseAreaBtn.pressed ? "#4a5560" : (snapshotMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214"))
                        border.color: snapshotBadge.isSavingSnapshot ?
                            "#ccff7a00" :
                            ((snapshotMouseAreaBtn.containsMouse || snapshotMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540")
                        border.width: 1
                    }

                    contentItem: Image {
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                        source: snapshotBadge.isSavingSnapshot ?
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ff7a00' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'></path><circle cx='12' cy='13' r='4'></circle></svg>" :
                            (snapshotMouseAreaBtn.containsMouse ?
                                "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'></path><circle cx='12' cy='13' r='4'></circle></svg>" :
                                "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'></path><circle cx='12' cy='13' r='4'></circle></svg>")
                    }

                    MouseArea {
                        id: snapshotMouseAreaBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: playerHoverArea.updateHoverState()
                        onClicked: {
                            root.takeSnapshot(false);
                        }
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: snapshotMouseAreaBtn.containsMouse
                    ToolTip.text: qsTr("Wykonaj stopklatkę w pełnej rozdzielczości")
                }

                Control {
                    id: playbackBadge

                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 5
                    visible: root.source !== "" && root.isHikvision
                    onVisibleChanged: playerHoverArea.updateHoverState()

                    background: Rectangle {
                        radius: 12
                        color: playbackMouseAreaBtn.pressed ? "#4a5560" : (playbackMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214")
                        border.color: (playbackMouseAreaBtn.containsMouse || playbackMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540"
                        border.width: 1
                    }

                    contentItem: Image {
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                        source: playbackMouseAreaBtn.containsMouse ?
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='5 3 19 12 5 21 5 3'></polygon></svg>" :
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='5 3 19 12 5 21 5 3'></polygon></svg>"
                    }

                    MouseArea {
                        id: playbackMouseAreaBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: playerHoverArea.updateHoverState()
                        onClicked: {
                            var recInfo = {
                                "ip": root.recorderIp,
                                "port": root.recorderPort,
                                "username": root.username,
                                "password": root.password
                            };
                            var camName = root.cameraNameInfo || ("Camera " + root.channelId);

                            rootWindow.openPlaybackWindow(recInfo, root.channelId, camName);
                        }
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: playbackMouseAreaBtn.containsMouse
                    ToolTip.text: qsTr("Archiwum nagrań")
                }

                Control {
                    id: quickPlaybackToggleBadge

                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 5
                    visible: root.source !== "" && root.isHikvision
                    onVisibleChanged: playerHoverArea.updateHoverState()

                    background: Rectangle {
                        radius: 12
                        color: root.isQuickPlayback ?
                            (quickPlaybackToggleMouseArea.pressed ? "#4400f5d4" : (quickPlaybackToggleMouseArea.containsMouse ? "#3300f5d4" : "#2200f5d4")) :
                            (quickPlaybackToggleMouseArea.pressed ? "#4a5560" : (quickPlaybackToggleMouseArea.containsMouse ? "#3a4550" : "#cc121214"))
                        border.color: root.isQuickPlayback ?
                            "#cc00f5d4" :
                            ((quickPlaybackToggleMouseArea.containsMouse || quickPlaybackToggleMouseArea.pressed) ? "#cc8898a6" : "#802a3540")
                        border.width: 1
                    }

                    contentItem: Image {
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                        source: (root.isQuickPlayback || quickPlaybackToggleMouseArea.containsMouse) ?
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M3 2v6h6'></path><path d='M3 13a9 9 0 1 0 3-7.7L3 8'></path></svg>" :
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M3 2v6h6'></path><path d='M3 13a9 9 0 1 0 3-7.7L3 8'></path></svg>"
                    }

                    MouseArea {
                        id: quickPlaybackToggleMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: playerHoverArea.updateHoverState()
                        onClicked: {
                            root.isQuickPlayback = !root.isQuickPlayback;
                        }
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: quickPlaybackToggleMouseArea.containsMouse
                    ToolTip.text: root.isQuickPlayback ? qsTr("Wyłącz szybki podgląd wstecz") : qsTr("Szybki podgląd wstecz (do 30 min)")
                }

                Control {
                    id: oneToOneBadge

                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 5
                    visible: root.source !== ""

                    background: Rectangle {
                        radius: 12
                        color: root.isOneToOne ?
                            (oneToOneMouseAreaBtn.pressed ? "#4400f5d4" : (oneToOneMouseAreaBtn.containsMouse ? "#3300f5d4" : "#2200f5d4")) :
                            (oneToOneMouseAreaBtn.pressed ? "#4a5560" : (oneToOneMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214"))
                        border.color: root.isOneToOne ?
                            "#cc00f5d4" :
                            ((oneToOneMouseAreaBtn.containsMouse || oneToOneMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540")
                        border.width: 1
                    }

                    contentItem: Image {
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                        source: (root.isOneToOne || oneToOneMouseAreaBtn.containsMouse) ?
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M6 8.5L8 7v10M16 8.5L18 7v10'></path><circle cx='12' cy='10' r='1' fill='%2300f5d4' stroke='none'></circle><circle cx='12' cy='14' r='1' fill='%2300f5d4' stroke='none'></circle></svg>" :
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M6 8.5L8 7v10M16 8.5L18 7v10'></path><circle cx='12' cy='10' r='1' fill='%23ffffff' stroke='none'></circle><circle cx='12' cy='14' r='1' fill='%23ffffff' stroke='none'></circle></svg>"
                    }

                    MouseArea {
                        id: oneToOneMouseAreaBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: playerHoverArea.updateHoverState()
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

                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 5
                    visible: root.source !== ""

                    background: Rectangle {
                        radius: 12
                        color: root.isZoomed ?
                            (zoomMouseAreaBtn.pressed ? "#44ff3333" : (zoomMouseAreaBtn.containsMouse ? "#33ff3333" : "#22121214")) :
                            (root.isZoomSelectionMode ?
                                (zoomMouseAreaBtn.pressed ? "#4400f5d4" : (zoomMouseAreaBtn.containsMouse ? "#3300f5d4" : "#2200f5d4")) :
                                (zoomMouseAreaBtn.pressed ? "#4a5560" : (zoomMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214"))
                            )
                        border.color: root.isZoomed ?
                            (zoomMouseAreaBtn.containsMouse ? "#ccff3333" : "#80ff3333") :
                            (root.isZoomSelectionMode ?
                                "#cc00f5d4" :
                                ((zoomMouseAreaBtn.containsMouse || zoomMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540")
                            )
                        border.width: 1
                    }

                    contentItem: Image {
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                        source: root.isZoomed ?
                            "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ff3333' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>" :
                            ((root.isZoomSelectionMode || zoomMouseAreaBtn.containsMouse) ?
                                "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='11' y1='8' x2='11' y2='14'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>" :
                                "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='11' y1='8' x2='11' y2='14'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>"
                            )
                    }

                    MouseArea {
                        id: zoomMouseAreaBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: playerHoverArea.updateHoverState()
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

        // --- QUICK PLAYBACK CONTROLS PANEL ---
        Rectangle {
            id: quickPlaybackControlsPanel
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 46
            color: root.isFullScreen ? "#801c242c" : "#661c242c"
            visible: root.isQuickPlayback

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPressed: mouse.accepted = true
                onReleased: mouse.accepted = true
                onDoubleClicked: mouse.accepted = true
            }

            Slider {
                id: qpSlider
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 18
                from: 0
                to: 1800
                value: root.quickPlaybackOffset
                focusPolicy: Qt.NoFocus
                padding: 0
                leftPadding: 0
                rightPadding: 0
                topPadding: 0
                bottomPadding: 0
                leftInset: 0
                rightInset: 0
                topInset: 0
                bottomInset: 0
                
                onPressedChanged: {
                    if (pressed) {
                        if (quickPlaybackPlayerLoader.item) {
                            quickPlaybackPlayerLoader.item.pause();
                        }
                    } else {
                        root.quickPlaybackOffset = value;
                        var seekTime = new Date(root.quickPlaybackActivationTime.getTime() - (1800 - root.quickPlaybackOffset) * 1000);
                        if (quickPlaybackPlayerLoader.item) {
                            quickPlaybackPlayerLoader.item.playAtTime(seekTime);
                            if (root.quickPlaybackSpeed !== 1) {
                                quickPlaybackPlayerLoader.item.setPlaybackSpeed(root.quickPlaybackSpeed);
                            }
                            if (!root.isQuickPlaybackPaused) {
                                quickPlaybackPlayerLoader.item.resume();
                            }
                        }
                    }
                }
                onMoved: {
                    if (pressed) {
                        root.quickPlaybackOffset = value;
                    }
                }

                background: Rectangle {
                    anchors.fill: parent
                    color: "#330a0a0c"

                    Canvas {
                        id: qpTimelineCanvas
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);

                            // 1. Availability segments
                            ctx.fillStyle = root.isFullScreen ? "rgba(0, 245, 212, 0.55)" : "rgba(0, 245, 212, 0.45)";
                            for (var k = 0; k < root.quickPlaybackSegments.length; k++) {
                                var seg = root.quickPlaybackSegments[k];
                                if (!seg) continue;
                                var windowStartMs = root.quickPlaybackActivationTime ? (root.quickPlaybackActivationTime.getTime() - 1800000) : 0;
                                var windowEndMs = root.quickPlaybackActivationTime ? root.quickPlaybackActivationTime.getTime() : 0;
                                var segStartMs = Math.max(windowStartMs, seg.startTime);
                                var segEndMs = Math.min(windowEndMs, seg.endTime);
                                if (segStartMs < segEndMs && root.quickPlaybackActivationTime) {
                                    var x1 = ((segStartMs - windowStartMs) / 1800000) * width;
                                    var w = ((segEndMs - segStartMs) / 1800000) * width;
                                    ctx.fillRect(x1, 0, w, height);
                                }
                            }

                            // 2. Timeline ticks & minute scale
                            var windowStartMs = root.quickPlaybackActivationTime ? (root.quickPlaybackActivationTime.getTime() - 1800000) : 0;
                            var windowEndMs = root.quickPlaybackActivationTime ? root.quickPlaybackActivationTime.getTime() : 0;
                            var startMinMs = Math.ceil(windowStartMs / 60000) * 60000;
                            var endMinMs = Math.floor(windowEndMs / 60000) * 60000;

                            for (var mMs = startMinMs; mMs <= endMinMs; mMs += 60000) {
                                var tx = ((mMs - windowStartMs) / 1800000) * width;
                                var d = new Date(mMs);
                                var isFiveMin = (d.getMinutes() % 5 === 0);
                                
                                ctx.fillStyle = isFiveMin ? "#ffffff" : "rgba(255, 255, 255, 0.5)";
                                var tickHeight = isFiveMin ? 6 : 3;
                                ctx.fillRect(tx, height - tickHeight, 1, tickHeight);
                                
                                if (isFiveMin) {
                                    var displayH = d.getHours();
                                    var displayM = d.getMinutes();
                                    var timeStr = (displayH < 10 ? "0" : "") + displayH + ":" + (displayM < 10 ? "0" : "") + displayM;
                                    
                                    ctx.font = "bold 9px sans-serif";
                                    
                                    // Black shadow/outline for extreme contrast on video background
                                    ctx.fillStyle = "#000000";
                                    ctx.fillText(timeStr, tx - 12 + 1, height - 8 + 1);
                                    
                                    // White foreground text
                                    ctx.fillStyle = "#ffffff";
                                    ctx.fillText(timeStr, tx - 12, height - 8);
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onQuickPlaybackSegmentsChanged() { qpTimelineCanvas.requestPaint(); }
                            function onQuickPlaybackActivationTimeChanged() { qpTimelineCanvas.requestPaint(); }
                        }
                    }
                    
                    Rectangle {
                        width: qpSlider.visualPosition * parent.width
                        height: parent.height
                        color: "#00f5d4"
                        opacity: 0.1
                    }
                }
                
                handle: Rectangle {
                    x: qpSlider.leftPadding + qpSlider.visualPosition * qpSlider.availableWidth - width / 2
                    y: qpSlider.topPadding
                    implicitWidth: 2
                    implicitHeight: 18
                    color: "red"
                }
            }

            RowLayout {
                id: qpButtonsRow
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 8
                    rightMargin: 8
                    bottomMargin: 2
                }
                height: 24
                spacing: 8

                CctvButton {
                    id: qpPlayPauseBtn
                    focusPolicy: Qt.NoFocus
                    isMini: true
                    isTransparent: true
                    iconSource: {
                        var colorStr = "%23ffffff";
                        if (root.isQuickPlaybackPaused) {
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='" + colorStr + "' stroke='none'><polygon points='8 5 19 12 8 19 8 5'></polygon></svg>";
                        } else {
                            return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='" + colorStr + "' stroke='none'><rect x='6' y='4' width='4' height='16' rx='1'></rect><rect x='14' y='4' width='4' height='16' rx='1'></rect></svg>";
                        }
                    }
                    onClicked: {
                        root.isQuickPlaybackPaused = !root.isQuickPlaybackPaused;
                        if (root.isQuickPlaybackPaused) {
                            if (quickPlaybackPlayerLoader.item) {
                                quickPlaybackPlayerLoader.item.pause();
                            }
                        } else {
                            if (quickPlaybackPlayerLoader.item) {
                                quickPlaybackPlayerLoader.item.resume();
                            }
                        }
                    }
                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: hovered
                    ToolTip.text: root.isQuickPlaybackPaused ? qsTr("Rozpocznij odtwarzanie") : qsTr("Wstrzymaj odtwarzanie")
                }

                Text {
                    id: qpTimeDisplay
                    Layout.minimumWidth: 100
                    color: "#ffffff"
                    font.pixelSize: 11
                    font.bold: true
                    visible: parent.width > 250
                    text: {
                        if (!root.quickPlaybackActivationTime) return "--:--:-- (now)";
                        var currentD = new Date(root.quickPlaybackActivationTime.getTime() - (1800 - root.quickPlaybackOffset) * 1000);
                        return root.formatTime(currentD) + " (" + root.formatRelativeTime(root.quickPlaybackOffset) + ")";
                    }
                }

                Item { Layout.fillWidth: true }

                CctvButton {
                    id: qpSpeedBtn
                    focusPolicy: Qt.NoFocus
                    text: root.quickPlaybackSpeed + "x"
                    isMini: true
                    isTransparent: true
                    onClicked: {
                        if (root.quickPlaybackSpeed === 1) root.quickPlaybackSpeed = 2;
                        else if (root.quickPlaybackSpeed === 2) root.quickPlaybackSpeed = 4;
                        else root.quickPlaybackSpeed = 1;
                        if (quickPlaybackPlayerLoader.item) {
                            quickPlaybackPlayerLoader.item.setPlaybackSpeed(root.quickPlaybackSpeed);
                        }
                    }
                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Prędkość odtwarzania")
                }

                CctvButton {
                    id: qpCloseBtn
                    focusPolicy: Qt.NoFocus
                    isMini: true
                    isTransparent: true
                    iconSource: {
                        var colorStr = qpCloseBtn.hovered ? "%23ff3333" : "%238898a6";
                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='18' y1='6' x2='6' y2='18'></line><line x1='6' y1='6' x2='18' y2='18'></line></svg>";
                    }
                    onClicked: {
                        root.isQuickPlayback = false;
                    }
                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Zamknij podgląd wstecz")
                }
            }
        }

        Timer {
            id: quickPlaybackTimer
            interval: 1000
            repeat: true
            onTriggered: {
                if (root.isQuickPlayback && !root.isQuickPlaybackPaused) {
                    var nextOffset = root.quickPlaybackOffset + root.quickPlaybackSpeed;
                    if (nextOffset > 1800) {
                        nextOffset = 1800;
                        root.isQuickPlaybackPaused = true;
                        if (quickPlaybackPlayerLoader.item) {
                            quickPlaybackPlayerLoader.item.pause();
                        }
                    }
                    root.quickPlaybackOffset = nextOffset;
                }
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
        qmlAvPlayer1.source = "";
        qmlAvPlayer1.isSubStreamOfPlayer = false;
        qmlAvPlayer2.source = "";
        qmlAvPlayer2.isSubStreamOfPlayer = false;
        activeStreamUrl = "";
        activeCameraId = "";
        seamlessSwitchTimer.stop();
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

    SnapshotSavedDialog {
        id: localSnapshotSavedDialog
    }
}
