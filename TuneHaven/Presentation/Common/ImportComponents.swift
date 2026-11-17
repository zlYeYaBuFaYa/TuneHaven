import SwiftUI

/// Shared by the import hub and Settings shortcuts.
enum MusicImportSource: String, CaseIterable, Identifiable {
    case files, appleMusic, cloudDrive, wifi, webDAV
    var id: String { rawValue }
    var title: String {
        switch self {
        case .files: return "文件导入"
        case .appleMusic: return "Apple Music"
        case .cloudDrive: return "云盘导入"
        case .wifi: return "WiFi 传输"
        case .webDAV: return "WebDAV 导入"
        }
    }
    var symbol: String {
        switch self {
        case .files: return "folder"
        case .appleMusic: return "music.note.house"
        case .cloudDrive: return "cloud"
        case .wifi: return "wifi"
        case .webDAV: return "server.rack"
        }
    }
    var subtitle: String {
        switch self {
        case .files: return "从「文件」中选择本地或云端音频"
        case .appleMusic: return "导入资料库中已下载、无 DRM 保护的音乐"
        case .cloudDrive: return "从网盘或其他 App 带入音乐"
        case .wifi: return "在同一 WiFi 下，从电脑浏览器上传"
        case .webDAV: return "连接 NAS、坚果云等个人音乐收藏"
        }
    }
}

struct ImportIntro: View {
    let symbol: String
    let title: String
    let message: String
    @Environment(\.themePalette) private var palette
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2).foregroundColor(palette.accent)
                .frame(width: 48, height: 48)
                .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title3.weight(.semibold)).foregroundColor(palette.textPrimary)
                Text(message).font(.subheadline).foregroundColor(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

struct ImportSourceLabel: View {
    let source: MusicImportSource
    var locked = false
    @Environment(\.themePalette) private var palette
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: source.symbol)
                .font(.title3).foregroundColor(palette.accent)
                .frame(width: 44, height: 44)
                .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(source.title).font(.body.weight(.medium))
                    if locked { Image(systemName: "lock.fill").font(.caption).accessibilityLabel("Premium 专属") }
                }
                .foregroundColor(palette.textPrimary)
                Text(locked ? "Premium 专属功能" : source.subtitle).font(.footnote).foregroundColor(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(palette.textSecondary).accessibilityHidden(true)
        }
        .padding(.vertical, 7).frame(minHeight: 60).contentShape(Rectangle())
    }
}

private struct ImportRowSurface: ViewModifier {
    var secondary: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .listRowBackground((secondary ? palette.surfaceSecondary : palette.surface).opacity(reduceTransparency ? 1 : 0.76))
            .listRowSeparatorTint(palette.separator)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
}

extension View {
    func importRowSurface(secondary: Bool = false) -> some View { modifier(ImportRowSurface(secondary: secondary)) }
}

enum ImportPickerFailure {
    static func message(for error: Error) -> String? {
        let error = error as NSError
        if (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
            || (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) { return nil }
        return "文件选择失败：\(error.localizedDescription)"
    }
}

extension ImportResult {
    var presentationTitle: String {
        if successCount > 0 {
            return failedCount + skippedFormatCount + skippedOversizeCount > 0 ? "部分导入完成" : "导入完成"
        }
        if failedCount > 0 { return "导入未完成" }
        if skippedFormatCount + skippedOversizeCount > 0 { return "没有可导入的文件" }
        if skippedDuplicateCount > 0 { return "已跳过重复文件" }
        return "没有可导入的文件"
    }
}
