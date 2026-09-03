import Foundation

// Native Messaging protocol: 4-byte LE uint32 length + UTF-8 JSON body.
// Inbound (extension → us): audible tabs, written to browser-tabs.json for Wavern.
// Outbound (us → extension): per-tab volumes, read from browser-tab-volumes.json
// which Wavern rewrites whenever a tab slider moves.

let outputDir: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("Wavern")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

let outputFile = outputDir.appendingPathComponent("browser-tabs.json")
let volumesFile = outputDir.appendingPathComponent("browser-tab-volumes.json")

func readMessage() -> Data? {
    let lengthData = FileHandle.standardInput.readData(ofLength: 4)
    guard lengthData.count == 4 else { return nil }
    let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    guard length > 0, length < 1_048_576 else { return nil }
    let body = FileHandle.standardInput.readData(ofLength: Int(length))
    guard body.count == Int(length) else { return nil }
    return body
}

func writeOutput(_ data: Data) {
    let tmp = outputFile.appendingPathExtension("tmp")
    try? data.write(to: tmp, options: .atomic)
    _ = try? FileManager.default.replaceItemAt(outputFile, withItemAt: tmp)
}

/// Only this thread writes stdout, so frames never interleave.
func sendToExtension(_ body: Data) {
    var length = UInt32(body.count).littleEndian
    let header = Data(bytes: &length, count: 4)
    FileHandle.standardOutput.write(header + body)
}

// Watch the volumes file and forward changes to the extension.
let watcher = Thread {
    var lastModified: Date?
    var lastSent: Data?
    while true {
        let attrs = try? FileManager.default.attributesOfItem(atPath: volumesFile.path)
        let modified = attrs?[.modificationDate] as? Date
        if modified != lastModified, let data = try? Data(contentsOf: volumesFile),
           (try? JSONSerialization.jsonObject(with: data)) != nil, data != lastSent {
            sendToExtension(data)
            lastSent = data
        }
        lastModified = modified
        Thread.sleep(forTimeInterval: 0.25)
    }
}
watcher.start()

while let message = readMessage() {
    guard var dict = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any] else {
        continue
    }
    dict["timestamp"] = Date().timeIntervalSince1970
    if let enriched = try? JSONSerialization.data(withJSONObject: dict) {
        writeOutput(enriched)
    }
}

// Chrome disconnected — write empty tabs so Wavern stops showing nudge immediately
let empty: [String: Any] = ["tabs": [], "timestamp": Date().timeIntervalSince1970]
if let data = try? JSONSerialization.data(withJSONObject: empty) {
    writeOutput(data)
}
