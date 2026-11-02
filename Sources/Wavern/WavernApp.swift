import AppKit
import SwiftUI

@main
struct WavernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // LSUIElement app: the UI lives in StatusPanel, this scene is never shown.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusPanel: StatusPanel?

    func applicationWillTerminate(_ notification: Notification) {
        AudioProcessController.shared.willTerminate()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioProcessController.shared.start()
        BrowserBridgeInstaller.install()
        UpdateChecker.shared.check()
        statusPanel = StatusPanel(controller: .shared, updateChecker: .shared)
    }
}
