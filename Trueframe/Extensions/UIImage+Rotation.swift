// Image orientation and analysis helpers.

import UIKit

extension UIImage {
    func correctedForOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // Returns average brightness (0.0 = black, 1.0 = white)
    func averageBrightness() -> CGFloat {
        guard let cgImage = self.cgImage else { return 0.5 }

        let width = 50  // Sample at low resolution for speed
        let height = 50
        let colorSpace = CGColorSpaceCreateDeviceGray()

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0.5 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let total = pixels.reduce(0) { $0 + Int($1) }
        return CGFloat(total) / CGFloat(pixels.count * 255)
    }

    var isPitchBlack: Bool {
        averageBrightness() < 0.05  // Less than 5% brightness
    }
}
