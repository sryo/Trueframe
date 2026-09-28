import UIKit

extension UIImage {
    /// The mean color, from a tiny downscale so it stays cheap.
    func averageColor() -> BurstField.RGB {
        let gray = BurstField.RGB(red: 0.5, green: 0.5, blue: 0.5)
        guard let cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return gray }

        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return gray }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var sums = [0, 0, 0]
        for pixel in 0..<(side * side) {
            for channel in 0..<3 { sums[channel] += Int(pixels[pixel * 4 + channel]) }
        }
        let scale = Double(side * side * 255)
        return BurstField.RGB(red: Double(sums[0]) / scale, green: Double(sums[1]) / scale, blue: Double(sums[2]) / scale)
    }
}
