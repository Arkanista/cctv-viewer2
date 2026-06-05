import QtQuick 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import QtQuick.Dialogs 1.3
import CCTV_Viewer.Utils 1.0
import CCTV_Viewer.Core 1.0

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

    ColumnLayout {
        anchors.fill: parent

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
}
