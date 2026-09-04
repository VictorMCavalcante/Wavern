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

    @Published private(set) var processes: [AudioProcess] = []

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
    private var lingerTimer: Timer?

    /// Called whenever a process starts or stops output: it was audible around now.
    func noteActivity(_ id: AudioObjectID) {
        log.info("Audio activity on process object \(id)")
        lingerUntil[id] = Date().addingTimeInterval(Self.lingerInterval)
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
        guard dev.uid != settings.deviceUID else { return }
        log.info("Output device changed to \(dev.name, privacy: .public)")
        settings.deviceUID = dev.uid
        outputDeviceName = dev.name
        attachOutputDevice(dev.id)
        // Drop everything: taps point at the old device, volumes belong to the old profile.
        for (_, tap) in taps { halQueue.async { tap.invalidate() } }
        taps = [:]
        volumes = [:]
        muted = []
        tapErrors = [:]
        restoredIDs = []
        reload()
    }

    // MARK: Volume state

    static let maxGain: Float = 2.0

    private var taps: [AudioObjectID: ProcessTap] = [:]
    /// Processes whose saved state has been loaded (reset on device change).
    private var restoredIDs: Set<AudioObjectID> = []
    @Published private(set) var volumes: [AudioObjectID: Float] = [:]
    @Published private(set) var muted: Set<AudioObjectID> = []
    @Published private(set) var tapErrors: [AudioObjectID: String] = [:]
    @Published private(set) var audioPermissionGranted: Bool

    func volume(for process: AudioProcess) -> Float { volumes[process.id] ?? 1.0 }
    func isMuted(_ process: AudioProcess) -> Bool { muted.contains(process.id) }
    func hasTap(_ process: AudioProcess) -> Bool { taps[process.id] != nil }

    func setVolume(_ value: Float, for process: AudioProcess) {
        volumes[process.id] = value
        if value > 0 { muted.remove(process.id) }
        if let b = process.resolvedBundleID { settings.setVolume(value, for: b) }
        applyGain(for: process)
    }

    func toggleMute(_ process: AudioProcess) {
        let nowMuted = !muted.contains(process.id)
        if nowMuted { muted.insert(process.id) } else { muted.remove(process.id) }
        if let b = process.resolvedBundleID { settings.setMuted(nowMuted, for: b) }
        applyGain(for: process)
    }

    /// Push the effective gain (volume × mute × ducking) to the process's tap,
    /// creating the tap if needed.
    func applyGain(for process: AudioProcess) {
        var effective: Float = muted.contains(process.id) ? 0 : (volumes[process.id] ?? 1.0)
        if isDucked(process) { effective *= duckLevel }
        guard let tap = ensureTap(for: process) else { return }
        tap.gain = effective
    }

    /// Load saved volume/mute once per process. Apps with a non-default level
    /// get their tap created immediately ("proactive tap"), so the very next
    /// sound already comes out at the saved level.
    private func restorePersistedState(for process: AudioProcess) {
        guard !restoredIDs.contains(process.id) else { return }
        restoredIDs.insert(process.id)
        guard let bundleID = process.resolvedBundleID else { return }
        let saved = settings.volume(for: bundleID)
        let savedMuted = settings.isMuted(bundleID)
        if let saved { volumes[process.id] = saved }
        if savedMuted { muted.insert(process.id) }
        if (saved != nil && saved != 1) || savedMuted { applyGain(for: process) }
    }

    private func ensureTap(for process: AudioProcess) -> ProcessTap? {
        if let existing = taps[process.id] { return existing }
        let tap = ProcessTap(process: process)
        taps[process.id] = tap
        tapErrors[process.id] = nil
        let id = process.id
        let name = process.name
        tap.onFirstIO = { [weak self] in self?.rememberPermissionGranted() }
        halQueue.async { [weak self] in
            do {
                let started = Date()
                try tap.activate()
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
                }
            }
        }
        return tap
    }

    private func rememberPermissionGranted() {
        guard !audioPermissionGranted else { return }
        audioPermissionGranted = true
        settings.hasGrantedAudioTap = true
    }

    private func pruneVanished(livingIDs: Set<AudioObjectID>) {
        for (id, tap) in taps where !livingIDs.contains(id) {
            halQueue.async { tap.invalidate() }
            taps.removeValue(forKey: id)
        }
        volumes = volumes.filter { livingIDs.contains($0.key) }
        muted = muted.filter { livingIDs.contains($0) }
        tapErrors = tapErrors.filter { livingIDs.contains($0.key) }
        restoredIDs = restoredIDs.filter { livingIDs.contains($0) }
        lingerUntil = lingerUntil.filter { livingIDs.contains($0.key) }
        for id in Set(listeners.keys.map(\.id)) where id != .system && !livingIDs.contains(id) {
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
        settings.deviceUID = dev.uid
        outputDeviceName = dev.name
        attachOutputDevice(dev.id)
        listen(kAudioHardwarePropertyProcessObjectList, on: .system) { [weak self] in self?.reload() }
        listen(kAudioHardwarePropertyDefaultOutputDevice, on: .system) { [weak self] in
            self?.handleOutputDeviceChange()
        }
        listen(kAudioHardwarePropertyDevices, on: .system) { [weak self] in self?.refreshOutputDevices() }
        startMediaKeysIfEnabled()
        reload()
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

    private func apply(_ result: [AudioProcess]) {
        reloadInFlight = false
        let previouslyPlaying = Set(processes.filter(\.isPlaying).map(\.id))
        processes = result
        let living = Set(result.map(\.id))
        for process in result {
            // HAL only notifies IsRunning reliably; IsRunningOutput is read on reload.
            listenProcess(kAudioProcessPropertyIsRunning, on: process.id)
            listenProcess(kAudioProcessPropertyIsRunningOutput, on: process.id)
            if process.isPlaying && !previouslyPlaying.contains(process.id) {
                noteActivity(process.id)
            }
            restorePersistedState(for: process)
        }
        pruneVanished(livingIDs: living)
        updateDucking()
        refreshNowPlaying(living: living)
        browserTabStore.refresh()
        if reloadPending { reloadPending = false; reload() }
    }

    nonisolated private static func enumerateProcesses() -> [AudioProcess] {
        do {
            let objectIDs: [AudioObjectID] = try AudioObjectID.system.readArray(
                kAudioHardwarePropertyProcessObjectList)
            return objectIDs.compactMap { $0.isValid ? makeProcess($0) : nil }
        } catch {
            log.error("Failed to read process list: \(String(describing: error))")
            return []
        }
    }

    nonisolated private static let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    nonisolated private static func makeProcess(_ objectID: AudioObjectID) -> AudioProcess? {
        let pid: pid_t = (try? objectID.read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
        guard pid > 0, pid != ownPID else { return nil }
        let bundleID: String? = try? objectID.readCF(kAudioProcessPropertyBundleID, as: String.self) ?? nil
        let isRunningOutput: UInt32 = (try? objectID.read(
            kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0
        return AudioProcess(objectID: objectID, pid: pid, bundleID: bundleID,
                            isPlaying: isRunningOutput != 0)
    }
}

