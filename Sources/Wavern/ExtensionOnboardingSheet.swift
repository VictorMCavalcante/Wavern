import AppKit
import SwiftUI

struct ExtensionOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var extensionPath: String {
        Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension").path ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install Wavern Tab Bridge")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Label("Open Chrome extensions page", systemImage: "1.circle")
                Button("Open chrome://extensions") {
                    NSWorkspace.shared.open(
                        URL(string: "googlechrome://extensions") ?? URL(string: "https://google.com")!)
                }
                .buttonStyle(.borderedProminent)

                Label("Enable **Developer Mode** (top-right toggle)", systemImage: "2.circle")
                    .fixedSize(horizontal: false, vertical: true)

                Label("Click **Load unpacked** and select this folder:", systemImage: "3.circle")
                HStack {
                    Text(extensionPath)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(extensionPath, forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
