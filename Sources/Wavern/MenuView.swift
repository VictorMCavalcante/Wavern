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
                VStack(spacing: 6) {
                    ForEach(playing) { process in
                        AudioProcessRow(process: process)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(8)
                .animation(.snappy(duration: 0.3), value: playing.map(\.id))
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 350)
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear { controller.beginLiveUpdates() }
        .onDisappear { controller.endLiveUpdates() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom))
            Text("Nothing is playing")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Apps show up here the moment they make a sound.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(controller.isDucking ? Color.accentColor : .secondary)
                Text("Duck others during calls")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $controller.duckLevel) {
                    ForEach(AudioProcessController.duckLevels, id: \.self) { level in
                        Text(level >= 1 ? "Off" : "to \(Int(level * 100))%").tag(level)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 84)
            }
            if !controller.outputDeviceName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: deviceSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(controller.outputDeviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("volumes saved per device")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .help("Each output device keeps its own per-app volumes.")
            }
            HStack(spacing: 6) {
                Image(systemName: "playpause")
                    .font(.system(size: 11))
                    .foregroundStyle(controller.mediaKeysEnabled && !controller.mediaKeysNeedPermission
                                     ? Color.accentColor : .secondary)
                Text("Media keys follow the playing app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $controller.mediaKeysEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .help("F7/F8/F9 and AirPods taps control the app that is actually playing, not whatever macOS picked.")
            if controller.mediaKeysNeedPermission {
                HStack(spacing: 4) {
                    Label("Needs Accessibility access.", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Button("Open settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(.borderless).font(.caption2)
                    Button("Retry") { controller.retryMediaKeys() }
                        .buttonStyle(.borderless).font(.caption2)
                }
            }
            HStack {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Spacer()
                if updateChecker.updateURL != nil {
                    Button(updateChecker.isInstalling ? "Installing…" : "Update available") {
                        updateChecker.installUpdate()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .disabled(updateChecker.isInstalling)
                }
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Quit Wavern")
            }
            if !controller.audioPermissionGranted {
                Label("First volume change asks for audio permission.",
                      systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var deviceSymbol: String {
        let n = controller.outputDeviceName.lowercased()
        if n.contains("airpods") || n.contains("headphone") || n.contains("buds") || n.contains("headset") {
            return "headphones"
        }
        if n.contains("hdmi") || n.contains("display") || n.contains("monitor") { return "display" }
        if n.contains("bluetooth") || n.contains("speaker") { return "hifispeaker.fill" }
        return "speaker.wave.2"
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
        "Couldn't tap audio. Grant Wavern permission in System Settings ▸ Privacy & Security ▸ Microphone, then retry."
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

// MARK: - BrowserTabRow

/// One audible browser tab: favicon, title, and its own 0–100% slider.
/// Applied inside the page by the extension (media element volume), on top
/// of the browser-wide tap gain above it.
struct BrowserTabRow: View {
    let tab: BrowserTab
    @EnvironmentObject var browserTabStore: BrowserTabStore

    private var volume: Binding<Double> {
        Binding(
            get: { Double(browserTabStore.volume(for: tab)) },
            set: { browserTabStore.setVolume(Float($0), for: tab) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            favicon
            MarqueeText(text: tab.title, font: .caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            VolumeSlider(value: volume, maxValue: 1, isMuted: false)
                .frame(height: 16)
            Text("\(Int((browserTabStore.volume(for: tab) * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .opacity(tab.tabId == nil ? 0.5 : 1)
        .help(tab.tabId == nil ? "Reload the Wavern extension in Chrome to control this tab." : tab.host ?? "")
    }

    @ViewBuilder private var favicon: some View {
        let placeholder = Image(systemName: "globe")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        if let s = tab.favIconUrl, let url = URL(string: s), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    placeholder.frame(width: 14, height: 14)
                }
            }
        } else {
            placeholder.frame(width: 14, height: 14)
        }
    }
}

// MARK: - VolumeSlider

/// Gradient volume slider: accent up to unity, warming into orange for the
/// boost zone. A tick marks 100%. Drag anywhere on the track to set the value.
struct VolumeSlider: View {
    @Binding var value: Double
    let maxValue: Double
    var isMuted: Bool

    @State private var isDragging = false
    @State private var isHovered = false

    private let trackHeight: CGFloat = 5
    private let thumbSize: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let frac = CGFloat(min(max(value / maxValue, 0), 1))
            let unityFrac = CGFloat(1 / maxValue)
            let thumbX = frac * (width - thumbSize) + thumbSize / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)

                LinearGradient(
                    stops: [
                        .init(color: .accentColor.opacity(0.75), location: 0),
                        .init(color: .accentColor, location: unityFrac),
                        .init(color: .orange, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(thumbX, trackHeight))
                    }
                    .saturation(isMuted ? 0 : 1)
                    .opacity(isMuted ? 0.4 : 1)

                // Unity tick
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 2, height: trackHeight + 4)
                    .offset(x: unityFrac * (width - thumbSize) + thumbSize / 2 - 1)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .scaleEffect(isDragging ? 1.2 : (isHovered ? 1.08 : 1))
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        let f = (g.location.x - thumbSize / 2) / max(width - thumbSize, 1)
                        value = min(max(Double(f), 0), 1) * maxValue
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isDragging)
            .animation(.easeOut(duration: 0.12), value: isHovered)
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
