import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation

@MainActor
final class AudioProcessController: ObservableObject {

    static let shared = AudioProcessController()

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

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 1.0

    private let halQueue = DispatchQueue(label: "com.wavern.hal", qos: .userInitiated)
    private var reloadInFlight = false
    private var reloadPending = false

    // MARK: Linger

    static let lingerInterval: TimeInterval = 30
    @Published private(set) var lingerUntil: [AudioObjectID: Date] = [:]

    private func noteActivity(_ id: AudioObjectID) {
        log.info("Audio activity on process object \(id)")
        lingerUntil[id] = Date().addingTimeInterval(Self.lingerInterval)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerInterval + 0.1) { [weak self] in
            guard let self else { return }
            let now = Date()
            self.lingerUntil = self.lingerUntil.filter { $0.value > now }
        }
    }

    // MARK: Property listeners

    private struct ListenerKey: Hashable { let id: AudioObjectID; let selector: AudioObjectPropertySelector }
    private var listeners: [ListenerKey: (AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = [:]

    private func listen(_ selector: AudioObjectPropertySelector, on objectID: AudioObjectID) {
        let key = ListenerKey(id: objectID, selector: selector)
        guard listeners[key] == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let isProcess = objectID != .system
        let isDeviceChange = selector == kAudioHardwarePropertyDefaultOutputDevice
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            log.debug("Listener fired: \(selector.fourCC, privacy: .public) on \(objectID)")
            Task { @MainActor in
                guard let self else { return }
                if isProcess { self.noteActivity(objectID) }
                if isDeviceChange { self.handleOutputDeviceChange() } else { self.reload() }
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, halQueue, block)
        guard status == noErr else {
            log.error("Listener failed for \(selector.fourCC, privacy: .public) on \(objectID): \(status)")
            return
        }
        listeners[key] = (address, block)
    }

    private func unlisten(_ objectID: AudioObjectID) {
        for key in listeners.keys where key.id == objectID {
            guard var entry = listeners.removeValue(forKey: key) else { continue }
            AudioObjectRemovePropertyListenerBlock(objectID, &entry.0, halQueue, entry.1)
        }
    }

    // MARK: Output device (= profile)

    /// Every output device carries its own set of per-app volumes. Switching
    /// device (AirPods ↔ speakers) swaps the whole profile and rebuilds taps,
    /// which are bound to the device they were created on.
    @Published private(set) var outputDeviceUID: String = ""
    @Published private(set) var outputDeviceName: String = ""

    private func readOutputDevice() -> (uid: String, name: String) {
        guard let id: AudioObjectID = try? AudioObjectID.system.read(
                  kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown),
              id.isValid else { return ("", "") }
        let uid: String = (try? id.readCF(kAudioDevicePropertyDeviceUID)) ?? ""
        let name: String = (try? id.readCF(kAudioObjectPropertyName)) ?? ""
        return (uid, name)
    }

    private func handleOutputDeviceChange() {
        let dev = readOutputDevice()
        guard dev.uid != outputDeviceUID else { return }
        log.info("Output device changed to \(dev.name, privacy: .public)")
        outputDeviceUID = dev.uid
        outputDeviceName = dev.name
        // Drop everything: taps point at the old device, volumes belong to the old profile.
        for (_, tap) in taps { halQueue.async { tap.invalidate() } }
        taps = [:]
        volumes = [:]
        muted = []
        tapErrors = [:]
        reload()
    }

    private func volumeKey(_ bundleID: String) -> String { "wavern.vol.\(outputDeviceUID).\(bundleID)" }
    private func mutedKey(_ bundleID: String) -> String { "wavern.muted.\(outputDeviceUID).\(bundleID)" }

    // MARK: Now playing

    @Published private(set) var nowPlaying: [AudioObjectID: NowPlaying] = [:]
    private var nowPlayingRefreshInFlight = false

    func nowPlaying(for process: AudioProcess) -> NowPlaying? { nowPlaying[process.id] }

    // MARK: Artwork

    @Published private(set) var artworkImages: [AudioObjectID: NSImage] = [:]
    private var artworkCache: [String: NSImage] = [:]

    private func artworkCacheKey(for np: NowPlaying) -> String { "\(np.artist)∙\(np.title)" }

    private func fetchSpotifyArtwork(for id: AudioObjectID, urlString: String, cacheKey: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.artworkCache[cacheKey] = image
                self.artworkImages[id] = image
            }
        }.resume()
    }

    // MARK: Browser tabs

    let browserTabStore = BrowserTabStore()

    // MARK: Transport

    func sendMediaCommand(_ command: NowPlayingService.Command, to process: AudioProcess) {
        guard let bundleID = process.resolvedBundleID,
              NowPlayingService.supports(bundleID) else { return }
        if command == .playPause, let current = nowPlaying[process.id] {
            nowPlaying[process.id] = NowPlaying(title: current.title, artist: current.artist,
                                                 album: current.album, isPlaying: !current.isPlaying)
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            NowPlayingService.send(command, bundleID: bundleID)
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run { self?.refreshNowPlaying() }
        }
    }

    // MARK: Smart media keys

    /// Route media keys to the app that is actually making sound (or was, most
    /// recently) instead of whatever macOS thinks is "Now Playing".
    @Published var mediaKeysEnabled: Bool = UserDefaults.standard.bool(forKey: "wavern.mediaKeys") {
        didSet {
            UserDefaults.standard.set(mediaKeysEnabled, forKey: "wavern.mediaKeys")
            if mediaKeysEnabled {
                if !MediaKeyTap.shared.start(promptIfNeeded: true) { mediaKeysNeedPermission = true }
            } else {
                MediaKeyTap.shared.stop()
                mediaKeysNeedPermission = false
            }
        }
    }
    @Published private(set) var mediaKeysNeedPermission = false

    private func startMediaKeysIfEnabled() {
        MediaKeyTap.shared.handler = { [weak self] command in
            self?.handleMediaKey(command) ?? false
        }
        guard mediaKeysEnabled else { return }
        mediaKeysNeedPermission = !MediaKeyTap.shared.start(promptIfNeeded: false)
    }

    /// Retry after the user grants Accessibility (permission changes don't notify us).
    func retryMediaKeys() {
        guard mediaKeysEnabled else { return }
        mediaKeysNeedPermission = !MediaKeyTap.shared.start(promptIfNeeded: true)
    }

    /// Pick the target: a supported app currently outputting audio, else the
    /// supported app that played most recently (linger window). nil = let macOS handle it.
    func mediaKeyTarget() -> AudioProcess? {
        let candidates = processes.filter { NowPlayingService.supports($0.resolvedBundleID) }
        if let live = candidates.first(where: \.isPlaying) { return live }
        return candidates
            .filter { lingerUntil[$0.id] != nil }
            .max { (lingerUntil[$0.id] ?? .distantPast) < (lingerUntil[$1.id] ?? .distantPast) }
    }

    private func handleMediaKey(_ command: NowPlayingService.Command) -> Bool {
        guard let target = mediaKeyTarget() else {
            log.info("Media key \(String(describing: command), privacy: .public): no target, passing through")
            return false
        }
        log.info("Media key \(String(describing: command), privacy: .public) → \(target.name, privacy: .public)")
        sendMediaCommand(command, to: target)
        return true
    }

    // MARK: Volume state

    private var taps: [AudioObjectID: ProcessTap] = [:]
    @Published private(set) var volumes: [AudioObjectID: Float] = [:]
    @Published private(set) var muted: Set<AudioObjectID> = []
    @Published private(set) var tapErrors: [AudioObjectID: String] = [:]

    @Published private(set) var audioPermissionGranted: Bool =
        UserDefaults.standard.bool(forKey: "wavern.hasGrantedAudioTap")

    static let maxGain: Float = 2.0

    func volume(for process: AudioProcess) -> Float { volumes[process.id] ?? 1.0 }
    func isMuted(_ process: AudioProcess) -> Bool { muted.contains(process.id) }

    func setVolume(_ value: Float, for process: AudioProcess) {
        volumes[process.id] = value
        if value > 0 { muted.remove(process.id) }
        if let b = process.resolvedBundleID {
            for key in [volumeKey(b), "wavern.vol.\(b)"] { UserDefaults.standard.set(value, forKey: key) }
            for key in [mutedKey(b), "wavern.muted.\(b)"] { UserDefaults.standard.set(false, forKey: key) }
        }
        applyGain(for: process)
    }

    func toggleMute(_ process: AudioProcess) {
        if muted.contains(process.id) { muted.remove(process.id) }
        else { muted.insert(process.id) }
        if let b = process.resolvedBundleID {
            for key in [mutedKey(b), "wavern.muted.\(b)"] {
                UserDefaults.standard.set(muted.contains(process.id), forKey: key)
            }
        }
        applyGain(for: process)
    }

    private func applyGain(for process: AudioProcess) {
        var effective: Float = muted.contains(process.id) ? 0 : (volumes[process.id] ?? 1.0)
        if isDucking && !isDucker(process) { effective *= duckLevel }
        guard let tap = ensureTap(for: process) else { return }
        tap.gain = effective
    }

    // MARK: Ducking

    /// Apps whose audio should lower everything else by default (calls/voice).
    static let defaultDuckers: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.apple.FaceTime", "com.hnc.Discord", "com.tinyspeck.slackmacgap",
        "com.cisco.webexmeetingsapp", "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
    ]
    static let duckLevels: [Float] = [1.0, 0.5, 0.3, 0.15]   // 1.0 = off

    /// Multiplier applied to non-ducker apps while a ducker is playing. 1.0 = off.
    @Published var duckLevel: Float = (UserDefaults.standard.object(forKey: "wavern.duckLevel") as? Float) ?? 0.3 {
        didSet {
            UserDefaults.standard.set(duckLevel, forKey: "wavern.duckLevel")
            updateDucking()
            reapplyAllGains()
        }
    }
    @Published private(set) var isDucking = false
    private var duckReleaseWork: DispatchWorkItem?

    func isDucker(_ process: AudioProcess) -> Bool {
        guard let b = process.resolvedBundleID else { return false }
        return (UserDefaults.standard.object(forKey: "wavern.ducker.\(b)") as? Bool)
            ?? Self.defaultDuckers.contains(b)
    }

    func toggleDucker(_ process: AudioProcess) {
        guard let b = process.resolvedBundleID else { return }
        UserDefaults.standard.set(!isDucker(process), forKey: "wavern.ducker.\(b)")
        objectWillChange.send()
        updateDucking()
        reapplyAllGains()
    }

    func isDucked(_ process: AudioProcess) -> Bool { isDucking && !isDucker(process) }

    private func updateDucking() {
        let active = processes.contains { $0.isPlaying && isDucker($0) }
        if active && duckLevel < 1 {
            duckReleaseWork?.cancel()
            duckReleaseWork = nil
            setDucking(true)
        } else if isDucking, duckReleaseWork == nil {
            // Short hold so brief silences in a call don't pump the music up and down.
            let work = DispatchWorkItem { [weak self] in
                self?.duckReleaseWork = nil
                self?.setDucking(false)
            }
            duckReleaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    private func setDucking(_ on: Bool) {
        guard isDucking != on else { return }
        isDucking = on
        log.info("Ducking \(on ? "on" : "off", privacy: .public) (level \(self.duckLevel))")
        reapplyAllGains()
    }

    /// Re-push gain to every app that is playing or already tapped.
    private func reapplyAllGains() {
        for p in processes where p.isPlaying || taps[p.id] != nil {
            // Don't create taps for duckers themselves just because ducking toggled.
            if taps[p.id] == nil && isDucker(p) { continue }
            applyGain(for: p)
        }
    }

    private func restorePersistedState(for process: AudioProcess) {
        guard let bundleID = process.resolvedBundleID else { return }
        guard volumes[process.id] == nil else { return }
        let d = UserDefaults.standard
        let v = (d.object(forKey: volumeKey(bundleID)) ?? d.object(forKey: "wavern.vol.\(bundleID)")) as? Float
        if let v { volumes[process.id] = v }
        let isMuted = (d.object(forKey: mutedKey(bundleID)) ?? d.object(forKey: "wavern.muted.\(bundleID)")) as? Bool ?? false
        if isMuted { muted.insert(process.id) }
        // Proactive tap: apps with a saved non-unity volume get tapped as soon as
        // their process object exists, so the very next sound already comes out
        // at the saved level (no need to wait for the user to touch the slider).
        if (v != nil && v != 1) || isMuted { applyGain(for: process) }
    }

    private func ensureTap(for process: AudioProcess) -> ProcessTap? {
        if let existing = taps[process.id] { return existing }
        let tap = ProcessTap(process: process)
        taps[process.id] = tap
        tapErrors[process.id] = nil
        let id = process.id
        let name = process.name
        halQueue.async { [weak self] in
            do {
                try tap.activate()
                Task { @MainActor in self?.rememberPermissionGranted() }
            } catch {
                let message = String(describing: error)
                log.error("Tap activation failed for \(name, privacy: .public): \(message, privacy: .public)")
                Task { @MainActor in
                    guard let self else { return }
                    if self.taps[id] === tap {
                        self.taps.removeValue(forKey: id)
                        self.tapErrors[id] = message
                    }
                }
            }
        }
        return tap
    }

    private func rememberPermissionGranted() {
        guard !audioPermissionGranted else { return }
        audioPermissionGranted = true
        UserDefaults.standard.set(true, forKey: "wavern.hasGrantedAudioTap")
    }

    private func pruneVanishedTaps(livingIDs: Set<AudioObjectID>) {
        for (id, tap) in taps where !livingIDs.contains(id) {
            halQueue.async { tap.invalidate() }
            taps.removeValue(forKey: id)
            volumes.removeValue(forKey: id)
            muted.remove(id)
            tapErrors.removeValue(forKey: id)
        }
        for id in Set(listeners.keys.map(\.id)) where id != .system && !livingIDs.contains(id) {
            unlisten(id)
            lingerUntil.removeValue(forKey: id)
        }
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        log.info("Wavern starting")
        halQueue.async { ProcessTap.reapLeakedDevices() }
        let dev = readOutputDevice()
        outputDeviceUID = dev.uid
        outputDeviceName = dev.name
        listen(kAudioHardwarePropertyProcessObjectList, on: .system)
        listen(kAudioHardwarePropertyDefaultOutputDevice, on: .system)
        startMediaKeysIfEnabled()
        reload()
    }

    // MARK: Live updates

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

    func reload() {
        guard !reloadInFlight else { reloadPending = true; return }
        reloadInFlight = true
        halQueue.async { [weak self] in
            let result = Self.enumerateProcesses()
            Task { @MainActor in
                guard let self else { return }
                self.reloadInFlight = false
                let previouslyPlaying = Set(self.processes.filter(\.isPlaying).map(\.id))
                self.processes = result
                let playingNames = result.filter(\.isPlaying).map(\.name).joined(separator: ", ")
                log.debug("Reload: \(result.count) processes, playing: [\(playingNames, privacy: .public)]")
                for process in result {
                    // HAL only notifies IsRunning reliably; IsRunningOutput is read on reload.
                    self.listen(kAudioProcessPropertyIsRunning, on: process.id)
                    self.listen(kAudioProcessPropertyIsRunningOutput, on: process.id)
                    if process.isPlaying && !(previouslyPlaying.contains(process.id)) {
                        self.noteActivity(process.id)
                    }
                    self.restorePersistedState(for: process)
                }
                let living = Set(result.map(\.id))
                self.pruneVanishedTaps(livingIDs: living)
                self.updateDucking()
                if self.reloadPending { self.reloadPending = false; self.reload() }
                self.nowPlaying = self.nowPlaying.filter { living.contains($0.key) }
                self.refreshNowPlaying()
                self.browserTabStore.refresh()
            }
        }
    }

    private func refreshNowPlaying() {
        guard !nowPlayingRefreshInFlight else { return }
        let targets: [(id: AudioObjectID, bundleID: String)] = playing.compactMap { process in
            guard let bundleID = process.resolvedBundleID,
                  NowPlayingService.supports(bundleID) else { return nil }
            return (process.id, bundleID)
        }
        let playingIDs = Set(targets.map(\.id))
        if nowPlaying.keys.contains(where: { !playingIDs.contains($0) }) {
            nowPlaying = nowPlaying.filter { playingIDs.contains($0.key) }
        }
        guard !targets.isEmpty else { return }
        nowPlayingRefreshInFlight = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var fetched: [AudioObjectID: NowPlaying] = [:]
            for target in targets {
                if var info = NowPlayingService.fetch(bundleID: target.bundleID) {
                    if let data = NowPlayingService.fetchArtworkData(bundleID: target.bundleID) {
                        info.artworkData = data
                    }
                    fetched[target.id] = info
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.nowPlayingRefreshInFlight = false
                for (id, info) in fetched { self.nowPlaying[id] = info }
                for id in playingIDs where fetched[id] == nil {
                    self.nowPlaying.removeValue(forKey: id)
                }
                for (id, info) in fetched {
                    let key = self.artworkCacheKey(for: info)
                    if let cached = self.artworkCache[key] {
                        self.artworkImages[id] = cached
                    } else if let data = info.artworkData, let img = NSImage(data: data) {
                        self.artworkCache[key] = img
                        self.artworkImages[id] = img
                    } else if let urlStr = info.artworkURLString {
                        self.fetchSpotifyArtwork(for: id, urlString: urlStr, cacheKey: key)
                    }
                }
                let liveKeys = Set(fetched.values.map { self.artworkCacheKey(for: $0) })
                self.artworkCache = self.artworkCache.filter { liveKeys.contains($0.key) }
                for id in self.artworkImages.keys where fetched[id] == nil {
                    self.artworkImages.removeValue(forKey: id)
                }
            }
        }
    }

    nonisolated private static func enumerateProcesses() -> [AudioProcess] {
        do {
            let objectIDs: [AudioObjectID] = try AudioObjectID.system.readArray(
                kAudioHardwarePropertyProcessObjectList)
            var result: [AudioProcess] = []
            result.reserveCapacity(objectIDs.count)
            for objectID in objectIDs where objectID.isValid {
                guard let process = makeProcess(objectID) else { continue }
                result.append(process)
            }
            return result
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
