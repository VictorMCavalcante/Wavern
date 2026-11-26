// Usage: swift scripts/list-aggregates.swift — counts Wavern aggregates/taps visible system-wide.
// Wavern's own are private (isPrivate) and invisible here: expect 0 while it runs, and 0 after it
// quits = nothing leaked. Live in-app count: log "Aggregates alive after rebuild".
import CoreAudio

func ids(_ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
    var out = [AudioObjectID](repeating: 0, count: Int(size) / 4)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &out)
    return out
}
func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr, let s = v else { return "" }
    return s.takeRetainedValue() as String
}
let aggs = ids(kAudioHardwarePropertyDevices).map { string($0, kAudioDevicePropertyDeviceUID) }.filter { $0.hasPrefix("com.wavern.aggregate.") }
let taps = ids(kAudioHardwarePropertyTapList).map { (string($0, kAudioTapPropertyUID), string($0, kAudioObjectPropertyName)) }.filter { $0.1.hasPrefix("Voulum-") }
print("aggregates: \(aggs.count)"); aggs.forEach { print("  \($0)") }
print("taps: \(taps.count)"); taps.forEach { print("  \($0.1) \($0.0)") }
