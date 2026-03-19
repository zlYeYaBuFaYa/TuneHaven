import SwiftUI

struct LyricsView: View {
    let lyricsData: LyricsData
    let currentTime: TimeInterval
    @Environment(\.themePalette) private var palette

    private var currentLineIndex: Int? {
        for (i, line) in lyricsData.lines.enumerated().reversed() {
            if currentTime >= line.timestamp { return i }
        }
        return nil
    }

    var body: some View {
        if !lyricsData.lines.isEmpty {
            syncedLyricsView
        } else if !lyricsData.rawText.isEmpty {
            plainTextView
        }
    }

    private var syncedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(lyricsData.lines) { line in
                        let isCurrent = currentLineIndex.map { lyricsData.lines[$0].id == line.id } ?? false
                        Text(line.text)
                            .font(isCurrent ? .headline.bold() : .subheadline)
                            .foregroundColor(isCurrent ? palette.primary : palette.playerSubtext)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.3), value: isCurrent)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 16)
            }
            .onChange(of: currentLineIndex) { _, newIdx in
                if let idx = newIdx {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(lyricsData.lines[idx].id, anchor: .center)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var plainTextView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(lyricsData.rawText)
                .font(.subheadline)
                .foregroundColor(palette.playerSubtext)
                .multilineTextAlignment(.center)
                .padding(.vertical, 40)
                .padding(.horizontal, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
