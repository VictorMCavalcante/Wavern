import AppKit
import CoreAudio
import Foundation

/// One Core Audio process object, resolved to the user-facing app that owns it.
///
/// Resolution (parent-PID walk + `NSRunningApplication`) happens once, at
/// enumeration time on the HAL queue, so views and sorting never pay for it.
struct AudioProcess: Identifiable, Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    var isPlaying: Bool

    /// The app this process belongs to (helper processes resolve to their parent app).
    let runningApp: NSRunningApplication?
    let name: String
    let resolvedBundleID: String?

    var id: AudioObjectID { objectID }
    var icon: NSImage? { runningApp?.icon }

    init(objectID: AudioObjectID, pid: pid_t, bundleID: String?, isPlaying: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isPlaying = isPlaying
        let app = Self.resolveApp(pid: pid)
        runningApp = app
        resolvedBundleID = app?.bundleIdentifier ?? bundleID
        if let n = app?.localizedName { name = n }
        else if let bundleID { name = Self.prettyBundleName(bundleID) }
        else { name = "PID \(pid)" }
    }

    /// Non-nil for Chromium-family browsers with tab enrichment support.
    var chromiumBrowserName: String? {
        guard let b = resolvedBundleID else { return nil }
        return Self.chromiumBrowsers[b]
    }

    private static let chromiumBrowsers: [String: String] = [
        "com.google.Chrome":           "Chrome",
        "company.thebrowser.Browser":  "Arc",
        "com.brave.Browser":           "Brave",
        "com.microsoft.edgemac":       "Edge",
    ]

    func activate() {
        runningApp?.activate(options: [.activateAllWindows])
    }

    // MARK: Hashable (identity + display state; the app object itself is derived)

    static func == (lhs: AudioProcess, rhs: AudioProcess) -> Bool {
        lhs.objectID == rhs.objectID && lhs.pid == rhs.pid
            && lhs.isPlaying == rhs.isPlaying && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(objectID)
        hasher.combine(pid)
        hasher.combine(isPlaying)
    }

    // MARK: Resolution

    /// Walk up the parent chain until we hit a regular (Dock-visible) app; fall
    /// back to the first process that is any kind of app at all.
    private static func resolveApp(pid: pid_t) -> NSRunningApplication? {
        var firstMatch: NSRunningApplication?
        var current: pid_t? = pid
        var hops = 0
        while let p = current, hops < 8 {
            if let app = NSRunningApplication(processIdentifier: p) {
                if app.activationPolicy == .regular { return app }
                if firstMatch == nil { firstMatch = app }
            }
            current = parentPID(of: p)
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

    private static func prettyBundleName(_ bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        guard parts.count > 2 else { return bundleID }
        return parts.dropFirst(2).joined(separator: " ")
    }
}
