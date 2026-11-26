import AppKit

// Wavern app icon: three fader rails with knobs forming a wave, on a dark rounded square.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns  (also writes docs/brand/icon.png)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { color($0.0, $0.1) } as CFArray,
               locations: stops.map { $0.2 })!
}
let lilac = gradient([(0xD8B4FE, 1, 0), (0xC084FC, 1, 0.5), (0x8B3DFF, 1, 1)])

// Symbol geometry in a 100-unit square (same numbers as docs/brand/mark.svg).
let rails: [CGFloat] = [28, 50, 72]
let knobY: [CGFloat] = [62, 46, 34]          // knob centers, rising left to right
let knob = CGSize(width: 19, height: 12)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let small = px <= 32
    // 1024 canvas, y down. Body is the macOS icon grid square (824 at 100 margin).
    let s = CGFloat(px) / 1024
    cg.translateBy(x: 0, y: CGFloat(px))
    cg.scaleBy(x: s, y: -s)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let u = body.width / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * u, y: body.minY + y * u) }

    // Body: diagonal dark gradient, top-left sheen, hairline rim.
    // CrispShot's squircle (124-unit path) scaled onto the body.
    let q = body.width / 124
    let shape = CGMutablePath()
    func sq(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * q, y: body.minY + y * q) }
    shape.move(to: sq(50, 0))
    shape.addCurve(to: sq(0, 50), control1: sq(9, 0), control2: sq(0, 9))
    shape.addLine(to: sq(0, 74))
    shape.addCurve(to: sq(50, 124), control1: sq(0, 115), control2: sq(9, 124))
    shape.addLine(to: sq(74, 124))
    shape.addCurve(to: sq(124, 74), control1: sq(115, 124), control2: sq(124, 115))
    shape.addLine(to: sq(124, 50))
    shape.addCurve(to: sq(74, 0), control1: sq(124, 9), control2: sq(115, 0))
    shape.closeSubpath()
    cg.saveGState()
    cg.addPath(shape); cg.clip()
    cg.drawLinearGradient(gradient([(0x2A2A33, 1, 0), (0x121218, 1, 0.55), (0x0B0B10, 1, 1)]),
                          start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])
    cg.drawRadialGradient(gradient([(0xFFFFFF, 0.10, 0), (0xFFFFFF, 0, 1)]), startCenter: p(28, 8), startRadius: 0,
                          endCenter: p(28, 8), endRadius: 70 * u, options: [])
    cg.restoreGState()
    cg.addPath(shape)
    cg.setStrokeColor(color(0xFFFFFF, 0.12)); cg.setLineWidth(small ? 24 : 6); cg.strokePath()

    // Glow behind the symbol (dropped at 16/32 px, where it only muddies the knobs).
    let c = p(50, 48)
    if !small { cg.drawRadialGradient(gradient([(0xA855F7, 0.55, 0), (0xA855F7, 0, 1)]), startCenter: c, startRadius: 0,
                          endCenter: c, endRadius: 36 * u, options: []) }

    // Rails.
    cg.setStrokeColor(color(0xFFFFFF, small ? 0.24 : 0.14))
    cg.setLineWidth((small ? 6 : 4.5) * u); cg.setLineCap(.round)
    for x in rails { cg.move(to: p(x, 22)); cg.addLine(to: p(x, 78)) }
    cg.strokePath()

    let lilacStart = p(rails[0] - knob.width / 2, knobY[2] - knob.height / 2)
    let lilacEnd = p(rails[2] + knob.width / 2, knobY[0] + knob.height / 2)

    // Wave: S-curve through the three knob centers, overshooting between them like a sound wave.
    if !small {
        let a = p(rails[0], knobY[0]), b = p(rails[1], knobY[1]), d = p(rails[2], knobY[2])
        let wave = CGMutablePath()
        wave.move(to: a)
        wave.addQuadCurve(to: b, control: p((rails[0] + rails[1]) / 2, knobY[1] - 12))
        wave.addQuadCurve(to: d, control: p((rails[1] + rails[2]) / 2, knobY[1] + 12))
        cg.saveGState()
        cg.addPath(wave.copy(strokingWithWidth: 5 * u, lineCap: .round, lineJoin: .round, miterLimit: 1))
        cg.clip()
        cg.setAlpha(0.8)
        cg.drawLinearGradient(lilac, start: lilacStart, end: lilacEnd, options: [])
        cg.restoreGState()
    }

    // Knobs: pills centered on the rails, each with its own top-left to bottom-right gradient and a soft shadow.
    let k = small ? CGSize(width: 20, height: 14) : knob
    for (x, y) in zip(rails, knobY) {
        let r = CGRect(x: p(x, y).x - k.width * u / 2, y: p(x, y).y - k.height * u / 2, width: k.width * u, height: k.height * u)
        let pill = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        if !small {
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 1.5 * u), blur: 5 * u, color: color(0x000000, 0.55))
            cg.addPath(pill); cg.setFillColor(color(0x8B3DFF)); cg.fillPath()
            cg.restoreGState()
        }
        cg.saveGState()
        cg.addPath(pill); cg.clip()
        cg.drawLinearGradient(lilac, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        cg.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try render(1024).write(to: URL(fileURLWithPath: "docs/brand/icon.png"))
print(task.terminationStatus == 0 ? "ok \(out.path)" : "iconutil failed")
