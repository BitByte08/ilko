import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.wallpapers.image as Wallpaper

WallpaperItem {
    id: root

    // Background
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // Image wallpaper
    Image {
        anchors.fill: parent
        source: root.configuration.wallpaperFile 
                ? ("file://" + root.configuration.wallpaperFile) 
                : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
    }

    // Debug text
    Text {
        anchors.centerIn: parent
        color: "#ffffff"
        font.pixelSize: 20
        text: {
            var path = root.configuration.wallpaperFile || ""
            return path === "" ? "No wallpaper set" : "File: " + path
        }
    }

    onConfigurationChanged: {
        // Configuration changed, image will auto-update
    }
}
