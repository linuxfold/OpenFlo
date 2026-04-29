import AppKit
import CoreGraphics
import Foundation

enum RasterImageUtilities {
    static func image(width: Int, height: Int, pixels: [UInt8]) -> NSImage {
        let providerData = Data(pixels) as CFData
        guard
            let provider = CGDataProvider(data: providerData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return NSImage(size: NSSize(width: width, height: height))
        }

        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    static func setPixel(
        x: Int,
        y: Int,
        color: (UInt8, UInt8, UInt8, UInt8),
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = (y * width + x) * 4
        pixels[offset] = color.0
        pixels[offset + 1] = color.1
        pixels[offset + 2] = color.2
        pixels[offset + 3] = color.3
    }

    static func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        color: (UInt8, UInt8, UInt8, UInt8),
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        var x0 = Int(start.x.rounded())
        var y0 = Int(start.y.rounded())
        let x1 = Int(end.x.rounded())
        let y1 = Int(end.y.rounded())
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var error = dx + dy

        while true {
            setPixel(x: x0, y: y0, color: color, width: width, height: height, pixels: &pixels)
            if x0 == x1, y0 == y1 { break }
            let doubledError = 2 * error
            if doubledError >= dy {
                error += dy
                x0 += sx
            }
            if doubledError <= dx {
                error += dx
                y0 += sy
            }
        }
    }
}
