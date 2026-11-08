import Foundation

struct BrowserTab: Codable, Identifiable, Hashable {
    let tabId: Int?
    let title: String
    let url: String
    let favIconUrl: String?
    let audible: Bool?
    /// Browser that published the tab: "" = Chrome extension (browser-tabs.json),
    /// "birdd" = browser-tabs-birdd.json. Tab ids are only unique within one source.
    var source = ""
    var id: String { "\(source)/" + (tabId.map(String.init) ?? url) }

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
    /// Per-tab volume 0...1, keyed by source, then by that browser's tab id. Missing = full volume.
    @Published private(set) var tabVolumes: [String: [Int: Float]] = [:]
    private var lastUpdated: [String: Date] = [:]
    private var tabsBySource: [String: [BrowserTab]] = [:]
    private let settings: SettingsStore
    private let dir: URL

    init(settings: SettingsStore, directory: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                             in: .userDomainMask)[0].appendingPathComponent("Wavern")) {
        self.settings = settings
        self.dir = directory
    }

    private func volumesURL(_ source: String) -> URL {
        dir.appendingPathComponent(source.isEmpty ? "browser-tab-volumes.json" : "browser-tab-volumes-\(source).json")
    }

    /// browser-tabs.json → "", browser-tabs-birdd.json → "birdd".
    private func tabFiles() -> [(source: String, url: URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix("browser-tabs"), name.hasSuffix(".json") else { return nil }
            let middle = name.dropFirst("browser-tabs".count).dropLast(".json".count)
            guard middle.isEmpty || middle.hasPrefix("-") && middle.count > 1 else { return nil }
            return (String(middle.dropFirst()), dir.appendingPathComponent(name))
        }
    }

    func refresh() {
        let now = Date()
        for (source, url) in tabFiles() {
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(BrowserTabsFile.self, from: data) else { continue }
            lastUpdated[source] = now
            tabsBySource[source] = file.tabs.filter { $0.audible ?? true }.map { var t = $0; t.source = source; return t }
        }
        for (source, last) in lastUpdated where now.timeIntervalSince(last) > 30 {
            lastUpdated[source] = nil
            tabsBySource[source] = nil
        }
        audibleTabs = tabsBySource.keys.sorted().flatMap { tabsBySource[$0] ?? [] }

        // New tabs inherit the volume remembered for their host (youtube.com → 40%).
        var changed = Set<String>()
        for tab in audibleTabs {
            guard let id = tab.tabId, tabVolumes[tab.source]?[id] == nil, let host = tab.host,
                  let saved = settings.tabVolume(forHost: host), saved < 1 else { continue }
            tabVolumes[tab.source, default: [:]][id] = saved
            changed.insert(tab.source)
        }
        // Entries for paused/closed tabs stay put: the extension needs them to
        // re-apply on resume, and it drops its own copy when a tab closes.
        // ponytail: unbounded map; cap it if someone opens thousands of tabs.
        for (source, map) in tabVolumes where map.count > 500 {
            let live = Set(tabs(for: source).compactMap(\.tabId))
            tabVolumes[source] = map.filter { live.contains($0.key) }
            changed.insert(source)
        }
        changed.forEach(writeVolumes)
    }

    func tabs(for source: String) -> [BrowserTab] { tabsBySource[source] ?? [] }

    func volume(for tab: BrowserTab) -> Float {
        guard let id = tab.tabId else { return 1 }
        return tabVolumes[tab.source]?[id] ?? 1
    }

    func setVolume(_ value: Float, for tab: BrowserTab) {
        guard let id = tab.tabId else { return }
        let v = min(max(value, 0), 1)
        tabVolumes[tab.source, default: [:]][id] = v
        if let host = tab.host { settings.setTabVolume(v, forHost: host) }
        writeVolumes(tab.source)
    }

    private func writeVolumes(_ source: String) {
        let map = tabVolumes[source] ?? [:]
        let payload: [String: Any] = [
            "volumes": Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: volumesURL(source), options: .atomic)
    }

    func isConnected(_ source: String) -> Bool {
        guard let last = lastUpdated[source] else { return false }
        return Date().timeIntervalSince(last) < 5
    }
}
