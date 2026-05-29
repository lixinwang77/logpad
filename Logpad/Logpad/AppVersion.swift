import Foundation

enum AppVersion {
    static let appName = "Logpad"

    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var displayString: String {
        "\(marketingVersion) (\(buildNumber))"
    }

    static var aboutVersionString: String {
        String(format: i18n.str("versionFormat"), marketingVersion, buildNumber)
    }
}
