import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    // Managed by the ilko daemon — not exposed in plugin config UI
    property string cfg_wallpaperFile
    property bool   cfg_playerPaused: false
    property real   cfg_playerRate: 1.0

    // Rendering settings — visible in plugin config
    property alias cfg_backgroundColor: colorButton.color
    property string cfg_fillMode
    property alias fillModeIndex: fillModeCombo.currentIndex

    Kirigami.FormLayout {
        Layout.fillWidth: true

        Label {
            Layout.fillWidth: true
            text: "Wallpaper and switching settings are managed by the ilko app."
            font.italic: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
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
    }

    ColorDialog {
        id: colorDialog
        selectedColor: colorButton.color
        onAccepted: colorButton.color = selectedColor
    }

    Item { Layout.fillHeight: true }
}
