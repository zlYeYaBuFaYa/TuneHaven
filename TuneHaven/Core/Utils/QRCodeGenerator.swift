import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCodeGenerator {
    /// 生成指定内容的二维码 CGImage（TDD Section 7.2 WiFi QR Code）
    static func generate(from string: String, size: CGFloat = 200) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up to avoid blurriness
        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaledImage = ciImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// SwiftUI wrapper for QR Code display
struct QRCodeView: View {
    let content: String
    var size: CGFloat = 200

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
                    .fill(Color.gray.opacity(0.2))
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
