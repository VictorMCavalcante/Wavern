import AppKit

/// Wavern's menu bar glyph: three fader rails with knobs, drawn as an 18 pt template image.
/// Idle: knobs level and low. Playing: knobs rise left to right, the wave of the app icon.
/// Coordinates sit on half points so every edge lands on a whole pixel at @2x.
enum BrandGlyph {
    static func menuBarImage(playing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let rails: [CGFloat] = [3, 9, 15]
            let knobY: [CGFloat] = playing ? [11.5, 8.5, 5.5] : [11.5, 11.5, 11.5]   // knob centers, y down
            NSColor.black.set()
            for x in rails {
                NSBezierPath(roundedRect: NSRect(x: x - 0.5, y: 1.5, width: 1, height: 15), xRadius: 0.5, yRadius: 0.5).fill()
            }
            for (x, y) in zip(rails, knobY) {
                let knob = NSRect(x: x - 2, y: y - 1.5, width: 4, height: 3)
                // A 1 pt gap in the rail around each knob keeps it legible as a separate cap.
                knob.insetBy(dx: 0, dy: -1).fill(using: .clear)
                NSBezierPath(roundedRect: knob, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Wavern"
        return image
    }
}
