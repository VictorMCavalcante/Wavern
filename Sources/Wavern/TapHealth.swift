import Foundation

struct TapSnapshot {
    var isPlaying: Bool          // IsRunningOutput do processo
    var activatedAt: TimeInterval
    var lastCallback: TimeInterval   // 0 = nunca
    var lastNonZero: TimeInterval    // 0 = nunca
}

enum TapVerdict: Equatable { case healthy, stalled, silentAfterEvent }

enum TapHealth {
    static let stallTimeout: TimeInterval = 2
    static let eventWindow: TimeInterval = 15
    static let soundBeforeEvent: TimeInterval = 5

    static func verdict(_ s: TapSnapshot, now: TimeInterval, lastEvent: TimeInterval?) -> TapVerdict {
        guard s.isPlaying else { return .healthy }
        if now - max(s.lastCallback, s.activatedAt) > stallTimeout { return .stalled }
        if let e = lastEvent,
           s.lastNonZero > 0, s.lastNonZero >= e - soundBeforeEvent,
           s.lastNonZero < e,
           now - e > stallTimeout, now - e < eventWindow {
            return .silentAfterEvent
        }
        return .healthy
    }
}

struct GiveUpPolicy {
    static let maxStrikes = 3
    private(set) var strikes: [UInt32: Int] = [:]
    /// true = desistir agora
    mutating func strike(_ id: UInt32) -> Bool {
        strikes[id, default: 0] += 1
        return strikes[id]! >= Self.maxStrikes
    }
    mutating func reset() { strikes = [:] }
    mutating func clear(_ id: UInt32) { strikes[id] = nil }
}

struct DeviceIdentity: Equatable { let id: UInt32; let uid: String }
enum DeviceChange: Equatable { case none, sameProfileRebuild, newProfile }

func classifyDeviceChange(old: DeviceIdentity, new: DeviceIdentity) -> DeviceChange {
    if new.uid.isEmpty { return .none }
    if new.uid != old.uid { return .newProfile }
    return new.id != old.id ? .sameProfileRebuild : .none
}
