func playing(_ act: Double = 0, cb: Double = 0, nz: Double = 0) -> TapSnapshot {
    TapSnapshot(isPlaying: true, activatedAt: act, lastCallback: cb, lastNonZero: nz)
}
func verdictStalled()        { assert(TapHealth.verdict(playing(cb: 10), now: 12.5, lastEvent: nil) == .stalled) }
func verdictNotPlayingIsHealthy() { var s = playing(cb: 1); s.isPlaying = false
                                    assert(TapHealth.verdict(s, now: 100, lastEvent: nil) == .healthy) }
func verdictFreshTapNotStalled() { assert(TapHealth.verdict(playing(10), now: 11, lastEvent: nil) == .healthy) }
func verdictSilentAppIsHealthy() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 0), now: 100, lastEvent: nil) == .healthy) }
func verdictZerosWithoutEventHealthy() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 50), now: 100, lastEvent: nil) == .healthy) }
func verdictSilentAfterEvent()  { assert(TapHealth.verdict(playing(cb: 99.9, nz: 89), now: 93, lastEvent: 90) == .silentAfterEvent) }
func verdictSoundResumedAfterEvent() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 92), now: 95, lastEvent: 90) == .healthy) }
func verdictEventTooOld()       { assert(TapHealth.verdict(playing(cb: 119.9, nz: 89), now: 120, lastEvent: 90) == .healthy) }
func verdictWasSilentBeforeEvent() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 70), now: 93, lastEvent: 90) == .healthy) }
func giveUpAfterThree() { var p = GiveUpPolicy(); assert(!p.strike(7)); assert(!p.strike(7)); assert(p.strike(7))
                          p.reset(); assert(!p.strike(7)) }
func deviceChanges() {
    let a = DeviceIdentity(id: 1, uid: "X")
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 1, uid: "X")) == .none)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 9, uid: "X")) == .sameProfileRebuild)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 9, uid: "Y")) == .newProfile)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 0, uid: "")) == .none)
}

let checks: [(String, () -> Void)] = [
    ("verdictStalled", verdictStalled),
    ("verdictNotPlayingIsHealthy", verdictNotPlayingIsHealthy),
    ("verdictFreshTapNotStalled", verdictFreshTapNotStalled),
    ("verdictSilentAppIsHealthy", verdictSilentAppIsHealthy),
    ("verdictZerosWithoutEventHealthy", verdictZerosWithoutEventHealthy),
    ("verdictSilentAfterEvent", verdictSilentAfterEvent),
    ("verdictSoundResumedAfterEvent", verdictSoundResumedAfterEvent),
    ("verdictEventTooOld", verdictEventTooOld),
    ("verdictWasSilentBeforeEvent", verdictWasSilentBeforeEvent),
    ("giveUpAfterThree", giveUpAfterThree),
    ("deviceChanges", deviceChanges),
]
for (name, f) in checks { f(); print("ok \(name)") }
