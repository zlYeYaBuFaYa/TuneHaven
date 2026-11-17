import SwiftUI

/// Visible alternative to dragging, also exposed as native menu actions to VoiceOver.
struct OrderMoveMenu: View {
    let title: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        Menu {
            Button { onMove(-1) } label: { Label("上移", systemImage: "arrow.up") }
                .disabled(!canMoveUp)
            Button { onMove(1) } label: { Label("下移", systemImage: "arrow.down") }
                .disabled(!canMoveDown)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.body)
                .foregroundColor(palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("调整顺序：\(title)")
    }
}
