import SwiftUI

/// 主色底上的图标。底为 `palette.primary`，内容必须用 `palette.onPrimary`。
struct PrimaryIconChip: View {
    let systemName: String
    var size: CGFloat = 36

    @Environment(\.themePalette) private var palette

    var body: some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundColor(palette.onPrimary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8).fill(palette.primary))
    }
}
