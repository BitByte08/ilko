import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string cfg_wallpaperFile
    property alias cfg_backgroundColor: colorButton.color
    property alias cfg_playbackRate: playbackRateSlider.value
    property alias cfg_volume: volumeSlider.value
    property string cfg_fillMode
    property alias fillModeIndex: fillModeCombo.currentIndex
    property alias cfg_pauseOnBattery: pauseOnBatteryCheck.checked
    property alias cfg_pauseOnFullscreen: pauseOnFullscreenCheck.checked

    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: "Wallpaper file:"

            TextField {
                id: filePathField
                text: root.cfg_wallpaperFile
                Layout.fillWidth: true
                readOnly: true
                placeholderText: "Select a video or image file..."
            }

            Button {
                icon.name: "document-open"
                text: "Browse..."
                onClicked: fileDialog.open()
            }

            Button {
                icon.name: "edit-clear"
                text: "Clear"
                onClicked: root.cfg_wallpaperFile = ""
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Background color:"

            Button {
                id: colorButton
                property color color: "#000000"
                onClicked: colorDialog.open()

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        Layout.preferredWidth: colorButton.height * 0.5
                        Layout.preferredHeight: colorButton.height * 0.5
                        radius: width / 2
                        color: colorButton.color
                        border.width: 1
                        border.color: Kirigami.Theme.textColor
                    }
                    Label {
                        text: "Choose Color"
                        color: Kirigami.Theme.buttonTextColor
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Playback speed:"

            Slider {
                id: playbackRateSlider
                from: 0.25
                to: 2.0
                stepSize: 0.25
                Layout.fillWidth: true
                value: 1.0
            }
            Label {
                text: playbackRateSlider.value.toFixed(2) + "x"
                Layout.minimumWidth: 40
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Volume:"

            Slider {
                id: volumeSlider
                from: 0.0
                to: 1.0
                stepSize: 0.1
                Layout.fillWidth: true
                value: 0.0
            }
            Label {
                text: Math.round(volumeSlider.value * 100) + "%"
                Layout.minimumWidth: 40
            }
        }

        ComboBox {
            id: fillModeCombo
            Kirigami.FormData.label: "Fill mode:"
            model: ["preserveAspectCrop", "preserveAspectFit", "stretch"]
            currentIndex: {
                var idx = model.indexOf(root.cfg_fillMode)
                return idx >= 0 ? idx : 0
            }
            onCurrentIndexChanged: root.cfg_fillMode = model[currentIndex]
        }

        CheckBox {
            id: pauseOnBatteryCheck
            Kirigami.FormData.label: "Pause on battery:"
            checked: true
            text: "Pause video when on battery power"
        }

        CheckBox {
            id: pauseOnFullscreenCheck
            Kirigami.FormData.label: "Pause on fullscreen:"
            checked: true
            text: "Pause video when a fullscreen app is active"
        }

        Label {
            Layout.fillWidth: true
            text: "Supported formats: MP4, WebM, MOV, AVI, MKV, M4V, FLV, WMV, and common image formats (JPG, PNG, etc.)"
            font.italic: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
        }
    }

    FileDialog {
        id: fileDialog
        title: "Select Wallpaper File"
        nameFilters: [
            "Media Files (*.mp4 *.webm *.mov *.avi *.mkv *.m4v *.flv *.wmv *.jpg *.jpeg *.png *.bmp *.webp *.gif *.svg *.tiff)",
            "Video Files (*.mp4 *.webm *.mov *.avi *.mkv *.m4v *.flv *.wmv)",
            "Image Files (*.jpg *.jpeg *.png *.bmp *.webp *.gif *.svg *.tiff)",
            "All Files (*)"
        ]
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file://")) path = path.substring(7)
            root.cfg_wallpaperFile = path
        }
    }

    ColorDialog {
        id: colorDialog
        selectedColor: colorButton.color
        onAccepted: colorButton.color = selectedColor
    }

    Item { Layout.fillHeight: true }
}