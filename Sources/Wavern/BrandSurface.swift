import AppKit
import SwiftUI

/// Panel background, ported from CrispShot/Editor/BrandBackdrop.swift: vibrancy under a 0.92 tint
/// with three aurora blobs at 0.55. Solid tint when Reduce Transparency is on. Static layers, no animation.
struct BrandSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> BrandBackdrop { BrandBackdrop() }
    func updateNSView(_: BrandBackdrop, context: Context) {}
}

final class BrandBackdrop: NSView {
    private let material: NSVisualEffectView = {
        let material = NSVisualEffectView()
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .active
        return material
    }()
    private let tint = BrandTint()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        for v in [material, tint] {
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            addSubview(v)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(apply),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        apply()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func apply() {
        let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        material.isHidden = solid
        tint.solid = solid
    }
}

private final class BrandTint: NSView {
    static let baseOpacity: CGFloat = 0.92
    static let auroraOpacity: Float = 0.55
    var solid = false { didSet { refresh() } }
    private let aurora = CALayer()
    private let blobs = (0..<3).map { _ in CAGradientLayer() }
    private static let blobCenters = [CGPoint(x: 0.2, y: 0.85), CGPoint(x: 0.85, y: 0.7), CGPoint(x: 0.55, y: 0.05)]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for blob in blobs {
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            blob.locations = [0, 0.45, 1]
            aurora.addSublayer(blob)
        }
        aurora.opacity = Self.auroraOpacity
        layer?.addSublayer(aurora)
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aurora.frame = bounds
        let side = max(bounds.width, bounds.height) * 1.1
        for (blob, center) in zip(blobs, Self.blobCenters) {
            blob.frame = CGRect(x: center.x * bounds.width - side / 2, y: center.y * bounds.height - side / 2, width: side, height: side)
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        func rgb(_ v: Int, _ a: CGFloat) -> CGColor {
            CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
        }
        let hues = dark ? [0x7C3AED, 0x4338CA, 0xC084FC] : [0xC084FC, 0xA78BFA, 0xE9D5FF]
        let strength: [CGFloat] = dark ? [0.85, 0.75, 0.45] : [0.35, 0.3, 0.5]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = rgb(dark ? 0x11111B : 0xF6F0FF, solid ? 1 : Self.baseOpacity)
        for (i, blob) in blobs.enumerated() {
            blob.colors = [rgb(hues[i], strength[i]), rgb(hues[i], strength[i] * 0.35), rgb(hues[i], 0)]
        }
        CATransaction.commit()
    }
}
