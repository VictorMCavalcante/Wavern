import AppKit
import CoreAudio
import Foundation

struct AudioProcess: Identifiable, Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    var isPlaying: Bool

    var id: AudioObjectID { objectID }

    var name: String {
        if let app = runningApp, let n = app.localizedName { return n }
        if let bundleID { return prettyBundleName(bundleID) }
        return "PID \(pid)"
    }

    var icon: NSImage? { runningApp?.icon }

    var resolvedBundleID: String? {
        runningApp?.bundleIdentifier ?? bundleID
    }

    /// Non-nil for Chromium-family browsers with tab enrichment support.
    var chromiumBrowserName: String? {
        guard let b = resolvedBundleID else { return nil }
        let known: [String: String] = [
            "com.google.Chrome":           "Chrome",
            "company.thebrowser.Browser":  "Arc",
            "com.brave.Browser":           "Brave",
            "com.microsoft.edgemac":       "Edge",
        ]
        return known[b]
    }

    var runningApp: NSRunningApplication? {
        var firstMatch: NSRunningApplication?
        var current: pid_t? = pid
        var hops = 0
        while let p = current, hops < 8 {
            if let app = NSRunningApplication(processIdentifier: p) {
                if app.activationPolicy == .regular { return app }
                if firstMatch == nil { firstMatch = app }
            }
            current = AudioProcess.parentPID(of: p)
            hops += 1
        }
        return firstMatch
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = mib.withUnsafeMutableBufferPointer { buf in
            sysctl(buf.baseAddress, UInt32(buf.count), &info, &size, nil, 0)
        }
        guard rc == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 1 ? ppid : nil
    }

    func activate() {
        runningApp?.activate(options: [.activateAllWindows])
    }
}

private func prettyBundleName(_ bundleID: String) -> String {
    let parts = bundleID.split(separator: ".")
    guard parts.count > 2 else { return bundleID }
    return parts.dropFirst(2).joined(separator: " ")
}
