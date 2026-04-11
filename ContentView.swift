/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Compatibility Bridge
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    @ViewBuilder
    func compatibleGlass(
        material: NSVisualEffectView.Material = .headerView, cornerRadius: CGFloat = 16
    ) -> some View {
        if #available(macOS 20.0, *) {
            self.background(
                VisualEffectView(material: material)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
        } else {
            self.background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - String Localization Extension
extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}

// MARK: - Language Manager
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: UserDefaultsKeys.appLanguage)
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    var availableLanguages: [(code: String, name: String)] {
        [
            ("auto", "system_language".localized),
            ("zh-Hans", "简体中文"),
            ("en", "English"),
        ]
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.appLanguage) ?? "auto"
        self.currentLanguage = saved
    }

    func localizedString(_ key: String) -> String {
        let language =
            currentLanguage == "auto" ? Locale.preferredLanguages.first ?? "en" : currentLanguage
        guard
            let path = Bundle.main.path(forResource: language, ofType: "lproj")
                ?? Bundle.main.path(
                    forResource: language.components(separatedBy: "-").first, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: "")
    }
}

// MARK: - Localization
enum L {
    static let selectWallpaperFolder = "📁"
    static let generating = "생성 중..."
    static let settings = "설정"
    static let wallpaperFolder = "월페이퍼 폴더"
    static let selectFolderEmoji = "📁"
    static let showInFinder = "📂"
    static let videoScalingMode = "비디오 크기 조절"
    static let scaleFill = "채우기"
    static let scaleFit = "맞추기"
    static let scaleStretch = "늘리기"
    static let scaleCenter = "가운데"
    static let scaleHeightFill = "높이 채우기"
    static let randomOnStartup = "시작 시 랜덤 월페이퍼"
    static let randomOnLid = "화면 켤 때 랜덤 월페이퍼"
    static let pauseWhenActive = "앱 포커스 시 일시정지"
    static let videoVolume = "비디오 볼륨"
    static let optimizeCodecs = "코덱 최적화"
    static let optimize = "최적화"
    static let clearCache = "캐시 삭제"
    static let clearCacheButton = "삭제"
    static let resetUserData = "데이터 초기화"
    static let reset = "초기화"
    static let selectFolderTitle = "폴더 선택"
    static let choose = "선택"
    static let selectFolderOrType = "경로를 입력하거나 선택하세요"
    static let wallpaperRotation = "월페이퍼 자동 전환"
    static let rotationType = "전환 방식"
    static let vinttageBar = "비네트 바 (변경 후 월페이퍼 재적용)"
    static let rotationDelay = "전환 간격"
}

// MARK: - UserDefaults Keys
enum UserDefaultsKeys {
    static let wallpaperFolder = "WallpaperFolder"
    static let scaleMode = "scale_mode"
    static let randomOnStartup = "random"
    static let randomOnLid = "random_lid"
    static let pauseOnAppFocus = "pauseOnAppFocus"
    static let volumePercentage = "wallpapervolumeprecentage"
    static let launchAtLogin = "LaunchAtLogin"
    static let appLanguage = "app_language"
    static let vignetteBar = "vinttage_bar"
    static let rotation = "rotation"
    static let rdelay = "rdelay"
    static let rtype = "rtype"

}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @State private var showSettings = false
    @State private var showProfiles = false
    @EnvironmentObject var locationWatcher: LocationWatcher
    @EnvironmentObject var switchController: SwitchController

    @Environment(\.dismiss) private var dismiss
    static var didCloseOnLaunch = false

    var body: some View {

        ZStack {

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                ToolbarView(
                    showSettings: $showSettings,
                    showProfiles: $showProfiles,
                    onReload: {
                        viewModel.reloadContent()
                        switchController.applyCurrentNetwork()
                    }
                )
                .padding(.horizontal).padding(.top, 24).padding(.bottom, 12)

                ZStack(alignment: .bottom) {
                    VideoGridView(
                        videos: viewModel.videos, viewModel: viewModel,
                        onVideoSelect: { video in
                            viewModel.startWallpaper(video: video)
                        }
                    )
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            .ignoresSafeArea(.all)
            .compatibleGlass(cornerRadius: 16)
            .frame(minWidth: 600, minHeight: 250)
            .onAppear {
                viewModel.reloadContent()
                if !Self.didCloseOnLaunch, let engine = sharedEngine, !engine.isFirstLaunch() {
                    Self.didCloseOnLaunch = true
                    dismiss()
                }
            }

            if showSettings {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showSettings = false }

                SettingsView(viewModel: viewModel)
                    .shadow(radius: 3)
                    .cornerRadius(15)
                    .onTapGesture {}
                    .animation(.easeInOut, value: showSettings)
            }

            if showProfiles {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showProfiles = false }

                ProfilesView()
                    .shadow(radius: 3)
                    .cornerRadius(15)
                    .onTapGesture {}
                    .animation(.easeInOut, value: showProfiles)
            }

        }.animation(.easeInOut, value: showSettings)
         .animation(.easeInOut, value: showProfiles)
    }
}

