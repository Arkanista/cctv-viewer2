import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import CCTV_Viewer.Hikvision 1.0
import QtGraphicalEffects 1.12
import CCTV_Viewer.Core 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Themes 1.0
import Qt.labs.settings 1.0
import Qt.labs.platform 1.1 as Platform


Window {
    id: playbackWindow
    width: 950
    height: 650
    title: qsTr("Archive - ") + cameraName

    property var recorderInfo
    property int channelId: 1
    property string cameraName: ""

    property date currentDate: new Date()
    property real playheadTimeMs: 0
    readonly property real currentPlayheadMs: playheadTimeMs - currentDate.getTime()
    property real zoomHours: 24
    property real panOffsetMs: 0
    property bool isPlaying: false
    property bool autoFollowEnabled: true
    property int playbackSpeed: 1
    property bool playbackStoppedForDownload: false

    property bool sidebarVisible: true
    property bool topBarAutoCollapse: true
    property bool hideTimelineOption: false
    readonly property bool isBottomPanelFloating: (fullScreenPlayerIndex !== -1) || (playbackWindow.visibility === Window.FullScreen)

    Timer {
        id: keepVisibleTimer
        interval: 350
        repeat: false
    }
    Timer {
        id: bottomKeepVisibleTimer
        interval: 350
        repeat: false
    }
    readonly property bool isBottomPanelShowed: !playbackWindow.hideTimelineOption || bottomHoverArea.containsMouse || bottomPanelMouseArea.containsMouse || bottomKeepVisibleTimer.running
    property int fullScreenPlayerIndex: -1

    onGridLayoutColumnsChanged: fullScreenPlayerIndex = -1
    onGridLayoutRowsChanged: fullScreenPlayerIndex = -1

    function toggleWindowFullScreen() {
        if (playbackWindow.visibility === Window.FullScreen) {
            playbackWindow.visibility = Window.Windowed;
        } else {
            playbackWindow.visibility = Window.FullScreen;
        }
    }

    Shortcut {
        sequences: ["F11", StandardKey.FullScreen]
        onActivated: toggleWindowFullScreen()
        onActivatedAmbiguously: toggleWindowFullScreen()
    }

    Shortcut {
        sequences: ["F9", "Ctrl+B"]
        onActivated: sidebarVisible = !sidebarVisible
    }

    property var daysWithRecords: {
        if (typeof rootWindow === 'undefined' || !rootWindow || !recorderInfo) return [];
        var key = recorderInfo.ip + "_" + channelId + "_" + currentDate.getFullYear() + "-" + currentDate.getMonth();
        return rootWindow.monthAvailabilitiesCache[key] || [];
    }
    property int fetchedYear: -1
    property int fetchedMonth: -1

    color: "#0a0f14"

    property var monthNames: [qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"), qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"), qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December")]

    property bool isSearchingRecordings: false
    property var monthAvailabilityFetching: ({})
    property bool isSearchingMonth: Object.keys(monthAvailabilityFetching).length > 0

    onIsSearchingRecordingsChanged: {
        timeline.requestPaint()
    }

    // Multi-camera grid and sidebar properties
    property var activePlayersList: []
    onActivePlayersListChanged: {
        timeline.requestPaint();
        prefetchActiveCameras();
    }
    property int selectedPlayerIndex: 0
    property var recordersList: []
    
    // User selected layout columns/rows (max 2x2, default 2x2)
    property int gridLayoutColumns: 2
    property int gridLayoutRows: 2
    
    // Cached segments for all active viewports (keyed by recorderIp_channelId_dateKey)
    property var activePlayersFetching: ({})
    
    function getDateKey(date) {
        if (!date) return "";
        return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate();
    }
    
    onSelectedPlayerIndexChanged: {
        updateActiveCameraProperties();
    }
    
    function loadRecordersList() {
        try {
            var jsonStr = rootWindow.hikvisionRecordersJson;
            if (jsonStr) {
                recordersList = JSON.parse(jsonStr);
            }
        } catch (e) {
            console.log("Error parsing recorders in PlaybackWindow:", e);
        }
    }

    function isCameraInGrid(ip, channelId) {
        for (var i = 0; i < activePlayersList.length; i++) {
            if (activePlayersList[i] && activePlayersList[i].ip === ip && activePlayersList[i].channelId === channelId) {
                return true;
            }
        }
        return false;
    }

    function isRecorderInGrid(ip) {
        for (var i = 0; i < activePlayersList.length; i++) {
            if (activePlayersList[i] && activePlayersList[i].ip === ip) {
                return true;
            }
        }
        return false;
    }

    function cameraMatches(cameraObj, query, recorderObj) {
        if (!query) return true;
        if (!cameraObj) return false;
        if (recorderObj) {
            var recName = (recorderObj.name || "").toLowerCase();
            var recIp = (recorderObj.ip || "").toLowerCase();
            if (recName.indexOf(query) !== -1 || recIp.indexOf(query) !== -1) {
                return true;
            }
        }
        var name = (cameraObj.customName || cameraObj.name || "").toLowerCase();
        var defaultName = ("kamera " + cameraObj.channelId).toLowerCase();
        var chName = "ch " + (cameraObj.channelId < 10 ? "0" + cameraObj.channelId : cameraObj.channelId);
        var chSimple = "ch" + cameraObj.channelId;
        var chNum = "" + cameraObj.channelId;
        return name.indexOf(query) !== -1 ||
               defaultName.indexOf(query) !== -1 ||
               chName.indexOf(query) !== -1 ||
               chSimple.indexOf(query) !== -1 ||
               chNum.indexOf(query) !== -1;
    }

    function hasMatchingCameras(recorderObj, query) {
        if (!query) return true;
        var recName = (recorderObj.name || "").toLowerCase();
        var recIp = (recorderObj.ip || "").toLowerCase();
        if (recName.indexOf(query) !== -1 || recIp.indexOf(query) !== -1) {
            return true;
        }
        if (!recorderObj.cameras) return false;
        for (var i = 0; i < recorderObj.cameras.length; i++) {
            if (cameraMatches(recorderObj.cameras[i], query, recorderObj)) {
                return true;
            }
        }
        return false;
    }

    function isAnyCameraSearching() {
        for (var i = 0; i < activePlayersList.length; i++) {
            var cam = activePlayersList[i];
            if (!cam) continue;
            var key = cam.ip + "_" + cam.channelId + "_" + getDateKey(currentDate);
            if (activePlayersFetching[key] === true) {
                return true;
            }
        }
        return false;
    }

    function getLoadedCameras() {
        var list = [];
        for (var i = 0; i < activePlayersList.length; i++) {
            var cam = activePlayersList[i];
            if (cam !== null && cam !== undefined) {
                list.push(cam);
            }
        }
        return list;
    }

    function resizeActivePlayersList(newSize) {
        var list = [];
        // Copy existing elements up to newSize
        for (var i = 0; i < Math.min(activePlayersList.length, newSize); i++) {
            list.push(activePlayersList[i]);
        }
        // Stop any players that are being removed
        if (activePlayersList.length > newSize) {
            for (var j = newSize; j < activePlayersList.length; j++) {
                var item = gridRepeater.itemAt(j);
                if (item && item.playerInstance) {
                    item.playerInstance.stop();
                }
                var removedCam = activePlayersList[j];
                if (removedCam) {
                    var key = removedCam.ip + "_" + removedCam.channelId;
                    var tempFetching = Object.assign({}, activePlayersFetching);
                    delete tempFetching[key];
                    activePlayersFetching = tempFetching;
                }
            }
        }
        // Pad with nulls if expanding
        while (list.length < newSize) {
            list.push(null);
        }
        activePlayersList = list;
        
        // Ensure selectedPlayerIndex is within range
        if (selectedPlayerIndex >= newSize) {
            selectedPlayerIndex = newSize - 1;
        }
        updateActiveCameraProperties();
    }

    function addCameraToGrid(rec, cam) {
        // Check if already in grid
        for (var i = 0; i < activePlayersList.length; i++) {
            if (activePlayersList[i] && activePlayersList[i].ip === rec.ip && activePlayersList[i].channelId === cam.channelId) {
                selectedPlayerIndex = i;
                updateActiveCameraProperties();
                return;
            }
        }
        
        // Ensure selectedPlayerIndex is valid and within bounds
        if (selectedPlayerIndex < 0 || selectedPlayerIndex >= activePlayersList.length) {
            var firstEmpty = -1;
            for (var k = 0; k < activePlayersList.length; k++) {
                if (!activePlayersList[k]) {
                    firstEmpty = k;
                    break;
                }
            }
            if (firstEmpty !== -1) {
                selectedPlayerIndex = firstEmpty;
            } else {
                selectedPlayerIndex = 0;
            }
        }
        
        // Stop existing player in this slot if any
        var existingItem = gridRepeater.itemAt(selectedPlayerIndex);
        if (existingItem && existingItem.playerInstance) {
            existingItem.playerInstance.stop();
        }
        if (activePlayersList[selectedPlayerIndex]) {
            var oldCam = activePlayersList[selectedPlayerIndex];
            var oldKey = oldCam.ip + "_" + oldCam.channelId;
            var tempFetching = Object.assign({}, activePlayersFetching);
            delete tempFetching[oldKey];
            activePlayersFetching = tempFetching;
        }
        
        var list = [];
        for (var j = 0; j < activePlayersList.length; j++) {
            list.push(activePlayersList[j]);
        }
        
        list[selectedPlayerIndex] = {
            "ip": rec.ip,
            "port": rec.port || 8000,
            "username": rec.username,
            "password": rec.password,
            "channelId": cam.channelId,
            "cameraName": cam.customName || cam.name || ("Kamera " + cam.channelId),
            "recorderName": rec.name || rec.ip
        };
        
        activePlayersList = list;
        updateActiveCameraProperties();
        timeline.requestPaint();
    }

    function removeCameraFromGrid(index) {
        if (index < 0 || index >= activePlayersList.length) {
            return;
        }
        
        if (fullScreenPlayerIndex === index) {
            fullScreenPlayerIndex = -1;
        }
        
        var removedCam = activePlayersList[index];
        if (!removedCam) {
            return;
        }
        
        var item = gridRepeater.itemAt(index);
        if (item && item.playerInstance) {
            item.playerInstance.stop();
        }
        
        // Remove from fetching state
        var fetchKey = removedCam.ip + "_" + removedCam.channelId + "_" + getDateKey(currentDate);
        var tempFetching = Object.assign({}, activePlayersFetching);
        delete tempFetching[fetchKey];
        activePlayersFetching = tempFetching;
        
        var list = [];
        for (var i = 0; i < activePlayersList.length; i++) {
            if (i === index) {
                list.push(null);
            } else {
                list.push(activePlayersList[i]);
            }
        }
        
        activePlayersList = list;
        updateActiveCameraProperties();
        timeline.requestPaint();
    }

    function updateActiveCameraProperties() {
        if (selectedPlayerIndex >= 0 && selectedPlayerIndex < activePlayersList.length) {
            var data = activePlayersList[selectedPlayerIndex];
            if (data) {
                playbackWindow.recorderInfo = {
                    "ip": data.ip,
                    "port": data.port || 8000,
                    "username": data.username,
                    "password": data.password,
                    "name": data.recorderName
                };
                playbackWindow.channelId = data.channelId;
                playbackWindow.cameraName = data.cameraName;
                
                var dateKey = getDateKey(currentDate);
                var cacheKey = data.ip + "_" + data.channelId + "_" + dateKey;
                var fetchKey = data.ip + "_" + data.channelId + "_" + dateKey;
                if (rootWindow.playbackSegmentsCache[cacheKey] !== undefined && activePlayersFetching[fetchKey] !== true) {
                    playbackWindow.isSearchingRecordings = isAnyCameraSearching();
                    timeline.segments = rootWindow.playbackSegmentsCache[cacheKey];
                    timeline.requestPaint();
                    fetchMonthAvailability(currentDate.getFullYear(), currentDate.getMonth());
                } else {
                    timeline.segments = rootWindow.playbackSegmentsCache[cacheKey] || [];
                    playbackWindow.isSearchingRecordings = isAnyCameraSearching();
                    timeline.requestPaint();
                    
                    if (rootWindow.playbackSegmentsCache[cacheKey] === undefined && activePlayersFetching[fetchKey] !== true) {
                        searchRecordingsForCamera(data, currentDate);
                    } else {
                        // It is fetching or already cached, fetch month availability
                        fetchMonthAvailability(currentDate.getFullYear(), currentDate.getMonth());
                    }
                }
            } else {
                // Empty slot selected
                playbackWindow.recorderInfo = null;
                playbackWindow.channelId = -1;
                playbackWindow.cameraName = "";
                timeline.segments = [];
                playbackWindow.isSearchingRecordings = isAnyCameraSearching();
                timeline.requestPaint();
            }
        }
    }

    function forEachPlayer(callback) {
        for (var i = 0; i < gridRepeater.count; ++i) {
            var item = gridRepeater.itemAt(i);
            if (item && item.playerInstance) {
                callback(item.playerInstance);
            }
        }
    }

    function getSelectedPlayer() {
        if (selectedPlayerIndex >= 0 && selectedPlayerIndex < gridRepeater.count) {
            var item = gridRepeater.itemAt(selectedPlayerIndex);
            if (item) return item.playerInstance;
        }
        return null;
    }

    function stopAllPlayers() {
        forEachPlayer(function(p) { p.stop(); });
    }

    Connections {
        target: HikvisionISAPI
        function onSearchFinished(recorderIp, channelId, startTime, segments) {
            var targetDate = new Date(startTime);
            targetDate.setDate(targetDate.getDate() + 1);
            var dateKey = getDateKey(targetDate);
            var cacheKey = recorderIp + "_" + channelId + "_" + dateKey;
            var fetchKey = recorderIp + "_" + channelId + "_" + dateKey;
            
            var tempFetching = Object.assign({}, activePlayersFetching);
            delete tempFetching[fetchKey];
            activePlayersFetching = tempFetching;

            // Adjust segments timezone offset to align with local timezone of the client
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

            var tempSegments = Object.assign({}, rootWindow.playbackSegmentsCache);
            tempSegments[cacheKey] = adjustedSegments;
            rootWindow.playbackSegmentsCache = tempSegments;

            if (dateKey === getDateKey(currentDate)) {
                timeline.requestPaint();
                if (playbackWindow.recorderInfo && recorderIp === playbackWindow.recorderInfo.ip && channelId === playbackWindow.channelId) {
                    timeline.segments = adjustedSegments
                }
            }

            playbackWindow.isSearchingRecordings = isAnyCameraSearching();
        }
        function onSearchFailed(recorderIp, channelId, startTime, error) {
            var targetDate = new Date(startTime);
            targetDate.setDate(targetDate.getDate() + 1);
            var dateKey = getDateKey(targetDate);
            var cacheKey = recorderIp + "_" + channelId + "_" + dateKey;
            var fetchKey = recorderIp + "_" + channelId + "_" + dateKey;
            
            var tempFetching = Object.assign({}, activePlayersFetching);
            delete tempFetching[fetchKey];
            activePlayersFetching = tempFetching;

            if (dateKey === getDateKey(currentDate)) {
                timeline.requestPaint();
                if (playbackWindow.recorderInfo && recorderIp === playbackWindow.recorderInfo.ip && channelId === playbackWindow.channelId) {
                    timeline.segments = []
                }
            }

            playbackWindow.isSearchingRecordings = isAnyCameraSearching();
        }
        function onMonthAvailabilityFinished(recorderIp, channelId, year, month, daysWithRecords, success) {
            var key = recorderIp + "_" + channelId + "_" + year + "-" + (month - 1);
            
            var tempFetching = Object.assign({}, monthAvailabilityFetching);
            delete tempFetching[key];
            monthAvailabilityFetching = tempFetching;

            if (success === false) {
                return;
            }

            var tempAvails = Object.assign({}, rootWindow.monthAvailabilitiesCache);
            tempAvails[key] = daysWithRecords;
            rootWindow.monthAvailabilitiesCache = tempAvails;
            
            timeline.requestPaint();

            prefetchActiveCameras();
        }
    }

    Component.onCompleted: {
        // Set default playback start time to 15 minutes before now
        var now = new Date()
        var targetTime = new Date(now.getTime() - 15 * 60 * 1000)
        var dStart = new Date(targetTime)
        dStart.setHours(0, 0, 0, 0)
        currentDate = dStart
        playheadTimeMs = targetTime.getTime()
        
        var viewDurationMs = zoomHours * 3600000
        panOffsetMs = currentPlayheadMs - viewDurationMs / 2
        
        loadRecordersList();
        
        if (recorderInfo) {
            var recName = recorderInfo.name || recorderInfo.ip;
            activePlayersList = [{
                "ip": recorderInfo.ip,
                "port": recorderInfo.port || 8000,
                "username": recorderInfo.username,
                "password": recorderInfo.password,
                "channelId": playbackWindow.channelId,
                "cameraName": playbackWindow.cameraName,
                "recorderName": recName
            }]
            // Single-camera open: force 1×1 layout so the grid button matches reality
            gridLayoutColumns = 1;
            gridLayoutRows = 1;
            
            playbackWindow.isPlaying = true
            
            searchRecordingsForDate(currentDate)
        } else {
            // When opened empty, pad the active players list to grid size with nulls
            resizeActivePlayersList(gridLayoutColumns * gridLayoutRows);
            // Auto-start playing so newly added cameras play instantly
            playbackWindow.isPlaying = true
        }
    }

    onClosing: {
        stopAllPlayers();
        activePlayersList = [];
        selectedPlayerIndex = -1;
        HikvisionISAPI.cancelAllSearches();
        rootWindow.playbackSegmentsCache = {};
        rootWindow.monthAvailabilitiesCache = {};
        // We defer the loader unloading and GC triggering to ensure the close sequence finishes cleanly.
        Qt.callLater(function() {
            if (typeof playbackWindowLoader !== "undefined" && playbackWindowLoader) {
                playbackWindowLoader.active = false;
            }
            if (typeof rootWindow !== "undefined" && rootWindow) {
                rootWindow.triggerGcDeferred();
            }
        });
    }

    Component.onDestruction: {
        activePlayersList = [];
        selectedPlayerIndex = -1;
    }

    DownloadDialog {
        id: downloadDialog
        onDownloadStarted: {
            playbackStoppedForDownload = true;
            forEachPlayer(function(p) { p.stop(); });
            isPlaying = false;
        }
        onClosed: {
            if (downloadDialog.isAnyDownloading()) {
                downloadDialog.stopAllDownloads();
            }
            if (playbackStoppedForDownload) {
                playbackStoppedForDownload = false;
                playAtTime(currentDate, currentPlayheadMs);
            }
        }
    }

    Timer {
        id: playbackTimer
        interval: 1000
        running: playbackWindow.isPlaying
        repeat: true
        onTriggered: {
            if (playbackSpeed > 0) {
                playheadTimeMs += (1000 * playbackSpeed)
            } else {
                playheadTimeMs -= (1000 * Math.abs(playbackSpeed))
            }
            if (currentPlayheadMs >= 86400000) {
                // Next day!
                var dNext = new Date(currentDate.getTime() + 86400000)
                dNext.setHours(0, 0, 0, 0)
                currentDate = dNext
                panOffsetMs -= 86400000
                searchRecordingsForDate(currentDate)
                playAtTime(currentDate, playheadTimeMs - currentDate.getTime())
            } else if (currentPlayheadMs < 0) {
                // Previous day!
                var dPrev = new Date(currentDate.getTime() - 86400000)
                dPrev.setHours(0, 0, 0, 0)
                currentDate = dPrev
                panOffsetMs += 86400000
                searchRecordingsForDate(currentDate)
                playAtTime(currentDate, playheadTimeMs - currentDate.getTime())
            }
            
            // Auto-center timeline on the playhead if it goes out of view during playback (and autoFollow is enabled)
            var viewDurationMs = zoomHours * 3600000
            if (autoFollowEnabled && !mouseArea.isDraggingPlayhead && (currentPlayheadMs < panOffsetMs || currentPlayheadMs > panOffsetMs + viewDurationMs)) {
                panOffsetMs = currentPlayheadMs - viewDurationMs / 2
                searchRecordingsForDate(currentDate)
            }
            
            timeline.requestPaint()
        }
    }

    function fetchMonthAvailabilityForCamera(recInfo, chId, y, m) {
        if (!recInfo) return;
        var ip = recInfo.ip;
        var key = ip + "_" + chId + "_" + y + "-" + m;
        
        if (rootWindow.monthAvailabilitiesCache[key] !== undefined) {
            return;
        }
        
        if (monthAvailabilityFetching[key] === true) {
            return;
        }
        
        var tempFetching = Object.assign({}, monthAvailabilityFetching);
        tempFetching[key] = true;
        monthAvailabilityFetching = tempFetching;
        
        var recorderInfoForCam = {
            "ip": ip,
            "port": recInfo.port || 8000,
            "username": recInfo.username,
            "password": recInfo.password
        };
        
        HikvisionISAPI.searchMonthAvailability(recorderInfoForCam, chId, y, m + 1);
    }

    function continuePrefetchingForCamera(cam) {
        if (!cam) return;
        var now = new Date();
        var currentY = now.getFullYear();
        var currentM = now.getMonth();
        
        // Fetch up to 2 months (current and previous) backwards sequentially
        for (var i = 0; i < 2; i++) {
            var d = new Date(currentY, currentM - i, 1);
            var y = d.getFullYear();
            var m = d.getMonth();
            var key = cam.ip + "_" + cam.channelId + "_" + y + "-" + m;
            
            if (rootWindow.monthAvailabilitiesCache[key] !== undefined) {
                continue;
            }
            
            if (monthAvailabilityFetching[key] === true) {
                return;
            }
            
            fetchMonthAvailabilityForCamera(cam, cam.channelId, y, m);
            return;
        }
    }

    function prefetchActiveCameras() {
        if (selectedPlayerIndex >= 0 && selectedPlayerIndex < activePlayersList.length) {
            var cam = activePlayersList[selectedPlayerIndex];
            if (cam) {
                continuePrefetchingForCamera(cam);
            }
        }
    }

    function clearCacheForCamera(ip, channelId) {
        var prefix = ip + "_" + channelId + "_";
        
        var tempAvails = Object.assign({}, rootWindow.monthAvailabilitiesCache);
        var changedAvails = false;
        for (var key in tempAvails) {
            if (key.indexOf(prefix) === 0) {
                delete tempAvails[key];
                changedAvails = true;
            }
        }
        if (changedAvails) {
            rootWindow.monthAvailabilitiesCache = tempAvails;
        }
        
        var tempSegments = Object.assign({}, rootWindow.playbackSegmentsCache);
        var changedSegments = false;
        for (var key2 in tempSegments) {
            if (key2.indexOf(prefix) === 0) {
                delete tempSegments[key2];
                changedSegments = true;
            }
        }
        if (changedSegments) {
            rootWindow.playbackSegmentsCache = tempSegments;
        }
    }

    function fetchMonthAvailability(y, m) {
        prefetchActiveCameras();
    }

    function searchRecordingsForCamera(cam, date) {
        var dateKey = getDateKey(date);
        var cacheKey = cam.ip + "_" + cam.channelId + "_" + dateKey;
        var fetchKey = cam.ip + "_" + cam.channelId + "_" + dateKey;
        if (activePlayersFetching[fetchKey] === true) {
            return;
        }
        
        var tempFetching = Object.assign({}, activePlayersFetching);
        tempFetching[fetchKey] = true;
        activePlayersFetching = tempFetching;
        
        playbackWindow.isSearchingRecordings = isAnyCameraSearching();
        prefetchActiveCameras();
        
        var monthKey = cam.ip + "_" + cam.channelId + "_" + date.getFullYear() + "-" + date.getMonth();
        var monthAvail = rootWindow.monthAvailabilitiesCache[monthKey];
        if (monthAvail !== undefined) {
            if (monthAvail.indexOf(date.getDate()) === -1) {
                var tempSegments = Object.assign({}, rootWindow.playbackSegmentsCache);
                tempSegments[cacheKey] = [];
                rootWindow.playbackSegmentsCache = tempSegments;
                
                var tempFetching2 = Object.assign({}, activePlayersFetching);
                delete tempFetching2[fetchKey];
                activePlayersFetching = tempFetching2;
                
                playbackWindow.isSearchingRecordings = isAnyCameraSearching();
                timeline.requestPaint();
                return;
            }
        }
        
        var start = new Date(date)
        start.setHours(0,0,0,0)
        start.setDate(start.getDate() - 1)
        
        var end = new Date(date)
        end.setHours(23,59,59,999)
        end.setDate(end.getDate() + 1)
        
        var recorderInfoForCam = {
            "ip": cam.ip,
            "port": cam.port || 8000,
            "username": cam.username,
            "password": cam.password
        };
        HikvisionISAPI.searchRecordings(recorderInfoForCam, cam.channelId, start, end);
    }

    function searchRecordingsForDate(date) {
        var dateKey = getDateKey(date);
        
        if (playbackWindow.recorderInfo) {
            var activeCacheKey = playbackWindow.recorderInfo.ip + "_" + playbackWindow.channelId + "_" + dateKey;
            timeline.segments = rootWindow.playbackSegmentsCache[activeCacheKey] || [];
        } else {
            timeline.segments = [];
        }
        
        var viewDurationMs = zoomHours * 3600000;
        var sodTime = currentDate.getTime();
        
        var startDate = new Date(sodTime + panOffsetMs);
        startDate.setHours(0, 0, 0, 0);
        var endDate = new Date(sodTime + panOffsetMs + viewDurationMs);
        endDate.setHours(0, 0, 0, 0);
        
        var datesToSearch = [];
        var targetD = new Date(date);
        targetD.setHours(0, 0, 0, 0);
        datesToSearch.push(targetD);
        
        for (var d = new Date(startDate); d.getTime() <= endDate.getTime(); d.setDate(d.getDate() + 1)) {
            var exists = false;
            for (var j = 0; j < datesToSearch.length; j++) {
                if (datesToSearch[j].getTime() === d.getTime()) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                datesToSearch.push(new Date(d));
            }
        }
        
        // Ensure all active cameras pre-fetch their availability in the background
        prefetchActiveCameras();
        
        var tempFetching = Object.assign({}, activePlayersFetching);
        var changedFetching = false;
        
        for (var dIdx = 0; dIdx < datesToSearch.length; dIdx++) {
            var currentSearchDate = datesToSearch[dIdx];
            var searchDateKey = getDateKey(currentSearchDate);
            
            for (var i = 0; i < activePlayersList.length; i++) {
                if (i !== selectedPlayerIndex) continue; // Only load day segments for the selected camera!
                var cam = activePlayersList[i];
                if (!cam) continue;
                
                var cacheKey = cam.ip + "_" + cam.channelId + "_" + searchDateKey;
                var fetchKey = cam.ip + "_" + cam.channelId + "_" + searchDateKey;
                
                if (rootWindow.playbackSegmentsCache[cacheKey] !== undefined || tempFetching[fetchKey] === true) {
                    continue;
                }
                
                // Optimize: If month availability is cached and has no records for this day, skip search!
                var monthKey = cam.ip + "_" + cam.channelId + "_" + currentSearchDate.getFullYear() + "-" + currentSearchDate.getMonth();
                var monthAvail = rootWindow.monthAvailabilitiesCache[monthKey];
                if (monthAvail !== undefined) {
                    if (monthAvail.indexOf(currentSearchDate.getDate()) === -1) {
                        var tempSegments = Object.assign({}, rootWindow.playbackSegmentsCache);
                        tempSegments[cacheKey] = [];
                        rootWindow.playbackSegmentsCache = tempSegments;
                        continue;
                    }
                }
                
                tempFetching[fetchKey] = true;
                changedFetching = true;
                
                var start = new Date(currentSearchDate)
                start.setHours(0,0,0,0)
                start.setDate(start.getDate() - 1)
                
                var end = new Date(currentSearchDate)
                end.setHours(23,59,59,999)
                end.setDate(end.getDate() + 1)
                
                var recorderInfoForCam = {
                    "ip": cam.ip,
                    "port": cam.port || 8000,
                    "username": cam.username,
                    "password": cam.password
                };
                HikvisionISAPI.searchRecordings(recorderInfoForCam, cam.channelId, start, end);
            }
        }
        
        if (changedFetching) {
            activePlayersFetching = tempFetching;
            playbackWindow.isSearchingRecordings = isAnyCameraSearching();
        }
        
        if (playbackWindow.recorderInfo) {
            var activeCacheKey = playbackWindow.recorderInfo.ip + "_" + playbackWindow.channelId + "_" + dateKey;
            timeline.segments = rootWindow.playbackSegmentsCache[activeCacheKey] || [];
        }
    }

    function playAtTime(date, msSinceMidnight) {
        var d = new Date(date)
        d.setHours(0, 0, 0, 0)
        var targetTime = new Date(d.getTime() + msSinceMidnight)
        
        forEachPlayer(function(p) {
            p.playAtTime(targetTime)
        });
        isPlaying = true
        playheadTimeMs = targetTime.getTime()
        timeline.requestPaint()
    }

    function jumpTime(offsetMs) {
        playheadTimeMs += offsetMs
        var d = new Date(playheadTimeMs)
        d.setHours(0, 0, 0, 0)
        currentDate = d
        playAtTime(currentDate, playheadTimeMs - d.getTime())
    }

    function normalizePanOffset() {
        var changed = false
        while (panOffsetMs < -43200000) {
            var dPrev = new Date(currentDate.getTime() - 86400000)
            dPrev.setHours(0, 0, 0, 0)
            currentDate = dPrev
            panOffsetMs += 86400000
            changed = true
        }
        while (panOffsetMs > 86400000 + 43200000) {
            var dNext = new Date(currentDate.getTime() + 86400000)
            dNext.setHours(0, 0, 0, 0)
            currentDate = dNext
            panOffsetMs -= 86400000
            changed = true
        }
        if (changed) {
            searchRecordingsForDate(currentDate)
        }
    }

    function togglePlayPause() {
        if (isPlaying) {
            forEachPlayer(function(p) { p.pause(); });
            isPlaying = false
        } else {
            var selPlayer = getSelectedPlayer();
            if (selPlayer && selPlayer.hasActiveStream() && selPlayer.hasReceivedFrames()) {
                forEachPlayer(function(p) { p.resume(); });
                isPlaying = true
            } else {
                playAtTime(currentDate, currentPlayheadMs)
            }
        }
    }

    function zoomToLast(hours) {
        var now = new Date()
        var d = new Date(now)
        d.setHours(0, 0, 0, 0)
        currentDate = d
        
        var msSinceMidnight = now.getHours() * 3600000 + now.getMinutes() * 60000 + now.getSeconds() * 1000
        zoomHours = hours
        var viewDurationMs = zoomHours * 3600000
        panOffsetMs = msSinceMidnight - viewDurationMs
        
        searchRecordingsForDate(currentDate)
        playAtTime(currentDate, msSinceMidnight)
    }

    Popup {
        id: calendarPopup
        width: 620
        height: 410
        background: Rectangle { 
            color: "#151d24"
            border.color: "#00f5d4"
            border.width: 1
            radius: 6
        }
        
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 100; easing.type: Easing.InQuad }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 100; easing.type: Easing.InQuad }
        }
        
        property int viewYear: currentDate.getFullYear()
        property int viewMonth: currentDate.getMonth()
        
        readonly property int rightYear: viewYear
        readonly property int rightMonth: viewMonth
        readonly property int leftYear: rightMonth === 0 ? rightYear - 1 : rightYear
        readonly property int leftMonth: rightMonth === 0 ? 11 : rightMonth - 1

        function getDaysModel(year, month) {
            var firstDay = new Date(year, month, 1)
            var lastDay = new Date(year, month + 1, 0)
            var startOffset = firstDay.getDay() === 0 ? 6 : firstDay.getDay() - 1 // 0 = Mon
            var totalDays = lastDay.getDate()
            
            var cells = []
            for (var i = 0; i < startOffset; i++) cells.push(0)
            for (var d = 1; d <= totalDays; d++) cells.push(d)
            while (cells.length % 7 !== 0) cells.push(0)
            return cells
        }

        function updateDaysModel() {
            leftDaysRepeater.model = getDaysModel(leftYear, leftMonth)
            rightDaysRepeater.model = getDaysModel(rightYear, rightMonth)
        }

        onOpened: {
            viewYear = currentDate.getFullYear()
            viewMonth = currentDate.getMonth()
            updateDaysModel()
            playbackWindow.fetchMonthAvailabilityForCamera(playbackWindow.recorderInfo, playbackWindow.channelId, leftYear, leftMonth)
            playbackWindow.fetchMonthAvailabilityForCamera(playbackWindow.recorderInfo, playbackWindow.channelId, rightYear, rightMonth)
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10
            
            RowLayout {
                Layout.fillWidth: true
                
                CctvButton {
                    text: qsTr("< Poprzedni")
                    iconSource: ""
                    onClicked: {
                        if (calendarPopup.viewMonth === 0) { 
                            calendarPopup.viewMonth = 11; 
                            calendarPopup.viewYear--; 
                        } else { 
                            calendarPopup.viewMonth--; 
                        }
                        calendarPopup.updateDaysModel()
                        playbackWindow.fetchMonthAvailabilityForCamera(playbackWindow.recorderInfo, playbackWindow.channelId, calendarPopup.leftYear, calendarPopup.leftMonth)
                        playbackWindow.fetchMonthAvailabilityForCamera(playbackWindow.recorderInfo, playbackWindow.channelId, calendarPopup.rightYear, calendarPopup.rightMonth)
                    }
                }
                
                Text {
                    text: qsTr("Wybierz datę archiwalną")
                    color: "#8898a6"
                    font.bold: true
                    font.pixelSize: 15
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
                
                CctvButton {
                    text: qsTr("Następny >")
                    iconSource: ""
                    onClicked: {
                        if (calendarPopup.viewMonth === 11) { 
                            calendarPopup.viewMonth = 0; 
                            calendarPopup.viewYear++; 
                        } else { 
                            calendarPopup.viewMonth++; 
                        }
                        calendarPopup.updateDaysModel()
                        playbackWindow.fetchMonthAvailabilityForCamera(playbackWindow.recorderInfo, playbackWindow.channelId, calendarPopup.leftYear, calendarPopup.leftMonth)
                        playbackWindow.fetchMonthAvailabilityForCamera(playbackWindow.recorderInfo, playbackWindow.channelId, calendarPopup.rightYear, calendarPopup.rightMonth)
                    }
                }
            }
            
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Text {
                        text: playbackWindow.monthNames[calendarPopup.leftMonth] + " " + calendarPopup.leftYear
                        color: "white"
                        font.bold: true
                        font.pixelSize: 16
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    
                    GridLayout {
                        columns: 7
                        rowSpacing: 4
                        columnSpacing: 4
                        Layout.alignment: Qt.AlignHCenter
                        
                        Repeater {
                            model: [qsTr("Mo"), qsTr("Tu"), qsTr("We"), qsTr("Th"), qsTr("Fr"), qsTr("Sa"), qsTr("Su")]
                            Text { 
                                text: modelData; color: "#8898a6"; font.bold: true; 
                                horizontalAlignment: Text.AlignHCenter; 
                                Layout.preferredWidth: 34
                            }
                        }
                        
                        Repeater {
                            id: leftDaysRepeater
                            model: []
                            
                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                color: {
                                    if (modelData === 0) return "transparent"
                                    var isCurrent = (calendarPopup.leftYear === currentDate.getFullYear() && calendarPopup.leftMonth === currentDate.getMonth() && modelData === currentDate.getDate())
                                    if (isCurrent) return "#33ffffff"
                                    return "transparent"
                                }
                                border.color: {
                                    if (modelData === 0) return "transparent"
                                    var key = (playbackWindow.recorderInfo ? playbackWindow.recorderInfo.ip : "") + "_" + playbackWindow.channelId + "_" + calendarPopup.leftYear + "-" + calendarPopup.leftMonth;
                                    var monthAvail = rootWindow.monthAvailabilitiesCache[key] || [];
                                    var hasRecords = (monthAvail.indexOf(modelData) !== -1);
                                    if (hasRecords) return "#00f5d4"
                                    return "transparent"
                                }
                                border.width: 1
                                radius: 4
                                
                                Text {
                                    text: modelData > 0 ? modelData : ""
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.bold: {
                                        if (modelData === 0) return false;
                                        var key = (playbackWindow.recorderInfo ? playbackWindow.recorderInfo.ip : "") + "_" + playbackWindow.channelId + "_" + calendarPopup.leftYear + "-" + calendarPopup.leftMonth;
                                        var monthAvail = rootWindow.monthAvailabilitiesCache[key] || [];
                                        return (monthAvail.indexOf(modelData) !== -1);
                                    }
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData > 0
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var d = new Date(calendarPopup.leftYear, calendarPopup.leftMonth, modelData)
                                        d.setHours(0, 0, 0, 0)
                                        var timeOfDay = currentPlayheadMs
                                        currentDate = d
                                        searchRecordingsForDate(currentDate)
                                        playAtTime(currentDate, timeOfDay)
                                        calendarPopup.close()
                                    }
                                }
                            }
                        }
                    }
                }
                
                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    color: "#445566"
                }
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Text {
                        text: playbackWindow.monthNames[calendarPopup.rightMonth] + " " + calendarPopup.rightYear
                        color: "white"
                        font.bold: true
                        font.pixelSize: 16
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    
                    GridLayout {
                        columns: 7
                        rowSpacing: 4
                        columnSpacing: 4
                        Layout.alignment: Qt.AlignHCenter
                        
                        Repeater {
                            model: [qsTr("Mo"), qsTr("Tu"), qsTr("We"), qsTr("Th"), qsTr("Fr"), qsTr("Sa"), qsTr("Su")]
                            Text { 
                                text: modelData; color: "#8898a6"; font.bold: true; 
                                horizontalAlignment: Text.AlignHCenter; 
                                Layout.preferredWidth: 34
                            }
                        }
                        
                        Repeater {
                            id: rightDaysRepeater
                            model: []
                            
                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                color: {
                                    if (modelData === 0) return "transparent"
                                    var isCurrent = (calendarPopup.rightYear === currentDate.getFullYear() && calendarPopup.rightMonth === currentDate.getMonth() && modelData === currentDate.getDate())
                                    if (isCurrent) return "#33ffffff"
                                    return "transparent"
                                }
                                border.color: {
                                    if (modelData === 0) return "transparent"
                                    var key = (playbackWindow.recorderInfo ? playbackWindow.recorderInfo.ip : "") + "_" + playbackWindow.channelId + "_" + calendarPopup.rightYear + "-" + calendarPopup.rightMonth;
                                    var monthAvail = rootWindow.monthAvailabilitiesCache[key] || [];
                                    var hasRecords = (monthAvail.indexOf(modelData) !== -1);
                                    if (hasRecords) return "#00f5d4"
                                    return "transparent"
                                }
                                border.width: 1
                                radius: 4
                                
                                Text {
                                    text: modelData > 0 ? modelData : ""
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.bold: {
                                        if (modelData === 0) return false;
                                        var key = (playbackWindow.recorderInfo ? playbackWindow.recorderInfo.ip : "") + "_" + playbackWindow.channelId + "_" + calendarPopup.rightYear + "-" + calendarPopup.rightMonth;
                                        var monthAvail = rootWindow.monthAvailabilitiesCache[key] || [];
                                        return (monthAvail.indexOf(modelData) !== -1);
                                    }
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData > 0
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var d = new Date(calendarPopup.rightYear, calendarPopup.rightMonth, modelData)
                                        d.setHours(0, 0, 0, 0)
                                        var timeOfDay = currentPlayheadMs
                                        currentDate = d
                                        searchRecordingsForDate(currentDate)
                                        playAtTime(currentDate, timeOfDay)
                                        calendarPopup.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Item {
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignHCenter
                
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: playbackWindow.isSearchingMonth
                    
                    Text {
                        text: "⚡"
                        color: "#00f5d4"
                        font.pixelSize: 11
                    }
                    Text {
                        text: qsTr("Pobieranie dostępności...")
                        color: "#8898a6"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.topMargin: 0
        spacing: 0

        // Left Sidebar: Camera List
        Rectangle {
            id: sidebarPanel
            Layout.fillHeight: true
            width: sidebarVisible ? 280 : 0
            visible: sidebarVisible
            color: "#0b0f13"
            
            // Separation line
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: "#1c242c"
            }
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                anchors.topMargin: 44
                spacing: 8
                
                Text {
                    text: qsTr("Kamery")
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                    Layout.fillWidth: true
                }
                
                
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    spacing: 8

                    TextField {
                        id: cameraSearchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        placeholderText: qsTr("Szukaj kamery...")
                        selectByMouse: true
                        color: "white"
                        font.pixelSize: 11
                        
                        background: Rectangle {
                            color: "#0f151b"
                            radius: 4
                            border.color: cameraSearchField.activeFocus ? "#00f5d4" : "#2a3540"
                            border.width: 1
                        }
                    }

                    Button {
                        id: clearSearchButton
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter
                        enabled: cameraSearchField.text.trim() !== ""

                        contentItem: Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            sourceSize.width: 14
                            sourceSize.height: 14
                            fillMode: Image.PreserveAspectFit
                            source: {
                                var colorStr = !clearSearchButton.enabled ? "%23445464" : (clearSearchButton.hovered ? "%23ff4d4d" : "%238898a6");
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><line x1='18' y1='6' x2='6' y2='18'></line><line x1='6' y1='6' x2='18' y2='18'></line></svg>";
                            }
                        }

                        background: Rectangle {
                            color: !clearSearchButton.enabled ? "transparent" : (clearSearchButton.pressed ? "#cc121214" : (clearSearchButton.hovered ? "#20ff0000" : "#1c242c"))
                            radius: 15
                            border.color: !clearSearchButton.enabled ? "#1c242c" : (clearSearchButton.hovered ? "#ff4d4d" : "#2a3540")
                            border.width: 1
                        }

                        onClicked: {
                            cameraSearchField.text = "";
                            cameraSearchField.forceActiveFocus();
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: clearSearchButton.hovered && clearSearchButton.enabled
                        ToolTip.text: qsTr("Wyczyść wyszukiwanie")
                    }
                }
                
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    ColumnLayout {
                        width: parent.width - 15
                        spacing: 12
                        
                        Repeater {
                            model: recordersList
                            
                            delegate: ColumnLayout {
                                id: recorderGroup
                                Layout.fillWidth: true
                                spacing: 4
                                visible: hasMatchingCameras(recorderObj, cameraSearchField.text.trim().toLowerCase())
                                
                                property var recorderObj: modelData
                                property bool userExpanded: isRecorderInGrid(recorderObj.ip)
                                property bool userCollapsedDuringSearch: false
                                
                                property bool expanded: {
                                    var query = cameraSearchField.text.trim().toLowerCase();
                                    if (query !== "") {
                                        return hasMatchingCameras(recorderObj, query) && !userCollapsedDuringSearch;
                                    }
                                    return userExpanded;
                                }
                                
                                Connections {
                                    target: cameraSearchField
                                    function onTextChanged() {
                                        if (cameraSearchField.text.trim() === "") {
                                            recorderGroup.userCollapsedDuringSearch = false;
                                        }
                                    }
                                }
                                
                                // Recorder Section Header with Click to Expand/Collapse
                                Rectangle {
                                    id: headerRect
                                    Layout.fillWidth: true
                                    height: 28
                                    color: headerMouseArea.containsMouse ? "#202c39" : "#141c24"
                                    radius: 4
                                    
                                    Text {
                                        text: recorderGroup.expanded ? "▼" : "▶"
                                        color: headerMouseArea.containsMouse ? "#00f5d4" : "#8898a6"
                                        font.pixelSize: 10
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    Text {
                                        text: (recorderObj.name ? recorderObj.name : recorderObj.ip) + " (" + recorderObj.ip + ")"
                                        color: headerMouseArea.containsMouse ? "#ffffff" : "#e2e8f0"
                                        font.bold: true
                                        font.pixelSize: 11
                                        anchors.left: parent.left
                                        anchors.leftMargin: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    MouseArea {
                                        id: headerMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var query = cameraSearchField.text.trim().toLowerCase();
                                            if (query !== "") {
                                                recorderGroup.userCollapsedDuringSearch = !recorderGroup.userCollapsedDuringSearch;
                                            } else {
                                                recorderGroup.userExpanded = !recorderGroup.userExpanded;
                                            }
                                        }
                                    }
                                }
                                
                                // Camera items for this recorder
                                Repeater {
                                    model: recorderGroup.recorderObj.cameras || []
                                    
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        visible: recorderGroup.expanded && cameraMatches(modelData, cameraSearchField.text.trim().toLowerCase(), recorderGroup.recorderObj)
                                        height: visible ? 62 : 0
                                        color: itemMouseArea.containsMouse ? "#1c242c" : "transparent"
                                        radius: 4
                                        
                                        property var parentRecorder: recorderGroup.recorderObj
                                        
                                        MouseArea {
                                            id: itemMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.ArrowCursor
                                        }
                                        
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 8
                                            
                                            // Thumbnail wrapper
                                            Rectangle {
                                                width: 96
                                                height: 54
                                                color: "#05080c"
                                                radius: 3
                                                clip: true
                                                
                                                Image {
                                                    anchors.fill: parent
                                                    source: "image://thumbnail/" + parentRecorder.ip + "_" + modelData.channelId
                                                    fillMode: Image.PreserveAspectCrop
                                                    opacity: status === Image.Ready ? 1.0 : 0.2
                                                }
                                                
                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: "#3300f5d4"
                                                    visible: isCameraInGrid(parentRecorder.ip, modelData.channelId)
                                                    border.color: "#00f5d4"
                                                    border.width: 1
                                                    radius: 3
                                                }
                                            }
                                            
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                                                   Text {
                                                     text: modelData.customName || modelData.name || ("Kamera " + modelData.channelId)
                                                     color: isCameraInGrid(parentRecorder.ip, modelData.channelId) ? "#00f5d4" : "white"
                                                     font.pixelSize: 11
                                                     font.bold: isCameraInGrid(parentRecorder.ip, modelData.channelId)
                                                     wrapMode: Text.Wrap
                                                     maximumLineCount: 2
                                                     elide: Text.ElideRight
                                                     Layout.fillWidth: true
                                                 }
                                                 
                                                 Text {
                                                     text: "CH " + (modelData.channelId < 10 ? "0" + modelData.channelId : modelData.channelId)
                                                     color: "#8898a6"
                                                     font.pixelSize: 9
                                                 }
                                             }

                                             // Dedicated "+" button to add camera to selected viewport in the grid
                                             Rectangle {
                                                 id: addButton
                                                 width: 24
                                                 height: 24
                                                 radius: 12
                                                 color: addButtonMouseArea.pressed ? "#00806f" : (addButtonMouseArea.containsMouse ? "#00bfa5" : "#00f5d4")
                                                 border.color: color
                                                 border.width: 1
                                                 Layout.alignment: Qt.AlignVCenter
                                                 Layout.rightMargin: 6

                                                 Text {
                                                     text: "+"
                                                     color: "#121214"
                                                     font.pixelSize: 14
                                                     font.bold: true
                                                     anchors.centerIn: parent
                                                     anchors.verticalCenterOffset: -1 // Visually center the plus character
                                                 }

                                                 MouseArea {
                                                     id: addButtonMouseArea
                                                     anchors.fill: parent
                                                     hoverEnabled: true
                                                     cursorShape: Qt.PointingHandCursor
                                                     onClicked: {
                                                         addCameraToGrid(parentRecorder, modelData);
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

        // Right Area: Grid of Players & Controls
        Item {
            id: rightArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Video Grid Area
            Rectangle {
                id: videoGridWrapper
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: (isBottomPanelFloating || playbackWindow.hideTimelineOption) ? parent.bottom : bottomPanel.top
                color: "black"
                
                Item {
                    id: videoContainer
                    anchors.fill: parent
                    clip: true

                    GridLayout {
                        id: playerGrid
                        anchors.fill: parent
                        anchors.margins: 4
                        columns: gridLayoutColumns
                        rows: gridLayoutRows
                        rowSpacing: 4
                        columnSpacing: 4
                        
                        Repeater {
                            id: gridRepeater
                            model: activePlayersList
                            
                            delegate: Rectangle {
                                id: tileContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: "black"
                                border.color: (index === selectedPlayerIndex) ? "#00f5d4" : "#1c242c"
                                border.width: 1
                                z: fullScreen ? 100 : 1
                                
                                property alias playerInstance: playerItem
                                property bool isSelected: index === selectedPlayerIndex
                                
                                property bool isOneToOne: false
                                property real oneToOneX: 0
                                property real oneToOneY: 0
                                property bool isZoomed: false
                                property bool isZoomSelectionMode: false
                                property real zoomX: 0
                                property real zoomY: 0
                                property real zoomWidth: 1.0
                                property real zoomHeight: 1.0
                                property bool fullScreen: index === fullScreenPlayerIndex && modelData !== null

                                onIsOneToOneChanged: {
                                    if (isOneToOne) {
                                        var videoW = (playerItem && playerItem.videoWidth > 0) ? playerItem.videoWidth : videoWrapper.width;
                                        var videoH = (playerItem && playerItem.videoHeight > 0) ? playerItem.videoHeight : videoWrapper.height;
                                        oneToOneX = Math.min(0, (videoWrapper.width - videoW) / 2);
                                        oneToOneY = Math.min(0, (videoWrapper.height - videoH) / 2);
                                    } else {
                                        oneToOneX = 0;
                                        oneToOneY = 0;
                                    }
                                }

                                Item {
                                    id: tileContent
                                    width: parent.width
                                    height: parent.height

                                    states: [
                                        State {
                                            name: "fullScreen"
                                            when: tileContainer.fullScreen

                                            PropertyChanges {
                                                target: tileContent
                                                x: -tileContainer.x
                                                y: -tileContainer.y
                                                width: playerGrid.width
                                                height: playerGrid.height
                                                z: 100
                                            }
                                        }
                                    ]

                                    transitions: [
                                        Transition {
                                            ParallelAnimation {
                                                PropertyAnimation {
                                                    properties: "x, y, width, height"
                                                    easing.type: Easing.OutQuad
                                                    duration: 200
                                                }
                                            }
                                        }
                                    ]
                                
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !tileContainer.isZoomSelectionMode
                                    onClicked: {
                                        selectedPlayerIndex = index;
                                    }
                                    onDoubleClicked: {
                                        selectedPlayerIndex = index;
                                        if (modelData !== null) {
                                            if (fullScreenPlayerIndex === index) {
                                                fullScreenPlayerIndex = -1;
                                            } else {
                                                fullScreenPlayerIndex = index;
                                            }
                                        }
                                    }
                                }
                                
                                Item {
                                    id: videoWrapper
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    clip: true
                                    visible: modelData !== null
                                    
                                    HikvisionArchivePlayer {
                                        id: playerItem
                                        x: tileContainer.isOneToOne ? tileContainer.oneToOneX : (tileContainer.isZoomed ? -tileContainer.zoomX * width : 0)
                                        y: tileContainer.isOneToOne ? tileContainer.oneToOneY : (tileContainer.isZoomed ? -tileContainer.zoomY * height : 0)
                                        width: tileContainer.isOneToOne ? ((playerItem.videoWidth > 0) ? playerItem.videoWidth : videoWrapper.width) : (videoWrapper.width / Math.max(0.001, tileContainer.zoomWidth))
                                        height: tileContainer.isOneToOne ? ((playerItem.videoHeight > 0) ? playerItem.videoHeight : videoWrapper.height) : (videoWrapper.height / Math.max(0.001, tileContainer.zoomHeight))
                                        recorderIp: modelData ? modelData.ip : ""
                                        username: modelData ? modelData.username : ""
                                        password: modelData ? modelData.password : ""
                                        channelId: modelData ? modelData.channelId : 1
                                        port: modelData ? (modelData.port || 8000) : 8000
                                        
                                        property string lastPlayedKey: ""
                                        
                                        function checkAndPlay() {
                                            if (!modelData || recorderIp === "" || username === "" || password === "") {
                                                return;
                                            }
                                            var currentKey = recorderIp + ":" + port + ":" + channelId;
                                            if (lastPlayedKey === currentKey) {
                                                return;
                                            }
                                            lastPlayedKey = currentKey;
                                            
                                            var targetTime = new Date(playheadTimeMs)
                                            playerItem.playAtTime(targetTime)
                                            playerItem.setPlaybackSpeed(playbackSpeed)
                                        }
                                        
                                        onRecorderIpChanged: Qt.callLater(checkAndPlay)
                                        onUsernameChanged: Qt.callLater(checkAndPlay)
                                        onPasswordChanged: Qt.callLater(checkAndPlay)
                                        onPortChanged: Qt.callLater(checkAndPlay)
                                        onChannelIdChanged: Qt.callLater(checkAndPlay)
                                        
                                        onVideoWidthChanged: {
                                            if (tileContainer.isOneToOne) {
                                                tileContainer.oneToOneX = Math.min(0, (videoWrapper.width - playerItem.videoWidth) / 2);
                                            }
                                        }
                                        onVideoHeightChanged: {
                                            if (tileContainer.isOneToOne) {
                                                tileContainer.oneToOneY = Math.min(0, (videoWrapper.height - playerItem.videoHeight) / 2);
                                            }
                                        }
                                        
                                        Component.onCompleted: {
                                            Qt.callLater(checkAndPlay);
                                        }
                                        
                                        onPlayingChanged: {
                                            if (isSelected) {
                                                playbackWindow.isPlaying = playerItem.isPlaying
                                            }
                                        }
                                    }

                                    // Zoom MouseArea
                                    MouseArea {
                                        id: zoomMouseArea
                                        anchors.fill: parent
                                        enabled: tileContainer.isZoomSelectionMode
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

                                                if (w > 10 && h > 10) {
                                                    tileContainer.zoomX = x1 / parent.width;
                                                    tileContainer.zoomY = y1 / parent.height;
                                                    tileContainer.zoomWidth = w / parent.width;
                                                    tileContainer.zoomHeight = h / parent.height;
                                                    tileContainer.isZoomed = true;
                                                }
                                                tileContainer.isZoomSelectionMode = false;
                                            }
                                        }
                                    }

                                    // Selection rectangle
                                    Rectangle {
                                        id: selectionRect
                                        visible: zoomMouseArea.isDragging
                                        x: Math.min(zoomMouseArea.startX, zoomMouseArea.currentX)
                                        y: Math.min(zoomMouseArea.startY, zoomMouseArea.currentY)
                                        width: Math.abs(zoomMouseArea.startX - zoomMouseArea.currentX)
                                        height: Math.abs(zoomMouseArea.startY - zoomMouseArea.currentY)
                                        color: "#3300f5d4"
                                        border.color: "#00f5d4"
                                        border.width: 1
                                    }

                                    // Middle-drag MouseArea for panning in 1:1 mode
                                    MouseArea {
                                        id: middleDragMouseArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.MiddleButton
                                        enabled: tileContainer.isOneToOne
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

                                                var videoW = playerItem.videoWidth > 0 ? playerItem.videoWidth : videoWrapper.width;
                                                var videoH = playerItem.videoHeight > 0 ? playerItem.videoHeight : videoWrapper.height;

                                                tileContainer.oneToOneX = Math.min(0, Math.max(videoWrapper.width - videoW, tileContainer.oneToOneX + dx));
                                                tileContainer.oneToOneY = Math.min(0, Math.max(videoWrapper.height - videoH, tileContainer.oneToOneY + dy));

                                                lastX = mouse.x;
                                                lastY = mouse.y;
                                            }
                                        }
                                    }

                                    Item {
                                        id: playerHoverArea
                                        property bool isHovered: false
                                        function updateHoverState() {
                                            isHovered = playerHoverAreaMouseArea.containsMouse ||
                                                        snapshotMouseAreaBtn.containsMouse ||
                                                        oneToOneMouseAreaBtn.containsMouse ||
                                                        zoomMouseAreaBtn.containsMouse ||
                                                        fullScreenMouseAreaBtn.containsMouse;
                                        }
                                        Component.onCompleted: updateHoverState()
                                        Connections {
                                            target: playerHoverAreaMouseArea
                                            function onContainsMouseChanged() { playerHoverArea.updateHoverState() }
                                        }
                                        Connections {
                                            target: snapshotMouseAreaBtn
                                            function onContainsMouseChanged() { playerHoverArea.updateHoverState() }
                                        }
                                        Connections {
                                            target: oneToOneMouseAreaBtn
                                            function onContainsMouseChanged() { playerHoverArea.updateHoverState() }
                                        }
                                        Connections {
                                            target: zoomMouseAreaBtn
                                            function onContainsMouseChanged() { playerHoverArea.updateHoverState() }
                                        }
                                        Connections {
                                            target: fullScreenMouseAreaBtn
                                            function onContainsMouseChanged() { playerHoverArea.updateHoverState() }
                                        }
                                        Connections {
                                            target: tileContainer
                                            function onVisibleChanged() { playerHoverArea.updateHoverState() }
                                        }
                                    }

                                    MouseArea {
                                        id: playerHoverAreaMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }

                                    // Controls overlay on the bottom right
                                    Row {
                                        anchors {
                                             right: parent.right
                                             bottom: parent.bottom
                                             margins: 6
                                             bottomMargin: (tileContainer.fullScreen && !playbackWindow.hideTimelineOption) ? (bottomPanel.height + 6) : 6
                                         }
                                        spacing: 6
                                        z: 10
                                        visible: (modelData !== null) && (!rootWindow.viewSettings.hoverControlIcons || playerHoverArea.isHovered)

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
                                                onClicked: {
                                                    var d = new Date();
                                                    var dateStr = Qt.formatDateTime(d, "yyyy-MM-dd_HH-mm-ss");
                                                    var nativeWidth = playerItem.videoWidth > 0 ? playerItem.videoWidth : 1920;
                                                    var nativeHeight = playerItem.videoHeight > 0 ? playerItem.videoHeight : 1080;

                                                    var rawCamName = modelData ? (modelData.cameraName + "_CH" + modelData.channelId) : "Camera";
                                                    rawCamName = rawCamName.replace(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/g, "");
                                                    rawCamName = rawCamName.replace(/([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}/g, "");
                                                    rawCamName = rawCamName.trim().replace(/^[_-\s]+|[_-\s]+$/g, "");
                                                    var camName = rawCamName.replace(/ /g, "_").replace(/[^a-zA-Z0-9_\-\.]/g, "");

                                                    var path = "";
                                                    if (typeof rootWindow !== "undefined" && rootWindow.generalSettings && rootWindow.generalSettings.snapshotPath !== "") {
                                                        path = rootWindow.generalSettings.snapshotPath;
                                                    } else {
                                                        path = Platform.StandardPaths.writableLocation(Platform.StandardPaths.PicturesLocation).toString();
                                                        if (path.indexOf("file://") === 0) path = path.substring(7);
                                                        path = path + "/CCTV";
                                                    }
                                                    Context.mkpath(path);
                                                    path = path + "/" + camName + "_ARCHIVE_" + dateStr + ".jpg";

                                                    snapshotBadge.isSavingSnapshot = true;
                                                    snapshotBadgeTimer.restart();

                                                    var saved = playerItem.saveCurrentFrame(path);
                                                    if (saved) {
                                                        console.log("Saved full frame snapshot directly to", path);
                                                    } else {
                                                        console.log("Failed saving frame directly, falling back to grabToImage");
                                                        playerItem.grabToImage(function(result) {
                                                            result.saveToFile(path);
                                                            console.log("Saved snapshot (viewport fallback) to", path);
                                                        }, Qt.size(nativeWidth, nativeHeight));
                                                    }
                                                }
                                            }

                                            ToolTip.delay: 500
                                            ToolTip.timeout: 5000
                                            ToolTip.visible: snapshotMouseAreaBtn.containsMouse
                                            ToolTip.text: qsTr("Wykonaj stopklatkę w pełnej rozdzielczości")
                                        }

                                        Control {
                                            id: oneToOneBadge
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 5

                                            background: Rectangle {
                                                radius: 12
                                                color: tileContainer.isOneToOne ?
                                                    (oneToOneMouseAreaBtn.pressed ? "#4400f5d4" : (oneToOneMouseAreaBtn.containsMouse ? "#3300f5d4" : "#2200f5d4")) :
                                                    (oneToOneMouseAreaBtn.pressed ? "#4a5560" : (oneToOneMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214"))
                                                border.color: tileContainer.isOneToOne ?
                                                    "#cc00f5d4" :
                                                    ((oneToOneMouseAreaBtn.containsMouse || oneToOneMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540")
                                                border.width: 1
                                            }

                                            contentItem: Image {
                                                sourceSize: Qt.size(32, 32)
                                                fillMode: Image.PreserveAspectFit
                                                source: (tileContainer.isOneToOne || oneToOneMouseAreaBtn.containsMouse) ?
                                                    "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M6 8.5L8 7v10M16 8.5L18 7v10'></path><circle cx='12' cy='10' r='1' fill='%2300f5d4' stroke='none'></circle><circle cx='12' cy='14' r='1' fill='%2300f5d4' stroke='none'></circle></svg>" :
                                                    "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M6 8.5L8 7v10M16 8.5L18 7v10'></path><circle cx='12' cy='10' r='1' fill='%23ffffff' stroke='none'></circle><circle cx='12' cy='14' r='1' fill='%23ffffff' stroke='none'></circle></svg>"
                                            }

                                            MouseArea {
                                                id: oneToOneMouseAreaBtn
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    tileContainer.isOneToOne = !tileContainer.isOneToOne;
                                                }
                                            }

                                            ToolTip.delay: 500
                                            ToolTip.timeout: 5000
                                            ToolTip.visible: oneToOneMouseAreaBtn.containsMouse
                                            ToolTip.text: tileContainer.isOneToOne ? qsTr("Wyłącz tryb 1:1") : qsTr("Włącz tryb 1:1 (piksel w piksel)")
                                        }

                                        Control {
                                            id: zoomBadge
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 5

                                            background: Rectangle {
                                                radius: 12
                                                color: tileContainer.isZoomed ?
                                                    (zoomMouseAreaBtn.pressed ? "#44ff3333" : (zoomMouseAreaBtn.containsMouse ? "#33ff3333" : "#22121214")) :
                                                    (tileContainer.isZoomSelectionMode ?
                                                        (zoomMouseAreaBtn.pressed ? "#4400f5d4" : (zoomMouseAreaBtn.containsMouse ? "#3300f5d4" : "#2200f5d4")) :
                                                        (zoomMouseAreaBtn.pressed ? "#4a5560" : (zoomMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214"))
                                                    )
                                                border.color: tileContainer.isZoomed ?
                                                    (zoomMouseAreaBtn.containsMouse ? "#ccff3333" : "#80ff3333") :
                                                    (tileContainer.isZoomSelectionMode ?
                                                        "#cc00f5d4" :
                                                        ((zoomMouseAreaBtn.containsMouse || zoomMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540")
                                                    )
                                                border.width: 1
                                            }

                                            contentItem: Image {
                                                sourceSize: Qt.size(32, 32)
                                                fillMode: Image.PreserveAspectFit
                                                source: tileContainer.isZoomed ?
                                                    "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ff3333' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='8'></circle><line x1='21' y1='21' x2='16.65' y2='16.65'></line><line x1='8' y1='11' x2='14' y2='11'></line></svg>" :
                                                    ((tileContainer.isZoomSelectionMode || zoomMouseAreaBtn.containsMouse) ?
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
                                                    if (tileContainer.isZoomed) {
                                                        tileContainer.isZoomed = false;
                                                        tileContainer.zoomX = 0;
                                                        tileContainer.zoomY = 0;
                                                        tileContainer.zoomWidth = 1.0;
                                                        tileContainer.zoomHeight = 1.0;
                                                        tileContainer.isZoomSelectionMode = false;
                                                    } else {
                                                        tileContainer.isZoomSelectionMode = !tileContainer.isZoomSelectionMode;
                                                    }
                                                }
                                            }

                                            ToolTip.delay: 500
                                            ToolTip.timeout: 5000
                                            ToolTip.visible: zoomMouseAreaBtn.containsMouse
                                            ToolTip.text: tileContainer.isZoomed ? qsTr("Reset Zoom") : (tileContainer.isZoomSelectionMode ? qsTr("Zaznacz obszar żeby przybliżyć") : qsTr("Wybierz obszar do zbliżenia"))
                                        }

                                        Control {
                                            id: fullScreenBadge
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 5

                                            background: Rectangle {
                                                radius: 12
                                                color: tileContainer.fullScreen ?
                                                    (fullScreenMouseAreaBtn.pressed ? "#4400f5d4" : (fullScreenMouseAreaBtn.containsMouse ? "#3300f5d4" : "#2200f5d4")) :
                                                    (fullScreenMouseAreaBtn.pressed ? "#4a5560" : (fullScreenMouseAreaBtn.containsMouse ? "#3a4550" : "#cc121214"))
                                                border.color: tileContainer.fullScreen ?
                                                    "#cc00f5d4" :
                                                    ((fullScreenMouseAreaBtn.containsMouse || fullScreenMouseAreaBtn.pressed) ? "#cc8898a6" : "#802a3540")
                                                border.width: 1
                                            }

                                            contentItem: Image {
                                                sourceSize: Qt.size(32, 32)
                                                fillMode: Image.PreserveAspectFit
                                                source: tileContainer.fullScreen ?
                                                    "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M4 14h6v6m10-6h-6v6M4 10h6V4m10 6h-6V4'></path></svg>" :
                                                    (fullScreenMouseAreaBtn.containsMouse ?
                                                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2300f5d4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3'></path></svg>" :
                                                        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3'></path></svg>"
                                                    )
                                            }

                                            MouseArea {
                                                id: fullScreenMouseAreaBtn
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    selectedPlayerIndex = index;
                                                    if (fullScreenPlayerIndex === index) {
                                                        fullScreenPlayerIndex = -1;
                                                    } else {
                                                        fullScreenPlayerIndex = index;
                                                    }
                                                }
                                            }

                                            ToolTip.delay: 500
                                            ToolTip.timeout: 5000
                                            ToolTip.visible: fullScreenMouseAreaBtn.containsMouse
                                            ToolTip.text: tileContainer.fullScreen ? qsTr("Przywróć widok siatki") : qsTr("Pokaż na pełnym ekranie")
                                        }
                                    }
                                }

                                // Premium Empty Viewport Placeholder
                                Rectangle {
                                    id: emptyPlaceholder
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    visible: modelData === null
                                    color: isSelected ? "#11171e" : "#0d131a"
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        color: "transparent"
                                        border.color: isSelected ? "#00f5d4" : "#24313c"
                                        border.width: 1
                                        radius: 6
                                    }
                                    
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 12
                                        
                                        Rectangle {
                                            id: placeholderAddButton
                                            width: 36
                                            height: 36
                                            radius: 18
                                            color: "transparent"
                                            border.color: isSelected ? "#00f5d4" : "#556b7c"
                                            border.width: 1
                                            Layout.alignment: Qt.AlignHCenter
                                            
                                            Text {
                                                text: "+"
                                                color: isSelected ? "#00f5d4" : "#556b7c"
                                                font.pixelSize: 20
                                                font.bold: true
                                                anchors.centerIn: parent
                                                anchors.verticalCenterOffset: -1
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    selectedPlayerIndex = index;
                                                }
                                            }
                                        }
                                        
                                        Text {
                                            text: qsTr("Pusty viewport")
                                            color: isSelected ? "#00f5d4" : "#8898a6"
                                            font.bold: true
                                            font.pixelSize: 12
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        
                                        Text {
                                            text: qsTr("Zaznacz to okno, wybierz kamerę z listy i kliknij + aby ją dodać")
                                            color: "#556b7c"
                                            font.pixelSize: 10
                                            Layout.alignment: Qt.AlignHCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            Layout.preferredWidth: parent.parent.width - 40
                                        }
                                    }
                                }
                                     // Discrete Camera Info Badge (matching LIVE mode design)
                                Rectangle {
                                    id: cameraInfoBadge
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        margins: 6
                                    }
                                    z: 15
                                    visible: modelData !== null
                                    
                                    color: "#66121214"
                                    border {
                                        color: (index === selectedPlayerIndex) ? "#00f5d4" : "#ff7a00"
                                        width: 1
                                    }
                                    radius: 4
                                    
                                    implicitWidth: cameraInfoContent.implicitWidth + 12
                                    implicitHeight: cameraInfoContent.implicitHeight + 6
                                    
                                    RowLayout {
                                        id: cameraInfoContent
                                        anchors.centerIn: parent
                                        spacing: 6
                                        
                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 3
                                            color: (index === selectedPlayerIndex) ? "#00f5d4" : "#8898a6"
                                        }
                                        
                                        Text {
                                            text: modelData ? (modelData.cameraName + " (" + modelData.recorderName + " CH " + (modelData.channelId < 10 ? "0" + modelData.channelId : modelData.channelId) + ")") : ""
                                            color: (index === selectedPlayerIndex) ? "#00f5d4" : "#eeeeee"
                                            font {
                                                pixelSize: 8
                                                bold: true
                                            }
                                        }
                                        
                                        Rectangle {
                                            width: 1
                                            height: 7
                                            color: (index === selectedPlayerIndex) ? "#4400f5d4" : "#448898a6"
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        
                                        Text {
                                            text: (playerItem ? playerItem.fps : 0) + " FPS"
                                            color: "#eeeeee"
                                            font {
                                                pixelSize: 8
                                                bold: true
                                            }
                                        }
                                    }
                                }

                                // Free-floating circular Close button
                                Rectangle {
                                    id: closeButton
                                    width: 20
                                    height: 20
                                    radius: 10
                                    z: 15
                                    anchors {
                                        top: parent.top
                                        right: parent.right
                                        margins: 6
                                    }
                                    visible: modelData !== null
                                    
                                    color: closeMouseArea.containsMouse ? "#ccff3333" : "#66121214"
                                    border.color: closeMouseArea.containsMouse ? "#ff3333" : "#8898a6"
                                    border.width: 1
                                    
                                    Image {
                                        anchors.centerIn: parent
                                        source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><line x1='18' y1='6' x2='6' y2='18'></line><line x1='6' y1='6' x2='18' y2='18'></line></svg>"
                                        width: 10
                                        height: 10
                                    }
                                    
                                    MouseArea {
                                        id: closeMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            removeCameraFromGrid(index);
                                        }
                                    }
                                }

                                // Dynamic bottom-left green recording timestamp badge (styled like camera name but green and larger)
                                Rectangle {
                                    id: timestampBadge
                                    anchors {
                                        left: parent.left
                                        bottom: parent.bottom
                                        margins: 6
                                    }
                                    z: 15
                                    visible: modelData !== null
                                    
                                    color: "#aa121214"
                                    border {
                                        color: (index === selectedPlayerIndex) ? "#00ff66" : "#8800dd00"
                                        width: 1
                                    }
                                    radius: 4
                                    
                                    implicitWidth: timestampText.implicitWidth + 12
                                    implicitHeight: timestampText.implicitHeight + 6
                                    
                                    Text {
                                        id: timestampText
                                        anchors.centerIn: parent
                                        text: {
                                            var t = new Date(playheadTimeMs);
                                            return Qt.formatDateTime(t, "yyyy-MM-dd HH:mm:ss");
                                        }
                                        color: "#00ff66"
                                        font {
                                            pixelSize: 11
                                            bold: true
                                        }
                                    }
                                }
                            }
                        }
                        }
                    }
                }
            }

            Rectangle {
                id: bottomPanel
                anchors.left: parent.left
                anchors.right: parent.right
                y: isBottomPanelShowed ? (parent.height - height) : parent.height
                height: 70 + Math.max(0, (getLoadedCameras().length - 1) * 8)
                color: isBottomPanelFloating ? "#331c242c" : "#1c242c"
                visible: true
                z: 200

                Behavior on y {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea {
                    id: bottomPanelMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: {
                        if (containsMouse) {
                            bottomKeepVisibleTimer.stop();
                        } else if (!bottomHoverArea.containsMouse) {
                            bottomKeepVisibleTimer.start();
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 5
                        Layout.leftMargin: 15
                        Layout.rightMargin: 15
                        spacing: 15
                        opacity: isBottomPanelFloating ? 0.75 : 1.0
                        
                        // Date selector
                        RowLayout {
                            spacing: 5
                            CctvButton {
                                text: "<"
                                width: 30
                                isSmall: true
                                onClicked: {
                                    var d = new Date(currentDate.getTime() - 86400000)
                                    d.setHours(0, 0, 0, 0)
                                    var timeOfDay = currentPlayheadMs
                                    currentDate = d
                                    searchRecordingsForDate(currentDate)
                                    playAtTime(currentDate, timeOfDay)
                                }
                            }
                            CctvButton {
                                id: calendarButton
                                text: Qt.formatDate(currentDate, "yyyy-MM-dd")
                                iconSource: "qrc:/images/calendar.svg"
                                isSmall: true
                                onClicked: {
                                    var pt = mapToItem(null, 0, 0)
                                    calendarPopup.x = pt.x
                                    calendarPopup.y = pt.y - calendarPopup.height - 10
                                    calendarPopup.open()
                                }
                            }
                            CctvButton {
                                text: ">"
                                width: 30
                                isSmall: true
                                onClicked: {
                                    var d = new Date(currentDate.getTime() + 86400000)
                                    d.setHours(0, 0, 0, 0)
                                    var timeOfDay = currentPlayheadMs
                                    currentDate = d
                                    searchRecordingsForDate(currentDate)
                                    playAtTime(currentDate, timeOfDay)
                                }
                            }
                            CctvButton {
                                text: qsTr("Dzisiaj")
                                isSmall: true
                                onClicked: {
                                    var d = new Date()
                                    d.setHours(0, 0, 0, 0)
                                    var timeOfDay = currentPlayheadMs
                                    currentDate = d
                                    searchRecordingsForDate(currentDate)
                                    playAtTime(currentDate, timeOfDay)
                                }
                            }
                            CctvButton {
                                text: qsTr("Odśwież")
                                isSmall: true
                                onClicked: {
                                    for (var i = 0; i < activePlayersList.length; i++) {
                                        var cam = activePlayersList[i];
                                        if (cam) {
                                            clearCacheForCamera(cam.ip, cam.channelId);
                                        }
                                    }
                                    searchRecordingsForDate(currentDate)
                                }
                            }
                        }
                        
                        // Zoom shortcuts
                        RowLayout {
                            spacing: 5
                            CctvButton {
                                text: qsTr("Ostatnia 1h")
                                isSmall: true
                                onClicked: zoomToLast(1)
                            }
                            CctvButton {
                                text: qsTr("Ostatnie 8h")
                                isSmall: true
                                onClicked: zoomToLast(8)
                            }
                            CctvButton {
                                text: qsTr("Cały dzień")
                                isSmall: true
                                onClicked: {
                                    zoomHours = 24
                                    panOffsetMs = 0
                                    timeline.requestPaint()
                                }
                            }
                            CctvButton {
                                text: qsTr("Wycentruj")
                                isSmall: true
                                onClicked: {
                                    autoFollowEnabled = true
                                    var viewDurationMs = zoomHours * 3600000
                                    panOffsetMs = currentPlayheadMs - viewDurationMs / 2
                                    normalizePanOffset()
                                    timeline.requestPaint()
                                }
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Playback speed shortcuts
                        RowLayout {
                            spacing: 3
                            Text { text: qsTr("Prędkość:"); color: "white"; font.bold: true; font.pixelSize: 10 }
                            
                            Repeater {
                                model: [1, 2, 4, 8]
                                CctvButton {
                                    isSmall: true
                                    property bool isSlow: modelData < 0
                                    property int absSpeed: Math.abs(modelData)
                                    text: absSpeed + "x"
                                    iconSource: isSlow ? "qrc:/images/rewind.svg" : (absSpeed === 1 ? "qrc:/images/play_small.svg" : "qrc:/images/forward.svg")
                                    isPrimary: playbackWindow.playbackSpeed === modelData
                                    onClicked: {
                                        playbackWindow.playbackSpeed = modelData
                                        forEachPlayer(function(p) { p.setPlaybackSpeed(modelData); })
                                    }
                                }
                            }
                        }
                        
                        // Download Controls
                        RowLayout {
                            spacing: 3
                            CctvButton {
                                text: qsTr("Pobierz")
                                isSmall: true
                                enabled: getLoadedCameras().length > 0
                                onClicked: {
                                    var loadedCams = getLoadedCameras();
                                    if (loadedCams.length === 0) return;
                                    downloadDialog.activeCamerasList = loadedCams;
                                    downloadDialog.targetDate = currentDate;
                                    downloadDialog.open();
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                        
                        // VCR Controls
                        RowLayout {
                            spacing: 3
                            CctvButton {
                                text: "60s"
                                iconSource: "qrc:/images/rewind.svg"
                                isSmall: true
                                onClicked: jumpTime(-60000)
                            }
                            CctvButton {
                                text: "45s"
                                iconSource: "qrc:/images/rewind.svg"
                                isSmall: true
                                onClicked: jumpTime(-45000)
                            }
                            CctvButton {
                                text: "15s"
                                iconSource: "qrc:/images/rewind.svg"
                                isSmall: true
                                onClicked: jumpTime(-15000)
                            }
                            CctvButton {
                                text: isPlaying ? qsTr("Pauza") : qsTr("Play")
                                iconSource: isPlaying ? "qrc:/images/pause.svg" : "qrc:/images/play.svg"
                                isSmall: true
                                isPrimary: true
                                onClicked: togglePlayPause()
                            }
                            CctvButton {
                                text: "15s"
                                iconSource: "qrc:/images/forward.svg"
                                isSmall: true
                                onClicked: jumpTime(15000)
                            }
                            CctvButton {
                                text: "45s"
                                iconSource: "qrc:/images/forward.svg"
                                isSmall: true
                                onClicked: jumpTime(45000)
                            }
                            CctvButton {
                                text: "60s"
                                iconSource: "qrc:/images/forward.svg"
                                isSmall: true
                                onClicked: jumpTime(60000)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            id: bottomPinButton
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignVCenter
                            hoverEnabled: true

                            property bool isPinned: !playbackWindow.hideTimelineOption

                            contentItem: Image {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                rotation: bottomPinButton.isPinned ? 0 : -45

                                Behavior on rotation {
                                    NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                                }

                                source: {
                                    var colorStr = bottomPinButton.isPinned
                                        ? (bottomPinButton.hovered ? "%23ffb703" : "%23ff7a00")
                                        : (bottomPinButton.hovered ? "%23ffcc66" : "%23e0a96d");
                                    if (bottomPinButton.isPinned) {
                                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='" + colorStr + "' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='12' x2='12' y1='17' y2='22'></line><path d='M5 17h14v-1.76a2 2 0 0 0-.44-1.24l-2.78-3.56A2 2 0 0 1 15 9.2V5a2 2 0 0 0-2-2h-2a2 2 0 0 0-2 2v4.2a2 2 0 0 1-.78 1.24L5.44 14a2 2 0 0 0-.44 1.24Z'></path></svg>";
                                    } else {
                                        return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='12' x2='12' y1='17' y2='22'></line><path d='M5 17h14v-1.76a2 2 0 0 0-.44-1.24l-2.78-3.56A2 2 0 0 1 15 9.2V5a2 2 0 0 0-2-2h-2a2 2 0 0 0-2 2v4.2a2 2 0 0 1-.78 1.24L5.44 14a2 2 0 0 0-.44 1.24Z'></path></svg>";
                                    }
                                }
                            }

                            background: Rectangle {
                                color: bottomPinButton.pressed ? "#cc121214" : (bottomPinButton.hovered ? "#3a4550" : "#1c242c")
                                radius: 15
                                border.color: bottomPinButton.isPinned
                                    ? (bottomPinButton.hovered ? "#ffb703" : "#ff7a00")
                                    : (bottomPinButton.hovered ? "#e0a96d" : "#2a3540")
                                border.width: 1
                            }

                            onClicked: {
                                playbackWindow.hideTimelineOption = !playbackWindow.hideTimelineOption;
                            }

                            ToolTip.delay: Compact.toolTipDelay
                            ToolTip.timeout: Compact.toolTipTimeout
                            ToolTip.visible: bottomPinButton.hovered
                            ToolTip.text: bottomPinButton.isPinned ? qsTr("Odepnij pasek dolny") : qsTr("Przypnij pasek dolny")
                        }
                    }
                    
                    // Timeline
                    Canvas {
                        id: timeline
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: true
                        clip: true
                        
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        
                        property var segments: []
                        
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            
                            ctx.fillStyle = isBottomPanelFloating ? "#330a0f14" : "#0a0f14"
                            ctx.fillRect(0, 0, width, height)
                            
                            var viewDurationMs = zoomHours * 3600000
                            var msPerPixel = viewDurationMs / width
                            var sodTime = currentDate.getTime()
                             if (playbackWindow.recorderInfo) {
                                 ctx.fillStyle = "rgba(0, 245, 212, 0.08)"
                                 var bgStartDate = new Date(sodTime + panOffsetMs)
                                 bgStartDate.setHours(0, 0, 0, 0)
                                 var bgEndDate = new Date(sodTime + panOffsetMs + viewDurationMs)
                                 bgEndDate.setHours(0, 0, 0, 0)
                                 
                                 for (var d = new Date(bgStartDate); d.getTime() <= bgEndDate.getTime(); d.setDate(d.getDate() + 1)) {
                                     var key = playbackWindow.recorderInfo.ip + "_" + playbackWindow.channelId + "_" + d.getFullYear() + "-" + d.getMonth();
                                     var monthAvail = rootWindow.monthAvailabilitiesCache[key];
                                     if (Array.isArray(monthAvail) && monthAvail.indexOf(d.getDate()) !== -1) {
                                         var dayStartMs = d.getTime()
                                         var dayEndMs = dayStartMs + 86400000
                                         
                                         var x1m = (dayStartMs - sodTime - panOffsetMs) / msPerPixel
                                         var x2m = (dayEndMs - sodTime - panOffsetMs) / msPerPixel
                                         
                                         if (x2m >= 0 && x1m <= width) {
                                             var drawXm = Math.max(0, x1m)
                                             var drawWm = Math.min(width - drawXm, x2m - drawXm)
                                             if (drawWm > 0) {
                                                 ctx.fillRect(drawXm, 0, Math.max(1, drawWm), height)
                                             }
                                         }
                                     }
                                 }
                             }
                            
                            var colors = ["#00f5d4", "#e0aaff", "#70e000", "#ff5c8a"]
                            var activeCams = getLoadedCameras()
                            var N = activeCams.length
                            var barsTotalHeight = N * 8
                            
                            // Find the start date and end date of the visible range
                            var startDate = new Date(sodTime + panOffsetMs)
                            startDate.setHours(0, 0, 0, 0)
                            var endDate = new Date(sodTime + panOffsetMs + viewDurationMs)
                            endDate.setHours(0, 0, 0, 0)
                            
                            // Draw stacked timeline segments for all active viewports
                            for (var i = 0; i < N; i++) {
                                var cam = activeCams[i]
                                var barColor = colors[i % colors.length]
                                var barY = height - (N - i) * 8
                                
                                ctx.fillStyle = barColor
                                
                                // Loop through all visible days
                                for (var d = new Date(startDate); d.getTime() <= endDate.getTime(); d.setDate(d.getDate() + 1)) {
                                    var cacheKey = cam.ip + "_" + cam.channelId + "_" + getDateKey(d)
                                    var camSegments = rootWindow.playbackSegmentsCache[cacheKey]
                                    
                                    var dayStartMs = d.getTime()
                                    var dayEndMs = dayStartMs + 86400000
                                    
                                    if (camSegments === undefined) {
                                        var monthKey = cam.ip + "_" + cam.channelId + "_" + d.getFullYear() + "-" + d.getMonth();
                                        var monthAvail = rootWindow.monthAvailabilitiesCache[monthKey];
                                        if (Array.isArray(monthAvail) && monthAvail.indexOf(d.getDate()) !== -1) {
                                            var startOffset = dayStartMs - sodTime;
                                            var endOffset = dayEndMs - sodTime;
                                            var x1 = (startOffset - panOffsetMs) / msPerPixel;
                                            var x2 = (endOffset - panOffsetMs) / msPerPixel;
                                            
                                            if (x2 >= 0 && x1 <= width) {
                                                var drawX = Math.max(0, x1);
                                                var drawW = Math.max(1, Math.min(width - drawX, x2 - drawX));
                                                ctx.save();
                                                ctx.globalAlpha = 0.25;
                                                ctx.fillStyle = barColor;
                                                ctx.fillRect(drawX, barY, drawW, 6);
                                                ctx.restore();
                                            }
                                        }
                                        continue;
                                    }
                                    
                                    for (var k = 0; k < camSegments.length; k++) {
                                        var seg = camSegments[k]
                                        // Only draw segments whose startTime is on this day
                                        if (seg.startTime < dayStartMs || seg.startTime >= dayEndMs) {
                                            continue
                                        }
                                        
                                        var startOffset = seg.startTime - sodTime
                                        var endOffset = seg.endTime - sodTime
                                        
                                        var x1 = (startOffset - panOffsetMs) / msPerPixel
                                        var x2 = (endOffset - panOffsetMs) / msPerPixel
                                        
                                        if (x2 >= 0 && x1 <= width) {
                                            var drawX = Math.max(0, x1)
                                            var drawW = Math.max(1, Math.min(width - drawX, x2 - drawX))
                                            ctx.fillRect(drawX, barY, drawW, 6)
                                        }
                                    }
                                }
                                
                                // Draw dark backing tag and text label on the left
                                var labelText = cam.cameraName || ("CH " + cam.channelId)
                                ctx.font = "9px sans-serif"
                                var textW = ctx.measureText(labelText).width
                                ctx.fillStyle = "rgba(10, 15, 20, 0.85)"
                                ctx.fillRect(4, barY, textW + 8, 7)
                                ctx.fillStyle = "#ffffff"
                                ctx.fillText(labelText, 8, barY + 6)
                            }
                            
                            // Draw day boundaries
                            ctx.strokeStyle = "#445566"
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            for (var dayOffset = -5; dayOffset <= 5; dayOffset++) {
                                var dayMs = dayOffset * 86400000
                                var dx = (dayMs - panOffsetMs) / msPerPixel
                                if (dx >= 0 && dx <= width) {
                                    ctx.moveTo(dx, 0)
                                    ctx.lineTo(dx, height)
                                    ctx.fillStyle = "#ffaa00"
                                    ctx.font = "12px sans-serif"
                                    var d = new Date(currentDate.getTime() + dayMs)
                                    ctx.fillText(Qt.formatDate(d, "yyyy-MM-dd"), dx + 5, 15)
                                }
                            }
                            ctx.stroke()
                            
                            // Draw hour markers (shifted up by barsTotalHeight)
                            ctx.fillStyle = "#8898a6"
                            ctx.font = "10px sans-serif"
                            var startHour = Math.floor(panOffsetMs / 3600000)
                            var endHour = Math.ceil((panOffsetMs + viewDurationMs) / 3600000)
                            
                            for (var h = startHour; h <= endHour; h++) {
                                var hMs = h * 3600000
                                var hx = (hMs - panOffsetMs) / msPerPixel
                                if (hx >= 0 && hx <= width) {
                                    ctx.fillRect(hx, height - barsTotalHeight - 15, 1, 15)
                                    var step = zoomHours > 12 ? 2 : (zoomHours > 6 ? 1 : 0.5)
                                    if (h % step === 0) {
                                        var displayH = ((h % 24) + 24) % 24
                                        ctx.fillText(displayH + ":00", hx + 3, height - barsTotalHeight - 5)
                                    }
                                }
                            }

                            // Minute ticks (shifted up by barsTotalHeight)
                            var minuteInterval = 0;
                            if (zoomHours <= 1) minuteInterval = 1;
                            else if (zoomHours <= 4) minuteInterval = 5;
                            else if (zoomHours <= 12) minuteInterval = 10;

                            if (minuteInterval > 0) {
                                ctx.fillStyle = "#556677"
                                var startMin = Math.floor(panOffsetMs / 60000);
                                var endMin = Math.ceil((panOffsetMs + viewDurationMs) / 60000);
                                for (var m = startMin; m <= endMin; m++) {
                                    if (m % 60 === 0) continue; 
                                    if (m % minuteInterval !== 0) continue;
                                    
                                    var mMs = m * 60000;
                                    var mx = (mMs - panOffsetMs) / msPerPixel;
                                    if (mx >= 0 && mx <= width) {
                                        ctx.fillRect(mx, height - barsTotalHeight - 8, 1, 8);
                                    }
                                }
                            }
                            
                            // Draw playhead
                            var activePlayheadMs = currentPlayheadMs
                            if (mouseArea.isDraggingPlayhead) {
                                  activePlayheadMs = mouseArea.dragPlayheadMs
                            }
                            
                            if (activePlayheadMs !== undefined) {
                                var px = (activePlayheadMs - panOffsetMs) / msPerPixel
                                if (px >= 0 && px <= width) {
                                    ctx.fillStyle = "red"
                                    ctx.fillRect(px, 0, 2, height)
                                    
                                    if (mouseArea.isDraggingPlayhead) {
                                        ctx.fillStyle = "white"
                                        ctx.font = "bold 12px sans-serif"
                                        var pt = new Date(currentDate.getTime() + activePlayheadMs)
                                        ctx.fillText(Qt.formatTime(pt, "hh:mm:ss"), px + 5, Math.max(12, height - barsTotalHeight - 5))
                                    }
                                }
                            }

                            // Draw loading text overlay
                            if (playbackWindow.isSearchingRecordings) {
                                var isCompact = height < 44;
                                var boxW = isCompact ? 280 : 320;
                                var boxH = isCompact ? 20 : 40;
                                var boxX = width - boxW - 20;
                                var boxY = isCompact ? (height - boxH) / 2 : 20;
                                var r = isCompact ? 6 : 12;
                                
                                // Elegant glassmorphic background pill
                                ctx.fillStyle = "rgba(10, 15, 20, 0.85)"
                                ctx.strokeStyle = "rgba(0, 245, 212, 0.6)"
                                ctx.lineWidth = 1
                                ctx.beginPath()
                                if (typeof ctx.roundRect === "function") {
                                    ctx.roundRect(boxX, boxY, boxW, boxH, r)
                                } else {
                                    ctx.moveTo(boxX + r, boxY)
                                    ctx.lineTo(boxX + boxW - r, boxY)
                                    ctx.arcTo(boxX + boxW, boxY, boxX + boxW, boxY + r, r)
                                    ctx.lineTo(boxX + boxW, boxY + boxH - r, boxY + r)
                                    ctx.arcTo(boxX + boxW, boxY + boxH, boxX + boxW - r, boxY + boxH, r)
                                    ctx.lineTo(boxX + r, boxY + boxH)
                                    ctx.arcTo(boxX, boxY + boxH, boxX, boxY + boxH - r, r)
                                    ctx.lineTo(boxX, boxY + r)
                                    ctx.arcTo(boxX, boxY, boxX + r, boxY, r)
                                    ctx.closePath()
                                }
                                ctx.fill()
                                ctx.stroke()

                                // Loading spinner
                                ctx.save()
                                ctx.translate(boxX + (isCompact ? 16 : 24), boxY + boxH / 2)
                                ctx.rotate(Date.now() / 150)
                                ctx.beginPath()
                                ctx.arc(0, 0, isCompact ? 5 : 8, 0, Math.PI * 1.5)
                                ctx.strokeStyle = "#00f5d4"
                                ctx.lineWidth = isCompact ? 1.5 : 2
                                ctx.stroke()
                                ctx.restore()

                                // Text inside pill
                                ctx.fillStyle = "#00f5d4"
                                ctx.font = isCompact ? "bold 8px sans-serif" : "bold 10px sans-serif"
                                var text = qsTr("Trwa ładowanie informacji o dostępności nagrania...")
                                var textW = ctx.measureText(text).width
                                ctx.fillText(text, boxX + (boxW - textW) / 2 + (isCompact ? 8 : 10), boxY + (isCompact ? 13 : 24))
                            }
                        }
                        
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            property real lastMouseX: -1
                            property real pressX: -1
                            property real pressPanOffsetMs: 0
                            property bool isPanning: false
                            property bool isDraggingPlayhead: false
                            property real dragPlayheadMs: 0

                            onPressed: {
                                if (mouse.button === Qt.RightButton) {
                                    lastMouseX = mouse.x
                                    autoFollowEnabled = false
                                } else if (mouse.button === Qt.LeftButton) {
                                    pressX = mouse.x
                                    pressPanOffsetMs = panOffsetMs
                                    isPanning = false
                                    isDraggingPlayhead = false
                                    autoFollowEnabled = false
                                }
                            }
                            
                            onPositionChanged: {
                                 var viewDurationMs = zoomHours * 3600000
                                 var msPerPixel = viewDurationMs / width
                                 
                                 if (pressedButtons & Qt.RightButton && lastMouseX >= 0) {
                                     var dx = mouse.x - lastMouseX
                                     panOffsetMs -= dx * msPerPixel
                                     normalizePanOffset()
                                     searchRecordingsForDate(currentDate)
                                     lastMouseX = mouse.x
                                     timeline.requestPaint()
                                 } else if (pressedButtons & Qt.LeftButton && pressX >= 0) {
                                     var dxL = mouse.x - pressX
                                     if (Math.abs(dxL) > 5 || isPanning) {
                                         isPanning = true
                                         panOffsetMs = pressPanOffsetMs - dxL * msPerPixel
                                         normalizePanOffset()
                                         searchRecordingsForDate(currentDate)
                                         timeline.requestPaint()
                                     }
                                 }
                             }

                             onReleased: {
                                 if (mouse.button === Qt.LeftButton) {
                                     var isDrag = isPanning || (pressX >= 0 && Math.abs(mouse.x - pressX) > 5)
                                     if (!isDrag && pressX >= 0) {
                                         // Simple left-click: place the playhead!
                                         var viewDurationMs = zoomHours * 3600000
                                         var msPerPixel = viewDurationMs / width
                                         var clickedMs = panOffsetMs + (mouse.x * msPerPixel)
                                         
                                         playAtTime(currentDate, clickedMs)
                                         autoFollowEnabled = true
                                     }
                                     isPanning = false
                                     pressX = -1
                                 }
                                 if (mouse.button === Qt.RightButton) {
                                     lastMouseX = -1
                                 }
                             }

                             onWheel: {
                                 autoFollowEnabled = false
                                 var viewDurationMs = zoomHours * 3600000
                                 var msPerPixel = viewDurationMs / width
                                 var msAtMouse = panOffsetMs + (wheel.x * msPerPixel)
                                 
                                 if (wheel.angleDelta.y > 0) {
                                     zoomHours = Math.max(0.5, zoomHours * 0.8)
                                 } else {
                                     zoomHours = Math.min(24 * 7, zoomHours * 1.25)
                                 }
                                 
                                 var newMsPerPixel = (zoomHours * 3600000) / width
                                 panOffsetMs = msAtMouse - (wheel.x * newMsPerPixel)
                                 normalizePanOffset()
                                 searchRecordingsForDate(currentDate)
                                 timeline.requestPaint()
                                 wheel.accepted = true
                             }
                        }
                    }
                }
                }
            }

            MouseArea {
                id: bottomHoverArea
                height: 12
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                hoverEnabled: true
                z: 199
                onContainsMouseChanged: {
                    if (containsMouse) {
                        bottomKeepVisibleTimer.stop();
                    } else if (!bottomPanelMouseArea.containsMouse) {
                        bottomKeepVisibleTimer.start();
                    }
                }
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
        y: (!playbackWindow.topBarAutoCollapse || hoverArea.containsMouse || topToolBarMouseArea.containsMouse || keepVisibleTimer.running) ? 0 : -height

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
            z: 10 // draw line on top of background
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
                    id: closeButton
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
                        color: closeButton.pressed ? "#cc2929" : (closeButton.hovered ? "#ff4d4d" : "#d63333")
                        radius: 15
                    }

                    onClicked: {
                        playbackWindow.close();
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: closeButton.hovered
                    ToolTip.text: qsTr("Zamknij okno")
                }

                Button {
                    id: pinButton
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter
                    hoverEnabled: true

                    property bool isPinned: !playbackWindow.topBarAutoCollapse

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        rotation: pinButton.isPinned ? 0 : -45

                        Behavior on rotation {
                            NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                        }

                        source: {
                            var colorStr = pinButton.isPinned
                                ? (pinButton.hovered ? "%23ffb703" : "%23ff7a00")
                                : (pinButton.hovered ? "%23ffcc66" : "%23e0a96d");
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
                        border.color: pinButton.isPinned
                            ? (pinButton.hovered ? "#ffb703" : "#ff7a00")
                            : (pinButton.hovered ? "#e0a96d" : "#2a3540")
                        border.width: 1
                    }

                    onClicked: {
                        playbackWindow.topBarAutoCollapse = !playbackWindow.topBarAutoCollapse;
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
                    hoverEnabled: true

                    property bool isActive: playbackWindow.visibility === Window.FullScreen

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: {
                            var colorStr = fullScreenBtn.hovered ? "%2300f5d4" : (fullScreenBtn.isActive ? "%2300f5d4" : "%2300b09b");
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
                        border.color: fullScreenBtn.hovered ? "#00f5d4" : "#2a3540"
                        border.width: 1
                    }

                    onClicked: {
                        toggleWindowFullScreen();
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: fullScreenBtn.hovered
                    ToolTip.text: fullScreenBtn.isActive ? qsTr("Wyjdź z pełnego ekranu") : qsTr("Pełny ekran okna")
                }

                Button {
                    id: sidebarToggleBtn
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter
                    hoverEnabled: true

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var colorStr = playbackWindow.sidebarVisible
                                ? (sidebarToggleBtn.hovered ? "%2300f5d4" : "%2300b4d8")
                                : (sidebarToggleBtn.hovered ? "%238898a6" : "%235a738e");
                            if (playbackWindow.sidebarVisible) {
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='3' width='18' height='18' rx='2' ry='2'></rect><line x1='9' y1='3' x2='9' y2='21'></line><path d='M3 3h6v18H3z' fill='" + colorStr + "' fill-opacity='0.2'></path></svg>";
                            } else {
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='3' width='18' height='18' rx='2' ry='2' stroke-dasharray='4,3'></rect></svg>";
                            }
                        }
                    }

                    background: Rectangle {
                        color: sidebarToggleBtn.pressed ? "#cc121214" : (sidebarToggleBtn.hovered ? "#3a4550" : "#1c242c")
                        radius: 15
                        border.color: playbackWindow.sidebarVisible
                            ? (sidebarToggleBtn.hovered ? "#00f5d4" : "#00b4d8")
                            : (sidebarToggleBtn.hovered ? "#8898a6" : "#2a3540")
                        border.width: 1
                    }

                    onClicked: {
                        playbackWindow.sidebarVisible = !playbackWindow.sidebarVisible;
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: sidebarToggleBtn.hovered
                    ToolTip.text: playbackWindow.sidebarVisible ? qsTr("Ukryj pasek boczny") : qsTr("Pokaż pasek boczny")
                }

                Button {
                    id: timelineToggleBtn
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter
                    hoverEnabled: true

                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var colorStr = !playbackWindow.hideTimelineOption
                                ? (timelineToggleBtn.hovered ? "%232ecc71" : "%2320bf6b")
                                : (timelineToggleBtn.hovered ? "%238898a6" : "%235a738e");
                            if (!playbackWindow.hideTimelineOption) {
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='10'></circle><polyline points='12 6 12 12 16 14'></polyline></svg>";
                            } else {
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='10'></circle><polyline points='12 6 12 12 16 14'></polyline><line x1='4' y1='4' x2='20' y2='20'></line></svg>";
                            }
                        }
                    }

                    background: Rectangle {
                        color: timelineToggleBtn.pressed ? "#cc121214" : (timelineToggleBtn.hovered ? "#3a4550" : "#1c242c")
                        radius: 15
                        border.color: !playbackWindow.hideTimelineOption
                            ? (timelineToggleBtn.hovered ? "#2ecc71" : "#20bf6b")
                            : (timelineToggleBtn.hovered ? "#8898a6" : "#2a3540")
                        border.width: 1
                    }

                    onClicked: {
                        playbackWindow.hideTimelineOption = !playbackWindow.hideTimelineOption;
                    }

                    ToolTip.delay: Compact.toolTipDelay
                    ToolTip.timeout: Compact.toolTipTimeout
                    ToolTip.visible: timelineToggleBtn.hovered
                    ToolTip.text: playbackWindow.hideTimelineOption ? qsTr("Pokaż oś czasu") : qsTr("Ukryj oś czasu")
                }

                Rectangle {
                    width: 1
                    height: 20
                    color: "#2a3540"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                }

                // Layout buttons on the left
                RowLayout {
                    spacing: 4
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                    Repeater {
                        model: ["1x1", "1x2", "2x1", "2x2"]
                        delegate: Button {
                            id: gridBtn
                            text: modelData
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignVCenter
                            hoverEnabled: true

                            property bool isActive: {
                                if (modelData === "1x1") return gridLayoutColumns === 1 && gridLayoutRows === 1;
                                if (modelData === "1x2") return gridLayoutColumns === 1 && gridLayoutRows === 2;
                                if (modelData === "2x1") return gridLayoutColumns === 2 && gridLayoutRows === 1;
                                if (modelData === "2x2") return gridLayoutColumns === 2 && gridLayoutRows === 2;
                                return false;
                            }

                            contentItem: Text {
                                text: gridBtn.text
                                font.bold: true
                                font.pixelSize: 10
                                color: gridBtn.isActive ? "white" : (gridBtn.hovered ? "#ffffff" : "#8898a6")
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                color: gridBtn.isActive ? "#00f5d4" : (gridBtn.pressed ? "#cc121214" : (gridBtn.hovered ? "#3a4550" : "#1c242c"))
                                radius: 15
                                border.color: gridBtn.isActive ? "#00f5d4" : (gridBtn.hovered ? "#8898a6" : "#2a3540")
                                border.width: 1
                            }

                            onClicked: {
                                if (modelData === "1x1") {
                                    gridLayoutColumns = 1;
                                    gridLayoutRows = 1;
                                } else if (modelData === "1x2") {
                                    gridLayoutColumns = 1;
                                    gridLayoutRows = 2;
                                } else if (modelData === "2x1") {
                                    gridLayoutColumns = 2;
                                    gridLayoutRows = 1;
                                } else if (modelData === "2x2") {
                                    gridLayoutColumns = 2;
                                    gridLayoutRows = 2;
                                }

                                var maxCams = gridLayoutColumns * gridLayoutRows;
                                resizeActivePlayersList(maxCams);
                            }
                        }
                    }
                }


            }
        }
    }

    // Top edge mouse detection area for sliding bar
    MouseArea {
        id: hoverArea
        height: 12
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        hoverEnabled: true
        z: 9998
        onContainsMouseChanged: {
            if (containsMouse) {
                keepVisibleTimer.stop();
            } else if (!topToolBarMouseArea.containsMouse) {
                keepVisibleTimer.start();
            }
        }
    }
}
