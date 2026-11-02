import AppKit
import SwiftUI

/// CrispShot's chrome tokens (CrispShot/Editor/ToolIsland.swift, `Chrome`). The only color source for the panel.
enum Theme {
    static let accentLight = Color(nsColor: NSColor(srgbRed: 0xC0 / 255, green: 0x84 / 255, blue: 0xFC / 255, alpha: 1))
    static let accentDeep = Color(nsColor: NSColor(srgbRed: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255, alpha: 1))
    static let accentGlow = Color(nsColor: NSColor(srgbRed: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255, alpha: 1))
    static let record = Color(nsColor: NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1))

    static let icon = dynamic(dark: NSColor(srgbRed: 0xBD / 255, green: 0xB8 / 255, blue: 0xD0 / 255, alpha: 1),
                              light: NSColor(srgbRed: 0x3A / 255, green: 0x37 / 255, blue: 0x4A / 255, alpha: 0.82))
    static let quiet = dynamic(dark: NSColor(srgbRed: 0x7E / 255, green: 0x7A / 255, blue: 0x92 / 255, alpha: 1),
                               light: NSColor(srgbRed: 0x6E / 255, green: 0x6A / 255, blue: 0x80 / 255, alpha: 1))
    static let hover = dynamic(dark: NSColor(white: 1, alpha: 0.09), light: NSColor(white: 0, alpha: 0.06))
    static let pressed = dynamic(dark: NSColor(white: 1, alpha: 0.15), light: NSColor(white: 0, alpha: 0.11))
    static let divider = dynamic(dark: NSColor(white: 1, alpha: 0.10), light: NSColor(white: 0, alpha: 0.10))

    static let accentGradient = LinearGradient(colors: [accentLight, accentDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)

    static let panelWidth: CGFloat = 300
    static let panelMaxHeight: CGFloat = 560
    static let cornerRadius: CGFloat = 14

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}
