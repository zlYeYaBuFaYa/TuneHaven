import SwiftUI

/// 播放器大封面（docs/UI设计文档.md §6：约 290、外圆角 30；§7.3：晴屿可用唱片样式）。
/// 唱片只是圆形裁切与纹路装饰，不修改原封面文件；减少动态效果时也不旋转（本轮不做旋转）。
struct PlayerCoverArt: View {
    let path: String?
    let style: PlayerCoverStyle
    let size: CGFloat

    @Environment(\.themePalette) private var palette

    var body: some View {
        switch style {
        case .disc:
            disc
        case .square, .auto:
            square
        }
    }

    private var square: some View {
        let inset: CGFloat = 8
        return CoverImageView(path: path, size: size - inset * 2, cornerRadius: 24)
            .padding(inset)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(palette.surface.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(palette.separator, lineWidth: 0.5)
            )
            .shadow(color: palette.cardShadow, radius: 24, y: 12)
    }

    private var disc: some View {
        let inset: CGFloat = 10
        let inner = size - inset * 2
        return ZStack {
            CoverImageView(path: path, size: inner, cornerRadius: inner / 2)
            // 唱片纹路
            ForEach(1..<6) { i in
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: inner * (0.45 + Double(i) * 0.1), height: inner * (0.45 + Double(i) * 0.1))
            }
            // 中心孔
            Circle()
                .fill(palette.surface.opacity(0.85))
                .frame(width: inner * 0.2, height: inner * 0.2)
                .overlay(Circle().stroke(palette.separator, lineWidth: 0.5))
        }
        .frame(width: inner, height: inner)
        .padding(inset)
        .background(Circle().fill(palette.surface.opacity(0.6)))
        .overlay(Circle().stroke(palette.separator, lineWidth: 0.5))
        .shadow(color: palette.cardShadow, radius: 24, y: 12)
    }
}
