import QtQuick
import QtMultimedia
import QtCore
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    property string wallpaperSource: root.configuration.wallpaperFile || ""
    property int lastTimestamp: 0
    property bool isVideo: {
        var f = wallpaperSource
        if (!f || f === "") return false
        var ext = f.split('.').pop().toLowerCase()
        return ["mp4", "webm", "mov", "avi", "mkv"].indexOf(ext) !== -1
    }

    property var fillModeMap: ({
        "preserveAspectFit": VideoOutput.PreserveAspectFit,
        "stretch": VideoOutput.Stretch,
        "preserveAspectCrop": VideoOutput.PreserveAspectCrop
    })

    property var imageFillModeMap: ({
        "preserveAspectFit": Image.PreserveAspectFit,
        "stretch": Image.Stretch,
        "preserveAspectCrop": Image.PreserveAspectCrop
    })

    // Poll ~/.ilko/current_wallpaper.json to receive daemon-driven wallpaper changes
    Timer {
        id: wallpaperPoller
        interval: 2000
        running: true
        repeat: true
        onTriggered: checkCurrentWallpaper()
    }

    function checkCurrentWallpaper() {
        var path = StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.ilko/current_wallpaper.json"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText !== "") {
                try {
                    var data = JSON.parse(xhr.responseText)
                    var ts = data.timestamp || 0
                    if (ts !== root.lastTimestamp && data.wallpaperFile) {
                        root.lastTimestamp = ts
                        root.wallpaperSource = data.wallpaperFile
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + path)
        xhr.send()
    }

    Rectangle {
        anchors.fill: parent
        color: root.configuration.backgroundColor || "#000000"
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: root.fillModeMap[root.configuration.fillMode] || VideoOutput.PreserveAspectCrop
        visible: isVideo
    }

    MediaPlayer {
        id: mediaPlayer
        videoOutput: videoOutput
        audioOutput: audioOutput
        source: isVideo ? wallpaperSource : ""
        loops: MediaPlayer.Infinite
        playbackRate: root.configuration.playbackRate || 1.0
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) mediaPlayer.play()
        onErrorOccurred: function(e, msg) { console.log("ILKO MediaPlayer error:", msg) }
    }

    AudioOutput {
        id: audioOutput
        muted: true
    }

    Image {
        anchors.fill: parent
        source: !isVideo && wallpaperSource ? "file://" + wallpaperSource : ""
        fillMode: root.imageFillModeMap[root.configuration.fillMode] || Image.PreserveAspectCrop
        visible: !isVideo && wallpaperSource !== ""
    }

    Component.onCompleted: {
        checkCurrentWallpaper()
        console.log("ILKO wallpaper plugin started, source:", wallpaperSource)
    }
}
