import SwiftUI

struct ImportProgressSection: View {
    let progress: ImportProgress
    var isCancelling = false
    let onCancel: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isCancelling ? "正在停止导入…" : "正在导入")
                        .font(.headline).foregroundColor(palette.textPrimary)
                    Spacer()
                    if progress.totalCount > 0 {
                        Text("\(progress.completedCount) / \(progress.totalCount)")
                            .font(.subheadline.monospacedDigit()).foregroundColor(palette.textSecondary)
                    }
                }
                Text(progress.currentFileName).font(.subheadline).foregroundColor(palette.textSecondary).lineLimit(2)
                ProgressView(value: min(max(progress.percentage, 0), 1)).tint(palette.accent)
                if let remaining = progress.estimatedRemainingSeconds, remaining.isFinite, remaining > 0, !isCancelling {
                    Text("约剩 \(remaining.formattedTime)").font(.footnote).foregroundColor(palette.textSecondary)
                }
            }
            .padding(.vertical, 4).importRowSurface()
            Button(action: onCancel) {
                Text(isCancelling ? "正在停止…" : "停止导入").frame(minHeight: 44)
            }
            .foregroundColor(palette.accent).disabled(isCancelling).importRowSurface()
        } footer: {
            Text("停止后，已经导入的音乐会保留。关闭页面不会停止导入。").foregroundColor(palette.textSecondary)
        }
    }
}
