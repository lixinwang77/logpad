import Foundation
import Combine
import SwiftUI

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: String = "en"

    private init() {
        currentLanguage = UserDefaults.standard.string(forKey: "app_language") ?? Locale.current.language.languageCode?.identifier ?? "en"
    }

    func setLanguage(_ lang: String) {
        currentLanguage = lang
        UserDefaults.standard.set(lang, forKey: "app_language")
    }

    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.main
    }

    func str(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

struct LocalizedString: View {
    let key: String
    @ObservedObject private var langManager = LanguageManager.shared

    var body: Text {
        Text(langManager.str(key))
    }
}