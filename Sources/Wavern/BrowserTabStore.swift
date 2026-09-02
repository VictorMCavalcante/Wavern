import Foundation

struct BrowserTab: Codable, Identifiable, Hashable {
    let title: String
    let url: String
    let favIconUrl: String?
    let audible: Bool?
    var id: String { url }
}

private struct BrowserTabsFile: Codable {
    let tabs: [BrowserTab]
    let timestamp: TimeInterval?
}

@MainActor
final class BrowserTabStore: ObservableObject {
    @Published private(set) var audibleTabs: [BrowserTab] = []
    private var lastUpdated: Date?

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Wavern/browser-tabs.json")
    }()

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
    }

    var isConnected: Bool {
        guard let last = lastUpdated else { return false }
        return Date().timeIntervalSince(last) < 5
    }
}
