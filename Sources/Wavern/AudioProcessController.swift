import AudioToolbox
import Combine
import CoreAudio
import Foundation

@MainActor
final class AudioProcessController: ObservableObject {

    static let shared = AudioProcessController()

    @Published private(set) var processes: [AudioProcess] = []
    var playing: [AudioProcess] {
        processes.filter(\.isPlaying)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 1.0

    private let halQueue = DispatchQueue(label: "com.wavern.hal", qos: .userInitiated)
    private var reloadInFlight = false

    // MARK: Now playing

    @Published private(set) var nowPlaying: [AudioObjectID: NowPlaying] = [:]
    private let scriptQueue = DispatchQueue(label: "com.wavern.nowplaying", qos: .userInitiated)
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
        scriptQueue.async { [weak self] in
            NowPlayingService.send(command, bundleID: bundleID)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.refreshNowPlaying()
            }
        }
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
            UserDefaults.standard.set(value, forKey: "wavern.vol.\(b)")
            UserDefaults.standard.set(false, forKey: "wavern.muted.\(b)")
        }
        applyGain(for: process)
    }

    func toggleMute(_ process: AudioProcess) {
        if muted.contains(process.id) { muted.remove(process.id) }
        else { muted.insert(process.id) }
        if let b = process.resolvedBundleID {
            UserDefaults.standard.set(muted.contains(process.id), forKey: "wavern.muted.\(b)")
        }
        applyGain(for: process)
    }

    private func applyGain(for process: AudioProcess) {
        let effective: Float = muted.contains(process.id) ? 0 : (volumes[process.id] ?? 1.0)
        guard let tap = ensureTap(for: process) else { return }
        tap.gain = effective
    }

    private func restorePersistedState(for process: AudioProcess) {
        guard let bundleID = process.resolvedBundleID else { return }
        guard volumes[process.id] == nil else { return }
        let v = UserDefaults.standard.float(forKey: "wavern.vol.\(bundleID)")
        if v > 0 { volumes[process.id] = v }
        if UserDefaults.standard.bool(forKey: "wavern.muted.\(bundleID)") {
            muted.insert(process.id)
        }
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
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        log.info("Wavern starting")
        halQueue.async { ProcessTap.reapLeakedDevices() }
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
        guard !reloadInFlight else { return }
        reloadInFlight = true
        halQueue.async { [weak self] in
            let result = Self.enumerateProcesses()
            Task { @MainActor in
                guard let self else { return }
                self.reloadInFlight = false
                self.processes = result
                for process in result { self.restorePersistedState(for: process) }
                let living = Set(result.map(\.id))
                self.pruneVanishedTaps(livingIDs: living)
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
        scriptQueue.async { [weak self] in
            var fetched: [AudioObjectID: NowPlaying] = [:]
            for target in targets {
                if var info = NowPlayingService.fetch(bundleID: target.bundleID) {
                    if let data = NowPlayingService.fetchArtworkData(bundleID: target.bundleID) {
                        info.artworkData = data
                    }
                    fetched[target.id] = info
                }
            }
            Task { @MainActor in
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
