import AppKit
import SwiftUI

// MARK: - MenuView

struct MenuView: View {
    @EnvironmentObject var controller: AudioProcessController
    @EnvironmentObject var browserTabStore: BrowserTabStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let playing = controller.playing
            if playing.isEmpty {
                emptyState
            } else {
                ForEach(playing) { process in
                    AudioProcessRow(process: process)
                    if process.id != playing.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
        .onAppear { controller.beginLiveUpdates() }
        .onDisappear { controller.endLiveUpdates() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Nothing is playing")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            if !controller.audioPermissionGranted {
                Label("First volume change asks for audio permission.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Quit Wavern") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                Spacer()
                if let url = updateChecker.updateURL {
                    Button("Update available →") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { launchAtLogin = LoginItem.setEnabled($0) }
        )
    }
}

// MARK: - AudioProcessRow

struct AudioProcessRow: View {
    let process: AudioProcess
    @EnvironmentObject var controller: AudioProcessController
    @EnvironmentObject var browserTabStore: BrowserTabStore
    @State private var isHovered = false
    @State private var showExtensionSheet = false

    private var isMuted: Bool { controller.isMuted(process) }

    private var volume: Binding<Double> {
        Binding(
            get: { isMuted ? 0 : Double(controller.volume(for: process)) },
            set: { controller.setVolume(Float($0), for: process) }
        )
    }

    private var enrichedTab: BrowserTab? {
        guard process.chromiumBrowserName != nil,
              browserTabStore.isConnected else { return nil }
        return browserTabStore.audibleTabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                artArea

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let tab = enrichedTab {
                            MarqueeText(text: tab.title, weight: .medium)
                        } else if let track = controller.nowPlaying(for: process) {
                            MarqueeText(text: track.title, weight: .medium)
                        } else {
                            MarqueeText(text: process.name, weight: .medium)
                        }
                        WaveformView(isAnimating: process.isPlaying && !isMuted)
                    }

                    if let tab = enrichedTab, let browserName = process.chromiumBrowserName {
                        Text(browserName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let track = controller.nowPlaying(for: process) {
                        MarqueeText(
                            text: track.subtitle.isEmpty
                                ? process.name
                                : "\(track.subtitle) · \(process.name)",
                            font: .caption
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        Text(process.isPlaying ? "Playing" : "Idle")
                            .font(.caption)
                            .foregroundStyle(process.isPlaying ? Color.green : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if controller.nowPlaying(for: process) != nil {
                    transportControls
                }

                Button { process.activate() } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Bring \(process.name) to front")
            }

            HStack(spacing: 8) {
                Button {
                    controller.toggleMute(process)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .foregroundStyle(isMuted ? Color.red : .primary)
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help(isMuted ? "Unmute" : "Mute")

                Slider(value: volume, in: 0...Double(AudioProcessController.maxGain))
                    .controlSize(.small)
                    .tint(.accentColor)

                Text(percentLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            if process.chromiumBrowserName != nil && !browserTabStore.isConnected {
                Button("Install browser extension for tab names →") {
                    showExtensionSheet = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            if let error = controller.tapErrors[process.id] {
                Text(errorHint(error))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovered ? Color(NSColor.quaternaryLabelColor).opacity(0.3) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showExtensionSheet) {
            ExtensionOnboardingSheet()
        }
    }

    private var percentLabel: String {
        if isMuted { return "muted" }
        return "\(Int((controller.volume(for: process) * 100).rounded()))%"
    }

    private func errorHint(_ raw: String) -> String {
        "Couldn't tap audio. Grant Wavern permission in System Settings ▸ Privacy & Security ▸ Microphone, then retry."
    }

    @ViewBuilder private var transportControls: some View {
        let isPlaying = controller.nowPlaying(for: process)?.isPlaying ?? false
        HStack(spacing: 8) {
            Button { controller.sendMediaCommand(.previous, to: process) } label: {
                Image(systemName: "backward.fill")
            }.help("Previous track")
            Button { controller.sendMediaCommand(.playPause, to: process) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }.help(isPlaying ? "Pause" : "Play")
            Button { controller.sendMediaCommand(.next, to: process) } label: {
                Image(systemName: "forward.fill")
            }.help("Next track")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var artArea: some View {
        let artwork: NSImage? = controller.artworkImages[process.id]
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let icon = process.icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                            .frame(width: 40, height: 40)
                        Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 20)).foregroundStyle(.secondary)
                        }
                }
            }
            if artwork != nil, let icon = process.icon {
                Image(nsImage: icon)
                    .resizable().frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1))
                    .shadow(radius: 1)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

// MARK: - ExtensionOnboardingSheet

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
