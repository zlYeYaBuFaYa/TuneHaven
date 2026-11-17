import AVFoundation
import AVKit
import SwiftUI

/// 音频输出入口（docs/UI设计文档.md §7.3；交互设计文档 §7.4）。
/// 显示系统实际输出设备名称，本机扬声器或听筒时显示「音频输出」；点击打开系统路由选择，不自绘设备菜单。
struct AudioOutputButton: View {
    @Environment(\.themePalette) private var palette
    @State private var deviceName = AudioOutputButton.currentDeviceName()
    @State private var trigger = 0

    var body: some View {
        Button {
            trigger += 1
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "airplayaudio")
                    .font(.subheadline)
                Text(deviceName)
                    .font(.subheadline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoutePickerTrigger(trigger: trigger).frame(width: 1, height: 1).opacity(0.01))
        .accessibilityLabel("音频输出：\(deviceName)")
        .accessibilityHint("选择播放设备")
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            Task { @MainActor in deviceName = Self.currentDeviceName() }
        }
    }

    static func currentDeviceName() -> String {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return "音频输出" }
        switch output.portType {
        case .builtInSpeaker, .builtInReceiver:
            return "音频输出"
        default:
            return output.portName.isEmpty ? "音频输出" : output.portName
        }
    }
}

/// 隐藏的系统路由选择器。`trigger` 变化时模拟点击其内部按钮，弹出系统设备选择。
private struct RoutePickerTrigger: UIViewRepresentable {
    let trigger: Int

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        guard trigger != context.coordinator.lastTrigger else { return }
        context.coordinator.lastTrigger = trigger
        view.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastTrigger = 0
    }
}
