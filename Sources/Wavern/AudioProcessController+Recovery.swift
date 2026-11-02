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
        !uncontrolled.contains(p.id)
            && (isMuted(p) || volume(for: p) != 1 || (isDucked(p) && p.isPlaying))
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
        if reason != .watchdog {
            lastRouteEvent = ProcessInfo.processInfo.systemUptime
            giveUp.reset()
            setUncontrolled([])
        }
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
        for t in old where t.lastNonZero > 0 {
            carriedNonZero[t.process.id] = max(carriedNonZero[t.process.id] ?? 0, t.lastNonZero)
        }
        // A muted app the watchdog gave up on stays on its mute-only tap; any other rebuild retries control.
        let keepMuteOnly = reason == .watchdog
            ? Set(old.filter { $0.mode == .muteOnly }.map(\.process.id)) : []
        taps = [:]
        tapErrors = [:]
        let rebuilt = processes.filter(needsTap)
        for p in rebuilt {
            let mode: ProcessTap.Mode = keepMuteOnly.contains(p.id) && isMuted(p) ? .muteOnly : .control
            ensureTap(for: p, initialGain: effectiveGain(for: p), mode: mode)
        }
        // After the loop on purpose: the hop lands behind the new activations, so an app
        // is never left without a tap (a muted app would play natively in that gap).
        retire(old) { [hal = halQueue] in
            // A leak shows as more aggregates than taps. The device list lags a destroy
            // by a moment, so count after it settles.
            hal.asyncAfter(deadline: .now() + 1) { Self.logAggregateCount(expected: rebuilt.count) }
        }
        log.notice("Tap rebuild (\(reason.rawValue, privacy: .public)): \(old.count) torn down, \(rebuilt.count) created")
    }

    /// Hop through halQueue first so any activate() still queued for these taps
    /// finishes before invalidate() (otherwise it would build an aggregate nobody
    /// tears down), then tear down on teardownQueue: a dead device can stall.
    func retire(_ old: [ProcessTap], then: (@Sendable () -> Void)? = nil) {
        let teardown = teardownQueue
        halQueue.async {
            teardown.async {
                old.forEach { $0.invalidate() }
                then?()
            }
        }
    }

    // MARK: Watchdog

    func startWatchdogIfNeeded() {
        guard watchdogTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchdogTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdogTimer = t
    }

    /// User touched the app: forget the give-up and, if it is being unmuted, drop
    /// the mute-only tap so the caller's applyGain builds a control tap again.
    func retryControl(_ p: AudioProcess, unmuting: Bool) {
        if uncontrolled.contains(p.id) { setUncontrolled(uncontrolled.subtracting([p.id])) }
        giveUp.clear(p.id)
        if unmuting, let tap = taps[p.id], tap.mode == .muteOnly {
            taps.removeValue(forKey: p.id)
            retire([tap])
        }
    }

    private func watchdogTick() {
        carriedNonZero = carriedNonZero.filter { taps[$0.key] != nil }
        if taps.values.contains(where: { $0.lastNonZero > 0 }) { rememberPermissionGranted() }
        guard rebuildWork == nil else { return }   // a rebuild is already on its way
        let now = ProcessInfo.processInfo.systemUptime
        let playing = Set(processes.filter(\.isPlaying).map(\.id))
        var needsRebuild = false
        for (id, tap) in taps where tap.mode == .control && tap.isActive {
            if tap.lastNonZero > 0 { carriedNonZero[id] = nil }
            // A just-built tap gets stallTimeout to deliver sound before it is judged.
            guard now - tap.activatedAt > TapHealth.stallTimeout else { continue }
            let snap = TapSnapshot(isPlaying: playing.contains(id), activatedAt: tap.activatedAt,
                                   lastCallback: tap.lastCallback,
                                   lastNonZero: max(tap.lastNonZero, carriedNonZero[id] ?? 0))
            let verdict = TapHealth.verdict(snap, now: now, lastEvent: lastRouteEvent)
            guard verdict != .healthy else { continue }
            let name = tap.process.name
            // Silence can be real (paused tab keeping its output open): one rebuild, then
            // stop judging it on the old sound. Only a stalled tap counts toward give-up.
            if verdict == .silentAfterEvent {
                log.notice("Watchdog: \(name, privacy: .public) silent after route event, one retry")
                carriedNonZero[id] = nil
                needsRebuild = true
                continue
            }
            guard giveUp.strike(id) else {
                log.notice("Watchdog: \(name, privacy: .public) \(String(describing: verdict), privacy: .public)")
                needsRebuild = true
                continue
            }
            taps.removeValue(forKey: id)
            if isMuted(tap.process) {
                log.notice("Watchdog: giving up on \(name, privacy: .public), holding it muted")
                ensureTap(for: tap.process, initialGain: 0, mode: .muteOnly)
            } else {
                log.notice("Watchdog: giving up on \(name, privacy: .public), back to native volume")
                setUncontrolled(uncontrolled.union([id]))
            }
            retire([tap])
        }
        if needsRebuild { rebuildAllTaps(reason: .watchdog) }
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
