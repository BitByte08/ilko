import QtQuick
import QtMultimedia
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.core as PlasmaCore
import org.kde.kquickcontrolsaddons as KQuickControlsAddons

PlasmaCore.SortFilterProxyModel {
    id: root
    sourceModel: PlasmaCore.DataModel { dataPath: "wallpapers" }

    property string wallpaperFile: ""
    property string currentProfile: ""
    property bool isVideo: false
    property bool shouldPause: false

    property int videoDuration: 0
    property real videoPosition: 0

    property int blurRadius: 0
    property real fadeDuration: 0.5

    property bool loopVideo: true
    property bool muteAudio: true
    property real volume: 1.0
    property int fitMode: 0

    QtObject {
        id: videoProvider
        property bool hasVideo: root.wallpaperFile !== ""
        property bool isPlaying: false
    }

    Video {
        id: videoPlayer
        source: root.wallpaperFile
        autoPlay: true
        loops: root.loopVideo ? MediaPlayer.Infinite : 1
        muted: root.muteAudio
        volume: root.volume

        onDurationChanged: {
            root.videoDuration = duration
        }

        onPositionChanged: {
            root.videoPosition = position
        }

        onPlayingChanged: {
            videoProvider.isPlaying = playing
        }

        Component.onCompleted: {
            if (root.isVideo && !root.shouldPause) {
                play()
            }
        }
    }

    Image {
        id: imageWallpaper
        source: root.wallpaperFile
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: !root.isVideo || !hasVideoWithExtension(root.wallpaperFile)
    }

    function hasVideoWithExtension(path) {
        if (path === "") return false
        var ext = path.split('.').pop().toLower()
        return ["mp4", "webm", "mov", "avi", "mkv", "m4v"].indexOf(ext) !== -1
    }

    function setVideoUrl(url) {
        if (hasVideoWithExtension(url)) {
            root.isVideo = true
            root.wallpaperFile = url

            videoPlayer.source = url
            videoPlayer.play()
        } else {
            root.isVideo = false
            root.wallpaperFile = url
        }
    }

    Connections {
        target: videoPlayer
        function onPaused() {
            if (root.shouldPause) {
                videoPlayer.pause()
            }
        }
    }
}