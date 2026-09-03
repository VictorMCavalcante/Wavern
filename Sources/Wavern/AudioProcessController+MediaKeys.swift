import CoreAudio
import Foundation

/// Smart media keys: route play/pause/next/previous to the app that is
/// actually making sound (or was, most recently) instead of whatever macOS
/// thinks is "Now Playing". Opt-in; needs Accessibility.
extension AudioProcessController {

    func startMediaKeysIfEnabled() {
        MediaKeyTap.shared.handler = { [weak self] command in
            self?.handleMediaKey(command) ?? false
        }
        guard mediaKeysEnabled else { return }
        setMediaKeysNeedPermission(!MediaKeyTap.shared.start(promptIfNeeded: false))
    }

    func mediaKeysEnabledDidChange() {
        settings.mediaKeysEnabled = mediaKeysEnabled
        if mediaKeysEnabled {
            setMediaKeysNeedPermission(!MediaKeyTap.shared.start(promptIfNeeded: true))
        } else {
            MediaKeyTap.shared.stop()
            setMediaKeysNeedPermission(false)
        }
    }

    /// Retry after the user grants Accessibility (permission changes don't notify us).
    func retryMediaKeys() {
        guard mediaKeysEnabled else { return }
        setMediaKeysNeedPermission(!MediaKeyTap.shared.start(promptIfNeeded: true))
    }

    /// A supported app currently outputting audio, else the supported app that
    /// played most recently (linger window). nil = let macOS handle the key.
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
}
