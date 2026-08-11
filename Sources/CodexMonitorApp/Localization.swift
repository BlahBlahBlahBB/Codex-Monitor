import Foundation
import SwiftUI

@MainActor
final class LocalizationController: ObservableObject {
    @Published private(set) var resolvedLanguage: String
    @Published private(set) var locale: Locale
    private(set) var storedPreference: InterfaceLanguage
    private(set) var preferredLanguages: [String]

    init(preference: InterfaceLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        let resolved = Self.resolve(preference: preference, preferredLanguages: preferredLanguages)
        storedPreference = preference
        self.preferredLanguages = preferredLanguages
        resolvedLanguage = resolved
        locale = Locale(identifier: resolved)
    }

    static func resolve(preference: InterfaceLanguage, preferredLanguages: [String]) -> String {
        preference.localeIdentifier ?? preferredLanguages.first ?? Locale.current.identifier
    }

    /// AppKit does not consume `-AppleLanguages` during its manual bootstrap.
    /// Resolve it before the first menu or SwiftUI root is constructed.
    static var launchPreferredLanguages: [String] {
        if let override = L10n.commandLineLanguageOverride { return [override] }
        return Locale.preferredLanguages
    }

    func refresh(preference: InterfaceLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        storedPreference = preference
        self.preferredLanguages = preferredLanguages
        let next = Self.resolve(preference: preference, preferredLanguages: preferredLanguages)
        resolvedLanguage = next
        locale = Locale(identifier: next)
        L10n.setResolvedLanguage(next)
        DiagnosticEvent.record(.localization, [
            "event": "resolved", "preference": preference.rawValue,
            "preferredLanguages": preferredLanguages.map { Locale(identifier: $0).language.languageCode?.identifier ?? "unknown" }.joined(separator: ","),
            "resolvedLocale": next
        ])
    }
}

/// The sole localization boundary for presentation strings. Runtime IDs, model
/// names, and protocol data remain untouched; only user-facing copy comes here.
enum L10n {
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var configuredLanguage: String?

    @MainActor
    static func configure(_ controller: LocalizationController) {
        controller.refresh(preference: controller.storedPreference, preferredLanguages: controller.preferredLanguages)
    }

    @MainActor
    static func setResolvedLanguage(_ language: String) {
        stateLock.lock()
        configuredLanguage = language
        stateLock.unlock()
    }

    static var resolvedLanguage: String {
        stateLock.lock()
        let configured = configuredLanguage
        stateLock.unlock()
        return configured ?? commandLineLanguageOverride ?? Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    static var locale: Locale { Locale(identifier: resolvedLanguage) }

    static func tr(_ key: String, languageCode: String? = nil) -> String {
        // SwiftPM writes the directory as `zh-hans.lproj` inside an app
        // bundle, while Locale reports `zh-Hans`. Resolve it explicitly so
        // packaged apps do not silently fall back to development-region copy.
        let requestedLanguage = languageCode ?? resolvedLanguage
        let localizedBundle = localizedBundle(for: requestedLanguage) ?? resourceBundle
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

    /// AppKit's manual entry point does not consume `-AppleLanguages` in the
    /// way SwiftUI's application bootstrap does. Honor that standard launch
    /// argument here so packaged language QA exercises the exact same bundle
    /// resolution path as a real system-language launch.
    fileprivate static var commandLineLanguageOverride: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AppleLanguages"), arguments.indices.contains(index + 1) else {
            return nil
        }
        let raw = arguments[index + 1]
            .trimmingCharacters(in: CharacterSet(charactersIn: "()[]\\\"' "))
        return raw.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
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
        let locale = L10n.resolvedLanguage
        let refresh = L10n.tr("menu.refresh")
        let usage = L10n.tr("menu.usage")
        let settings = L10n.tr("menu.settings")
        print("CODEX_MONITOR_UI_QA revision=\(revision) built=\(timestamp) locale=\(locale) refresh=\(refresh) usage=\(usage) settings=\(settings)")
#endif
    }
}
