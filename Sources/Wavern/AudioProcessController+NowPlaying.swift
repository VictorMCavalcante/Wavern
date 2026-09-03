import AppKit
import CoreAudio
import Foundation

/// Track metadata + artwork for players with an AppleScript recipe
/// (Spotify, Music, VLC), and transport commands sent back to them.
extension AudioProcessController {

    func nowPlaying(for process: AudioProcess) -> NowPlaying? { nowPlaying[process.id] }

    // MARK: Transport

    func sendMediaCommand(_ command: NowPlayingService.Command, to process: AudioProcess) {
        guard let bundleID = process.resolvedBundleID,
              NowPlayingService.supports(bundleID) else { return }
        // Optimistic flip so the button reacts before AppleScript round-trips.
        if command == .playPause, var current = nowPlaying[process.id] {
            current.isPlaying.toggle()
            var updated = nowPlaying
            updated[process.id] = current
            setNowPlaying(updated)
        }
        Task.detached(priority: .userInitiated) {
            NowPlayingService.send(command, bundleID: bundleID)
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self.refreshNowPlaying()
        }
    }

    // MARK: Refresh

    /// Fetch metadata for every supported app in the list. `living` prunes
    /// entries for processes that vanished since the last reload.
    func refreshNowPlaying(living: Set<AudioObjectID>? = nil) {
        let targets: [(id: AudioObjectID, bundleID: String)] = playing.compactMap { process in
            guard let bundleID = process.resolvedBundleID,
                  NowPlayingService.supports(bundleID) else { return nil }
            return (process.id, bundleID)
        }
        let targetIDs = Set(targets.map(\.id))
        let keep = nowPlaying.filter { targetIDs.contains($0.key) && (living?.contains($0.key) ?? true) }
        if keep.count != nowPlaying.count { setNowPlaying(keep) }

        guard !targets.isEmpty, !nowPlayingRefreshInFlight else { return }
        nowPlayingRefreshInFlight = true
        Task.detached(priority: .userInitiated) {
            let fetched = Self.fetchAll(targets)
            await self.applyFetched(fetched, targetIDs: targetIDs)
        }
    }

    nonisolated private static func fetchAll(
        _ targets: [(id: AudioObjectID, bundleID: String)]) -> [AudioObjectID: NowPlaying] {
        var result: [AudioObjectID: NowPlaying] = [:]
        for target in targets {
            guard var info = NowPlayingService.fetch(bundleID: target.bundleID) else { continue }
            info.artworkData = NowPlayingService.fetchArtworkData(bundleID: target.bundleID)
            result[target.id] = info
        }
        return result
    }

    private func applyFetched(_ fetched: [AudioObjectID: NowPlaying], targetIDs: Set<AudioObjectID>) {
        nowPlayingRefreshInFlight = false
        setNowPlaying(nowPlaying.filter { !targetIDs.contains($0.key) }.merging(fetched) { $1 })

        var images = artworkImages.filter { fetched[$0.key] != nil }
        for (id, info) in fetched {
            let key = artworkCacheKey(for: info)
            if let cached = artworkCache[key] {
                images[id] = cached
            } else if let data = info.artworkData, let img = NSImage(data: data) {
                artworkCache[key] = img
                images[id] = img
            } else if let urlString = info.artworkURLString {
                fetchRemoteArtwork(for: id, urlString: urlString, cacheKey: key)
            }
        }
        setArtworkImages(images)
        let liveKeys = Set(fetched.values.map { artworkCacheKey(for: $0) })
        artworkCache = artworkCache.filter { liveKeys.contains($0.key) }
    }

    // MARK: Artwork

    private func storeArtwork(_ image: NSImage, for id: AudioObjectID, cacheKey: String) {
        artworkCache[cacheKey] = image
        var images = artworkImages
        images[id] = image
        setArtworkImages(images)
    }

    private func artworkCacheKey(for np: NowPlaying) -> String { "\(np.artist)∙\(np.title)" }

    private func fetchRemoteArtwork(for id: AudioObjectID, urlString: String, cacheKey: String) {
        guard let url = URL(string: urlString), url.scheme == "https" else { return }
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            await self.storeArtwork(image, for: id, cacheKey: cacheKey)
        }
    }
}
