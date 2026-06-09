import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import QtQuick.Dialogs 1.3
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Core 1.0
import Qt.labs.platform 1.1 as Platform

Dialog {
    title: qsTr("Settings")
    modality: Qt.ApplicationModal
    standardButtons: StandardButton.Ok | StandardButton.Cancel

    onVisibleChanged: {
        if (visible) {
            loadSettings();
        }
    }
    onAccepted: saveSettings()

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: parent.width

        ColumnLayout {
            width: parent.width
            spacing: 12

        GroupBox {
            title: qsTr("General")

            Layout.fillWidth: true

            ColumnLayout {

                width: parent.width

                CheckBox {
                    id: singleApplicationCheckBox
                    enabled: false
                    text: qsTr("Allow running multiple application instances")
                }

                CheckBox {
                    id: sidebarAutoCollapseCheckBox

                    text: qsTr("Automatically collapse sidebar") 
                }

                CheckBox {
                    id: allowSwappingViewportsCheckBox

                    text: qsTr("Allow swapping viewport places")
                }

                CheckBox {
                    id: enableChangeViewportSettingsCheckBox

                    text: qsTr("Allow changing viewport settings")
                }

                CheckBox {
                    id: enableStreamSelectionCheckBox

                    text: qsTr("Enable stream selection")
                }
            }
        }

        GroupBox {
            title: qsTr("View")

            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: 12

                CheckBox {
                    id: hideCursorWhenFullScreenCheckBox

                    text: qsTr("Hide cursor in full screen mode")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: qsTr("Language:")
                    }

                    ComboBox {
                        id: languageComboBox
                        Layout.fillWidth: true
                        model: [
                            { text: qsTr("System default"), value: "system" },
                            { text: "English", value: "en" },
                            { text: "Polski", value: "pl" }
                        ]
                        textRole: "text"

                        background: Rectangle {
                            implicitHeight: 32
                            color: "#151d24"
                            border.color: languageComboBox.activeFocus ? "#ff7a00" : "#3a4550"
                            border.width: 1
                            radius: 6
                        }

                        contentItem: Text {
                            text: languageComboBox.displayText
                            color: "#eeeeee"
                            font {
                                pixelSize: 11
                                bold: true
                            }
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                        }

                        delegate: ItemDelegate {
                            width: languageComboBox.width
                            height: 32
                            contentItem: Text {
                                text: modelData.text
                                color: hovered ? "#00f5d4" : "#eeeeee"
                                font {
                                    pixelSize: 11
                                    bold: true
                                }
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                            }
                            background: Rectangle {
                                color: hovered ? "#2a3540" : "transparent"
                                border.color: hovered ? "#00f5d4" : "transparent"
                                border.width: 1
                                radius: 4
                            }
                        }

                        popup: Popup {
                            y: languageComboBox.height + 2
                            width: languageComboBox.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 4

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: languageComboBox.popup.visible ? languageComboBox.delegateModel : null
                                currentIndex: languageComboBox.highlightedIndex

                                ScrollIndicator.vertical: ScrollIndicator { }
                            }

                            background: Rectangle {
                                color: "#151d24"
                                border.color: "#ff7a00"
                                border.width: 1
                                radius: 6
                            }
                        }
                    }
                }
            }
        }



        GroupBox {
            title: qsTr("Presets")

            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width

                RowLayout  {
                    width: parent.width

                    CheckBox {
                        id: carouselRunningCheckBox

                        text: qsTr("Run presets carousel with interval (sec.):")

                        Layout.fillWidth: true
                    }

                    SpinBox {
                        id: carouselIntervalSpinBox

                        property int valueFactor: 1000

                        enabled: carouselRunningCheckBox.checked

                        stepSize: 100
                        from: stepSize
                        to: 300 * stepSize
                        editable: true

                        validator: DoubleValidator {
                            decimals: 2
                            bottom: Math.min(carouselIntervalSpinBox.from, carouselIntervalSpinBox.to)
                            top:  Math.max(carouselIntervalSpinBox.from, carouselIntervalSpinBox.to)
                        }
                        textFromValue: function(value, locale) {
                            return Number(value / valueFactor).toLocaleString(locale, 'f', validator.decimals)
                        }
                        valueFromText: function(text, locale) {
                            return Number.fromLocaleString(locale, text) * valueFactor
                        }
                    }
                }
            }
        }

        GroupBox {
            title: qsTr("Zapis")
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: 12

                Text {
                    text: qsTr("Domyślna ścieżka stopklatek:")
                    color: "#eeeeee"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    TextField {
                        id: snapshotPathField
                        Layout.fillWidth: true
                        selectByMouse: true
                    }
                    Button {
                        text: "..."
                        onClicked: {
                            var path = snapshotPathField.text;
                            var folderUrl = Context.dirExists(path) ? Context.pathToUrl(path) : Context.pathToUrl(Context.homePath());
                            snapshotFolderDialog.folder = folderUrl;
                            snapshotFolderDialog.currentFolder = folderUrl;
                            snapshotFolderDialog.open();
                        }
                    }
                }

                Text {
                    text: qsTr("Domyślna ścieżka nagrań:")
                    color: "#eeeeee"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    TextField {
                        id: videoPathField
                        Layout.fillWidth: true
                        selectByMouse: true
                    }
                    Button {
                        text: "..."
                        onClicked: {
                            var path = videoPathField.text;
                            var folderUrl = Context.dirExists(path) ? Context.pathToUrl(path) : Context.pathToUrl(Context.homePath());
                            videoFolderDialog.folder = folderUrl;
                            videoFolderDialog.currentFolder = folderUrl;
                            videoFolderDialog.open();
                        }
                    }
                }
            }
        }
    }
}

    function loadSettings() {
        singleApplicationCheckBox.checked = !generalSettings.singleApplication;
        
        sidebarAutoCollapseCheckBox.checked = rootWindowSettings.sidebarAutoCollapse;
        
        allowSwappingViewportsCheckBox.checked = generalSettings.allowSwappingViewports;

        enableChangeViewportSettingsCheckBox.checked = generalSettings.enableChangeViewportSettings;
        
        enableStreamSelectionCheckBox.checked = generalSettings.enableStreamSelection;
        
        hideCursorWhenFullScreenCheckBox.checked = viewSettings.hideCursorWhenFullScreen;

        carouselRunningCheckBox.checked = presetsSettings.carouselRunning;
        carouselIntervalSpinBox.value = presetsSettings.carouselInterval;

        var snapPath = generalSettings.snapshotPath;
        if (snapPath === "") {
            var picLoc = Platform.StandardPaths.writableLocation(Platform.StandardPaths.PicturesLocation).toString();
            if (picLoc.indexOf("file://") === 0) picLoc = picLoc.substring(7);
            snapPath = picLoc + "/CCTV";
        }
        Context.mkpath(snapPath);
        snapshotPathField.text = snapPath;

        var vidPath = generalSettings.videoPath;
        if (vidPath === "") {
            var movLoc = Platform.StandardPaths.writableLocation(Platform.StandardPaths.MoviesLocation).toString();
            if (movLoc.indexOf("file://") === 0) movLoc = movLoc.substring(7);
            vidPath = movLoc + "/CCTV";
        }
        Context.mkpath(vidPath);
        videoPathField.text = vidPath;

        var lang = Context.getLanguage();
        for (var i = 0; i < languageComboBox.model.length; ++i) {
            if (languageComboBox.model[i].value === lang) {
                languageComboBox.currentIndex = i;
                break;
            }
        }
    }

    function saveSettings() {
        generalSettings.singleApplication = !singleApplicationCheckBox.checked;
        
        rootWindowSettings.sidebarAutoCollapse = sidebarAutoCollapseCheckBox.checked;
        
        generalSettings.allowSwappingViewports = allowSwappingViewportsCheckBox.checked;

        generalSettings.enableChangeViewportSettings = enableChangeViewportSettingsCheckBox.checked;
        
        generalSettings.enableStreamSelection = enableStreamSelectionCheckBox.checked;
        
        viewSettings.hideCursorWhenFullScreen = hideCursorWhenFullScreenCheckBox.checked;

        presetsSettings.carouselRunning = carouselRunningCheckBox.checked;
        presetsSettings.carouselInterval = carouselIntervalSpinBox.value;

        generalSettings.snapshotPath = snapshotPathField.text;
        generalSettings.videoPath = videoPathField.text;
        Context.mkpath(snapshotPathField.text);
        Context.mkpath(videoPathField.text);

        var selectedLang = languageComboBox.model[languageComboBox.currentIndex].value;
        Context.setLanguage(selectedLang);
    }

    Connections {
        target: Context
        onLanguageChanged: {
            var lang = Context.getLanguage();
            for (var i = 0; i < languageComboBox.model.length; ++i) {
                if (languageComboBox.model[i].value === lang) {
                    languageComboBox.currentIndex = i;
                    break;
                }
            }
        }
    }

    Platform.FolderDialog {
        id: snapshotFolderDialog
        title: qsTr("Wybierz folder dla stopklatek")
        options: Platform.FolderDialog.DontUseNativeDialog
        onAccepted: {
            var path = snapshotFolderDialog.folder.toString();
            if (path.indexOf("file://") === 0) path = path.substring(7);
            if (path.length > 1 && (path.endsWith("/") || path.endsWith("\\"))) {
                path = path.substring(0, path.length - 1);
            }
            snapshotPathField.text = path;
        }
    }

    Platform.FolderDialog {
        id: videoFolderDialog
        title: qsTr("Wybierz folder dla nagrań")
        options: Platform.FolderDialog.DontUseNativeDialog
        onAccepted: {
            var path = videoFolderDialog.folder.toString();
            if (path.indexOf("file://") === 0) path = path.substring(7);
            if (path.length > 1 && (path.endsWith("/") || path.endsWith("\\"))) {
                path = path.substring(0, path.length - 1);
            }
            videoPathField.text = path;
        }
    }
}