// MARK: - Toolbar View
struct ToolbarView: View {
    @Binding var showSettings: Bool
    @Binding var showProfiles: Bool
    let onReload: () -> Void

    var body: some View {
        HStack {
            Spacer()

            if #available(macOS 26.0, *) {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
            } else {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
            }

            if #available(macOS 26.0, *) {
                Button(action: { showProfiles = true }) {
                    Image(systemName: "person.2")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
            } else {
                Button(action: { showProfiles = true }) {
                    Image(systemName: "person.2")
                        .font(.system(size: 16))
                }
            }

            if #available(macOS 26.0, *) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
            } else {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                }
            }
        }
    }
}

// MARK: - Video Grid View
struct VideoGridView: View {
    let videos: [VideoItem]
    let viewModel: WallpaperViewModel
    let onVideoSelect: (VideoItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 2)]

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = L.selectFolderTitle
                    panel.prompt = L.choose

                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.folderPath = url.path
                        sharedEngine?.selectFolder(url.path())
                        viewModel.reloadContent()
                    }
                } label: {
                    Text(L.selectWallpaperFolder)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(videos) { video in
                        VideoThumbnailButton(video: video) {
                            onVideoSelect(video)
                        }
                        .id(video.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Video Thumbnail Button
struct VideoThumbnailButton: View {
    let video: VideoItem
    let action: () -> Void
    @ObservedObject private var cache = ThumbnailCache.shared

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                let _ = cache.lastUpdate

                if let thumbnail = video.loadThumbnail() {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 140)
                        .overlay {
                            VStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(L.generating)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                if let quality = video.quality, !quality.isEmpty {
                    QualityBadge(text: quality)
                        .padding(8)
                }
            }
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(video.filename)
    }
}

// MARK: - Quality Badge
struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black, lineWidth: 1)
            )
    }
}

