import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt.labs.settings 1.0
import CCTV_Viewer.Hikvision 1.0
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Themes 1.0

ColumnLayout {
    id: rootPanel

    spacing: 12
    Layout.fillWidth: true
    Layout.margins: 10

    // Persist active recorders in application settings as JSON
    // Format: [{"ip":"...", "port":8000, "username":"...", "password":"...", "cameras":[{"channelId":1, "name":"..."}]}]
    property var recorders: []

    // Map of active session IPs (IP -> bool)
    property var activeSessionIps: ({})

    // Live UX feedback state
    property string statusMessage: ""
    property string statusColor: "#ff7a00"

    // Track NVR editing state
    property int editingIndex: -1

    // ── NvrCamerasWindow Component ──────────────────────────────────────
    // Declared here (outside the Repeater) so its QML creation context
    // belongs to rootPanel, NOT to any Repeater delegate.  When the
    // Repeater rebuilds its delegates (e.g. after loadRecorders()),
    // already-opened NvrCamerasWindow instances keep a valid context
    // because rootPanel is never destroyed.
    Component {
        id: nvrCamerasWindowComponent
        NvrCamerasWindow {}
    }

    function openCamerasWindow(recorderData) {
        var win = nvrCamerasWindowComponent.createObject(rootWindow);
        win.recorder = JSON.parse(JSON.stringify(recorderData));
        win.show();
    }

    Component.onCompleted: {
        loadRecorders();
    }

    Connections {
        target: rootWindow
        onHikvisionRecordersJsonChanged: {
            rootPanel.loadRecorders();
        }
    }

    Connections {
        target: HikvisionManager
        function onSessionStatusChanged(ip, loggedIn) {
            var states = Object.assign({}, rootPanel.activeSessionIps);
            states[ip] = loggedIn;
            rootPanel.activeSessionIps = states;
        }
    }

    function initializeActiveSessions() {
        var states = {};
        for (var i = 0; i < recorders.length; i++) {
            var ip = recorders[i].ip;
            states[ip] = HikvisionManager.isLogged(ip);
        }
        activeSessionIps = states;
    }

    function loadRecorders() {
        try {
            var data = rootWindow.hikvisionRecordersJson;
            if (data) {
                recorders = JSON.parse(data);
            } else {
                recorders = [];
            }
            initializeActiveSessions();
        } catch(e) {
            console.log("[Hikvision QML Error] Failed to load recorders:", e);
            recorders = [];
        }
    }

    function saveRecorders() {
        try {
            rootWindow.hikvisionRecordersJson = JSON.stringify(recorders);
        } catch(e) {
            console.log("[Hikvision QML Error] Failed to save recorders:", e);
        }
    }

    Text {
        text: qsTr("Add Hikvision Recorder")
        color: "white"
        font {
            pixelSize: 13
            bold: true
        }
        Layout.fillWidth: true
    }

    Frame {
        Layout.fillWidth: true
        background: Rectangle {
            color: "#1c242c"
            radius: 6
            border.color: "#2a3540"
            border.width: 1
        }

        ColumnLayout {
            width: parent.width
            spacing: 8

            TextField {
                id: nameField
                placeholderText: qsTr("Recorder Name (optional)")
                selectByMouse: true
                Layout.fillWidth: true
                color: "white"
                background: Rectangle {
                    color: "#0f151b"
                    radius: 4
                    border.color: nameField.activeFocus ? "#ff7a00" : "#2a3540"
                }
                onTextChanged: rootPanel.statusMessage = ""
            }

            TextField {
                id: ipField
                placeholderText: qsTr("IP Address")
                selectByMouse: true
                Layout.fillWidth: true
                color: "white"
                background: Rectangle {
                    color: "#0f151b"
                    radius: 4
                    border.color: ipField.activeFocus ? "#ff7a00" : "#2a3540"
                }
                onTextChanged: rootPanel.statusMessage = ""
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: portField
                    placeholderText: qsTr("Port (8000)")
                    text: "8000"
                    selectByMouse: true
                    Layout.fillWidth: true
                    color: "white"
                    background: Rectangle {
                        color: "#0f151b"
                        radius: 4
                        border.color: portField.activeFocus ? "#ff7a00" : "#2a3540"
                    }
                    onTextChanged: rootPanel.statusMessage = ""
                }

                TextField {
                    id: userField
                    placeholderText: qsTr("Username")
                    text: "admin"
                    selectByMouse: true
                    Layout.fillWidth: true
                    color: "white"
                    background: Rectangle {
                        color: "#0f151b"
                        radius: 4
                        border.color: userField.activeFocus ? "#ff7a00" : "#2a3540"
                    }
                    onTextChanged: rootPanel.statusMessage = ""
                }
            }

            TextField {
                id: passField
                placeholderText: qsTr("Password")
                echoMode: TextInput.Password
                selectByMouse: true
                Layout.fillWidth: true
                color: "white"
                background: Rectangle {
                    color: "#0f151b"
                    radius: 4
                    border.color: passField.activeFocus ? "#ff7a00" : "#2a3540"
                }
                onTextChanged: rootPanel.statusMessage = ""
            }

            // Live status message feedback
            Text {
                text: rootPanel.statusMessage
                color: rootPanel.statusColor
                font.pixelSize: 10
                font.bold: true
                visible: text !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    id: addBtn
                    text: rootPanel.editingIndex === -1 ? qsTr("Connect & Discover") : qsTr("Save & Update")
                    Layout.fillWidth: true
                    highlighted: true

                    contentItem: Text {
                        text: addBtn.text
                        font.bold: true
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: addBtn.pressed ? "#d66600" : (addBtn.hovered ? "#ff8c00" : "#ff7a00")
                        radius: 4
                    }

                    onClicked: {
                        if (ipField.text === "" || passField.text === "") {
                            rootPanel.statusColor = "#ff3333";
                            rootPanel.statusMessage = qsTr("Error: IP and Password are required.");
                            return;
                        }

                        var ip = ipField.text;
                        var port = parseInt(portField.text) || 8000;
                        var user = userField.text;
                        var pass = passField.text;

                        rootPanel.statusColor = "#00f5d4"; // Cyan glowing text for loading
                        rootPanel.statusMessage = qsTr("Connecting to NVR and discovering channels...");

                        // Log in and fetch camera channels from NVR
                        var cameras = HikvisionManager.discoverCameras(ip, port, user, pass);
                        if (cameras.length === 0) {
                            rootPanel.statusColor = "#ff3333";
                            rootPanel.statusMessage = qsTr("Login failed or no cameras discovered.");
                            return;
                        }

                        var newRecorder = {
                            name: nameField.text.trim(),
                            ip: ip,
                            port: port,
                            username: user,
                            password: pass,
                            cameras: cameras
                        };

                        if (rootPanel.editingIndex === -1) {
                            // ADD MODE
                            var arr = rootPanel.recorders.slice();
                            // Check if already added
                            for (var idx = 0; idx < arr.length; idx++) {
                                if (arr[idx].ip === ip) {
                                    arr.splice(idx, 1); // overwrite
                                    break;
                                }
                            }

                            arr.push(newRecorder);
                            rootPanel.recorders = arr;
                            saveRecorders();

                            // Generate a dynamic preset layout containing all discovered cameras
                            var numCams = cameras.length;
                            var gridSize = Math.ceil(Math.sqrt(numCams));
                            
                            var newLayout = layoutsCollectionModel.append();
                            newLayout.size = Qt.size(gridSize, gridSize);
                            newLayout.isNvr = true;
                            newLayout.nvrIp = ip;

                            for (var i = 0; i < numCams; ++i) {
                                var vp = newLayout.get(i);
                                if (vp) {
                                    // Store Hikvision URI
                                    vp.url = "hikvision://" + user + ":" + pass + "@" + ip + ":" + port + "/" + cameras[i].channelId;
                                    vp.secondaryUrl = vp.url;
                                    vp.volume = 0;
                                }
                            }

                            // Force navigation to the newly created preset!
                            stackLayout.currentIndex = layoutsCollectionModel.count - 1;

                        } else {
                            // EDIT MODE
                            var arr = rootPanel.recorders.slice();
                            var oldIp = arr[rootPanel.editingIndex].ip;
                            arr[rootPanel.editingIndex] = newRecorder;
                            rootPanel.recorders = arr;
                            saveRecorders();

                            // Update corresponding NVR view layout
                            for (var j = 0; j < layoutsCollectionModel.count; ++j) {
                                var l = layoutsCollectionModel.get(j);
                                if (l && l.isNvr && l.nvrIp === oldIp) {
                                    l.nvrIp = ip;
                                    var numCams = cameras.length;
                                    var gridSize = Math.ceil(Math.sqrt(numCams));
                                    l.size = Qt.size(gridSize, gridSize);

                                    for (var k = 0; k < numCams; ++k) {
                                        var vp = l.get(k);
                                        if (vp) {
                                            vp.url = "hikvision://" + user + ":" + pass + "@" + ip + ":" + port + "/" + cameras[k].channelId;
                                            vp.secondaryUrl = vp.url;
                                            vp.volume = 0;
                                        }
                                    }
                                    break;
                                }
                            }
                            rootPanel.editingIndex = -1;
                        }

                         // Clear fields & status
                        nameField.text = "";
                        ipField.text = "";
                        portField.text = "8000";
                        userField.text = "admin";
                        passField.text = "";
                        rootPanel.statusMessage = "";
                    }
                }

                Button {
                    id: cancelBtn
                    text: qsTr("Cancel")
                    visible: rootPanel.editingIndex !== -1
                    implicitWidth: 80
                    Layout.fillHeight: true

                    contentItem: Text {
                        text: cancelBtn.text
                        font.bold: true
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: cancelBtn.pressed ? "#404040" : (cancelBtn.hovered ? "#505050" : "#303030")
                        radius: 4
                    }

                    onClicked: {
                        rootPanel.editingIndex = -1;
                        nameField.text = "";
                        ipField.text = "";
                        portField.text = "8000";
                        userField.text = "admin";
                        passField.text = "";
                        rootPanel.statusMessage = "";
                    }
                }
            }
        }
    }

    Text {
        text: qsTr("Connected Recorders")
        color: "white"
        font {
            pixelSize: 13
            bold: true
        }
        Layout.fillWidth: true
        visible: rootPanel.recorders.length > 0
    }

    ColumnLayout {
        id: recordersListColumn
        Layout.fillWidth: true
        spacing: 6
        visible: rootPanel.recorders.length > 0

        Repeater {
            model: rootPanel.recorders
            delegate: Rectangle {
                Layout.fillWidth: true
                height: 38
                color: "#1c242c"
                radius: 4
                border.color: "#2a3540"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true

                        Text {
                            text: modelData.name ? modelData.name + " (" + modelData.ip + ")" : modelData.ip
                            color: "white"
                            font.bold: true
                            font.pixelSize: 11
                        }
                        Text {
                            text: qsTr("%1 cameras connected").arg(modelData.cameras ? modelData.cameras.length : 0)
                            color: "#8898a6"
                            font.pixelSize: 9
                        }
                    }

                    MouseArea {
                        id: statusArea
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                        implicitWidth: statusLayout.implicitWidth
                        implicitHeight: statusLayout.implicitHeight
                        hoverEnabled: true

                        RowLayout {
                            id: statusLayout
                            anchors.fill: parent
                            spacing: 6

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                antialiasing: true
                                color: (rootPanel.activeSessionIps[modelData.ip] || false) ? "#00ff66" : "#ff3333"
                            }

                            Text {
                                text: (rootPanel.activeSessionIps[modelData.ip] || false) ? qsTr("LOGGED IN") : qsTr("NOT LOGGED IN")
                                color: (rootPanel.activeSessionIps[modelData.ip] || false) ? "#00ff66" : "#ff3333"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }

                        ToolTip {
                            delay: Compact.toolTipDelay
                            timeout: Compact.toolTipTimeout
                            visible: statusArea.containsMouse
                            text: qsTr("Green: Active SDK session (PTZ/Archive). Red: No active session (RTSP stream works independently).")
                        }
                    }

                    Button {
                        id: listBtn
                        implicitWidth: 30
                        implicitHeight: 30
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: {
                                var colorStr = listBtn.hovered ? "%2300f5d4" : "%238898a6";
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='3' width='20' height='14' rx='2' ry='2'></rect><line x1='8' y1='21' x2='16' y2='21'></line><line x1='12' y1='17' x2='12' y2='21'></line></svg>";
                            }
                        }

                        background: Rectangle {
                            color: listBtn.pressed ? "#cc121214" : (listBtn.hovered ? "#3a4550" : "#1c242c")
                            radius: 15
                            border.color: listBtn.hovered ? "#00f5d4" : "#2a3540"
                            border.width: 1
                        }

                        onClicked: {
                            rootPanel.openCamerasWindow(modelData);
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: listBtn.hovered
                        ToolTip.text: qsTr("Pokaż listę kamer rejestratora")
                    }

                    Button {
                        id: editBtn
                        implicitWidth: 30
                        implicitHeight: 30
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: {
                                var colorStr = editBtn.hovered ? "%23ff7a00" : "%238898a6";
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='16 3 21 8 8 21 3 21 3 16 16 3'></polygon></svg>";
                            }
                        }

                        background: Rectangle {
                            color: editBtn.pressed ? "#cc121214" : (editBtn.hovered ? "#3a4550" : "#1c242c")
                            radius: 15
                            border.color: editBtn.hovered ? "#ff7a00" : "#2a3540"
                            border.width: 1
                        }

                        onClicked: {
                            // Populate input fields for editing
                            nameField.text = modelData.name || "";
                            ipField.text = modelData.ip;
                            portField.text = modelData.port;
                            userField.text = modelData.username;
                            passField.text = modelData.password;
                            rootPanel.editingIndex = index;
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: editBtn.hovered
                        ToolTip.text: qsTr("Edytuj dane połączenia rejestratora")
                    }

                    Button {
                        id: delBtn
                        implicitWidth: 30
                        implicitHeight: 30
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: {
                                var colorStr = delBtn.hovered ? "%23ff4d4d" : "%238898a6";
                                return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + colorStr + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polyline points='3 6 5 6 21 6'></polyline><path d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'></path><line x1='10' y1='11' x2='10' y2='17'></line><line x1='14' y1='11' x2='14' y2='17'></line></svg>";
                            }
                        }

                        background: Rectangle {
                            color: delBtn.pressed ? "#cc121214" : (delBtn.hovered ? "#3a4550" : "#1c242c")
                            radius: 15
                            border.color: delBtn.hovered ? "#ff4d4d" : "#2a3540"
                            border.width: 1
                        }

                        onClicked: {
                            deleteConfirmDialog1.targetIndex = index;
                            deleteConfirmDialog1.targetIp = modelData.ip;
                            deleteConfirmDialog1.open();
                        }

                        ToolTip.delay: Compact.toolTipDelay
                        ToolTip.timeout: Compact.toolTipTimeout
                        ToolTip.visible: delBtn.hovered
                        ToolTip.text: qsTr("Usuń rejestrator z listy")
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: deleteConfirmDialog1
        title: qsTr("Confirm NVR Deletion")
        iconSource: "qrc:/images/icon-warning.svg"
        message: qsTr("Are you sure you want to delete this NVR?")
        property int targetIndex: -1
        property string targetIp: ""
        
        onAccepted: {
            deleteConfirmDialog2.targetIndex = targetIndex;
            deleteConfirmDialog2.targetIp = targetIp;
            deleteConfirmDialog2.open();
        }
    }

    ConfirmDialog {
        id: deleteConfirmDialog2
        title: qsTr("Warning!")
        iconSource: "qrc:/images/icon-warning.svg"
        message: qsTr("Are you absolutely sure and aware of what you are doing?")
        property int targetIndex: -1
        property string targetIp: ""
        
        onAccepted: {
            if (targetIndex >= 0 && targetIndex < rootPanel.recorders.length) {
                HikvisionManager.logout(targetIp);
                
                // Remove from active recorders list
                var arr = rootPanel.recorders.slice();
                arr.splice(targetIndex, 1);
                rootPanel.recorders = arr;
                rootPanel.saveRecorders();

                // Automatically remove corresponding NVR view layout(s)
                for (var j = layoutsCollectionModel.count - 1; j >= 0; --j) {
                    var l = layoutsCollectionModel.get(j);
                    if (l && l.isNvr && l.nvrIp === targetIp) {
                        layoutsCollectionModel.remove(j);
                    }
                }
            }
        }
    }
}
