import QtQuick
import QtMultimedia
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    // Daemon pushes wallpaperFile to Plasma config via PlasmaShell.evaluateScript.
    // Reading root.configuration.*  requires no env vars or XHR.
    property string wallpaperSource: {
        var f = root.configuration.wallpaperFile || ""
        if (!f) return ""
        // Ensure file:// URL with encoded special chars ({} in UUIDs)
        return f.startsWith("file://") ? f : encodeURI("file://" + f)
    }

    property bool playerPaused: root.configuration.playerPaused  || false
    property double playerRate:  root.configuration.playerRate    || 1.0

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
        // No AudioOutput — skipping audio decode saves CPU
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
        source: !isVideo && wallpaperSource ? wallpaperSource : ""
        fillMode: root.imageFillModeMap[root.configuration.fillMode] || Image.PreserveAspectCrop
        visible: !isVideo && wallpaperSource !== ""
    }

    Component.onCompleted: {
        console.log("ILKO wallpaper plugin started, source:", wallpaperSource)
    }
}
