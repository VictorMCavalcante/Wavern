import Foundation

enum BrowserBridgeInstaller {

    static let hostName = "com.wavern.browserbridge"
    // Filled in during Task 8 after key pair generation.
    static let extensionID = "jkfkclphcapaiomnkpllkodpnncllbfd"

    private static var bridgePath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/WavernBrowserBridge")
            .path
    }

    private static let browserSupportDirs = [
        "Google/Chrome",
        "BraveSoftware/Brave-Browser",
        "Arc",
        "Microsoft Edge",
    ]

    static func install() {
        guard FileManager.default.fileExists(atPath: bridgePath) else { return }
        let manifest: [String: Any] = [
            "name":        hostName,
            "description": "Wavern browser tab bridge",
            "path":        bridgePath,
            "type":        "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest,
                                                      options: .prettyPrinted) else { return }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        for dir in browserSupportDirs {
            let hostDir = appSupport
                .appendingPathComponent(dir)
                .appendingPathComponent("NativeMessagingHosts")
            try? FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)
            let dest = hostDir.appendingPathComponent("\(hostName).json")
            if let existing = try? Data(contentsOf: dest),
               let existingStr = String(data: existing, encoding: .utf8),
               existingStr.contains(bridgePath) { continue }
            try? data.write(to: dest)
        }
    }
}
