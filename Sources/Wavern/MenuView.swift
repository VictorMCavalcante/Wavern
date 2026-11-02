import AppKit
import CoreAudio
import SwiftUI

/// Panel content, CrispShot style: header with the output chip, master tile,
/// "Now playing" tiles (one highlighted), footer chips.
struct MenuView: View {
    @EnvironmentObject var controller: AudioProcessController
    @EnvironmentObject var browserTabStore: BrowserTabStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var hoveredID: AudioObjectID?
    @State private var listHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if controller.masterVolume != nil {
                masterTile.padding(.top, 10)
            }
            let tiles = orderedPlaying
            if tiles.isEmpty {
                emptyState
            } else {
                Text("Now playing")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 2)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                // A tile removed under the cursor never reports hover-out; ignore its stale id.
                let highlighted = tiles.contains { $0.id == hoveredID } ? hoveredID : tiles.first(where: \.isPlaying)?.id
                ScrollView {
                VStack(spacing: 6) {
                    ForEach(tiles) { process in
                        AudioProcessRow(process: process, isFocused: process.id == highlighted)
                            .onHover { hoveredID = $0 ? process.id : (hoveredID == process.id ? nil : hoveredID) }
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.3), value: tiles.map(\.id))
                .padding(.horizontal, 12)   // room for the focused tile's glow inside the clip
                .padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                // Grows with the tiles up to the cap, then scrolls. Until measured, guess
                // from the tile count so the panel opens near its final size.
                .frame(height: min(listHeight ?? CGFloat(tiles.count) * 76 + 12, Self.listMaxHeight))
                .padding(.horizontal, -12)
                .padding(.vertical, -6)
            }
            footer
        }
        .padding(12)
        .frame(width: Theme.panelWidth)
        .background(BrandSurface())
    }

    /// Panel cap minus header, master tile and footer.
    private static let listMaxHeight = Theme.panelMaxHeight - 170

    /// Focused app first, then the rest that are playing, then the lingering ones.
    private var orderedPlaying: [AudioProcess] {
        let focused = controller.focusedID
        return controller.playing.enumerated().sorted { a, b in
            func rank(_ p: AudioProcess) -> Int { p.id == focused ? 0 : (p.isPlaying ? 1 : 2) }
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Wavern")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            if !controller.outputDevices.isEmpty {
                MenuChip {
                    Section("Volumes are saved per device") {
                        ForEach(controller.outputDevices) { device in
                            Button { controller.selectOutputDevice(device.id) } label: {
                                Label(device.name, systemImage: device.id == controller.outputDeviceID ? "checkmark" : device.symbol)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: currentDevice?.symbol ?? "speaker.wave.2")
                            .symbolRenderingMode(.hierarchical)
                        Text(currentDevice?.name ?? controller.outputDeviceName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 150, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.quiet)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.icon)
                }
                .help("Output device. Each device keeps its own per-app volumes.")
            }
        }
    }

    // MARK: Master

    private var masterVolume: Binding<Double> {
        Binding(
            get: { Double(controller.masterVolume ?? 0) },
            set: { controller.setMasterVolume(Float($0)) }
        )
    }

    private var masterTile: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.icon)
                .frame(width: 16)
            VolumeSlider(value: masterVolume, maxValue: 1, isMuted: false)
                .frame(height: 16)
            Text("\(Int(((controller.masterVolume ?? 0) * 100).rounded()))%")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Theme.quiet)
                .frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help("System output volume")
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(nsImage: BrandGlyph.menuBarImage(playing: false))
                .renderingMode(.template)
                .resizable()
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.quiet)
            Text("Nothing is playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.icon)
            Text("Apps show up here the moment they make a sound.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.quiet)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.divider).frame(height: 1)
                .padding(.top, 8)
                .padding(.bottom, 2)
            HStack(spacing: 6) {
                MenuChip {
                    Section("Lower other apps during calls") {
                        ForEach(AudioProcessController.duckLevels, id: \.self) { level in
                            Button { controller.duckLevel = level } label: {
                                if level == controller.duckLevel {
                                    Label(duckLabel(level), systemImage: "checkmark")
                                } else {
                                    Text(duckLabel(level))
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.wave.2")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(controller.isDucking ? AnyShapeStyle(Theme.accentLight) : AnyShapeStyle(Theme.icon))
                        Text("Calls · \(duckLabel(controller.duckLevel))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.icon)
                }
                .help("Lower other apps while a call app uses the microphone")
                Spacer()
                if updateChecker.updateURL != nil {
                    Chip {
                        Button(updateChecker.isInstalling ? "Installing…" : "Update") { updateChecker.installUpdate() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accentLight)
                            .disabled(updateChecker.isInstalling)
                    }
                }
                MenuChip { settingsMenu } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.icon)
                }
                .help("Settings")
            }
            if controller.mediaKeysNeedPermission {
                Label("Media keys need Accessibility access — see ⚙︎", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.quiet)
            }
            if !controller.audioPermissionGranted {
                Label("First volume change asks for audio permission.", systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.quiet)
            }
        }
    }

    @ViewBuilder private var settingsMenu: some View {
        Toggle("Media keys follow the playing app", isOn: $controller.mediaKeysEnabled)
        if controller.mediaKeysNeedPermission {
            Button("Open Accessibility settings…") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            Button("Retry media keys") { controller.retryMediaKeys() }
        }
        Toggle("Launch at login", isOn: launchAtLoginBinding)
        if updateChecker.updateURL != nil {
            Button(updateChecker.isInstalling ? "Installing update…" : "Install update") { updateChecker.installUpdate() }
                .disabled(updateChecker.isInstalling)
        }
        Divider()
        Button("Quit Wavern") { NSApp.terminate(nil) }
    }

    private func duckLabel(_ level: Float) -> String {
        level >= 1 ? "Off" : "\(Int(level * 100))%"
    }

    private var currentDevice: OutputDevice? {
        controller.outputDevices.first { $0.id == controller.outputDeviceID }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { launchAtLogin = LoginItem.setEnabled($0) }
        )
    }
}