// MARK: - Profiles View
struct ProfilesView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var locationWatcher: LocationWatcher
    @EnvironmentObject var switchController: SwitchController
    @State private var editingProfile: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("프로필 관리")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    editingProfile = Profile(id: UUID(), name: "", gatewayMAC: locationWatcher.currentGatewayMAC, wallpaperPath: "")
                } label: {
                    Label("추가", systemImage: "plus")
                }
            }
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileRowView(
                            profile: profile,
                            currentNetworkID: locationWatcher.currentGatewayMAC,
                            onEdit: { editingProfile = profile },
                            onDelete: {
                                let isActive = switchController.activeProfile?.id == profile.id
                                profileManager.delete(id: profile.id)
                                if isActive, let fallback = profileManager.profiles.first(where: { $0.gatewayMAC == nil }) {
                                    switchController.apply(fallback)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(
                profile: profile,
                isDefaultProfile: profile.gatewayMAC == nil,
                currentNetworkID: locationWatcher.currentGatewayMAC,
                onSave: { updated in
                    let isNew = !profileManager.profiles.contains(where: { $0.id == updated.id })
                    if isNew {
                        profileManager.add(updated)
                        switchController.apply(updated)
                    } else {
                        profileManager.update(updated)
                    }
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
        }
        .background(.ultraThinMaterial)
        .compatibleGlass(cornerRadius: 1)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @AppStorage(UserDefaultsKeys.scaleMode) var scaleMode: Int = 0
    @State private var isShowingView = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text(L.settings)
                    .font(.title2)
                    .fontWeight(.bold)

            }
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Folder Selection
                    SettingRow(title: L.wallpaperFolder) {
                        HStack {
                            TextField(L.selectFolderOrType, text: $viewModel.folderPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Button(action: selectFolder) {
                                Image(systemName: "folder.fill")
                            }
                            Button(action: openInFinder) {
                                Image(systemName: "finder")
                            }
                            
                            
                        }
                    }

                    Divider()

                    // Scale Mode
                    SettingRow(title: L.videoScalingMode) {

                        Picker("", selection: $scaleMode) {
                            Text(L.scaleFill).tag(0)
                            Text(L.scaleFit).tag(1)
                            Text(L.scaleStretch).tag(2)
                            Text(L.scaleCenter).tag(3)
                            Text(L.scaleHeightFill).tag(4)
                        }
                        .onChange(of: scaleMode) {

                            viewModel.engine.updateScaleMode(scaleMode)
                        }

                    }

                    Divider()

                    // Auto-Pause When App is Active
                    SettingRow(title: L.pauseWhenActive) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(
                                        forKey: UserDefaultsKeys.pauseOnAppFocus)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.pauseOnAppFocus)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    //Vinttage Bar
                    SettingRow(title: L.vinttageBar) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.vignetteBar)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.vignetteBar)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    Divider()

                    // Video Volume
                    SettingRow(title: L.videoVolume) {
                        HStack {
                            Slider(value: $viewModel.volume, in: 0...100, step: 1)
                                .frame(width: 200)
                                .onChange(of: viewModel.volume) { newValue in
                                    sharedEngine?.updateVolume(newValue)
                                }
                            Text("\(Int(viewModel.volume))%")
                                .frame(width: 60, alignment: .leading)
                                .monospacedDigit()
                        }
                    }

                    Divider()

                    // Optimize Videos
                    SettingRow(title: L.optimizeCodecs) {
                        Button(L.optimize) {
                            viewModel.optimizeVideos()
                        }
                        .disabled(true)
                    }

                    // Clear Cache
                    SettingRow(title: L.clearCache) {
                        Button(L.clearCacheButton) {
                            viewModel.clearCache()
                        }
                    }

                    // Reset User Data
                    SettingRow(title: L.resetUserData) {
                        Button(L.reset) {
                            viewModel.resetUserData()
                        }
                    }

                }
                .padding()
            }
        }
        .padding()
        .frame(width: 600, height: 500)
        .background(.ultraThinMaterial)
        .compatibleGlass(cornerRadius: 1)

    }
    func formatTime(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m) min"
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = L.selectFolderTitle
        panel.prompt = L.choose

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.folderPath = url.path
            sharedEngine?.selectFolder(url.path())
            viewModel.reloadContent()
        }
    }

    private func openInFinder() {
        if let url = URL(string: "file://\(viewModel.folderPath)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Setting Row
struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 200, alignment: .leading)
            content
            Spacer()
        }
    }
}

// MARK: - Video Item
struct VideoItem: Identifiable {
    let id = UUID()
    let filename: String
    let path: String
    let thumbnailPath: String
    var quality: String?

    func loadThumbnail() -> NSImage? {
        return ThumbnailCache.shared.image(for: thumbnailPath)
    }
}

