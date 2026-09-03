import Foundation

struct BrowserTab: Codable, Identifiable, Hashable {
    let tabId: Int?
    let title: String
    let url: String
    let favIconUrl: String?
    let audible: Bool?
    var id: String { tabId.map(String.init) ?? url }

    var host: String? { URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") }

    enum CodingKeys: String, CodingKey {
        case tabId = "id", title, url, favIconUrl, audible
    }
}

private struct BrowserTabsFile: Codable {
    let tabs: [BrowserTab]
    let timestamp: TimeInterval?
}

@MainActor
final class BrowserTabStore: ObservableObject {
    @Published private(set) var audibleTabs: [BrowserTab] = []
    /// Per-tab volume 0...1, keyed by Chrome tab id. Missing = full volume.
    @Published private(set) var tabVolumes: [Int: Float] = [:]
    private var lastUpdated: Date?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private let dir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Wavern")
    }()
    private var fileURL: URL { dir.appendingPathComponent("browser-tabs.json") }
    private var volumesURL: URL { dir.appendingPathComponent("browser-tab-volumes.json") }

    func refresh() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(BrowserTabsFile.self, from: data) else {
            if let last = lastUpdated, Date().timeIntervalSince(last) > 30 {
                audibleTabs = []
                lastUpdated = nil
            }
            return
        }
        lastUpdated = Date()
        audibleTabs = file.tabs.filter { $0.audible ?? true }

        // New tabs inherit the volume remembered for their host (youtube.com → 40%).
        var changed = false
        for tab in audibleTabs {
            guard let id = tab.tabId, tabVolumes[id] == nil, let host = tab.host,
                  let saved = settings.tabVolume(forHost: host), saved < 1 else { continue }
            tabVolumes[id] = saved
            changed = true
        }
        // Entries for paused/closed tabs stay put: the extension needs them to
        // re-apply on resume, and it drops its own copy when a tab closes.
        // ponytail: unbounded map; cap it if someone opens thousands of tabs.
        if tabVolumes.count > 500 {
            let live = Set(audibleTabs.compactMap(\.tabId))
            tabVolumes = tabVolumes.filter { live.contains($0.key) }
            changed = true
        }
        if changed { writeVolumes() }
    }

    func volume(for tab: BrowserTab) -> Float {
        guard let id = tab.tabId else { return 1 }
        return tabVolumes[id] ?? 1
    }

    func setVolume(_ value: Float, for tab: BrowserTab) {
        guard let id = tab.tabId else { return }
        let v = min(max(value, 0), 1)
        tabVolumes[id] = v
        if let host = tab.host { settings.setTabVolume(v, forHost: host) }
        writeVolumes()
    }

    private func writeVolumes() {
        let payload: [String: Any] = [
            "volumes": Dictionary(uniqueKeysWithValues: tabVolumes.map { (String($0.key), $0.value) })
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: volumesURL, options: .atomic)
    }

    var isConnected: Bool {
        guard let last = lastUpdated else { return false }
        return Date().timeIntervalSince(last) < 5
    }
}
