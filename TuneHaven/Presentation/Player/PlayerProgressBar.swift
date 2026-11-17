import SwiftUI

/// 播放进度条，在 PlayerView 和 LyricsPageView 中共享（交互设计文档 §7.2）。
/// 视觉轨道细，命中区至少 44；拖动时只预览时间，松手才 seek，并保持原来的播放／暂停状态。
/// 没有有效时长时不可拖动，读出「时长未知」。
struct PlayerProgressBar: View {
    let barHeight: CGFloat
    let touchHeight: CGFloat
    let timeFont: Font
    let timeColor: Color?

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @Environment(\.themePalette) private var palette

    /// 拖动中的预览位置（0…1）。nil 表示未在拖动
    @State private var scrubRatio: Double?

    init(
        barHeight: CGFloat = 5,
        touchHeight: CGFloat = 44,
        timeFont: Font = .caption.monospacedDigit(),
        timeColor: Color? = nil
    ) {
        self.barHeight = barHeight
        self.touchHeight = max(touchHeight, 44)
        self.timeFont = timeFont
        self.timeColor = timeColor
    }

    private var hasDuration: Bool { engine.duration.isFinite && engine.duration > 0 }

    private var displayRatio: Double {
        if let scrubRatio { return scrubRatio }
        guard hasDuration else { return 0 }
        return min(max(engine.currentTime / engine.duration, 0), 1)
    }

    private var displayTime: TimeInterval {
        scrubRatio.map { $0 * engine.duration } ?? engine.currentTime
    }

    var body: some View {
        let resolvedTimeColor = timeColor ?? palette.textSecondary
        let isScrubbing = scrubRatio != nil

        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.progressBackground)
                        .frame(height: barHeight)
                    Capsule()
                        .fill(palette.actionFill)
                        .frame(width: max(geo.size.width * displayRatio, barHeight), height: barHeight)
                    Circle()
                        .fill(palette.actionFill)
                        .frame(width: isScrubbing ? 18 : 12, height: isScrubbing ? 18 : 12)
                        .offset(x: geo.size.width * displayRatio - (isScrubbing ? 9 : 6))
                        .opacity(hasDuration ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard hasDuration else { return }
                            scrubRatio = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            guard hasDuration else { return }
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            playback.seek(to: ratio * engine.duration)
                            scrubRatio = nil
                        }
                )
                .animation(.easeOut(duration: 0.12), value: isScrubbing)
            }
            .frame(height: touchHeight)
            .accessibilityElement()
            .accessibilityLabel("播放进度")
            .accessibilityValue(hasDuration
                                ? "\(displayTime.formattedTime)，共 \(engine.duration.formattedTime)"
                                : "时长未知")
            .accessibilityAdjustableAction { direction in
                guard hasDuration else { return }
                let step: TimeInterval = 10
                let target = direction == .increment ? engine.currentTime + step : engine.currentTime - step
                playback.seek(to: min(max(target, 0), engine.duration))
            }

            HStack {
                Text(displayTime.formattedTime)
                Spacer()
                Text(hasDuration ? "−\(max(engine.duration - displayTime, 0).formattedTime)" : "--:--")
            }
            .font(timeFont)
            .foregroundColor(isScrubbing ? palette.textPrimary : resolvedTimeColor)
            .accessibilityHidden(true)
        }
    }
}