// MARK: - Thumbnail Cache
class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    @Published var lastUpdate = Date()

    private init() {
        cache.countLimit = 100

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailSaved(_:)),
            name: NSNotification.Name("ThumbnailSaved"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailsGenerated),
            name: NSNotification.Name("ThumbnailsGenerated"),
            object: nil
        )
    }

    @objc private func thumbnailSaved(_ notification: Notification) {
        if let path = notification.userInfo?["path"] as? String {
            cache.removeObject(forKey: path as NSString)
        }
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    @objc private func thumbnailsGenerated() {
        cache.removeAllObjects()
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    func image(for path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        guard FileManager.default.fileExists(atPath: path),
            let img = NSImage(contentsOfFile: path)
        else {
            return nil
        }

        cache.setObject(img, forKey: path as NSString)
        return img
    }

    func clearCache() {
        cache.removeAllObjects()
        lastUpdate = Date()
    }
}

// MARK: - Wallpaper View Model
@MainActor
class WallpaperViewModel: ObservableObject {

    @Published var videos: [VideoItem] = []
    @Published var folderPath: String = ""
    @Published var scaleMode: String = "fill"
    @Published var randomOnStartup: Bool = false
    @Published var pauseOnAppFocus: Bool = true
    @Published var volume: Double = 50.0
    @Published var vinttageBar: Bool = true

    private var currentReloadID = UUID()
    private let reloadIDLock = NSLock()
    private let defaults = UserDefaults.standard
    let engine: WallpaperEngine

    init(engine: WallpaperEngine = sharedEngine ?? WallpaperEngine.shared()) {
        self.engine = engine
        loadSettings()
        self.engine.setupNotifications()
    }

    func invalidate() {
        engine.removeNotifications()
    }

    func loadSettings() {
        folderPath = engine.getFolderPath()
        scaleMode = defaults.string(forKey: UserDefaultsKeys.scaleMode) ?? "fill"
        randomOnStartup = defaults.bool(forKey: UserDefaultsKeys.randomOnStartup)
        pauseOnAppFocus = defaults.bool(forKey: UserDefaultsKeys.pauseOnAppFocus)
        volume = Double(defaults.float(forKey: UserDefaultsKeys.volumePercentage))
        vinttageBar = defaults.bool(forKey: UserDefaultsKeys.vignetteBar)
    }

    func reloadContent() {
        engine.checkFolderPath()
        ThumbnailCache.shared.clearCache()

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else {
            return
        }

        let videoFiles = files.filter { f in
            let e = (f as NSString).pathExtension.lowercased()
            return e == "mp4" || e == "mov"
        }

        let reloadID = UUID()
        reloadIDLock.lock()
        currentReloadID = reloadID
        reloadIDLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let newVideos: [VideoItem] = videoFiles.map { f in
                let full = (self.folderPath as NSString).appendingPathComponent(f)
                let base = (f as NSString).deletingPathExtension
                let thumbPath =
                    (self.engine.thumbnailCachePath() as NSString?)?.appendingPathComponent(
                        "\(base).png") ?? ""

                var item = VideoItem(filename: f, path: full, thumbnailPath: thumbPath)
                self.engine.videoQualityBadge(for: URL(fileURLWithPath: full)) { badge in
                    item.quality = badge
                }
                return item
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.reloadIDLock.lock()
                let isValid = reloadID == self.currentReloadID
                self.reloadIDLock.unlock()

                if isValid {
                    self.videos = newVideos

                    let missingThumbnails = newVideos.filter { $0.loadThumbnail() == nil }
                    if !missingThumbnails.isEmpty {
                        NSLog(
                            "Found \(missingThumbnails.count) videos without thumbnails, generating..."
                        )
                        self.engine.generateThumbnails()
                    }
                }
            }
        }
    }

    func startWallpaper(video: VideoItem) {
        let displays = NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }
        engine.startWallpaper(withPath: video.path, onDisplays: displays)
    }

    func clearCache() {
        engine.clearCache()
        ThumbnailCache.shared.clearCache()
        reloadContent()
    }

    func resetUserData() {
        engine.resetUserData()
        loadSettings()
        reloadContent()
    }

    func optimizeVideos() {
        engine.generateStaticWallpapers(forFolder: folderPath) {}
    }

    private func getDisplayName(for id: CGDirectDisplayID) -> String {
        for s in NSScreen.screens {
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                n.uint32Value == id
            {
                return s.localizedName
            }
        }
        return "Display \(id)"
    }
}

