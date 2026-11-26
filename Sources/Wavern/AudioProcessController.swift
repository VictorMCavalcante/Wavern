import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Central model: which processes make sound, their taps and gains, and the
/// output device profile. Ducking, media keys and now-playing metadata live in
/// the `+Ducking`, `+MediaKeys` and `+NowPlaying` extensions.
///
/// Threading: all state is main-actor. Blocking HAL calls (enumeration, tap
/// creation/teardown) run on `halQueue` and hop back to the main actor.
@MainActor
final class AudioProcessController: ObservableObject {

    static let shared = AudioProcessController()

    let settings = SettingsStore()
    let browserTabStore: BrowserTabStore
    let halQueue = DispatchQueue(label: "com.wavern.hal", qos: .userInitiated)
    /// Property notifications are delivered here, never on `halQueue`: a single
    /// HAL call can hang for coreaudiod's 30 s timeout, and the device-change
    /// notification must not queue behind it.
    let listenerQueue = DispatchQueue(label: "com.wavern.listeners", qos: .userInitiated)
    /// Old taps are torn down here, off `halQueue`: destroying an aggregate on a
    /// dead device can stall, and must not delay the replacement taps.
    let teardownQueue = DispatchQueue(label: "com.wavern.teardown", qos: .userInitiated)

    init() {
        browserTabStore = BrowserTabStore(settings: settings)
        audioPermissionGranted = settings.hasGrantedAudioTap
        duckLevel = settings.duckLevel
        mediaKeysEnabled = settings.mediaKeysEnabled
    }

    // MARK: State owned by the extensions (stored properties must live here)

    // +Ducking
    @Published var duckLevel: Float { didSet { duckLevelDidChange() } }
    @Published private(set) var isDucking = false
    var duckReleaseWork: DispatchWorkItem?
    var duckInputTimer: Timer?
    var duckerCache: [String: Bool] = [:]

    // +MediaKeys
    @Published var mediaKeysEnabled: Bool { didSet { mediaKeysEnabledDidChange() } }
    @Published private(set) var mediaKeysNeedPermission = false

    // +OutputDevice
    @Published private(set) var outputDevices: [OutputDevice] = []
    /// nil when the current device has no settable main volume.
    @Published private(set) var masterVolume: Float?
    var outputDeviceID: AudioObjectID = .unknown

    func setOutputDevices(_ v: [OutputDevice]) { outputDevices = v }
    func setMasterVolumeState(_ v: Float?) { masterVolume = v }

    // +NowPlaying
    @Published private(set) var nowPlaying: [AudioObjectID: NowPlaying] = [:]
    @Published private(set) var artworkImages: [AudioObjectID: NSImage] = [:]
    var nowPlayingRefreshInFlight = false
    var artworkCache: [String: NSImage] = [:]

    func setDucking(_ on: Bool) {
        guard isDucking != on else { return }
        isDucking = on
        log.info("Ducking \(on ? "on" : "off", privacy: .public) (level \(self.duckLevel))")
        reapplyAllGains()
    }
    func setMediaKeysNeedPermission(_ v: Bool) { mediaKeysNeedPermission = v }
    func setNowPlaying(_ v: [AudioObjectID: NowPlaying]) { nowPlaying = v }
    func setArtworkImages(_ v: [AudioObjectID: NSImage]) { artworkImages = v }

    // MARK: Processes

    @Published var processes: [AudioProcess] = []

