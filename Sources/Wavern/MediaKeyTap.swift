import AppKit
import CoreGraphics
import Foundation

/// Global media-key interception (F7/F8/F9, AirPods taps, keyboard media keys).
///
/// macOS routes media keys to whichever app last registered as "Now Playing",
/// which is often wrong (a YouTube tab steals Spotify's keys). We install a
/// session-level CGEventTap on NX_SYSDEFINED events, ask the handler for a
/// target, and swallow the key when we handled it — otherwise let it through.
///
/// Requires Accessibility permission. Callbacks run on the main run loop.
@MainActor
final class MediaKeyTap {

    static let shared = MediaKeyTap()

    /// Return true when the key was handled (event is swallowed).
    var handler: ((NowPlayingService.Command) -> Bool)?

    private(set) var isRunning = false
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowingKey: Int32?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask for Accessibility (shows the system prompt once) and start if granted.
    @discardableResult
    func start(promptIfNeeded: Bool) -> Bool {
        if isRunning { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): promptIfNeeded] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }

        let mask = CGEventMask(1 << NX_SYSDEFINED)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: MediaKeyTap.callback, userInfo: refcon) else {
            log.error("Media key tap creation failed")
            return false
        }
        self.port = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isRunning = true
        log.info("Media key tap active")
        return true
    }

    func stop() {
        guard isRunning else { return }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        isRunning = false
    }

    // MARK: Event plumbing

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
        // Callback is delivered on the main run loop (source added there).
        return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == UInt32(NX_SYSDEFINED),
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = ns.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let keyFlags = data & 0xFFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0xA

        let command: NowPlayingService.Command
        switch keyCode {
        case NX_KEYTYPE_PLAY:                       command = .playPause
        case NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST:      command = .next
        case NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND: command = .previous
        default: return Unmanaged.passUnretained(event)
        }

        if isDown {
            if handler?(command) == true {
                swallowingKey = keyCode
                return nil
            }
            swallowingKey = nil
            return Unmanaged.passUnretained(event)
        }
        // Key up: swallow only if we swallowed the matching down.
        if swallowingKey == keyCode {
            swallowingKey = nil
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
