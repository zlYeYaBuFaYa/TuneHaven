import SwiftUI

struct ImportProgressSection: View {
    let progress: ImportProgress
    let onCancel: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("正在导入 \(progress.currentFileName)")
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                ProgressView(value: progress.percentage)
                    .tint(palette.primary)
                HStack {
                    Text("\(progress.completedCount)/\(progress.totalCount)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                    if let remaining = progress.estimatedRemainingSeconds {
                        Text("约剩 \(remaining.formattedTime)")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(palette.surface)

            Button("取消导入") {
                onCancel()
            }
            .foregroundColor(SemanticColor.danger)
            .listRowBackground(palette.surface)
        }
    }
}
