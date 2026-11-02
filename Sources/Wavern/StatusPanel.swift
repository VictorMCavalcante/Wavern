import AppKit
import Combine
import SwiftUI

/// Menu bar item plus a borderless, non-activating panel below it. Ported from CrispShot's
/// MenuBarController/MenuPanel. The SwiftUI tree exists only while the panel is open: `show`
/// builds a fresh hosting view, `close` drops it, so nothing renders or animates while closed.
@MainActor
final class StatusPanel {
    private static let gap: CGFloat = 6

    private(set) var isOpen = false
    private let controller: AudioProcessController
    private let updateChecker: UpdateChecker
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let target = ClickTarget()
    private var panel: Panel?
    private var clickMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var playingSub: AnyCancellable?

    init(controller: AudioProcessController, updateChecker: UpdateChecker) {
        self.controller = controller
        self.updateChecker = updateChecker
        let button = statusItem.button
        button?.image = BrandGlyph.menuBarImage(playing: controller.isAnyPlaying)
        button?.target = target
        button?.action = #selector(ClickTarget.clicked)
        button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        target.onClick = { [weak self] in self?.toggle() }
        playingSub = controller.$processes
            .map { $0.contains(where: \.isPlaying) }
            .removeDuplicates()
            .sink { [weak button] in button?.image = BrandGlyph.menuBarImage(playing: $0) }
    }

    func toggle() {
        isOpen ? close() : show()
    }

    private func show() {
        guard !isOpen, let anchor = statusItem.button?.window?.frame else { return }
        isOpen = true
        controller.beginLiveUpdates()

        let host = NSHostingView(rootView: PanelRoot()
            .environmentObject(controller)
            .environmentObject(controller.browserTabStore)
            .environmentObject(updateChecker))
        let size = CGSize(width: Theme.panelWidth, height: host.fittingSize.height)
        let panel = Panel(contentRect: Self.frame(size: size, below: anchor),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.close() }
        self.panel = panel

        // Rows come and go while open; the hosting view resizes the window, keep its top under the item.
        let top = panel.frame.maxY
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.setFrameTopLeftPoint(NSPoint(x: panel?.frame.minX ?? 0, y: top)) }
        }
        // Global monitors only see events bound for other apps, so clicks in our own menus,
        // pickers and sheets (separate windows of this app) never close the panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        statusItem.button?.highlight(true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        guard isOpen, let panel else { return }
        isOpen = false
        self.panel = nil
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
        resizeObserver.map(NotificationCenter.default.removeObserver)
        resizeObserver = nil
        panel.onEscape = {}
        statusItem.button?.highlight(false)
        if let sheet = panel.attachedSheet { panel.endSheet(sheet) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.contentView = nil
                panel.close()
                // A reopen during the fade already started its own live updates.
                if self?.isOpen == false { self?.controller.endLiveUpdates() }
            }
        })
    }

    private static func frame(size: CGSize, below anchor: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(anchor.midX - size.width / 2, vf.minX + gap), vf.maxX - size.width - gap)
        let y = max(min(anchor.minY, vf.maxY) - gap - size.height, vf.minY)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

private final class ClickTarget: NSObject {
    var onClick: () -> Void = {}
    @objc func clicked() { onClick() }
}

private final class Panel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, attachedSheet == nil { return onEscape() }
        super.sendEvent(event)
    }
}

/// Panel chrome around MenuView: rounded clip, hairline border and the open animation.
private struct PanelRoot: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        MenuView()
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.divider, lineWidth: 0.5))
            .scaleEffect(appeared || reduceMotion ? 1 : 0.96, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.38, bounce: 0.22)) { appeared = true }
            }
    }
}
