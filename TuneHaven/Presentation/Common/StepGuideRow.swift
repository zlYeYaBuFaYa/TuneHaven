import SwiftUI

struct StepGuideRow: View {
    let step: String
    let text: String
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundColor(palette.onPrimary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(palette.primary))
            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
        }
        .padding(.vertical, 2)
        .listRowBackground(palette.surface)
    }
}
