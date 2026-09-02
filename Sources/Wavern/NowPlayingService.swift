import AppKit
import Foundation

enum NowPlayingService {

    enum Command { case playPause, next, previous }

    private struct Recipe {
        let metadata: String
        let playPause: String
        let next: String
        let previous: String
    }

    private static let recipes: [String: Recipe] = [
        "com.spotify.client": spotifyStyle(),
        "com.apple.Music":    musicStyle(),
        "org.videolan.vlc":   vlcStyle(),
    ]

    static func supports(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return recipes[bundleID] != nil
    }

    static func send(_ command: Command, bundleID: String) {
        guard let recipe = recipes[bundleID] else { return }
        let source: String
        switch command {
        case .playPause: source = recipe.playPause
        case .next:      source = recipe.next
        case .previous:  source = recipe.previous
        }
        run(source, context: "command \(command)")
    }

    static func fetch(bundleID: String) -> NowPlaying? {
        guard let recipe = recipes[bundleID] else { return nil }
        guard let raw = run(recipe.metadata, context: "metadata"),
              raw != noTrackSentinel else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 4 else { return nil }
        let album = parts[2].isEmpty ? nil : parts[2]
        let isPlaying = parts[3].caseInsensitiveCompare("playing") == .orderedSame
        let artURLString: String? = parts.count >= 5 && !parts[4].isEmpty ? parts[4] : nil
        return NowPlaying(title: parts[0], artist: parts[1], album: album,
                          isPlaying: isPlaying, artworkURLString: artURLString)
    }

    static func fetchArtworkData(bundleID: String) -> Data? {
        guard bundleID == "com.apple.Music" else { return nil }
        let source = """
        tell application "Music"
            try
                get data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil { return nil }
        return descriptor.data
    }

    @discardableResult
    private static func run(_ source: String, context: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            log.error("NowPlaying \(context, privacy: .public) failed: \(errorInfo)")
            return nil
        }
        return output.stringValue
    }

    private static func spotifyStyle() -> Recipe {
        let metadata = """
        tell application "Spotify"
            try
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set playState to (player state as text)
                set artURL to ""
                try
                    set artURL to artwork url of current track
                end try
                return trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & playState & linefeed & artURL
            on error
                return "__wavern_no_track__"
            end try
        end tell
        """
        return Recipe(
            metadata: metadata,
            playPause: "tell application \"Spotify\" to playpause",
            next:      "tell application \"Spotify\" to next track",
            previous:  "tell application \"Spotify\" to previous track")
    }

    private static func musicStyle() -> Recipe {
        let metadata = """
        tell application "Music"
            try
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set playState to (player state as text)
                return trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & playState & linefeed & ""
            on error
                return "__wavern_no_track__"
            end try
        end tell
        """
        return Recipe(
            metadata: metadata,
            playPause: "tell application \"Music\" to playpause",
            next:      "tell application \"Music\" to next track",
            previous:  "tell application \"Music\" to previous track")
    }

    private static func vlcStyle() -> Recipe {
        let metadata = """
        tell application "VLC"
            try
                set trackName to name of current item
                if trackName is missing value then set trackName to ""
                set playState to "paused"
                if (playing) then set playState to "playing"
                if trackName is "" then return "__wavern_no_track__"
                return trackName & linefeed & "" & linefeed & "" & linefeed & playState & linefeed & ""
            on error
                return "__wavern_no_track__"
            end try
        end tell
        """
        return Recipe(
            metadata: metadata,
            playPause: "tell application \"VLC\" to play",
            next:      "tell application \"VLC\" to next",
            previous:  "tell application \"VLC\" to previous")
    }

    private static let noTrackSentinel = "__wavern_no_track__"
}