// MARK: - Profile Row
struct ProfileRowView: View {
    let profile: Profile
    let currentNetworkID: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).fontWeight(.medium)
                Text(profile.gatewayMAC.map { "MAC: \($0)" } ?? "기본 프로필")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("편집", action: onEdit)
            if profile.gatewayMAC != nil {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Profile Editor Sheet
struct ProfileEditorView: View {
    @State var profile: Profile
    let isDefaultProfile: Bool
    let currentNetworkID: String?
    let onSave: (Profile) -> Void
    let onCancel: () -> Void

    @State private var thumbnailImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile.wallpaperPath.isEmpty ? "프로필 추가" : "프로필 편집")
                .font(.title2).fontWeight(.bold)

            // 이름
            LabeledContent("이름") {
                TextField("홈, 카페, 회사…", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .disabled(isDefaultProfile)
            }

            // 네트워크
            LabeledContent("네트워크") {
                HStack {
                    Text(profile.gatewayMAC ?? "없음 = 기본 프로필")
                        .foregroundStyle(profile.gatewayMAC == nil ? .secondary : .primary)
                        .frame(width: 160, alignment: .leading)
                        .font(.system(.body, design: .monospaced))

                    if !isDefaultProfile {
                        if let mac = currentNetworkID {
                            if profile.gatewayMAC == mac {
                                Label("현재 네트워크", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button("현재 네트워크로") {
                                    profile.gatewayMAC = mac
                                }
                                .font(.caption)
                            }
                        }

                        if profile.gatewayMAC != nil {
                            Button("초기화") {
                                profile.gatewayMAC = nil
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 월페이퍼 파일
            LabeledContent("월페이퍼") {
                HStack {
                    Text(profile.wallpaperPath.isEmpty ? "파일 없음" : URL(fileURLWithPath: profile.wallpaperPath).lastPathComponent)
                        .foregroundStyle(profile.wallpaperPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 160, alignment: .leading)

                    Button("선택") { pickFile() }
                }
            }

            // 미리보기
            if let img = thumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }

            Divider()

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                Button("저장") { onSave(profile) }
                    .buttonStyle(.borderedProminent)
                    .disabled(profile.name.isEmpty || profile.wallpaperPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task(id: profile.wallpaperPath) {
            thumbnailImage = await loadThumbnail(path: profile.wallpaperPath)
        }
    }

    private func loadThumbnail(path: String) async -> NSImage? {
        guard !path.isEmpty else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png":
            return NSImage(contentsOfFile: path)
        case "mp4", "mov":
            return await Task.detached(priority: .utility) {
                let asset = AVAsset(url: URL(fileURLWithPath: path))
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 800, height: 500)
                guard let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
                return NSImage(cgImage: cgImage, size: .zero)
            }.value
        default:
            return nil
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .jpeg, .png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let dest = try ProfileManager.importWallpaper(from: url)
            profile.wallpaperPath = dest.path
        } catch {
            // 복사 실패 시 원본 경로 그대로 사용
            profile.wallpaperPath = url.path
        }
    }
}

#Preview {
    ContentView()
}

#Preview {
    SettingsView(viewModel: WallpaperViewModel())
        .environmentObject(ProfileManager())
        .environmentObject(LocationWatcher())
}
