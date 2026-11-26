import AudioToolbox
import CoreAudio
import Foundation

/// Per-process volume control built on Core Audio process taps (macOS 14.4+).
///
/// Pipeline:
///   1. Create a `CATapDescription` for the target process with
///      `.mutedWhenTapped` — the process's normal output is silenced and its
///      audio is instead delivered to us.
///   2. Build a *private* aggregate device combining the current default output
///      device and that tap.
///   3. Run an IOProc that mixes the tapped frames to the output device
///      (`AudioMix.render`), ramping to `gain`. gain 0 = mute, 1 = unity, >1 = boost.
///
/// `gain` (and the IO timestamps) live behind stable pointers so the realtime
/// audio thread can read/write them without locking while the UI writes it from the main thread (aligned
/// 4-byte float access is atomic on Apple Silicon).
/// `@unchecked Sendable`: instances are created on the main thread but activated,
/// torn down, and reaped on `AudioProcessController`'s serial HAL queue, while the
/// UI reads `gain`/`isActive`. Cross-thread access is deliberate — `gain` is
/// pointer-backed (atomic aligned write) and every HAL mutation is serialized on
/// that one queue.
final class ProcessTap: @unchecked Sendable {

    /// `.control` routes the app through our aggregate and applies `gain`.
    /// `.muteOnly` just holds a `.muted` tap: no aggregate, no IOProc.
    enum Mode { case control, muteOnly }

    let process: AudioProcess
    let mode: Mode

    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.wavern.tap.io", qos: .userInteractive)

