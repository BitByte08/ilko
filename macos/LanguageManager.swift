import Combine
import Foundation

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
