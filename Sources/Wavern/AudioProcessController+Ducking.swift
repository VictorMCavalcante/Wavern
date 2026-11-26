import CoreAudio
import Foundation

/// Automatic ducking: while a "ducker" app (calls, voice chat) outputs audio,
/// every other app is scaled by `duckLevel`. Released after a short hold so
/// gaps in a conversation don't pump the music up and down.
extension AudioProcessController {

    /// Apps whose audio lowers everything else by default.
    static let defaultDuckers: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.apple.FaceTime", "com.hnc.Discord", "com.tinyspeck.slackmacgap",
        "com.cisco.webexmeetingsapp", "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
    ]
    static let duckLevels: [Float] = [1.0, 0.5, 0.3, 0.15]   // 1.0 = off
    private static let releaseHold: TimeInterval = 1.0

    func isDucker(_ process: AudioProcess) -> Bool {
        guard let b = process.resolvedBundleID else { return false }
        if let cached = duckerCache[b] { return cached }
        let value = settings.duckerOverride(for: b) ?? Self.defaultDuckers.contains(b)
        duckerCache[b] = value
        return value
    }

    func toggleDucker(_ process: AudioProcess) {
        guard let b = process.resolvedBundleID else { return }
        let next = !isDucker(process)
        settings.setDucker(next, for: b)
        duckerCache[b] = next
        objectWillChange.send()
        updateDucking()
        reapplyAllGains()
    }

    func isDucked(_ process: AudioProcess) -> Bool { isDucking && !isDucker(process) }

    func duckLevelDidChange() {
        settings.duckLevel = duckLevel
        updateDucking()
        reapplyAllGains()
    }

    /// The HAL doesn't reliably notify IsRunningInput, so while ducking is on and a
    /// ducker is present, poll just those processes once a second. No timer otherwise.
    private func syncDuckInputTimer() {
        let needed = duckLevel < 1 && processes.contains { isDucker($0) }
        if !needed { duckInputTimer?.invalidate(); duckInputTimer = nil; return }
        guard duckInputTimer == nil else { return }
        duckInputTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollDuckerInput() }
        }
    }

    private func pollDuckerInput() {
        let ids = processes.filter { isDucker($0) }.map(\.id)
        halQueue.async { [weak self] in
            let values = ids.map { id -> (AudioObjectID, Bool) in
                let v: UInt32 = (try? id.read(kAudioProcessPropertyIsRunningInput, default: UInt32(0))) ?? 0
                return (id, v != 0)
            }
            Task { @MainActor in
                guard let self else { return }
                var changed = false
                for (id, on) in values {
                    if let i = self.processes.firstIndex(where: { $0.id == id }),
                       self.processes[i].isUsingInput != on {
                        self.processes[i].isUsingInput = on
                        changed = true
                    }
                }
                if changed { self.updateDucking() }
            }
        }
    }

    func updateDucking() {
        syncDuckInputTimer()
        let active = processes.contains { $0.isUsingInput && isDucker($0) }
        if active && duckLevel < 1 {
            duckReleaseWork?.cancel()
            duckReleaseWork = nil
            setDucking(true)
        } else if isDucking, duckReleaseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.duckReleaseWork = nil
                self?.setDucking(false)
            }
            duckReleaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseHold, execute: work)
        }
    }

    /// Re-push gain to every app that is playing or already tapped. Duckers
    /// without a tap are skipped: ducking never changes their own level.
    func reapplyAllGains() {
        for p in processes where p.isPlaying || hasTap(p) {
            if !hasTap(p) && isDucker(p) { continue }
            applyGain(for: p)
        }
    }
}
