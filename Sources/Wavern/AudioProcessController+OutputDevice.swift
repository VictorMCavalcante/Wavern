import AudioToolbox
import CoreAudio
import Foundation

/// One selectable output device, as shown in the menu's device picker.
struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let name: String
    let transport: UInt32

    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods") || n.contains("headphone") || n.contains("buds") || n.contains("headset") {
            return "headphones"
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "display"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "hifispeaker.fill"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        default: return "speaker.wave.2"
        }
    }
}

/// System-wide output: the device picker and the master volume slider, the
/// same two controls as macOS's own Sound menu. Master volume is the device's
/// virtual main volume, so it matches the menu-bar slider and the volume keys.
extension AudioProcessController {

    private static let mainVolume = kAudioHardwareServiceDeviceProperty_VirtualMainVolume

    /// Point volume tracking at `id` (the new default device) and refresh the list.
    func attachOutputDevice(_ id: AudioObjectID) {
        if outputDeviceID.isValid { unlisten(outputDeviceID) }
        outputDeviceID = id
        if id.isValid {
            listen(Self.mainVolume, on: id, scope: kAudioObjectPropertyScopeOutput) { [weak self] in
                self?.refreshMasterVolume()
            }
            // Taps are built for one format; a real change means rebuild. These also fire
            // without a change (aggregates come and go on the device), so compare first.
            tapFormat = Self.formatSignature(id)
            listen(kAudioDevicePropertyNominalSampleRate, on: id) { [weak self] in
                self?.formatMayHaveChanged(id)
            }
            listen(kAudioDevicePropertyStreamConfiguration, on: id, scope: kAudioObjectPropertyScopeOutput) { [weak self] in
                self?.formatMayHaveChanged(id)
            }
            listen(kAudioDevicePropertyDeviceIsAlive, on: id) { [weak self] in
                let alive: UInt32 = (try? id.read(kAudioDevicePropertyDeviceIsAlive, default: UInt32(1))) ?? 0
                if alive == 0 { self?.rebuildAllTaps(reason: .deviceDied) }
            }
        }
        refreshMasterVolume()
        refreshOutputDevices()
    }

    private func formatMayHaveChanged(_ id: AudioObjectID) {
        guard id == outputDeviceID else { return }
        let now = Self.formatSignature(id)
        guard now != tapFormat else { return }
        log.notice("Output format \(self.tapFormat, privacy: .public) → \(now, privacy: .public)")
        tapFormat = now
        rebuildAllTaps(reason: .formatChanged)
    }

    /// Sample rate + channels of each output stream, e.g. "48000:2".
    nonisolated static func formatSignature(_ id: AudioObjectID) -> String {
        let rate: Float64 = (try? id.read(kAudioDevicePropertyNominalSampleRate, default: Float64(0))) ?? 0
        let streams: [AudioObjectID] = (try? id.readArray(
            kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)) ?? []
        let channels = streams.map { s -> String in
            let f: AudioStreamBasicDescription? = try? s.read(
                kAudioStreamPropertyVirtualFormat, default: AudioStreamBasicDescription())
            return String(f?.mChannelsPerFrame ?? 0)
        }
        return "\(Int(rate)):" + channels.joined(separator: ",")
    }

    func refreshMasterVolume() {
        let id = outputDeviceID
        guard id.isValid,
              id.hasProperty(Self.mainVolume, scope: kAudioObjectPropertyScopeOutput),
              let v: Float32 = try? id.read(Self.mainVolume, scope: kAudioObjectPropertyScopeOutput,
                                            default: Float32(1)) else {
            setMasterVolumeState(nil)
            return
        }
        setMasterVolumeState(v)
    }

    func setMasterVolume(_ value: Float) {
        let id = outputDeviceID
        guard id.isValid else { return }
        let clamped = min(max(value, 0), 1)
        setMasterVolumeState(clamped)
        volumeQueue.async {
            do {
                try id.write(clamped, Self.mainVolume, scope: kAudioObjectPropertyScopeOutput)
            } catch {
                log.error("Master volume write failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func scheduleOutputDevicesRefresh() {
        deviceListWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshOutputDevices() }
        deviceListWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func refreshOutputDevices() {
        deviceListWork = nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let devices = Self.readOutputDevices() else { return }
            Task { @MainActor in self?.setOutputDevices(devices) }
        }
    }

    nonisolated private static func readOutputDevices() -> [OutputDevice]? {
        guard let ids: [AudioObjectID] = try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices)
        else { return nil }
        return ids.compactMap { id -> OutputDevice? in
            guard id.isValid,
                  (try? id.readArray(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput,
                                     of: AudioObjectID.self).isEmpty) == false,
                  let uid: String = try? id.readCF(kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(ProcessTap.aggregateUIDPrefix),
                  let name: String = try? id.readCF(kAudioObjectPropertyName)
            else { return nil }
            let hidden: UInt32 = (try? id.read(kAudioDevicePropertyIsHidden, default: UInt32(0))) ?? 0
            guard hidden == 0 else { return nil }
            let transport: UInt32 = (try? id.read(kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0
            // Virtual drivers (Teams, Zoom) are hidden by macOS's Sound menu too.
            guard transport != kAudioDeviceTransportTypeVirtual else { return nil }
            return OutputDevice(id: id, name: name, transport: transport)
        }
    }

    /// Make `id` the system default output; the HAL notifies us back and the
    /// normal device-change path swaps profile and taps.
    func selectOutputDevice(_ id: AudioObjectID) {
        guard id.isValid, id != outputDeviceID else { return }
        do {
            try AudioObjectID.system.write(id, kAudioHardwarePropertyDefaultOutputDevice)
        } catch {
            log.error("Selecting output device failed: \(String(describing: error), privacy: .public)")
        }
    }
}
