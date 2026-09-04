import AppKit
import CoreAudio
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var controller: AudioProcessController
    @EnvironmentObject var browserTabStore: BrowserTabStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.masterVolume != nil {
                masterVolumeRow
                Divider().opacity(0.5)
            }
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

    private var masterVolume: Binding<Double> {
        Binding(
            get: { Double(controller.masterVolume ?? 0) },
            set: { controller.setMasterVolume(Float($0)) }
        )
    }

    private var masterVolumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            VolumeSlider(value: masterVolume, maxValue: 1, isMuted: false)
                .frame(height: 16)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help("System output volume")
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
            if !controller.outputDevices.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: currentDevice?.symbol ?? "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("", selection: deviceSelection) {
                        ForEach(controller.outputDevices) { device in
                            Label(device.name, systemImage: device.symbol).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    Spacer()
                    Text("volumes saved per device")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .help("Output device. Each device keeps its own per-app volumes.")
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

    private var currentDevice: OutputDevice? {
        controller.outputDevices.first { $0.id == controller.outputDeviceID }
    }

    private var deviceSelection: Binding<AudioObjectID> {
        Binding(
            get: { controller.outputDeviceID },
            set: { controller.selectOutputDevice($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { launchAtLogin = LoginItem.setEnabled($0) }
        )
    }
}
