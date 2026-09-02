import Foundation

struct NowPlaying: Equatable {
    let title: String
    let artist: String
    let album: String?
    let isPlaying: Bool
    var artworkData: Data?        // Apple Music: raw bytes from AppleScript descriptor
    var artworkURLString: String? // Spotify: URL string, download via URLSession

    var subtitle: String {
        switch (artist.isEmpty, album?.isEmpty ?? true) {
        case (false, false): return "\(artist) — \(album!)"
        case (false, true):  return artist
        case (true, false):  return album!
        case (true, true):   return ""
        }
    }
}
