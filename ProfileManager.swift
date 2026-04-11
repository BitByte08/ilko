import Combine
import Foundation

/// ilko 프로필 — 게이트웨이 MAC 하나에 월페이퍼 파일 하나를 매핑한다.
/// gatewayMAC이 nil이면 기본(일코) 프로필로 동작한다.
struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var gatewayMAC: String?  // nil = 기본 프로필 (일치하는 네트워크 없을 때 적용)
    var wallpaperPath: String
}

/// 프로필 CRUD + ~/Library/Application Support/ilko/config.json 영속성
@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?

    private let configURL: URL

    /// ilko 전용 월페이퍼 저장 디렉터리.
    /// LiveWallpaper의 WallpaperFolder와 완전히 분리된다.
    static let wallpapersDirectory: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent("ilko/Wallpapers")
    }()

    /// 파일을 ilko 월페이퍼 디렉터리로 복사한다. 이미 같은 경로면 그대로 반환.
    static func importWallpaper(from source: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: wallpapersDirectory, withIntermediateDirectories: true)
        let dest = wallpapersDirectory.appendingPathComponent(source.lastPathComponent)
        if dest.path == source.path { return dest }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = support.appendingPathComponent("ilko")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: ProfileManager.wallpapersDirectory, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.json")

        load()
        if profiles.isEmpty {
            profiles = [Profile(id: UUID(), name: "기본 (일코)", gatewayMAC: nil, wallpaperPath: "")]
            save()
        }
    }

    func add(_ profile: Profile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: Profile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        save()
    }

    /// 게이트웨이 MAC에 맞는 프로필을 반환한다. 없으면 기본 프로필(gatewayMAC == nil)을 반환.
    func profileFor(gatewayMAC: String?) -> Profile? {
        if let mac = gatewayMAC, let match = profiles.first(where: { $0.gatewayMAC == mac }) {
            return match
        }
        return profiles.first(where: { $0.gatewayMAC == nil })
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode([Profile].self, from: data)
        else { return }
        profiles = decoded
    }
}
