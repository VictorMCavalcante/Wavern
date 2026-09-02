import Foundation

/// Checks GitHub releases for a newer version once at launch.
/// If a newer tag is found, `updateURL` is set to the release page.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var updateURL: URL? = nil

    private let apiURL = URL(string: "https://api.github.com/repos/VictorMCavalcante/Wavern/releases/latest")!

    func check() {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        Task.detached(priority: .background) {
            guard let (data, _) = try? await URLSession.shared.data(from: self.apiURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let releaseURL = URL(string: htmlURL) else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard latest.compare(current, options: .numeric) == .orderedDescending else { return }
            await MainActor.run { self.updateURL = releaseURL }
        }
    }
}
