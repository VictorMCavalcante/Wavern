import AppKit
import SwiftUI

struct AudioProcessRow: View {
    let process: AudioProcess
    @EnvironmentObject var controller: AudioProcessController
    @EnvironmentObject var browserTabStore: BrowserTabStore
    @State private var isHovered = false
    @State private var showExtensionSheet = false

    private var isMuted: Bool { controller.isMuted(process) }
    private var isDucker: Bool { controller.isDucker(process) }
    private var isDucked: Bool { controller.isDucked(process) }
    private var artwork: NSImage? { controller.artworkImages[process.id] }

    private var volume: Binding<Double> {
        Binding(
            get: { isMuted ? 0 : Double(controller.volume(for: process)) },
            set: { controller.setVolume(Float($0), for: process) }
        )
    }

    private var browserTabs: [BrowserTab] {
        guard process.chromiumBrowserName != nil, browserTabStore.isConnected else { return [] }
        return browserTabStore.audibleTabs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                artArea

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if browserTabs.count == 1, let tab = browserTabs.first {
                            MarqueeText(text: tab.title, weight: .semibold)
                        } else if let track = controller.nowPlaying(for: process) {
                            MarqueeText(text: track.title, weight: .semibold)
                        } else {
                            MarqueeText(text: process.name, weight: .semibold)
                        }
                        WaveformView(isAnimating: process.isPlaying && !isMuted)
                    }
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if controller.nowPlaying(for: process) != nil {
                    transportControls
                }

                Button { controller.toggleDucker(process) } label: {
                    Image(systemName: isDucker ? "person.wave.2.fill" : "person.wave.2")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isDucker ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .opacity(isHovered || isDucker ? 1 : 0)
                .help(isDucker ? "Lowers other apps while playing" : "Lower other apps while this plays")

                Button { process.activate() } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .opacity(isHovered ? 1 : 0)
                .help("Bring \(process.name) to front")
            }

            HStack(spacing: 10) {
                Button {
                    controller.toggleMute(process)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : speakerSymbol)
                        .font(.system(size: 12))
                        .foregroundStyle(isMuted ? Color.red : .secondary)
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(isMuted ? "Unmute" : "Mute")

                VolumeSlider(value: volume,
                             maxValue: Double(AudioProcessController.maxGain),
                             isMuted: isMuted)
                    .frame(height: 20)

                HStack(spacing: 2) {
                    if isDucked && !isMuted {
                        Image(systemName: "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(percentLabel)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(isBoosted ? Color.orange : .secondary)
                        .contentTransition(.numericText())
                }
                .frame(width: 44, alignment: .trailing)
                .help(isDucked ? "Ducked to \(Int(controller.duckLevel * 100))% while a call is active" : "")
            }

            if browserTabs.count > 0 {
                VStack(spacing: 4) {
                    ForEach(browserTabs) { tab in
                        BrowserTabRow(tab: tab)
                    }
                }
                .padding(.leading, 28)
            }

            if process.chromiumBrowserName != nil && !browserTabStore.isConnected {
                Button("Install browser extension for tab names →") {
                    showExtensionSheet = true
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
            }

            if let error = controller.tapErrors[process.id] {
                Text(errorHint(error))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            ZStack {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 28)
                        .opacity(isMuted ? 0.12 : 0.3)
                        .saturation(1.3)
                }
                Color.primary.opacity(isHovered ? 0.07 : 0.04)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 0.5)
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showExtensionSheet) {
            ExtensionOnboardingSheet()
        }
    }

    @ViewBuilder private var subtitle: some View {
        if !browserTabs.isEmpty, let browserName = process.chromiumBrowserName {
            Text(browserTabs.count == 1 ? browserName : "\(browserTabs.count) tabs playing")
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
        } else if process.isPlaying {
            Text("Playing")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        } else {
            Text("Played just now")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
        HStack(spacing: 10) {
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
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var artArea: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                } else if let icon = process.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .frame(width: 44, height: 44)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary)
                        .frame(width: 44, height: 44)
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
                    .shadow(radius: 2)
                    .offset(x: 4, y: 4)
            }
        }
        .opacity(isMuted ? 0.55 : 1)
    }
}
