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
    @State private var isScrubbing = false
    @State private var scrubRatio: Double = 0

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
        let displayProgress: Double = {
            if isScrubbing { return scrubRatio }
            return engine.duration > 0 ? engine.currentTime / engine.duration : 0
        }()
        let displayTime = isScrubbing ? scrubRatio * engine.duration : engine.currentTime

        VStack(spacing: barHeight >= 5 ? 6 : 4) {
            GeometryReader { geo in
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
                        .frame(width: max(geo.size.width * displayProgress, barHeight), height: barHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubRatio = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            playback.seek(to: scrubRatio * engine.duration)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: touchHeight)

            HStack {
                Text(displayTime.formattedTime)
                    .font(timeFont)
                    .foregroundColor(resolvedTimeColor)
                Spacer()
                Text("-\((engine.duration - displayTime).formattedTime)")
                    .font(timeFont)
                    .foregroundColor(resolvedTimeColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(displayTime.formattedTime)，共\(engine.duration.formattedTime)")
    }
}
