import SwiftUI

struct ImportResultSection: View {
    let result: ImportResult
    @Environment(\.themePalette) private var palette

    var body: some View {
        Section("导入结果") {
            ImportResultRow(title: "成功", count: result.successCount, color: palette.primary, icon: "checkmark.circle")
            if result.incompleteMetadataCount > 0 {
                ImportResultRow(title: "元数据不完整", count: result.incompleteMetadataCount, color: SemanticColor.warning, icon: "exclamationmark.circle")
            }
            if result.skippedDuplicateCount > 0 {
                ImportResultRow(title: "已跳过（重复）", count: result.skippedDuplicateCount, color: palette.textSecondary, icon: "arrow.2.circlepath")
            }
            if result.skippedFormatCount > 0 {
                ImportResultRow(title: "格式不支持", count: result.skippedFormatCount, color: palette.textTertiary, icon: "doc.badge.minus")
            }
            if result.skippedOversizeCount > 0 {
                ImportResultRow(title: "超过大小限制", count: result.skippedOversizeCount, color: SemanticColor.warning, icon: "exclamationmark.triangle")
            }
            if result.failedCount > 0 {
                ImportResultRow(title: "失败", count: result.failedCount, color: SemanticColor.danger, icon: "xmark.circle")
            }
        }
    }
}

struct ImportResultRow: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text("\(count) 首")
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
        .listRowBackground(palette.surface)
    }
}
