import SwiftUI

struct FlowChoiceLabel: View {
    let symbol: String
    let title: String
    let message: String
    @Environment(\.themePalette) private var palette
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundColor(palette.accent)
                .frame(width: 44, height: 44)
                .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium)).foregroundColor(palette.textPrimary)
                Text(message).font(.footnote).foregroundColor(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(palette.textSecondary).accessibilityHidden(true)
        }
        .frame(minHeight: 60).contentShape(Rectangle())
    }
}

struct FlowPrimaryButtonStyle: ButtonStyle {
    @Environment(\.themePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(palette.onAction)
            .padding(.horizontal, 22).frame(minHeight: 48)
            .background(palette.actionFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
