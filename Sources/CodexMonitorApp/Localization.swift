import Foundation
import SwiftUI

/// Bridges Codex Monitor's supported interface choices to the localization
/// identifiers bundled by Sparkle. Sparkle resolves its standard UI strings
/// when its framework bundle is first loaded, so this must run before AppKit
/// creates the standard updater controller.
enum SparkleLocalization {
    private static let appleLanguagesKey = "AppleLanguages"

    struct LaunchState: Equatable {
        let driverLanguage: String
        let nativeDriverMatchesSelection: Bool
    }

    /// Records the next launch's native-bundle language only in this app's
    /// preference domain. It never changes the macOS-wide language list.
    /// Removing the app value restores normal system-language lookup for
    /// Follow System mode.
    static func persistForNextLaunch(
        preference: InterfaceLanguage,
        defaults: UserDefaults = .standard
    ) {
        switch preference {
        case .simplifiedChinese:
            // Sparkle 2.10.0 ships Simplified Chinese as `zh_CN.lproj`.
            defaults.set(["zh_CN", "zh-Hans", "en"], forKey: appleLanguagesKey)
        case .english:
            defaults.set(["en"], forKey: appleLanguagesKey)
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
        }
    }

    /// The Sparkle framework is dynamically loaded before Swift's `main`.
    /// Capture its already-selected language before persisting the user's new
    /// choice. If they differ, this process must not present mixed-language
    /// standard Sparkle UI; the persisted value takes effect on the next
    /// normal launch.
    @MainActor
    static func prepareForLaunch(
        preference: InterfaceLanguage,
        defaults: UserDefaults = .standard,
        persistentDomainName: String? = Bundle.main.bundleIdentifier,
        systemPreferredLanguages: [String] = Locale.preferredLanguages
    ) -> LaunchState {
        // `stringArray(forKey:)` merges the global language domain. We need
        // only this App's persisted override to distinguish Follow System
        // from a prior explicit interface-language choice.
        let existingPreferences = persistentDomainName.flatMap {
            defaults.persistentDomain(forName: $0)?[appleLanguagesKey] as? [String]
        }
        let frameworkLanguage = driverLanguage(
            for: existingPreferences?.first ?? systemPreferredLanguages.first ?? Locale.current.identifier
        )
        let selectedLanguage = driverLanguage(
            for: LocalizationController.resolve(
                preference: preference,
                preferredLanguages: systemPreferredLanguages
            )
        )
        persistForNextLaunch(preference: preference, defaults: defaults)
        return LaunchState(
            driverLanguage: frameworkLanguage,
            nativeDriverMatchesSelection: frameworkLanguage == selectedLanguage
        )
    }

    /// The standard Sparkle driver cannot change localization after its
    /// framework bundle has been loaded. Compare the canonical language rather
    /// than raw locale spellings so `zh-Hans` and `zh_CN` remain one choice.
    static func driverLanguage(for resolvedLanguage: String) -> String {
        let language = Locale(identifier: resolvedLanguage).language.languageCode?.identifier.lowercased()
        return language == "zh" ? "zh_CN" : "en"
    }
}

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
        if let explicit = preference.localeIdentifier { return normalize(explicit) }
        return normalize(preferredLanguages.first ?? Locale.current.identifier)
    }

    static func normalize(_ identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        switch locale.language.languageCode?.identifier.lowercased() {
        case "zh": return "zh-Hans"
        case "en": return "en"
        default: return identifier
        }
    }

    /// AppKit does not consume `-AppleLanguages` during its manual bootstrap.
    /// Resolve it before the first menu or SwiftUI root is constructed.
    static var launchPreferredLanguages: [String] {
        systemPreferredLanguages
    }

    /// `Locale.preferredLanguages` is process-cached after an app-specific
    /// AppleLanguages override has been used. Follow System must instead read
    /// the immutable macOS global preference domain, never write to it.
    static var systemPreferredLanguages: [String] {
        if let override = L10n.commandLineLanguageOverride { return [override] }
        if let globalLanguages = UserDefaults.standard
            .persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String],
           !globalLanguages.isEmpty {
            return globalLanguages
        }
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

/// The single live localization root for every SwiftUI surface. Changing the
/// controller invalidates the root identity, so strings evaluated through the
/// shared `L10n` boundary cannot remain mixed with a previous locale.
struct LocalizedRoot<Content: View>: View {
    @ObservedObject var localization: LocalizationController
    let content: Content

    init(localization: LocalizationController, @ViewBuilder content: () -> Content) {
        self.localization = localization
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, localization.locale)
            .id(localization.resolvedLanguage)
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
