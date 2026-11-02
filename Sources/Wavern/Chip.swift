import SwiftUI

/// Small rounded pill used for the panel's controls (CrispShot style).
struct Chip<Label: View>: View {
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        label
            .font(.system(size: 11))
            .foregroundStyle(Theme.icon)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isHovered ? Theme.pressed : Theme.hover,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// A Chip that opens a menu.
struct MenuChip<Label: View, Content: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let label: Label

    var body: some View {
        Chip {
            Menu { content } label: { label }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}
