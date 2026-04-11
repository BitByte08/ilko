import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                existingProfiles: profileManager.profiles,
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
    let existingProfiles: [Profile]
    let currentNetworkID: String?
    let onSave: (Profile) -> Void
    let onCancel: () -> Void

    @State private var thumbnailImage: NSImage?

    private var isDuplicateName: Bool {
        existingProfiles.contains { $0.id != profile.id && $0.name == profile.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile.wallpaperPath.isEmpty ? "프로필 추가" : "프로필 편집")
                .font(.title2).fontWeight(.bold)

            // 이름
            LabeledContent("이름") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("홈, 카페, 회사…", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .disabled(isDefaultProfile)
                    if isDuplicateName {
                        Text("이미 같은 이름의 프로필이 있어요.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
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
                    .disabled(profile.name.isEmpty || profile.wallpaperPath.isEmpty || isDuplicateName)
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
