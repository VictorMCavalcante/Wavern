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
        }
        refreshMasterVolume()
        refreshOutputDevices()
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
        do {
            try id.write(clamped, Self.mainVolume, scope: kAudioObjectPropertyScopeOutput)
        } catch {
            log.error("Master volume write failed: \(String(describing: error), privacy: .public)")
        }
    }

    func refreshOutputDevices() {
        guard let ids: [AudioObjectID] = try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices)
        else { return }
        let devices = ids.compactMap { id -> OutputDevice? in
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
        setOutputDevices(devices)
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
