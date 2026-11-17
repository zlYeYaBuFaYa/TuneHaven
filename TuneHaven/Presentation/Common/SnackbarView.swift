import SwiftUI

// MARK: - SnackbarView（TDD §1.2 Common）

struct SnackbarView: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(palette.onAction)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.onAction)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Capsule().stroke(palette.onAction.opacity(0.5), lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        // 反色提示：主操作色底 + onAction 文字，三套主题日夜都满足对比度
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.actionFill)
        )
        .shadow(color: palette.cardShadow, radius: 14, y: 6)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - SnackbarState（全局状态，注入到 App）

@MainActor
final class SnackbarState: ObservableObject {
    @Published private(set) var isShowing = false
    @Published private(set) var message = ""
    @Published private(set) var actionTitle: String? = nil
    private var action: (() -> Void)? = nil
    private var hideTask: Task<Void, Never>? = nil

    func show(message: String,
              actionTitle: String? = nil,
              action: (() -> Void)? = nil,
              duration: TimeInterval = 4.0) {
        hideTask?.cancel()
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        withAnimation(.spring(response: 0.35)) { isShowing = true }

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func performAction() {
        action?()
        action = nil
        hide()
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(.easeOut(duration: 0.25)) { isShowing = false }
        action = nil
        actionTitle = nil
    }
}

// MARK: - ViewModifier 将 Snackbar 叠加到底部

struct SnackbarModifier: ViewModifier {
    @ObservedObject var state: SnackbarState
    /// 悬浮底栏 + 迷你播放器之上
    var bottomPadding: CGFloat = 150

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if state.isShowing {
                SnackbarView(
                    message: state.message,
                    actionTitle: state.actionTitle,
                    action: state.actionTitle != nil ? { state.performAction() } : nil
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, bottomPadding)
                .zIndex(999)
            }
        }
        .onChange(of: state.isShowing) { showing in
            guard showing else { return }
            AccessibilityNotification.Announcement(state.message).post()
        }
    }
}

extension View {
    func snackbar(_ state: SnackbarState, bottomPadding: CGFloat = 150) -> some View {
        modifier(SnackbarModifier(state: state, bottomPadding: bottomPadding))
    }
}
