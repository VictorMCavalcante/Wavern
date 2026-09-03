import Foundation

/// Single owner of every UserDefaults key Wavern uses.
///
/// Per-app volume and mute are stored twice: under the current output device
/// (the "profile") and under a device-less key that acts as the last-used
/// fallback for devices that have no profile yet.
///
/// Writes are coalesced: a slider drag produces dozens of values per second,
/// and each one hitting cfprefsd is wasted work. Values are held in `pending`
/// and flushed 300ms after the last change (or explicitly on quit).
@MainActor
final class SettingsStore {

    private let defaults: UserDefaults
    private var pending: [String: Any] = [:]
    private var flushTimer: Timer?
    private let flushDelay: TimeInterval = 0.3

    /// Output device UID the per-app profile keys are scoped to.
    var deviceUID: String = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Per-app volume / mute

    func volume(for bundleID: String) -> Float? {
        read(Key.volume(bundleID, device: deviceUID)) ?? read(Key.volume(bundleID, device: nil))
    }

    func isMuted(_ bundleID: String) -> Bool {
        read(Key.muted(bundleID, device: deviceUID)) ?? read(Key.muted(bundleID, device: nil)) ?? false
    }

    func setVolume(_ value: Float, for bundleID: String) {
        write(value, Key.volume(bundleID, device: deviceUID))
        write(value, Key.volume(bundleID, device: nil))
        setMuted(false, for: bundleID)
    }

    func setMuted(_ muted: Bool, for bundleID: String) {
        write(muted, Key.muted(bundleID, device: deviceUID))
        write(muted, Key.muted(bundleID, device: nil))
    }

    // MARK: Ducking

    var duckLevel: Float {
        get { read(Key.duckLevel) ?? 0.3 }
        set { write(newValue, Key.duckLevel) }
    }

    /// nil = no user override, use the built-in default list.
    func duckerOverride(for bundleID: String) -> Bool? { read(Key.ducker(bundleID)) }
    func setDucker(_ enabled: Bool, for bundleID: String) { write(enabled, Key.ducker(bundleID)) }

    // MARK: Misc flags

    var mediaKeysEnabled: Bool {
        get { read(Key.mediaKeys) ?? false }
        set { write(newValue, Key.mediaKeys) }
    }

    var hasGrantedAudioTap: Bool {
        get { read(Key.hasGrantedAudioTap) ?? false }
        set { write(newValue, Key.hasGrantedAudioTap) }
    }

    // MARK: Browser tabs

    func tabVolume(forHost host: String) -> Float? { read(Key.tabVolume(host)) }
    func setTabVolume(_ value: Float, forHost host: String) { write(value, Key.tabVolume(host)) }

    // MARK: Plumbing

    /// Write everything pending right now (call before quitting).
    func flush() {
        flushTimer?.invalidate()
        flushTimer = nil
        for (key, value) in pending { defaults.set(value, forKey: key) }
        pending.removeAll()
    }

    private func read<T>(_ key: String) -> T? {
        if let v = pending[key] as? T { return v }
        return defaults.object(forKey: key) as? T
    }

    private func write(_ value: Any, _ key: String) {
        pending[key] = value
        guard flushTimer == nil else { return }
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    private enum Key {
        static func volume(_ b: String, device: String?) -> String {
            device.map { "wavern.vol.\($0).\(b)" } ?? "wavern.vol.\(b)"
        }
        static func muted(_ b: String, device: String?) -> String {
            device.map { "wavern.muted.\($0).\(b)" } ?? "wavern.muted.\(b)"
        }
        static func ducker(_ b: String) -> String { "wavern.ducker.\(b)" }
        static func tabVolume(_ host: String) -> String { "wavern.tabvol.\(host)" }
        static let duckLevel = "wavern.duckLevel"
        static let mediaKeys = "wavern.mediaKeys"
        static let hasGrantedAudioTap = "wavern.hasGrantedAudioTap"
    }
}
