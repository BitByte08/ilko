import QtQuick
import QtMultimedia
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

WallpaperItem {
    id: root

    property string currentFile: root.configuration.wallpaperFile || ""
    property bool isVideo: isVideoFile(currentFile)

    function isVideoFile(path) {
        if (!path || path === "") return false
        var ext = String(path).split('.').pop().toLowerCase()
        return ["mp4", "webm", "mov", "avi", "mkv", "m4v", "flv", "wmv"].indexOf(ext) !== -1
    }

    Rectangle {
        anchors.fill: parent
        color: root.configuration.backgroundColor || "#000000"
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root.isVideo && root.currentFile !== ""
    }

    MediaPlayer {
        id: mediaPlayer
        videoOutput: videoOutput
        audioOutput: audioOutput
        source: root.isVideo ? root.currentFile : ""
        loops: MediaPlayer.Infinite
        playbackRate: 1.0

        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                mediaPlayer.play()
            }
        }

        onErrorOccurred: function(error, errorString) {
            console.log("ILKO Video Error:", errorString)
        }
    }

    AudioOutput {
        id: audioOutput
        muted: true
        volume: 0.0
    }

    Image {
        id: imageWallpaper
        anchors.fill: parent
        source: !root.isVideo && root.currentFile !== "" ? ("file://" + root.currentFile) : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        visible: !root.isVideo && root.currentFile !== ""
    }

    Kirigami.PlaceholderMessage {
        visible: root.currentFile === ""
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        icon.name: "video-symbolic"
        text: i18n("No wallpaper configured.\nSelect a video or image in the settings.")
    }

    Component.onCompleted: {
        if (root.isVideo && root.currentFile !== "") {
            mediaPlayer.play()
        }
    }

    onCurrentFileChanged: {
        if (root.isVideo && root.currentFile !== "") {
            mediaPlayer.stop()
            mediaPlayer.source = root.currentFile
            mediaPlayer.play()
        }
    }
}
