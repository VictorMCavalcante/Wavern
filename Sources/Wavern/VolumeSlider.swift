import AppKit
import SwiftUI

// MARK: - VolumeSlider

/// Gradient volume slider: accent up to unity, warming into orange for the
/// boost zone. A tick marks 100%. Drag anywhere on the track to set the value.
struct VolumeSlider: View {
    @Binding var value: Double
    let maxValue: Double
    var isMuted: Bool

    @State private var isDragging = false
    @State private var isHovered = false

    private let trackHeight: CGFloat = 5
    private let thumbSize: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let frac = CGFloat(min(max(value / maxValue, 0), 1))
            let unityFrac = CGFloat(1 / maxValue)
            let thumbX = frac * (width - thumbSize) + thumbSize / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)

                LinearGradient(
                    stops: [
                        .init(color: .accentColor.opacity(0.75), location: 0),
                        .init(color: .accentColor, location: unityFrac),
                        .init(color: .orange, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(thumbX, trackHeight))
                    }
                    .saturation(isMuted ? 0 : 1)
                    .opacity(isMuted ? 0.4 : 1)

                // Unity tick
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 2, height: trackHeight + 4)
                    .offset(x: unityFrac * (width - thumbSize) + thumbSize / 2 - 1)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .scaleEffect(isDragging ? 1.2 : (isHovered ? 1.08 : 1))
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        let f = (g.location.x - thumbSize / 2) / max(width - thumbSize, 1)
                        value = min(max(Double(f), 0), 1) * maxValue
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isDragging)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }
}

// MARK: - BrowserTabRow

/// One audible browser tab: favicon, title, and its own 0–100% slider.
/// Applied inside the page by the extension (media element volume), on top
/// of the browser-wide tap gain above it.
struct BrowserTabRow: View {
    let tab: BrowserTab
    @EnvironmentObject var browserTabStore: BrowserTabStore

    private var volume: Binding<Double> {
        Binding(
            get: { Double(browserTabStore.volume(for: tab)) },
            set: { browserTabStore.setVolume(Float($0), for: tab) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            favicon
            MarqueeText(text: tab.title, font: .caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            VolumeSlider(value: volume, maxValue: 1, isMuted: false)
                .frame(height: 16)
            Text("\(Int((browserTabStore.volume(for: tab) * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .opacity(tab.tabId == nil ? 0.5 : 1)
        .help(tab.tabId == nil ? "Reload the Wavern extension in Chrome to control this tab." : tab.host ?? "")
    }

    @ViewBuilder private var favicon: some View {
        let placeholder = Image(systemName: "globe")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        if let s = tab.favIconUrl, let url = URL(string: s), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    placeholder.frame(width: 14, height: 14)
                }
            }
        } else {
            placeholder.frame(width: 14, height: 14)
        }
    }
}
