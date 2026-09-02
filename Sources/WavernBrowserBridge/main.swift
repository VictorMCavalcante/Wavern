import Foundation

// Native Messaging protocol: 4-byte LE uint32 length + UTF-8 JSON body

let outputDir: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("Wavern")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

let outputFile = outputDir.appendingPathComponent("browser-tabs.json")

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
