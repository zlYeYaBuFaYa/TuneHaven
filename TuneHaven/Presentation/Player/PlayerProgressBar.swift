import SwiftUI

/// 播放进度条组件，在 PlayerView 和 LyricsPageView 中共享
struct PlayerProgressBar: View {
    let barHeight: CGFloat
    let touchHeight: CGFloat
    let timeFont: Font
    let timeColor: Color?

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @Environment(\.themePalette) private var palette

    init(
        barHeight: CGFloat = 6,
        touchHeight: CGFloat = 24,
        timeFont: Font = .caption.monospacedDigit(),
        timeColor: Color? = nil
    ) {
        self.barHeight = barHeight
        self.touchHeight = touchHeight
        self.timeFont = timeFont
        self.timeColor = timeColor
    }

    var body: some View {
        let resolvedTimeColor = timeColor ?? palette.textSecondary

        VStack(spacing: barHeight >= 5 ? 6 : 4) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.progressBackground)
                        .frame(height: barHeight)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.gradientStart, palette.gradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, barHeight), height: barHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            playback.seek(to: ratio * engine.duration)
                        }
                )
            }
            .frame(height: touchHeight)

            HStack {
                Text(engine.currentTime.formattedTime)
                    .font(timeFont)
                    .foregroundColor(resolvedTimeColor)
                Spacer()
                Text("-\((engine.duration - engine.currentTime).formattedTime)")
                    .font(timeFont)
                    .foregroundColor(resolvedTimeColor)
            }
        }
    }
}
