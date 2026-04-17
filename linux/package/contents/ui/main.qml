import QtQuick
import QtMultimedia
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    property string ilkoWallpaper: ""
    property string effectiveFile: ilkoWallpaper !== "" ? ilkoWallpaper : (root.configuration.wallpaperFile || "")
    property bool isVideo: {
        if (!effectiveFile || effectiveFile === "") return false
        var ext = effectiveFile.split('.').pop().toLowerCase()
        return ["mp4", "webm", "mov", "avi", "mkv"].indexOf(ext) !== -1
    }
    property bool onBattery: false
    property bool hasFullscreenApp: false
    property bool initialized: false

    property double playbackRate: root.configuration.playbackRate || 1.0
    property double volume: root.configuration.volume || 0.0
    property string fillMode: root.configuration.fillMode || "preserveAspectCrop"
    property bool pauseOnBattery: root.configuration.pauseOnBattery !== undefined ? root.configuration.pauseOnBattery : true
    property bool pauseOnFullscreen: root.configuration.pauseOnFullscreen !== undefined ? root.configuration.pauseOnFullscreen : true

    property bool shouldPause: initialized && ((onBattery && pauseOnBattery) || (hasFullscreenApp && pauseOnFullscreen))

    function loadWallpaperFile() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                try {
                    var obj = JSON.parse(xhr.responseText || "{}")
                    if (obj.wallpaperFile && obj.wallpaperFile !== "") {
                        if (root.ilkoWallpaper !== obj.wallpaperFile) {
                            root.ilkoWallpaper = obj.wallpaperFile
                        }
                    }
                } catch(e) {}
            }
        }
        xhr.open("GET", "file:///home/bitbyte08/.ilko/current_wallpaper.json")
        xhr.send()
    }

    function checkBattery() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var text = (xhr.responseText || "").trim()
                root.onBattery = (text === "Discharging")
            }
        }
        xhr.open("GET", "file:///sys/class/power_supply/BAT1/status")
        xhr.onerror = function() {
            var xhr2 = new XMLHttpRequest()
            xhr2.onreadystatechange = function() {
                if (xhr2.readyState === XMLHttpRequest.DONE) {
                    var text2 = (xhr2.responseText || "").trim()
                    root.onBattery = (text2 === "Discharging")
                }
            }
            xhr2.open("GET", "file:///sys/class/power_supply/BAT0/status")
            xhr2.send()
        }
        xhr.send()
    }

    function checkFullscreen() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                try {
                    var data = JSON.parse(xhr.responseText || "[]")
                    root.hasFullscreenApp = data.length > 0
                } catch(e) {
                    root.hasFullscreenApp = false
                }
            }
        }
        xhr.open("GET", "file:///home/bitbyte08/.ilko/fullscreen_state.json")
        xhr.send()
    }

    Timer { interval: 10000; running: true; repeat: true; onTriggered: loadWallpaperFile() }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: { checkBattery(); checkFullscreen(); } }

    Timer {
        id: initTimer
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            root.initialized = true
            checkBattery()
        }
    }

    onShouldPauseChanged: {
        if (shouldPause) mediaPlayer.pause()
        else if (root.isVideo && root.effectiveFile !== "" && mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia) mediaPlayer.play()
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: fillMode === "preserveAspectCrop" ? VideoOutput.PreserveAspectCrop : 
                  fillMode === "stretch" ? VideoOutput.Stretch : 
                  fillMode === "preserveAspectFit" ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
        visible: root.isVideo
    }

    MediaPlayer {
        id: mediaPlayer
        videoOutput: videoOutput
        audioOutput: audioOutput
        source: root.isVideo ? root.effectiveFile : ""
        loops: MediaPlayer.Infinite
        playbackRate: root.playbackRate
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                if (!root.shouldPause) mediaPlayer.play()
                else mediaPlayer.pause()
            }
        }
        onErrorOccurred: function(err, msg) { console.log("ILKO Error:", msg) }
    }

    AudioOutput { id: audioOutput; muted: true; volume: root.volume }

    Image {
        anchors.fill: parent
        source: !root.isVideo && root.effectiveFile !== "" ? ("file://" + root.effectiveFile) : ""
        fillMode: Image.PreserveAspectCrop
        visible: !root.isVideo && root.effectiveFile !== ""
    }

    Rectangle { anchors.fill: parent; color: root.configuration.backgroundColor || "#000000" }

    Component.onCompleted: loadWallpaperFile()

    onEffectiveFileChanged: {
        if (root.isVideo && root.effectiveFile !== "") {
            mediaPlayer.stop()
            mediaPlayer.source = root.effectiveFile
            if (!root.shouldPause) mediaPlayer.play()
        }
    }
}