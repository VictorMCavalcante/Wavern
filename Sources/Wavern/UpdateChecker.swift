import AppKit
import Foundation

/// Checks GitHub releases for a newer version once at launch.
/// If a newer DMG is found, `installUpdate()` downloads, mounts, copies and relaunches.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var updateURL: URL? = nil
    @Published private(set) var isInstalling = false

    private let apiURL = URL(string: "https://api.github.com/repos/VictorMCavalcante/Wavern/releases/latest")!
    private var dmgDownloadURL: URL?

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

            let dmgURL: URL? = (json["assets"] as? [[String: Any]])?
                .first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap { URL(string: $0) }

            await MainActor.run {
                self.updateURL = releaseURL
                self.dmgDownloadURL = dmgURL
            }
        }
    }

    func installUpdate() {
        guard let dmgURL = dmgDownloadURL else {
            if let url = updateURL { NSWorkspace.shared.open(url) }
            return
        }
        isInstalling = true
        let appPath = Bundle.main.bundlePath

        Task.detached(priority: .userInitiated) {
            let tmp = FileManager.default.temporaryDirectory
            let dmgDest = tmp.appendingPathComponent("WavernUpdate.dmg")

            // Download
            guard let (dl, _) = try? await URLSession.shared.download(from: dmgURL) else {
                await MainActor.run { self.isInstalling = false }
                return
            }
            try? FileManager.default.moveItem(at: dl, to: dmgDest)

            // Shell script runs after we quit: mount → ditto → unmount → reopen
            let script = """
            #!/bin/sh
            sleep 1
            MNT=$(mktemp -d)
            hdiutil attach '\(dmgDest.path)' -mountpoint "$MNT" -nobrowse -quiet
            ditto "$MNT/Wavern.app" '\(appPath)'
            hdiutil detach "$MNT" -quiet
            rm -rf "$MNT" '\(dmgDest.path)'
            open '\(appPath)'
            """
            let sh = tmp.appendingPathComponent("wavern-install.sh")
            try? script.write(to: sh, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                                   ofItemAtPath: sh.path)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = [sh.path]
            try? proc.run()

            await MainActor.run { NSApp.terminate(nil) }
        }
    }
}
