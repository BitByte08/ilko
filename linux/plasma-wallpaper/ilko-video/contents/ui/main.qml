import QtQuick
import QtMultimedia
import QtCore
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    property string wallpaperSource: root.configuration.wallpaperFile || ""
    property int lastTimestamp: 0
    property bool onBattery: false
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

    // Combined poller: wallpaper changes + battery state
    Timer {
        id: poller
        interval: 2000
        running: true
        repeat: true
        onTriggered: { checkCurrentWallpaper(); checkBatteryState(); }
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

    function checkBatteryState() {
        var path = StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.ilko/battery_state.json"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText !== "") {
                try {
                    var data = JSON.parse(xhr.responseText)
                    root.onBattery = !data.charging
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + path)
        xhr.send()
    }

    // Pause video when on battery and cfg_pauseOnBattery is enabled
    readonly property bool shouldPause: root.configuration.pauseOnBattery && root.onBattery

    onShouldPauseChanged: {
        if (shouldPause) mediaPlayer.pause()
        else if (isVideo && mediaPlayer.playbackState !== MediaPlayer.PlayingState) mediaPlayer.play()
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
        // No AudioOutput — wallpaper audio is always disabled, skipping audio decode saves CPU
        source: isVideo ? wallpaperSource : ""
        loops: MediaPlayer.Infinite
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && !root.shouldPause) {
                mediaPlayer.play()
            }
        }
        onErrorOccurred: function(e, msg) { console.log("ILKO MediaPlayer error:", msg) }
    }

    Image {
        anchors.fill: parent
        source: !isVideo && wallpaperSource ? "file://" + wallpaperSource : ""
        fillMode: root.imageFillModeMap[root.configuration.fillMode] || Image.PreserveAspectCrop
        visible: !isVideo && wallpaperSource !== ""
    }

    Component.onCompleted: {
        checkCurrentWallpaper()
        checkBatteryState()
        console.log("ILKO wallpaper plugin started, source:", wallpaperSource)
    }
}
