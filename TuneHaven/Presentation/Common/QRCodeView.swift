import SwiftUI

struct QRCodeView: View {
    let content: String
    var size: CGFloat = 200

    @Environment(\.themePalette) private var palette
    @State private var qrImage: UIImage?

    var body: some View {
        Group {
            if let img = qrImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.surface)
                    .frame(width: size, height: size)
                    .overlay(ProgressView())
            }
        }
        .task { qrImage = QRCodeGenerator.generate(from: content, size: size) }
        .onChange(of: content) { _, new in
            qrImage = QRCodeGenerator.generate(from: new, size: size)
        }
    }
}
