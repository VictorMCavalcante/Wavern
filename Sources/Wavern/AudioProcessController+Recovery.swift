import CoreAudio
import Foundation

enum RebuildReason: String {
    case deviceChanged, sameDeviceNewID, formatChanged, deviceDied, wake, serviceRestarted, watchdog
}

/// One path to recover taps after anything that invalidates them (route,
/// format, sleep, coreaudiod restart): throw every tap away and recreate the
/// ones that need to exist, each born at its effective gain.
extension AudioProcessController {

    /// A tap exists only when it changes something: mute, non-unity volume, or ducking.
    func needsTap(_ p: AudioProcess) -> Bool {
        isMuted(p) || volume(for: p) != 1 || (isDucked(p) && p.isPlaying)
    }

    /// volume × mute × ducking.
    func effectiveGain(for p: AudioProcess) -> Float {
        var g: Float = isMuted(p) ? 0 : volume(for: p)
        if isDucked(p) { g *= duckLevel }
        return g
    }

    /// Coalesced: a burst of triggers (rapid device switching) yields one rebuild,
    /// run once the route has settled. Bluetooth settles slower.
    func rebuildAllTaps(reason: RebuildReason) {
        log.notice("Tap rebuild requested: \(reason.rawValue, privacy: .public)")
        if reason != .watchdog { lastRouteEvent = ProcessInfo.processInfo.systemUptime }
        rebuildWork?.cancel()
        let transport: UInt32 = (try? outputDeviceID.read(
            kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.performRebuild(reason) }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (bluetooth ? 0.3 : 0.05), execute: work)
    }

    private func performRebuild(_ reason: RebuildReason) {
        rebuildWork = nil
        let old = Array(taps.values)
        taps = [:]
        tapErrors = [:]
        // Hop through halQueue first so any activate() still queued for these
        // taps finishes before invalidate(); otherwise it would build an
        // aggregate nobody tears down.
        let teardown = teardownQueue, hal = halQueue
        let rebuilt = processes.filter(needsTap)
        hal.async {
            teardown.async {
                old.forEach { $0.invalidate() }
                // Queued behind the new taps' activations: a leak shows as more aggregates than taps.
                hal.async { Self.logAggregateCount(expected: rebuilt.count) }
            }
        }
        for p in rebuilt { ensureTap(for: p, initialGain: effectiveGain(for: p)) }
        log.notice("Tap rebuild (\(reason.rawValue, privacy: .public)): \(old.count) torn down, \(rebuilt.count) created")
    }

    /// Our private aggregates are invisible to other processes, so only we can count them.
    nonisolated private static func logAggregateCount(expected: Int) {
        let devices: [AudioObjectID] = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices)) ?? []
        let ours = devices.filter {
            ((try? $0.readCF(kAudioDevicePropertyDeviceUID, as: String.self)) ?? nil)?
                .hasPrefix(ProcessTap.aggregateUIDPrefix) == true
        }.count
        log.notice("Aggregates alive after rebuild: \(ours) (taps: \(expected))")
    }
}
