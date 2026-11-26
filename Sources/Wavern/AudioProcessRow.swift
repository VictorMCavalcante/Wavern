import AppKit
import SwiftUI

struct AudioProcessRow: View {
    let process: AudioProcess
    /// The one highlighted tile: lilac gradient, white text and slider.
    var isFocused = false
    @EnvironmentObject var controller: AudioProcessController
    @EnvironmentObject var browserTabStore: BrowserTabStore
    @State private var isHovered = false
    @State private var showExtensionSheet = false

    private var isMuted: Bool { controller.isMuted(process) }
    private var isDucker: Bool { controller.isDucker(process) }
    private var isDucked: Bool { controller.isDucked(process) }
    private var artwork: NSImage? { controller.artworkImages[process.id] }

    private var textColor: Color { isFocused ? .white : .primary }
    private var subColor: AnyShapeStyle { isFocused ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(Theme.quiet) }
    private var iconColor: AnyShapeStyle { isFocused ? AnyShapeStyle(Color.white.opacity(0.9)) : AnyShapeStyle(Theme.icon) }

    private var volume: Binding<Double> {
        Binding(
            get: { isMuted ? 0 : Double(controller.volume(for: process)) },
            set: { controller.setVolume(Float($0), for: process) }
        )
    }

    private var browserTabs: [BrowserTab] {
        guard let source = process.browserTabSource, browserTabStore.isConnected(source) else { return [] }
        return browserTabStore.tabs(for: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                artArea

                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if browserTabs.count == 1, let tab = browserTabs.first {
                            MarqueeText(text: tab.title, font: .system(size: 12), weight: titleWeight)
                        } else if let track = controller.nowPlaying(for: process) {
                            MarqueeText(text: track.title, font: .system(size: 12), weight: titleWeight)
                        } else {
                            MarqueeText(text: process.name, font: .system(size: 12), weight: titleWeight)
                        }
                    }
                    .foregroundStyle(textColor)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered || isDucker {
                    iconButton(isDucker ? "person.wave.2.fill" : "person.wave.2",
                               help: isDucker ? "Lowers other apps while playing" : "Lower other apps while this plays") {
                        controller.toggleDucker(process)
                    }
                }
                if isHovered {
                    iconButton("arrow.up.forward", help: "Bring \(process.name) to front") { process.activate() }
                }

                if controller.nowPlaying(for: process) != nil {
                    transportControls
                }

                trailingLabel
            }

            HStack(spacing: 8) {
                Button {
                    controller.toggleMute(process)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : speakerSymbol)
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isMuted ? AnyShapeStyle(Theme.record) : iconColor)
                        .frame(width: 16)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Unmute" : "Mute")

                VolumeSlider(value: volume,
                             maxValue: Double(AudioProcessController.maxGain),
                             isMuted: isMuted,
                             onAccent: isFocused)
                    .frame(height: 16)
            }

            if browserTabs.count > 0 {
                VStack(spacing: 4) {
                    ForEach(browserTabs) { tab in
                        BrowserTabRow(tab: tab, onAccent: isFocused)
                    }
                }
                .padding(.leading, 24)
            }

            if process.chromiumBrowserName != nil && !browserTabStore.isConnected("") {
                Button("Install browser extension for tab names →") {
                    showExtensionSheet = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(isFocused ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accentLight))
            }

            if controller.isUncontrolled(process) {
                Button { controller.retry(process) } label: {
                    Label("No control — tap to retry", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(subColor)
            }

            if let error = controller.tapErrors[process.id] {
                Text(errorHint(error))
                    .font(.system(size: 10))
                    .foregroundStyle(isFocused ? Color.white : Theme.record)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            if isFocused {
                shape.fill(Theme.accentGradient).opacity(0.95)
                    .shadow(color: Theme.accentGlow.opacity(0.5), radius: 9, y: 4)
            } else {
                shape.fill(isHovered ? Theme.pressed : Theme.hover)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isMuted ? 0.55 : (process.isPlaying ? 1 : 0.75))
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showExtensionSheet) {
            ExtensionOnboardingSheet()
        }
    }

    private var titleWeight: Font.Weight { isFocused ? .semibold : .medium }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var trailingLabel: some View {
        if isMuted {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.record)
        } else {
            HStack(spacing: 2) {
                if isDucked {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isFocused ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accentLight))
                }
                Text(percentLabel)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(isBoosted && !isFocused ? AnyShapeStyle(Theme.accentLight) : subColor)
                    .contentTransition(.numericText())
            }
            .help(isDucked ? "Ducked to \(Int(controller.duckLevel * 100))% while a call is active" : "")
        }
    }

    @ViewBuilder private var subtitle: some View {
        Group {
            if !browserTabs.isEmpty, let browserName = process.chromiumBrowserName {
                Text(browserTabs.count == 1 ? browserName : "\(browserTabs.count) tabs playing")
            } else if let track = controller.nowPlaying(for: process) {
                MarqueeText(
                    text: track.subtitle.isEmpty
                        ? process.name
                        : "\(track.subtitle) · \(process.name)",
                    font: .system(size: 10)
                )
            } else if isDucker && controller.isDucking {
                Text("In a call · lowering others")
            } else if process.isPlaying {
                Text("Playing")
            } else {
                Text("Played just now")
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .foregroundStyle(subColor)
    }

    private var isBoosted: Bool { !isMuted && controller.volume(for: process) > 1.001 }

    private var speakerSymbol: String {
        let v = controller.volume(for: process)
        if v > 1.001 { return "speaker.wave.3.fill" }
        if v > 0.5 { return "speaker.wave.2.fill" }
        if v > 0 { return "speaker.wave.1.fill" }
        return "speaker.fill"
    }

    private var percentLabel: String {
        if isMuted { return "muted" }
        return "\(Int((controller.volume(for: process) * 100).rounded()))%"
    }

    private func errorHint(_ raw: String) -> String {
        "Couldn't tap audio. Grant Wavern permission in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then retry."
    }

    @ViewBuilder private var transportControls: some View {
        let isPlaying = controller.nowPlaying(for: process)?.isPlaying ?? false
        HStack(spacing: 8) {
            Button { controller.sendMediaCommand(.previous, to: process) } label: {
                Image(systemName: "backward.fill")
            }.help("Previous track")
            Button { controller.sendMediaCommand(.playPause, to: process) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }.help(isPlaying ? "Pause" : "Play")
            Button { controller.sendMediaCommand(.next, to: process) } label: {
                Image(systemName: "forward.fill")
            }.help("Next track")
        }
        .buttonStyle(.plain)
        .font(.system(size: 10))
        .foregroundStyle(iconColor)
    }

    @ViewBuilder private var artArea: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30)
                        .clipShape(shape)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                } else if let icon = process.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                } else {
                    shape.fill(Theme.hover)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 14)).foregroundStyle(iconColor)
                        }
                }
            }
            if artwork != nil, let icon = process.icon {
                Image(nsImage: icon)
                    .resizable().frame(width: 13, height: 13)
                    .shadow(radius: 1.5)
                    .offset(x: 3, y: 3)
            }
        }
    }
}
