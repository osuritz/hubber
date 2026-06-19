import AppKit
import Sparkle

/// Owns Sparkle's standard updater for the Standard (non-MAS) build and exposes
/// the menu wiring for "Check for Updates…".
///
/// The rest of the app does not import Sparkle: it drives updates through
/// `checkForUpdatesTarget` / `checkForUpdatesAction`, which point straight at
/// `SPUStandardUpdaterController` so Sparkle's own `canCheckForUpdates`
/// menu-item validation applies automatically.
///
/// Auto-update only activates when the bundle carries `SUFeedURL` + `SUPublicEDKey`
/// (injected at build time in release/CI). In dev builds those keys are absent, so
/// scheduled checks are inert and "Check for Updates…" reports no feed — which still
/// proves the wiring.
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Target for the "Check for Updates…" menu item — Sparkle's controller itself.
    var checkForUpdatesTarget: AnyObject {
        controller
    }

    /// Action for the "Check for Updates…" menu item.
    var checkForUpdatesAction: Selector {
        #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }
}
