import SwiftUI

struct ImportResultSection: View {
    let result: ImportResult
    var wasCancelled = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        Section {
            Label(wasCancelled ? "已停止导入" : result.presentationTitle,
                  systemImage: wasCancelled ? "stop.circle" : (result.successCount > 0 ? "checkmark.circle" : "info.circle"))
                .font(.headline).foregroundColor(palette.textPrimary).importRowSurface()
            ImportResultRow(title: "成功", count: result.successCount, color: palette.accent, icon: "checkmark.circle")
            if result.incompleteMetadataCount > 0 {
                ImportResultRow(title: "元数据不完整", count: result.incompleteMetadataCount, color: SemanticColor.warning, icon: "exclamationmark.circle")
            }
            if result.skippedDuplicateCount > 0 {
                ImportResultRow(title: "已跳过（重复）", count: result.skippedDuplicateCount, color: palette.textSecondary, icon: "arrow.2.circlepath")
            }
            if result.skippedFormatCount > 0 {
                ImportResultRow(title: "格式不支持", count: result.skippedFormatCount, color: palette.textSecondary, icon: "doc.badge.minus")
            }
            if result.skippedOversizeCount > 0 {
                ImportResultRow(title: "超过大小限制", count: result.skippedOversizeCount, color: SemanticColor.warning, icon: "exclamationmark.triangle")
            }
            if result.failedCount > 0 {
                ImportResultRow(title: "失败", count: result.failedCount, color: SemanticColor.danger, icon: "xmark.circle")
            }
            ForEach(Array(result.details.filter { $0.status == .failed }.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 5) {
                    if !item.fileName.isEmpty { Text(item.fileName).font(.subheadline).foregroundColor(palette.textPrimary) }
                    Text(item.errorMessage ?? "这个文件暂时无法导入，请重新选择后重试。")
                        .font(.footnote).foregroundColor(palette.textSecondary)
                }
                .importRowSurface()
            }
        } header: {
            Text("导入结果").foregroundColor(palette.textSecondary)
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
        .importRowSurface()
    }
}
