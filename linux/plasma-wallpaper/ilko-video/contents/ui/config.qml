import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string cfg_wallpaperFile
    property alias cfg_backgroundColor: colorButton.color

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
                onClicked: {
                    root.cfg_wallpaperFile = ""
                }
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
            if (path.startsWith("file://")) {
                path = path.substring(7)
            }
            root.cfg_wallpaperFile = path
        }
    }

    ColorDialog {
        id: colorDialog
        selectedColor: colorButton.color
        onAccepted: {
            colorButton.color = selectedColor
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
