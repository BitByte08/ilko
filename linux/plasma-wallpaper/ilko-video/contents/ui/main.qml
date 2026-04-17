import QtQuick
import QtMultimedia
import QtCore
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    // Daemon JSON is authoritative; do not init from Plasma's own config.
    // pollWallpaper() on Component.onCompleted will set the correct value.
    property string wallpaperSource: ""
    property int lastTimestamp: 0
    property bool playerPaused: false
    property double playerRate: 1.0
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

    // Poll daemon-written control files every 2 seconds
    Timer {
        id: poller
        interval: 2000
        running: true
        repeat: true
        onTriggered: { pollWallpaper(); pollPlayerControl(); }
    }

    function pollWallpaper() {
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

    function pollPlayerControl() {
        var path = StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.ilko/player_control.json"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText !== "") {
                try {
                    var data = JSON.parse(xhr.responseText)
                    root.playerPaused = data.paused || false
                    root.playerRate = data.playbackRate || 1.0
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + path)
        xhr.send()
    }

    onPlayerPausedChanged: applyPlayerState()
    onPlayerRateChanged:   applyPlayerState()

    function applyPlayerState() {
        if (!isVideo) return
        mediaPlayer.playbackRate = root.playerRate
        if (root.playerPaused) {
            mediaPlayer.pause()
        } else if (mediaPlayer.playbackState !== MediaPlayer.PlayingState) {
            mediaPlayer.play()
        }
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
        // No AudioOutput — skipping audio decode saves CPU (wallpaper audio is always silent)
        source: isVideo ? wallpaperSource : ""
        loops: MediaPlayer.Infinite
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && !root.playerPaused) {
                mediaPlayer.playbackRate = root.playerRate
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
        pollWallpaper()
        pollPlayerControl()
        console.log("ILKO wallpaper plugin started, source:", wallpaperSource)
    }
}
