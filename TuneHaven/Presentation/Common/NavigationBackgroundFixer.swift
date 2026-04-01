import SwiftUI
import UIKit

// ⚠️ 技术债务：依赖 UIKit responder chain 内部实现遍历视图层级，
// 未来 iOS 版本可能导致行为变化，需关注兼容性

/// 通过 UIKit responder chain 找到父级 UINavigationController，
/// 设置其 view.backgroundColor，防止导航转场时露出系统默认黑色背景。
struct NavigationBackgroundFixer: UIViewRepresentable {
    let color: Color

    func makeUIView(context: Context) -> UIView {
        let view = LayoutPassView(color: UIColor(color))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let passView = uiView as? LayoutPassView else { return }
        passView.targetColor = UIColor(color)
        passView.applyToNavigationController()
    }
}

private final class LayoutPassView: UIView {
    var targetColor: UIColor

    init(color: UIColor) {
        self.targetColor = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyToNavigationController()
    }

    func applyToNavigationController() {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let nav = next as? UINavigationController {
                if nav.view.backgroundColor != targetColor {
                    nav.view.backgroundColor = targetColor
                    AppLogger.shared.debug("NavBGFixer: set UINavigationController.view.backgroundColor")
                }
                return
            }
            responder = next
        }
    }
}

extension View {
    /// 修复 NavigationStack 内部 UINavigationController 的背景色
    func fixNavigationControllerBackground(_ color: Color) -> some View {
        self.background(NavigationBackgroundFixer(color: color))
    }
}
