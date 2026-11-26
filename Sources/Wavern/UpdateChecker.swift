import AppKit
import Sparkle

/// Sparkle-backed updates. The appcast lives on the latest GitHub release
/// (`SUFeedURL`); every archive is EdDSA-signed in CI and verified against
/// `SUPublicEDKey` before Sparkle installs it.
@MainActor
final class UpdateChecker: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = UpdateChecker()

    /// Version of an update Sparkle found in the background; drives the menu chip.
    @Published private(set) var availableVersion: String?

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        // Menu-bar app: without this, Sparkle's window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }

    /// Background (LSUIElement) app: let scheduled checks surface via the menu chip.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
