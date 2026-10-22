import Foundation

/// A compile-time-only boundary for the disposable Sparkle lifecycle build.
/// It is deliberately not controlled by an environment variable, preference,
/// command-line argument, or remote response, so the boundary survives an
/// updater relaunch and cannot be enabled in a normal release by user state.
enum QAIsolation {
#if CODEX_MONITOR_QA_ISOLATION
    static let enabled = true
    static let expectedBundleIdentifier: String? = "com.codexmonitor.sparkle.productionqa"
#else
    static let enabled = false
    static let expectedBundleIdentifier: String? = nil
#endif

    static var preferences: UserDefaults {
        // `standard` is already keyed by the process bundle identifier. The
        // QA binary has a dedicated identifier, so this is a separate domain
        // from production without relying on a suite entitlement/API that can
        // be unavailable in an ad-hoc application bundle.
        .standard
    }

    /// This check runs before `NSApplication` is created. It makes the
    /// disposable compiler flag and the packaged identity mutually binding:
    /// a QA binary cannot silently run as the production application, and a
    /// production binary rejects a QA-marked Info.plist.
    static func verifyPackaging() {
        let infoQAFlag = Bundle.main.object(forInfoDictionaryKey: "CodexMonitorQAIsolation") as? Bool ?? false
#if CODEX_MONITOR_QA_ISOLATION
        precondition(enabled)
        precondition(infoQAFlag, "QA binary requires CodexMonitorQAIsolation=true")
        precondition(Bundle.main.bundleIdentifier == expectedBundleIdentifier, "QA binary requires its dedicated bundle identifier")
#else
        precondition(!infoQAFlag, "Production binary must not carry the QA isolation marker")
#endif
    }
}
