import AppKit
import SwiftUI

@main
struct WavernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AudioProcessController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
                .environmentObject(controller.browserTabStore)
        } label: {
            if controller.playing.isEmpty {
                Image(systemName: "speaker.wave.2.fill")
            } else {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative.reversing, isActive: true)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioProcessController.shared.start()
        BrowserBridgeInstaller.install()
        // Make the MenuBarExtra panel transparent so VisualEffectBackground shows through
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                if window is NSPanel {
                    window.backgroundColor = .clear
                    window.isOpaque = false
                }
            }
        }
    }
}
