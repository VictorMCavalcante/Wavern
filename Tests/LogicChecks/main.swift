import CoreAudio

/// Builds an interleaved AudioBufferList; each element is (samples, channels). Leaks on purpose (test process).
func abl(_ bufs: [([Float], Int)]) -> UnsafeMutableAudioBufferListPointer {
    let list = AudioBufferList.allocate(maximumBuffers: bufs.count)
    for (i, (data, ch)) in bufs.enumerated() {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: max(data.count, 1))
        p.initialize(from: data, count: data.count)
        list[i] = AudioBuffer(mNumberChannels: UInt32(ch),
                              mDataByteSize: UInt32(data.count * MemoryLayout<Float>.size), mData: p)
    }
    return list
}
func samples(_ list: UnsafeMutableAudioBufferListPointer, _ i: Int = 0) -> [Float] {
    let b = list[i]
    return Array(UnsafeBufferPointer(start: b.mData!.assumingMemoryBound(to: Float.self),
                                     count: Int(b.mDataByteSize) / MemoryLayout<Float>.size))
}
func mix(_ input: UnsafeMutableAudioBufferListPointer, _ output: UnsafeMutableAudioBufferListPointer,
         _ g: [Float] = [1, 1]) -> (Bool, [Float]) {
    let gs = UnsafeMutablePointer<Float>.allocate(capacity: 2); gs.initialize(from: g, count: 2)
    let r = AudioMix.render(input: input, output: output, gainState: gs)
    return (r, [gs[0], gs[1]])
}
func mixStereoUnity() { let o = abl([([0, 0, 0, 0], 2)])
                        assert(mix(abl([([1, -1, 0.5, -0.5], 2)]), o).0); assert(samples(o) == [1, -1, 0.5, -0.5]) }
func mixMonoOut() { let o = abl([([0, 0], 1)]); _ = mix(abl([([1, 0, 0, 1], 2)]), o); assert(samples(o) == [0.5, 0.5]) }
func mixMultichannelOut() { let o = abl([([Float](repeating: 7, count: 6), 6)]); _ = mix(abl([([1, 2], 2)]), o)
                            assert(samples(o) == [1, 2, 0, 0, 0, 0]) }
func mixPicksLastInputStream() { let o = abl([([0, 0], 2)]); _ = mix(abl([([9, 9], 2), ([1, 1], 2)]), o)
                                 assert(samples(o) == [1, 1]) }
func mixRamp() {
    let o = abl([([Float](repeating: 0, count: 8), 2)])
    let (_, g) = mix(abl([([Float](repeating: 1, count: 8), 2)]), o, [1, 0])
    let l = stride(from: 0, to: 8, by: 2).map { samples(o)[$0] }
    assert(zip(l, l.dropFirst()).allSatisfy { $0 < $1 }); assert(l.last! < 1 && l.last! >= 0.75); assert(g[1] == 1)
}
func mixSilenceReportsFalse() { assert(!mix(abl([([0, 0, 0, 0], 2)]), abl([([0, 0, 0, 0], 2)])).0) }

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
func giveUpClearOne() { var p = GiveUpPolicy(); _ = p.strike(7); _ = p.strike(7); _ = p.strike(8); _ = p.strike(8)
                        p.clear(7); assert(!p.strike(7)); assert(p.strike(8)) }
func deviceChanges() {
    let a = DeviceIdentity(id: 1, uid: "X")
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 1, uid: "X")) == .none)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 9, uid: "X")) == .sameProfileRebuild)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 9, uid: "Y")) == .newProfile)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 0, uid: "")) == .none)
}

func freshStore() -> (UserDefaults, SettingsStore) {
    let d = UserDefaults(suiteName: "wavern.checks.\(UUID())")!
    return (d, MainActor.assumeIsolated { SettingsStore(defaults: d) })
}
func zeroVolumeReadsAsMuted() {
    let (d, s) = freshStore()
    d.set(Float(0), forKey: "wavern.vol.com.x")
    MainActor.assumeIsolated { assert(s.volume(for: "com.x") == nil); assert(s.isMuted("com.x")) }
}
func settingZeroMutesAndKeepsVolume() {
    let (_, s) = freshStore()
    MainActor.assumeIsolated {
        s.setVolume(0.4, for: "com.x"); s.setVolume(0, for: "com.x")
        assert(s.isMuted("com.x")); assert(s.volume(for: "com.x") == 0.4)
    }
}
func positiveVolumeUnmutes() {
    let (_, s) = freshStore()
    MainActor.assumeIsolated {
        s.setVolume(0.4, for: "com.x"); s.setVolume(0, for: "com.x"); s.setVolume(0.7, for: "com.x")
        assert(!s.isMuted("com.x")); assert(s.volume(for: "com.x") == 0.7)
    }
}

func unmuteClearsLegacyZero() {
    let (d, s) = freshStore()
    d.set(Float(0), forKey: "wavern.vol.com.y")
    MainActor.assumeIsolated {
        assert(s.isMuted("com.y")); s.setMuted(false, for: "com.y"); s.flush()
        assert(!s.isMuted("com.y")); assert(s.volume(for: "com.y") == nil)
        assert(!SettingsStore(defaults: d).isMuted("com.y"))
    }
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
    ("giveUpClearOne", giveUpClearOne),
    ("deviceChanges", deviceChanges),
    ("mixStereoUnity", mixStereoUnity),
    ("mixMonoOut", mixMonoOut),
    ("mixMultichannelOut", mixMultichannelOut),
    ("mixPicksLastInputStream", mixPicksLastInputStream),
    ("mixRamp", mixRamp),
    ("mixSilenceReportsFalse", mixSilenceReportsFalse),
    ("zeroVolumeReadsAsMuted", zeroVolumeReadsAsMuted),
    ("settingZeroMutesAndKeepsVolume", settingZeroMutesAndKeepsVolume),
    ("positiveVolumeUnmutes", positiveVolumeUnmutes),
    ("unmuteClearsLegacyZero", unmuteClearsLegacyZero),
]
for (name, f) in checks { f(); print("ok \(name)") }
