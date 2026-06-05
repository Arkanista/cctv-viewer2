import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import Qt.labs.settings 1.0
import CCTV_Viewer.Hikvision 1.0
import CCTV_Viewer.Utils 1.0

ColumnLayout {
    id: rootPanel

    spacing: 12
    Layout.fillWidth: true
    Layout.margins: 10

    // Persist active recorders in application settings as JSON
    // Format: [{"ip":"...", "port":8000, "username":"...", "password":"...", "cameras":[{"channelId":1, "name":"..."}]}]
    property var recorders: []

    // Live UX feedback state
    property string statusMessage: ""
    property string statusColor: "#ff7a00"

    // Track NVR editing state
    property int editingIndex: -1

    Component.onCompleted: {
        loadRecorders();
    }

    Connections {
        target: rootWindow
        onHikvisionRecordersJsonChanged: {
            rootPanel.loadRecorders();
        }
    }

    function loadRecorders() {
        try {
            var data = rootWindow.hikvisionRecordersJson;
            if (data) {
                recorders = JSON.parse(data);
            } else {
                recorders = [];
            }
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

                    Button {
                        id: listBtn
                        text: "📺"
                        implicitWidth: 32
                        implicitHeight: 32
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Text {
                            text: listBtn.text
                            font.pixelSize: 16
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: listBtn.pressed ? "#4000f5d4" : (listBtn.hovered ? "#2000f5d4" : "transparent")
                            radius: 4
                            border.color: listBtn.hovered ? "#00f5d4" : "transparent"
                        }

                        onClicked: {
                            var component = Qt.createComponent("NvrCamerasWindow.qml");
                            if (component.status === Component.Ready) {
                                var win = component.createObject(rootWindow, { "recorder": modelData });
                                win.show();
                            } else {
                                console.log("Error loading NvrCamerasWindow:", component.errorString());
                            }
                        }
                    }

                    Button {
                        id: editBtn
                        text: "✏️"
                        implicitWidth: 32
                        implicitHeight: 32
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Text {
                            text: editBtn.text
                            font.pixelSize: 16
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: editBtn.pressed ? "#4000ff00" : (editBtn.hovered ? "#2000ff00" : "transparent")
                            radius: 4
                            border.color: editBtn.hovered ? "#00ff00" : "transparent"
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
                    }

                    Button {
                        id: delBtn
                        text: "🗑️"
                        implicitWidth: 32
                        implicitHeight: 32
                        Layout.alignment: Qt.AlignVCenter

                        contentItem: Text {
                            text: delBtn.text
                            font.pixelSize: 16
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: delBtn.pressed ? "#40ff0000" : (delBtn.hovered ? "#20ff0000" : "transparent")
                            radius: 4
                            border.color: delBtn.hovered ? "#ff0000" : "transparent"
                        }

                        onClicked: {
                            HikvisionManager.logout(modelData.ip);
                            
                            // Remove from active recorders list
                            var arr = rootPanel.recorders.slice();
                            arr.splice(index, 1);
                            rootPanel.recorders = arr;
                            rootPanel.saveRecorders();

                            // Automatically remove corresponding NVR view layout(s)
                            for (var j = layoutsCollectionModel.count - 1; j >= 0; --j) {
                                var l = layoutsCollectionModel.get(j);
                                if (l && l.isNvr && l.nvrIp === modelData.ip) {
                                    layoutsCollectionModel.remove(j);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
