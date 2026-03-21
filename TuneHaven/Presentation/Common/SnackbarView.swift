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
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [palette.gradientStart, palette.gradientEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.gradientStart.opacity(0.3), radius: 8, y: 2)
        .padding(.horizontal, 16)
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
            await self?.hide()
        }
    }

    func performAction() {
        action?()
        action = nil
        hide()
    }

    func hide() {
        withAnimation(.easeOut(duration: 0.25)) { isShowing = false }
    }
}

// MARK: - ViewModifier 将 Snackbar 叠加到底部

struct SnackbarModifier: ViewModifier {
    @ObservedObject var state: SnackbarState
    var bottomPadding: CGFloat = 90

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
    }
}

extension View {
    func snackbar(_ state: SnackbarState, bottomPadding: CGFloat = 90) -> some View {
        modifier(SnackbarModifier(state: state, bottomPadding: bottomPadding))
    }
}