    /// Processes currently outputting audio, plus any that did so within the
    /// last `lingerInterval` — so short sounds (notifications) stay adjustable.
    var playing: [AudioProcess] {
        let now = Date()
        return processes
            .filter { $0.isPlaying || (lingerUntil[$0.id] ?? .distantPast) > now }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var isAnyPlaying: Bool { processes.contains(where: \.isPlaying) }

    // MARK: Linger

    static let lingerInterval: TimeInterval = 30
    @Published private(set) var lingerUntil: [AudioObjectID: Date] = [:]
    /// The app that most recently started playing; the panel highlights it and lists it first.
    @Published private(set) var focusedID: AudioObjectID?
    private var lingerTimer: Timer?
    /// Last run-state change per process; drives idle tap pausing.
    var lastActivity: [AudioObjectID: Date] = [:]

    /// Called whenever a process starts or stops output: it was audible around now.
    func noteActivity(_ id: AudioObjectID) {
        log.info("Audio activity on process object \(id)")
        lingerUntil[id] = Date().addingTimeInterval(Self.lingerInterval)
        lastActivity[id] = Date()
        scheduleLingerExpiry()
    }

    private func scheduleLingerExpiry() {
        guard lingerTimer == nil, let next = lingerUntil.values.min() else { return }
        let delay = max(next.timeIntervalSinceNow, 0) + 0.1
        lingerTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.lingerTimer = nil
                let now = Date()
                self.lingerUntil = self.lingerUntil.filter { $0.value > now }
                self.scheduleLingerExpiry()
            }
        }
    }

    // MARK: Property listeners

    private struct ListenerKey: Hashable {
        let id: AudioObjectID
        let selector: AudioObjectPropertySelector
    }
    private var listeners: [ListenerKey: (AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = [:]

    func listen(_ selector: AudioObjectPropertySelector, on objectID: AudioObjectID,
                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                action: @escaping @MainActor () -> Void) {
        let key = ListenerKey(id: objectID, selector: selector)
        guard listeners[key] == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in action() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, listenerQueue, block)
        guard status == noErr else {
            log.error("Listener failed for \(selector.fourCC, privacy: .public) on \(objectID): \(status)")
            return
        }
        listeners[key] = (address, block)
    }

    private func listenProcess(_ selector: AudioObjectPropertySelector, on objectID: AudioObjectID) {
        listen(selector, on: objectID) { [weak self] in
            self?.resumeIdleTap(objectID)
            self?.noteActivity(objectID)
            self?.reload()
        }
    }

    func unlisten(_ objectID: AudioObjectID) {
        for key in listeners.keys where key.id == objectID {
            guard var entry = listeners.removeValue(forKey: key) else { continue }
            AudioObjectRemovePropertyListenerBlock(objectID, &entry.0, listenerQueue, entry.1)
        }
    }

    // MARK: Output device (= profile)

    /// Every output device carries its own set of per-app volumes. Switching
    /// device (AirPods ↔ speakers) swaps the whole profile and rebuilds taps,
    /// which are bound to the device they were created on.
    @Published private(set) var outputDeviceName: String = ""
    /// The device the current taps and profile belong to.
    var currentDevice = DeviceIdentity(id: .unknown, uid: "")

    // +Recovery
    var rebuildWork: DispatchWorkItem?
    /// Processes the pending rebuild covers; nil = all.
    var rebuildScope: Set<AudioObjectID>?
    /// Output format the taps were built for; format listeners rebuild only when it really changes.
    var tapFormat = ""
    var deviceListWork: DispatchWorkItem?
    /// Master-volume writes go here: a stalled HAL write must not freeze the panel mid-drag.
    let volumeQueue = DispatchQueue(label: "com.wavern.volume", qos: .userInitiated)
    var lastRouteEvent: TimeInterval?
    var watchdogTimer: Timer?
    var giveUp = GiveUpPolicy()
    /// Last sound heard per process before a rebuild replaced its tap (whose own stamp restarts at 0).
    var carriedNonZero: [AudioObjectID: TimeInterval] = [:]
    /// Given up with a reduced volume: left at native level until the user touches it.
    @Published private(set) var uncontrolled: Set<AudioObjectID> = []
    func setUncontrolled(_ v: Set<AudioObjectID>) { uncontrolled = v }
    func isUncontrolled(_ p: AudioProcess) -> Bool { uncontrolled.contains(p.id) }

    private func readOutputDevice() -> (id: AudioObjectID, uid: String, name: String) {
        guard let id: AudioObjectID = try? AudioObjectID.system.read(
                  kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown),
              id.isValid else { return (.unknown, "", "") }
        let uid: String = (try? id.readCF(kAudioDevicePropertyDeviceUID)) ?? ""
        let name: String = (try? id.readCF(kAudioObjectPropertyName)) ?? ""
        return (id, uid, name)
    }

    private func handleOutputDeviceChange() {
        let dev = readOutputDevice()
        let new = DeviceIdentity(id: dev.id, uid: dev.uid)
        switch classifyDeviceChange(old: currentDevice, new: new) {
        case .none:
            return
        case .sameProfileRebuild:
            // Same device re-enumerated with a new id (e.g. Bluetooth reconnect): keep volumes.
            log.notice("Output device \(dev.name, privacy: .public) has a new id \(dev.id)")
            currentDevice = new
            attachOutputDevice(dev.id)
            rebuildAllTaps(reason: .sameDeviceNewID)
        case .newProfile:
            log.notice("Output device changed to \(dev.name, privacy: .public)")
            currentDevice = new
            settings.deviceUID = dev.uid
            outputDeviceName = dev.name
            attachOutputDevice(dev.id)
            // Volumes belong to the old profile. Load the new one now (not via the
            // async reload) so the rebuild never sees an empty profile: a muted app
            // must not lose its tap. No taps are spawned here; the rebuild makes them.
            volumes = [:]
            muted = []
            restoredIDs = []
            for p in processes { loadPersistedState(for: p) }
            rebuildAllTaps(reason: .deviceChanged)
            reload()
        }
    }

    // MARK: Volume state

    static let maxGain: Float = 2.0

    var taps: [AudioObjectID: ProcessTap] = [:] {
        didSet { if taps.isEmpty { watchdogTimer?.invalidate(); watchdogTimer = nil } }
    }
    /// Processes whose saved state has been loaded (reset on device change).
    private var restoredIDs: Set<AudioObjectID> = []
    @Published private(set) var volumes: [AudioObjectID: Float] = [:]
    @Published private(set) var muted: Set<AudioObjectID> = []
    @Published var tapErrors: [AudioObjectID: String] = [:]
    @Published private(set) var audioPermissionGranted: Bool

    func volume(for process: AudioProcess) -> Float { volumes[process.id] ?? 1.0 }
    func isMuted(_ process: AudioProcess) -> Bool { muted.contains(process.id) }
    func hasTap(_ process: AudioProcess) -> Bool { taps[process.id] != nil }

    func setVolume(_ value: Float, for process: AudioProcess) {
        retryControl(process, unmuting: value > 0)
        if value > 0 { volumes[process.id] = value; muted.remove(process.id) } else { muted.insert(process.id) }
        if let b = process.resolvedBundleID { settings.setVolume(value, for: b) }
        applyGain(for: process)
    }

    /// Re-attempts control without touching volume or mute state.
    func retry(_ process: AudioProcess) {
        retryControl(process, unmuting: !isMuted(process))
        applyGain(for: process)
    }

    func toggleMute(_ process: AudioProcess) {
        let nowMuted = !muted.contains(process.id)
        retryControl(process, unmuting: !nowMuted)
        if nowMuted { muted.insert(process.id) } else { muted.remove(process.id) }
        if let b = process.resolvedBundleID { settings.setMuted(nowMuted, for: b) }
        applyGain(for: process)
    }

    /// Push the effective gain (volume × mute × ducking) to the process's tap,
    /// creating the tap if needed.
    func applyGain(for process: AudioProcess) {
        guard !uncontrolled.contains(process.id) else { return }   // given up: native until touched
        let effective = effectiveGain(for: process)
        ensureTap(for: process, initialGain: effective).gain = effective
    }

    /// Load saved volume/mute once per process. Apps with a non-default level
    /// get their tap created immediately ("proactive tap"), so the very next
    /// sound already comes out at the saved level.
    private func restorePersistedState(for process: AudioProcess) {
        if loadPersistedState(for: process) { applyGain(for: process) }
    }

    /// Loads saved volume/mute without touching taps. true = non-default level.
    @discardableResult
    private func loadPersistedState(for process: AudioProcess) -> Bool {
        guard !restoredIDs.contains(process.id) else { return false }
        restoredIDs.insert(process.id)
        guard let bundleID = process.resolvedBundleID else { return false }
        let saved = settings.volume(for: bundleID)
        let savedMuted = settings.isMuted(bundleID)
        if let saved { volumes[process.id] = saved }
        if savedMuted { muted.insert(process.id) }
        return (saved != nil && saved != 1) || savedMuted
    }

    /// Existing tap, or a new one that starts at `initialGain` (never a jump from 100%).
    @discardableResult
    func ensureTap(for process: AudioProcess, initialGain: Float,
                   mode: ProcessTap.Mode = .control, replacing old: ProcessTap? = nil) -> ProcessTap {
        if let existing = taps[process.id] { return existing }
        let tap = ProcessTap(process: process, mode: mode)
        tap.gain = initialGain
        taps[process.id] = tap
        startWatchdogIfNeeded()
        tapErrors[process.id] = nil
        let id = process.id
        let name = process.name
        halQueue.async { [weak self] in
            do {
                let started = Date()
                try tap.activate()
                // Both taps now carry this app; the old one fades out within a buffer.
                old?.gain = 0
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 1 {
                    log.error("Tap activation for \(name, privacy: .public) took \(elapsed, format: .fixed(precision: 1))s — coreaudiod stalled")
                }
            } catch {
                let message = String(describing: error)
                log.error("Tap activation failed for \(name, privacy: .public): \(message, privacy: .public)")
                Task { @MainActor in
                    guard let self, self.taps[id] === tap else { return }
                    self.taps.removeValue(forKey: id)
                    self.tapErrors[id] = message
                    // Mute is always mute: fall back to a mute-only tap (no aggregate needed).
                    if tap.mode == .control, self.isMuted(tap.process) {
                        self.ensureTap(for: tap.process, initialGain: 0, mode: .muteOnly)
                    }
                }
            }
        }
        return tap
    }

    func rememberPermissionGranted() {
        guard !audioPermissionGranted else { return }
        audioPermissionGranted = true
        settings.hasGrantedAudioTap = true
    }

    private func pruneVanished(livingIDs: Set<AudioObjectID>) {
        for (id, tap) in taps where !livingIDs.contains(id) {
            retire([tap])   // off halQueue: a stalled destroy must not block new activations
            taps.removeValue(forKey: id)
        }
        volumes = volumes.filter { livingIDs.contains($0.key) }
        muted = muted.filter { livingIDs.contains($0) }
        uncontrolled = uncontrolled.filter { livingIDs.contains($0) }
        tapErrors = tapErrors.filter { livingIDs.contains($0.key) }
        restoredIDs = restoredIDs.filter { livingIDs.contains($0) }
        lingerUntil = lingerUntil.filter { livingIDs.contains($0.key) }
        lastActivity = lastActivity.filter { livingIDs.contains($0.key) }
        if let f = focusedID, !livingIDs.contains(f) { focusedID = nil }
        // Only process listeners: the output device's (volume, format, alive) must survive.
        for id in Set(listeners.keys.map(\.id))
        where id != .system && id != outputDeviceID && !livingIDs.contains(id) {
            unlisten(id)
        }
    }

    // MARK: Lifecycle

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        log.info("Wavern starting")
        halQueue.async { ProcessTap.reapLeakedDevices() }
        let dev = readOutputDevice()
        currentDevice = DeviceIdentity(id: dev.id, uid: dev.uid)
        if !dev.uid.isEmpty { settings.deviceUID = dev.uid }
        outputDeviceName = dev.name
        attachOutputDevice(dev.id)
        registerSystemListeners()
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildAllTaps(reason: .wake) }
        }
        startMediaKeysIfEnabled()
        reload()
    }

    private func registerSystemListeners() {
        listen(kAudioHardwarePropertyProcessObjectList, on: .system) { [weak self] in self?.reload() }
        listen(kAudioHardwarePropertyDefaultOutputDevice, on: .system) { [weak self] in
            self?.handleOutputDeviceChange()
        }
        listen(kAudioHardwarePropertyDevices, on: .system) { [weak self] in self?.scheduleOutputDevicesRefresh() }
        listen(kAudioHardwarePropertyServiceRestarted, on: .system) { [weak self] in
            self?.handleServiceRestarted()
        }
    }

    /// coreaudiod restarted: every object id we hold (listeners, taps,
    /// aggregates) died with it, so drop them without HAL calls and start over.
    private func handleServiceRestarted() {
        log.notice("coreaudiod restarted")
        // System-object listeners survive the restart (that is how we got here); keep
        // them so registerSystemListeners() doesn't add duplicates.
        listeners = listeners.filter { $0.key.id == .system }
        // Their ids are stale; invalidating just clears our handles. On halQueue so it
        // finishes before any new tap activates (a reused id must not be destroyed).
        let dead = Array(taps.values)
        taps = [:]
        halQueue.async { dead.forEach { $0.invalidate() } }
        // Process ids may be reassigned to other apps after the restart. Saved state
        // is per bundle, so reload → restorePersistedState re-taps muted apps.
        processes = []
        volumes = [:]
        muted = []
        restoredIDs = []
        tapErrors = [:]
        lingerUntil = [:]; lastActivity = [:]
        focusedID = nil
        outputDeviceID = .unknown   // its listeners are gone too; don't unlisten
        registerSystemListeners()
        let dev = readOutputDevice()
        currentDevice = DeviceIdentity(id: dev.id, uid: dev.uid)
        attachOutputDevice(dev.id)
        reload()
        rebuildAllTaps(reason: .serviceRestarted)
    }

    func willTerminate() {
        settings.flush()
    }

    // MARK: Live updates (menu open)

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 1.0

    /// Detection is event-driven; this poll only keeps now-playing metadata and
    /// browser tabs fresh while the menu is visible.
    func beginLiveUpdates() {
        reload()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func endLiveUpdates() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Enumeration

    private var reloadInFlight = false
    private var reloadPending = false

    func reload() {
        guard !reloadInFlight else { reloadPending = true; return }
        reloadInFlight = true
        halQueue.async { [weak self] in
            let result = Self.enumerateProcesses()
            Task { @MainActor in self?.apply(result) }
        }
    }

    /// nil = the HAL read failed: keep the current state rather than wiping it.
    private func apply(_ result: [AudioProcess]?) {
        reloadInFlight = false
        defer { if reloadPending { reloadPending = false; reload() } }
        guard let result else { return }
        let previouslyPlaying = Set(processes.filter(\.isPlaying).map(\.id))
        processes = result
        let living = Set(result.map(\.id))
        for process in result {
            // HAL only notifies IsRunning reliably; IsRunningOutput is read on reload.
            listenProcess(kAudioProcessPropertyIsRunning, on: process.id)
            listenProcess(kAudioProcessPropertyIsRunningOutput, on: process.id)
            listenProcess(kAudioProcessPropertyIsRunningInput, on: process.id)
            if process.isPlaying && !previouslyPlaying.contains(process.id) {
                noteActivity(process.id)
                focusedID = process.id
            }
            restorePersistedState(for: process)
        }
        pruneVanished(livingIDs: living)
        updateIdleTaps()
        updateDucking()
        refreshNowPlaying(living: living)
        browserTabStore.refresh()
    }

    nonisolated private static func enumerateProcesses() -> [AudioProcess]? {
        do {
            let objectIDs: [AudioObjectID] = try AudioObjectID.system.readArray(
                kAudioHardwarePropertyProcessObjectList)
            return objectIDs.compactMap { $0.isValid ? makeProcess($0) : nil }
        } catch {
            log.error("Failed to read process list: \(String(describing: error))")
            return nil
        }
    }

    nonisolated private static let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    nonisolated private static func makeProcess(_ objectID: AudioObjectID) -> AudioProcess? {
        let pid: pid_t = (try? objectID.read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
        guard pid > 0, pid != ownPID else { return nil }
        let bundleID: String? = try? objectID.readCF(kAudioProcessPropertyBundleID, as: String.self) ?? nil
        let isRunningOutput: UInt32 = (try? objectID.read(
            kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0
        let isRunningInput: UInt32 = (try? objectID.read(
            kAudioProcessPropertyIsRunningInput, default: UInt32(0))) ?? 0
        return AudioProcess(objectID: objectID, pid: pid, bundleID: bundleID,
                            isPlaying: isRunningOutput != 0, isUsingInput: isRunningInput != 0)
    }
}

