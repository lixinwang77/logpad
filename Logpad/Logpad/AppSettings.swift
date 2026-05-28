import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "app_language")
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "app_language") {
            language = saved
        } else {
            language = Locale.current.language.languageCode?.identifier ?? "en"
        }
    }
}