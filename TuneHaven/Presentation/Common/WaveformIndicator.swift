import SwiftUI

struct WaveformIndicator: View {
    let color: Color

    var body: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "waveform")
                .font(.caption2)
                .foregroundColor(color)
                .symbolEffect(.variableColor.iterative)
        } else {
            Image(systemName: "waveform")
                .font(.caption2)
                .foregroundColor(color)
        }
    }
}
