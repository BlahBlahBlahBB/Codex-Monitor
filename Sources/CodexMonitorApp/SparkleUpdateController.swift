import AppKit
import Sparkle

/// Owns only Sparkle's lifecycle. It intentionally has no reference to the
/// monitor runtime, account provider, approval observer, or Codex Desktop.
/// Sparkle's standard user driver presents every install/relaunch decision.
@MainActor
final class SparkleUpdateController {
    enum CheckResult: Equatable {
        case started
        case restartRequiredForLanguage
    }

    private var updaterController: SPUStandardUpdaterController?
    private var driverLanguage: String?
    private var nativeDriverMatchesSelection = false

    func start(language: String, nativeDriverMatchesSelection: Bool) {
        guard updaterController == nil else { return }
        driverLanguage = SparkleLocalization.driverLanguage(for: language)
        self.nativeDriverMatchesSelection = nativeDriverMatchesSelection
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates(language: String) -> CheckResult {
        guard nativeDriverMatchesSelection,
              driverLanguage == SparkleLocalization.driverLanguage(for: language) else {
            return .restartRequiredForLanguage
        }
        updaterController?.checkForUpdates(nil)
        return .started
    }

    func stop() {
        // Releasing the controller during app termination cancels ownership of
        // the in-process updater without asking Sparkle to touch any external
        // app or Codex Desktop state.
        updaterController = nil
        driverLanguage = nil
        nativeDriverMatchesSelection = false
    }
}