    /// [0] = target gain (UI writes), [1] = last applied gain (only IO writes).
    private let gainState: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        p.initialize(repeating: 1.0, count: 2)
        return p
    }()
    /// [0] = last IO callback, [1] = last callback with a non-zero sample.
    /// Seconds in the `mach_absolute_time` base; 0 = never. Only IO writes.
    private let times: UnsafeMutablePointer<Double> = {
        let p = UnsafeMutablePointer<Double>.allocate(capacity: 2)
        p.initialize(repeating: 0, count: 2)
        return p
    }()
    /// Host ticks → seconds, computed once so the IO block calls nothing.
    private let hostTicksToSeconds: Double

    private(set) var isActive = false
    private(set) var activatedAt: TimeInterval = 0
    /// Main-actor only: IO stopped because the app went quiet (see `pauseIO`).
    var idlePaused = false
    /// Main-actor only: when IO last restarted after an idle pause; the watchdog's grace starts here.
    var resumedAt: TimeInterval = 0

    init(process: AudioProcess, mode: Mode = .control) {
        self.process = process
        self.mode = mode
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        hostTicksToSeconds = Double(tb.numer) / Double(tb.denom) / 1_000_000_000
    }

    var gain: Float {
        get { gainState[0] }
        set { gainState[0] = max(0, newValue) }
    }

    // `mHostTime` is `mach_absolute_time` ticks; scaled by the timebase it is
    // the same clock as `ProcessInfo.systemUptime` (both stop during sleep), so
    // these compare directly against `systemUptime`. On Apple Silicon the two
    // coincide exactly.
    var lastCallback: TimeInterval { times[0] }
    var lastNonZero: TimeInterval { times[1] }

    // MARK: Lifecycle

    func activate() throws {
        guard !isActive else { return }
        // Before the first buffer: no ramp from the init value of 1.
        gainState[1] = gainState[0]
        times[0] = 0; times[1] = 0  // IO is not running yet; drop any previous run's stamps

        // 1. Tap the process, muting its normal output.
        let description = CATapDescription(
            stereoMixdownOfProcesses: [process.objectID])
        description.name = "\(Self.tapNamePrefix)\(process.pid)"
        description.isPrivate = true
        description.muteBehavior = mode == .muteOnly ? .muted : .mutedWhenTapped
        // Inclusive list: tap ONLY this process. `isExclusive = true` would flip
        // the list's meaning to "tap everything EXCEPT this process", which routes
        // every *other* app's audio through our aggregate — so lowering one app's
        // slider would mute all the others (and leave the target untouched).
        description.isExclusive = false

        var newTapID: AudioObjectID = .unknown
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID.isValid else {
            throw TapError.create("AudioHardwareCreateProcessTap", status)
        }
        tapID = newTapID

        if mode == .muteOnly {
            isActive = true
            activatedAt = ProcessInfo.processInfo.systemUptime
            log.info("Mute-only tap for \(self.process.name, privacy: .public) (pid \(self.process.pid))")
            return
        }

        // 2. Resolve current default output device + build the aggregate.
        let outputUID: String, tapUID: String
        do {
            let outputID: AudioObjectID = try AudioObjectID.system.read(
                kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown)
            guard outputID.isValid,
                  let o: String = try outputID.readCF(kAudioDevicePropertyDeviceUID),
                  let t: String = try tapID.readCF(kAudioTapPropertyUID) else {
                throw TapError.setup("Could not resolve output/tap UID")
            }
            outputUID = o
            tapUID = t
        } catch {
            teardown()  // don't leak the tap we just created
            throw error
        }

        let aggregateUID = "\(Self.aggregateUIDPrefix)\(process.pid).\(UUID().uuidString)"
        let description2: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Wavern \(process.name)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var newAggregate: AudioObjectID = .unknown
        status = AudioHardwareCreateAggregateDevice(description2 as CFDictionary, &newAggregate)
        guard status == noErr, newAggregate.isValid else {
            teardown()
            throw TapError.create("AudioHardwareCreateAggregateDevice", status)
        }
        aggregateID = newAggregate

        // AudioMix assumes the tap is the LAST input stream; log the count so a
        // mic-bearing output device (extra stream ahead of the tap) is visible.
        let inputStreams = (try? aggregateID.readArray(
            kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput,
            of: AudioObjectID.self))?.count ?? -1
        log.notice("Aggregate for \(self.process.name, privacy: .public) has \(inputStreams) input stream(s)")

        // 3. Install the gain-applying IOProc and start it. Captures only raw
        // pointers and a Double: no self, no ARC traffic on the IO thread.
        let gainState = self.gainState
        let times = self.times
        let toSeconds = hostTicksToSeconds
        let ioBlock: AudioDeviceIOBlock = { inNow, inInputData, _, outOutputData, _ in
            let now = Double(inNow.pointee.mHostTime) * toSeconds
            times[0] = now
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let output = UnsafeMutableAudioBufferListPointer(outOutputData)
            if AudioMix.render(input: input, output: output, gainState: gainState) {
                times[1] = now
            }
        }

        var newProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateID, ioQueue, ioBlock)
        guard status == noErr, let procID = newProcID else {
            teardown()
            throw TapError.create("AudioDeviceCreateIOProcIDWithBlock", status)
        }
        ioProcID = procID
        if inputStreams > 1 { useOnlyTapInput(procID, streams: inputStreams) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            teardown()
            throw TapError.create("AudioDeviceStart", status)
        }

        isActive = true
        activatedAt = ProcessInfo.processInfo.systemUptime
        log.info("Tap active for \(self.process.name, privacy: .public) (pid \(self.process.pid))")
    }

    /// The aggregate's inputs are the output device's own mic streams, then the tap.
    /// Turning the mic streams off for our IOProc keeps the HAL from starting the mic
    /// (orange indicator, headset dropping to its call profile). The tap stays last.
    private func useOnlyTapInput(_ procID: AudioDeviceIOProcID, streams: Int) {
        let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!
        let size = offset + streams * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(streams), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for i in 0..<streams {
            raw.storeBytes(of: i == streams - 1 ? 1 : 0, toByteOffset: offset + i * 4, as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(size), raw)
        log.notice("Mic streams off for \(self.process.name, privacy: .public): status \(status)")
    }

    /// Idle: stop pulling the tap so the aggregate does no IO (CPU, battery, Bluetooth).
    /// While stopped, `.mutedWhenTapped` lets the app play natively. Call on the HAL queue.
    func pauseIO() {
        guard isActive, let procID = ioProcID, aggregateID.isValid else { return }
        AudioDeviceStop(aggregateID, procID)
    }

    func resumeIO() {
        guard isActive, let procID = ioProcID, aggregateID.isValid else { return }
        gainState[1] = gainState[0]   // no ramp from a stale level
        let status = AudioDeviceStart(aggregateID, procID)
        if status != noErr { log.error("Resume failed for \(self.process.name, privacy: .public): \(status)") }
    }

    func invalidate() {
        guard isActive else { return }
        teardown()
        isActive = false
    }

    private func teardown() {
        if let procID = ioProcID, aggregateID.isValid {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    deinit {
        teardown()
        gainState.deallocate()
        times.deallocate()
    }
}

extension ProcessTap {
    /// UID prefix stamped on every aggregate device we create. Used both to build
    /// new ones and to recognise orphans left behind by a previous crash.
    static let aggregateUIDPrefix = "com.wavern.aggregate."
    /// Prefix on every process-tap description name we create.
    static let tapNamePrefix = "Voulum-"

    /// Destroy any private aggregate devices / process taps this app leaked in a
    /// prior run (e.g. a crash or force-quit that skipped `teardown`). These
    /// accumulate inside coreaudiod and can eventually wedge the whole audio HAL,
    /// so we sweep them at launch. Must run off the main thread — it makes
    /// blocking HAL calls. Safe to call when there's nothing to reap.
    static func reapLeakedDevices() {
        // Orphaned aggregate devices.
        if let devices: [AudioObjectID] = try? AudioObjectID.system.readArray(
            kAudioHardwarePropertyDevices) {
            for device in devices where device.isValid {
                guard let uid: String = try? device.readCF(kAudioDevicePropertyDeviceUID),
                      uid.hasPrefix(aggregateUIDPrefix) else { continue }
                let status = AudioHardwareDestroyAggregateDevice(device)
                log.info("Reaped leaked aggregate \(uid, privacy: .public) (status \(status))")
            }
        }

        // Orphaned process taps.
        if let taps: [AudioObjectID] = try? AudioObjectID.system.readArray(
            kAudioHardwarePropertyTapList) {
            for tap in taps where tap.isValid {
                guard let desc: CATapDescription = try? tap.readCF(kAudioTapPropertyDescription),
                      desc.name.hasPrefix(tapNamePrefix) else { continue }
                let name = desc.name
                let status = AudioHardwareDestroyProcessTap(tap)
                log.info("Reaped leaked tap \(name, privacy: .public) (status \(status))")
            }
        }
    }
}

enum TapError: Error, CustomStringConvertible {
    case create(String, OSStatus)
    case setup(String)

    var description: String {
        switch self {
        case let .create(call, status): return "\(call) failed (\(status))"
        case let .setup(message): return message
        }
    }
}
