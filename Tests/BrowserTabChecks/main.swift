import Foundation

// Per-browser tab files: browser-tabs.json (Chrome extension) and browser-tabs-<browser>.json (e.g. Birdd).
// Everything runs in a temp folder and a throwaway defaults suite; never the real ~/Library.

@MainActor func makeStore() -> (BrowserTabStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wavern-checks-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "wavern-checks-\(UUID().uuidString)")!
    return (BrowserTabStore(settings: SettingsStore(defaults: defaults), directory: dir), dir)
}

func write(_ name: String, _ tabs: [[String: Any]], in dir: URL) {
    let data = try! JSONSerialization.data(withJSONObject: ["tabs": tabs, "timestamp": 1000])
    try! data.write(to: dir.appendingPathComponent(name), options: .atomic)
}

func volumes(_ name: String, in dir: URL) -> [String: Double]? {
    guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return (json["volumes"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
}

let radio: [String: Any] = ["id": 7, "title": "Rádio", "url": "https://radio.test/", "audible": true]

@MainActor func readsEveryBrowserFile() {
    let (store, dir) = makeStore()
    write("browser-tabs.json", [radio], in: dir)
    write("browser-tabs-birdd.json", [radio, ["id": 8, "title": "Mudo", "url": "https://mudo.test/", "audible": false]], in: dir)
    write("browser-tab-volumes.json", [], in: dir) // not a tabs file
    store.refresh()
    assert(store.audibleTabs.count == 2)
    assert(store.tabs(for: "").map(\.title) == ["Rádio"])
    assert(store.tabs(for: "birdd").map(\.tabId) == [7])
    assert(store.isConnected("") && store.isConnected("birdd") && !store.isConnected("arc"))
    print("ok readsEveryBrowserFile")
}

@MainActor func sameIdInTwoBrowsersDoesNotCollide() {
    let (store, dir) = makeStore()
    write("browser-tabs.json", [radio], in: dir)
    write("browser-tabs-birdd.json", [radio], in: dir)
    store.refresh()
    let chrome = store.tabs(for: "")[0], birdd = store.tabs(for: "birdd")[0]
    assert(chrome.id != birdd.id)
    store.setVolume(0.4, for: birdd)
    assert(store.volume(for: birdd) == 0.4 && store.volume(for: chrome) == 1)
    assert(volumes("browser-tab-volumes-birdd.json", in: dir) == ["7": Double(Float(0.4))])
    assert(volumes("browser-tab-volumes.json", in: dir) == nil) // Chrome's file untouched
    store.setVolume(0.2, for: chrome)
    assert(volumes("browser-tab-volumes.json", in: dir) == ["7": Double(Float(0.2))])
    assert(volumes("browser-tab-volumes-birdd.json", in: dir) == ["7": Double(Float(0.4))])
    print("ok sameIdInTwoBrowsersDoesNotCollide")
}

@MainActor func hostVolumeIsWrittenToTheOwnersFile() {
    let (store, dir) = makeStore()
    write("browser-tabs.json", [radio], in: dir)
    store.refresh()
    store.setVolume(0.5, for: store.tabs(for: "")[0]) // remembers radio.test → 50%
    write("browser-tabs-birdd.json", [["id": 9, "title": "Outra", "url": "https://radio.test/b", "audible": true]], in: dir)
    store.refresh()
    assert(volumes("browser-tab-volumes-birdd.json", in: dir) == ["9": 0.5])
    assert(volumes("browser-tab-volumes.json", in: dir) == ["7": 0.5])
    print("ok hostVolumeIsWrittenToTheOwnersFile")
}

MainActor.assumeIsolated {
    readsEveryBrowserFile()
    sameIdInTwoBrowsersDoesNotCollide()
    hostVolumeIsWrittenToTheOwnersFile()
}
