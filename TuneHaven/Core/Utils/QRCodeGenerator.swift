import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = 200) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaledImage = ciImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
