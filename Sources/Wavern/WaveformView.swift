import SwiftUI

/// Three-bar animated waveform. Paused when isAnimating is false — no CPU used when muted/idle.
struct WaveformView: View {
    var isAnimating: Bool

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let barW: CGFloat = 3
                let gap: CGFloat = 2
                let phases: [Double] = [0, .pi * 0.7, .pi * 1.4]
                for (i, phase) in phases.enumerated() {
                    let x = CGFloat(i) * (barW + gap)
                    let frac: CGFloat = isAnimating
                        ? CGFloat(0.25 + 0.75 * (sin(t * 4 + phase) * 0.5 + 0.5))
                        : 0.25
                    let h = size.height * frac
                    let y = (size.height - h) / 2
                    ctx.fill(
                        Path(roundedRect: CGRect(x: x, y: y, width: barW, height: h),
                             cornerRadius: 1.5),
                        with: .color(isAnimating ? .accentColor : .secondary)
                    )
                }
            }
        }
        .frame(width: 13, height: 14)
    }
}
