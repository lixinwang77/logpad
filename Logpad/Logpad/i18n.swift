import Foundation

struct i18n {
    static func str(_ key: String) -> String {
        return LanguageManager.shared.str(key)
    }
}