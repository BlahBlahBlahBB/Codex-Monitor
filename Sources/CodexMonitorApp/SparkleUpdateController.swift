import AppKit
import Sparkle

/// Owns only Sparkle's lifecycle. It intentionally has no reference to the
/// monitor runtime, account provider, approval observer, or Codex Desktop.
/// Sparkle's standard user driver presents every install/relaunch decision.
@MainActor
final class SparkleUpdateController {
    private var updaterController: SPUStandardUpdaterController?

    func start() {
        guard updaterController == nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func stop() {
        // Releasing the controller during app termination cancels ownership of
        // the in-process updater without asking Sparkle to touch any external
        // app or Codex Desktop state.
        updaterController = nil
    }
}
