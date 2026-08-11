import Foundation

/// The sole localization boundary for presentation strings. Runtime IDs, model
/// names, and protocol data remain untouched; only user-facing copy comes here.
enum L10n {
    static func tr(_ key: String, languageCode: String? = nil) -> String {
        let localizedBundle: Bundle
        if let languageCode,
           let path = resourceBundle.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            localizedBundle = bundle
        } else {
            localizedBundle = resourceBundle
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private static var resourceBundle: Bundle {
        let bundleName = "CodexMonitorContracts_CodexMonitorApp.bundle"
        if let resources = Bundle.main.resourceURL,
           let appResourceBundle = Bundle(url: resources.appendingPathComponent(bundleName)) {
            return appResourceBundle
        }
        return .module
    }

    static var unknown: String { tr("value.unknown") }
    static var unavailable: String { tr("value.unavailable") }
}
