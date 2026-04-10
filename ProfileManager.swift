import Combine
import Foundation

/// ilko 프로필 — SSID 하나에 월페이퍼 파일 하나를 매핑한다.
/// ssid가 nil이면 기본(일코) 프로필로 동작한다.
struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var ssid: String?        // nil = 기본 프로필 (일치하는 SSID 없을 때 적용)
    var wallpaperPath: String
}

/// 프로필 CRUD + ~/Library/Application Support/ilko/config.json 영속성
@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?

    private let configURL: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = support.appendingPathComponent("ilko")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.json")

        load()
        if profiles.isEmpty {
            profiles = [Profile(id: UUID(), name: "기본 (일코)", ssid: nil, wallpaperPath: "")]
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

    /// SSID에 맞는 프로필을 반환한다. 없으면 기본 프로필(ssid == nil)을 반환.
    func profileFor(ssid: String?) -> Profile? {
        if let ssid, let match = profiles.first(where: { $0.ssid == ssid }) {
            return match
        }
        return profiles.first(where: { $0.ssid == nil })
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
