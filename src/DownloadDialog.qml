import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import QtQuick.Dialogs 1.2
import CCTV_Viewer.Hikvision 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Core 1.0
import Qt.labs.platform 1.1 as Platform

Popup {
    id: downloadDialog
    modal: true
    focus: true
    anchors.centerIn: parent
    width: 1200
    height: 240 + Math.max(1, downloadModel.count) * 65
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    signal downloadStarted()

    // Backwards compatibility properties
    property var recorderInfo
    property int channelId: 0
    property string recorderName: ""
    property string cameraName: ""
    property var targetDate: new Date()
    property var startDate: new Date()
    property var endDate: new Date()
    property bool isSelectingStart: true

    // Multi-camera properties
    property var activeCamerasList: []
    property int activeCameraIndex: -1

    ListModel {
        id: downloadModel
    }

    background: Rectangle {
        color: "#1e2227"
        border.color: "#30363d"
        radius: 8
    }

    Popup {
        id: calendarPopup
        width: 320
        height: 380
        modal: true
        focus: true
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { 
            color: "#151d24"
            border.color: "#ff7a00"
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
        
        property int viewYear: targetDate.getFullYear()
        property int viewMonth: targetDate.getMonth()
        property var monthNames: [qsTr("Styczeń"), qsTr("Luty"), qsTr("Marzec"), qsTr("Kwiecień"), qsTr("Maj"), qsTr("Czerwiec"), qsTr("Lipiec"), qsTr("Sierpień"), qsTr("Wrzesień"), qsTr("Październik"), qsTr("Listopad"), qsTr("Grudzień")]
        
        function updateDaysModel() {
            var firstDay = new Date(viewYear, viewMonth, 1)
            var lastDay = new Date(viewYear, viewMonth + 1, 0)
            var startOffset = firstDay.getDay() === 0 ? 6 : firstDay.getDay() - 1
            var totalDays = lastDay.getDate()
            
            var cells = []
            for (var i = 0; i < startOffset; i++) cells.push(0)
            for (var d = 1; d <= totalDays; d++) cells.push(d)
            while (cells.length % 7 !== 0) cells.push(0)
            
            daysRepeater.model = cells
        }

        onOpened: {
            viewYear = targetDate.getFullYear()
            viewMonth = targetDate.getMonth()
            updateDaysModel()
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            
            Text {
                text: calendarPopup.monthNames[calendarPopup.viewMonth] + " " + calendarPopup.viewYear
                color: "white"
                font.bold: true
                font.pixelSize: 18
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                Layout.bottomMargin: 10
            }
            
            GridLayout {
                columns: 7
                rowSpacing: 5
                columnSpacing: 5
                Layout.alignment: Qt.AlignHCenter
                
                Repeater {
                    model: ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]
                    Text { 
                        text: modelData; color: "#8898a6"; font.bold: true; 
                        horizontalAlignment: Text.AlignHCenter; 
                        Layout.preferredWidth: 36 
                    }
                }
                
                Repeater {
                    id: daysRepeater
                    model: []
                    
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        color: {
                            if (modelData === 0) return "transparent"
                            var isCurrent = (calendarPopup.viewYear === targetDate.getFullYear() && calendarPopup.viewMonth === targetDate.getMonth() && modelData === targetDate.getDate())
                            if (isCurrent) return "#33ffffff"
                            return "transparent"
                        }
                        border.width: 0
                        radius: 4
                        
                        Text {
                            text: modelData > 0 ? modelData : ""
                            anchors.centerIn: parent
                            color: "white"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData > 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var newDate = new Date(calendarPopup.viewYear, calendarPopup.viewMonth, modelData)
                                if (isSelectingStart) {
                                    startDate = newDate
                                    startDateField.text = Qt.formatDateTime(startDate, "dd.MM.yyyy")
                                } else {
                                    endDate = newDate
                                    endDateField.text = Qt.formatDateTime(endDate, "dd.MM.yyyy")
                                }
                                calendarPopup.close()
                            }
                        }
                    }
                }
            }
            
            Item { Layout.fillHeight: true }
            
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 20
                
                CctvButton {
                    text: qsTr("< Poprzedni")
                    onClicked: {
                        if (calendarPopup.viewMonth === 0) { 
                            calendarPopup.viewMonth = 11; 
                            calendarPopup.viewYear--; 
                        } else { 
                            calendarPopup.viewMonth--; 
                        }
                        calendarPopup.updateDaysModel()
                    }
                }
                CctvButton {
                    text: qsTr("Następny >")
                    onClicked: {
                        if (calendarPopup.viewMonth === 11) { 
                            calendarPopup.viewMonth = 0; 
                            calendarPopup.viewYear++; 
                        } else { 
                            calendarPopup.viewMonth++; 
                        }
                        calendarPopup.updateDaysModel()
                    }
                }
            }
        }
    }

    onOpened: {
        var baseDate = targetDate || new Date()
        
        startDate = new Date(baseDate)
        startDate.setHours(0, 0, 0, 0)
        
        endDate = new Date(baseDate)
        endDate.setHours(23, 59, 59, 0)
        
        startDateField.text = Qt.formatDateTime(startDate, "dd.MM.yyyy")
        endDateField.text = Qt.formatDateTime(endDate, "dd.MM.yyyy")
        startTimeField.text = "00:00:00"
        endTimeField.text = "23:59:59"

        downloadModel.clear();
        for (var i = 0; i < activeCamerasList.length; i++) {
            var cam = activeCamerasList[i];
            if (!cam) continue;
            
            var d = Qt.formatDateTime(startDate, "yyyy-MM-dd");
            var filename = cam.recorderName + "_" + cam.channelId + "_" + cam.cameraName + "_" + d + ".mp4";
            filename = filename.replace(/ /g, "_").replace(/[^a-zA-Z0-9_\-\.]/g, "");
            
            var moviesPath = "";
            if (typeof generalSettings !== "undefined" && generalSettings.videoPath !== "") {
                moviesPath = generalSettings.videoPath;
            } else {
                moviesPath = Platform.StandardPaths.writableLocation(Platform.StandardPaths.MoviesLocation).toString();
                if (moviesPath.indexOf("file://") === 0) {
                    moviesPath = moviesPath.substring(7);
                }
                moviesPath = moviesPath + "/CCTV";
            }
            var defaultSavePath = moviesPath + "/" + filename;
            
            downloadModel.append({
                "cameraIndex": i,
                "cameraName": cam.cameraName,
                "channelId": cam.channelId,
                "ip": cam.ip,
                "port": cam.port || 8000,
                "username": cam.username,
                "password": cam.password,
                "recorderName": cam.recorderName,
                "savePath": defaultSavePath,
                "downloadEnabled": true,
                "progress": 0,
                "isDownloading": false,
                "statusText": ""
            });
        }
    }
    
    onClosed: {
        stopAllDownloads()
    }

    function isAnyDownloading() {
        for (var i = 0; i < downloadModel.count; i++) {
            if (downloadModel.get(i).isDownloading) {
                return true;
            }
        }
        return false;
    }

    function isAnyEnabled() {
        for (var i = 0; i < downloadModel.count; i++) {
            if (downloadModel.get(i).downloadEnabled) {
                return true;
            }
        }
        return false;
    }

    function stopAllDownloads() {
        for (var i = 0; i < cameraRepeater.count; i++) {
            var delegateItem = cameraRepeater.itemAt(i);
            if (delegateItem && downloadModel.get(i).isDownloading) {
                delegateItem.stopRowDownload();
            }
        }
    }

    function getStartDateTime() {
        var partsDateStart = startDateField.text.split(".")
        var start = new Date()
        if (partsDateStart.length === 3) {
            start.setFullYear(parseInt(partsDateStart[2]), parseInt(partsDateStart[1])-1, parseInt(partsDateStart[0]))
        }
        var partsStart = startTimeField.text.split(":")
        start.setHours(parseInt(partsStart[0]||"0"), parseInt(partsStart[1]||"0"), parseInt(partsStart[2]||"0"), 0)
        return start
    }
    
    function getEndDateTime() {
        var partsDateEnd = endDateField.text.split(".")
        var end = new Date()
        if (partsDateEnd.length === 3) {
            end.setFullYear(parseInt(partsDateEnd[2]), parseInt(partsDateEnd[1])-1, parseInt(partsDateEnd[0]))
        }
        var partsEnd = endTimeField.text.split(":")
        end.setHours(parseInt(partsEnd[0]||"23"), parseInt(partsEnd[1]||"59"), parseInt(partsEnd[2]||"59"), 0)
        return end
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        Text {
            text: qsTr("Pobieranie nagrań")
            color: "white"
            font.pixelSize: 18
            font.bold: true
            Layout.fillWidth: true
        }

        GridLayout {
            columns: 3
            rowSpacing: 10
            columnSpacing: 10
            Layout.fillWidth: true

            Text { text: qsTr("Od:"); color: "white" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 2
                TextField {
                    id: startDateField
                    Layout.fillWidth: true
                    selectByMouse: true
                    palette.highlight: "#00f5d4"
                    palette.highlightedText: "#000000"
                    enabled: !downloadDialog.isAnyDownloading()
                }
                CctvButton {
                    text: "📅"
                    isSmall: true
                    Layout.preferredWidth: 30
                    enabled: !downloadDialog.isAnyDownloading()
                    onClicked: {
                        isSelectingStart = true
                        var parts = startDateField.text.split(".")
                        if (parts.length === 3) {
                            startDate.setFullYear(parseInt(parts[2]), parseInt(parts[1])-1, parseInt(parts[0]))
                        }
                        calendarPopup.viewYear = startDate.getFullYear()
                        calendarPopup.viewMonth = startDate.getMonth()
                        calendarPopup.updateDaysModel()
                        calendarPopup.open()
                    }
                }
            }
            TextField {
                id: startTimeField
                Layout.fillWidth: true
                selectByMouse: true
                palette.highlight: "#00f5d4"
                palette.highlightedText: "#000000"
                enabled: !downloadDialog.isAnyDownloading()
            }

            Text { text: qsTr("Do:"); color: "white" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 2
                TextField {
                    id: endDateField
                    Layout.fillWidth: true
                    selectByMouse: true
                    palette.highlight: "#00f5d4"
                    palette.highlightedText: "#000000"
                    enabled: !downloadDialog.isAnyDownloading()
                }
                CctvButton {
                    text: "📅"
                    isSmall: true
                    Layout.preferredWidth: 30
                    enabled: !downloadDialog.isAnyDownloading()
                    onClicked: {
                        isSelectingStart = false
                        var parts = endDateField.text.split(".")
                        if (parts.length === 3) {
                            endDate.setFullYear(parseInt(parts[2]), parseInt(parts[1])-1, parseInt(parts[0]))
                        }
                        calendarPopup.viewYear = endDate.getFullYear()
                        calendarPopup.viewMonth = endDate.getMonth()
                        calendarPopup.updateDaysModel()
                        calendarPopup.open()
                    }
                }
            }
            TextField {
                id: endTimeField
                Layout.fillWidth: true
                selectByMouse: true
                palette.highlight: "#00f5d4"
                palette.highlightedText: "#000000"
                enabled: !downloadDialog.isAnyDownloading()
            }
        }

        // Cameras List with fields
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Repeater {
                id: cameraRepeater
                model: downloadModel
                
                delegate: ColumnLayout {
                    id: rowLayout
                    Layout.fillWidth: true
                    spacing: 4
                    
                    HikvisionDownloader {
                        id: rowDownloader
                        onProgressChanged: {
                            model.progress = rowDownloader.progress
                            if (rowDownloader.isDownloading) {
                                model.statusText = "Pobieranie... " + rowDownloader.progress + "%"
                            }
                        }
                        onDownloadFinished: {
                            model.isDownloading = false
                            if (success) {
                                model.statusText = "Ukończono pomyślnie"
                            } else {
                                model.statusText = "Błąd: " + message
                            }
                        }
                    }
                    
                    function startRowDownload(recInfo, startDt, endDt) {
                        model.isDownloading = true
                        model.statusText = "Inicjalizacja..."
                        rowDownloader.startDownload(recInfo, model.channelId, startDt, endDt, model.savePath)
                    }
                    
                    function stopRowDownload() {
                        rowDownloader.stopDownload()
                        model.isDownloading = false
                        model.statusText = "Zatrzymano"
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        
                        CheckBox {
                            checked: model.downloadEnabled
                            onCheckedChanged: model.downloadEnabled = checked
                            enabled: !downloadDialog.isAnyDownloading()
                        }
                        
                        Text {
                            text: model.cameraName
                            color: "white"
                            font.bold: true
                            Layout.preferredWidth: 180
                            elide: Text.ElideRight
                        }
                        
                        TextField {
                            id: savePathInput
                            Layout.fillWidth: true
                            enabled: model.downloadEnabled && !downloadDialog.isAnyDownloading()
                            selectByMouse: true
                            palette.highlight: "#00f5d4"
                            palette.highlightedText: "#000000"
                            onTextEdited: model.savePath = text

                            Binding {
                                target: savePathInput
                                property: "text"
                                value: model.savePath
                                when: !savePathInput.activeFocus
                            }
                        }
                        
                        CctvButton {
                            text: "..."
                            Layout.preferredWidth: 36
                            enabled: model.downloadEnabled && !downloadDialog.isAnyDownloading()
                            onClicked: {
                                var p = model.savePath
                                if (p.indexOf("file://") !== 0) {
                                    p = "file://" + p
                                }
                                activeCameraIndex = index
                                fileDialog.currentFile = p
                                fileDialog.open()
                            }
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        visible: model.isDownloading || model.statusText !== ""
                        spacing: 10
                        
                        ProgressBar {
                            from: 0
                            to: 100
                            value: model.progress
                            Layout.fillWidth: true
                            visible: model.isDownloading
                        }
                        
                        Text {
                            text: model.statusText
                            color: model.statusText.indexOf("Błąd") !== -1 ? "#ff3b30" : (model.statusText.indexOf("Pobieranie") !== -1 ? "#8898a6" : "#00f5d4")
                            font.pixelSize: 11
                            Layout.fillWidth: !model.isDownloading
                            Layout.preferredWidth: model.isDownloading ? 120 : undefined
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.fillWidth: true } // Spacer

            CctvButton {
                text: qsTr("Anuluj")
                onClicked: {
                    downloadDialog.close()
                }
            }

            CctvButton {
                text: downloadDialog.isAnyDownloading() ? qsTr("Zatrzymaj") : qsTr("Pobierz")
                isPrimary: true
                enabled: downloadDialog.isAnyDownloading() || downloadDialog.isAnyEnabled()
                onClicked: {
                    if (downloadDialog.isAnyDownloading()) {
                        downloadDialog.stopAllDownloads()
                    } else {
                        downloadStarted()
                        
                        var startDt = downloadDialog.getStartDateTime()
                        var endDt = downloadDialog.getEndDateTime()
                        
                        for (var i = 0; i < cameraRepeater.count; i++) {
                            var modelItem = downloadModel.get(i)
                            if (modelItem.downloadEnabled) {
                                var delegateItem = cameraRepeater.itemAt(i)
                                if (delegateItem) {
                                     var recInfo = {
                                         "ip": modelItem.ip,
                                         "port": modelItem.port,
                                         "username": modelItem.username,
                                         "password": modelItem.password
                                     }
                                     var path = modelItem.savePath;
                                     var dirPath = path.substring(0, Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\")));
                                     if (dirPath !== "") {
                                         Context.mkpath(dirPath);
                                     }
                                     delegateItem.startRowDownload(recInfo, startDt, endDt)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Platform.FileDialog {
        id: fileDialog
        title: "Zapisz jako"
        fileMode: Platform.FileDialog.SaveFile
        nameFilters: ["Filmy MP4 (*.mp4)", "Wszystkie pliki (*)"]
        defaultSuffix: "mp4"
        folder: {
            if (typeof generalSettings !== "undefined" && generalSettings.videoPath !== "") {
                Context.mkpath(generalSettings.videoPath);
                return "file://" + generalSettings.videoPath;
            }
            var mLoc = Platform.StandardPaths.writableLocation(Platform.StandardPaths.MoviesLocation).toString();
            if (mLoc.indexOf("file://") === 0) mLoc = mLoc.substring(7);
            var defaultPath = mLoc + "/CCTV";
            Context.mkpath(defaultPath);
            return "file://" + defaultPath;
        }
        onAccepted: {
            var path = fileDialog.file.toString()
            if (path.indexOf("file://") === 0) {
                path = path.substring(7)
            }
            if (activeCameraIndex >= 0 && activeCameraIndex < downloadModel.count) {
                downloadModel.setProperty(activeCameraIndex, "savePath", path)
            }
        }
    }
}
