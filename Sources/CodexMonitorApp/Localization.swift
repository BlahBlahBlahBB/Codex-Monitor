import Foundation

/// The sole localization boundary for presentation strings. Runtime IDs, model
/// names, and protocol data remain untouched; only user-facing copy comes here.
enum L10n {
    static func tr(_ key: String, languageCode: String? = nil) -> String {
        // SwiftPM writes the directory as `zh-hans.lproj` inside an app
        // bundle, while Locale reports `zh-Hans`. Resolve it explicitly so
        // packaged apps do not silently fall back to development-region copy.
        let requestedLanguage = languageCode ?? Locale.preferredLanguages.first
        let localizedBundle = requestedLanguage.flatMap(localizedBundle(for:)) ?? resourceBundle
        return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private static func localizedBundle(for languageCode: String) -> Bundle? {
        let locale = Locale(identifier: languageCode)
        let candidates = [languageCode, languageCode.lowercased(), locale.identifier, locale.identifier.lowercased()]
            + (locale.language.languageCode.map { [$0.identifier] } ?? [])
        let lprojURLs = resourceBundle.urls(forResourcesWithExtension: "lproj", subdirectory: nil) ?? []
        for candidate in candidates {
            if let url = lprojURLs.first(where: { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame }),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
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

enum UIBuildDiagnostics {
    static func logStartup() {
#if DEBUG
        let info = Bundle.main.infoDictionary ?? [:]
        let revision = info["UIBuildRevision"] as? String ?? "unversioned"
        let timestamp = info["UIBuildTimestamp"] as? String ?? "unknown"
        let locale = Locale.preferredLanguages.first ?? Locale.current.identifier
        let refresh = L10n.tr("menu.refresh")
        let usage = L10n.tr("menu.usage")
        let settings = L10n.tr("menu.settings")
        print("CODEX_MONITOR_UI_QA revision=\(revision) built=\(timestamp) locale=\(locale) refresh=\(refresh) usage=\(usage) settings=\(settings)")
#endif
    }
}
