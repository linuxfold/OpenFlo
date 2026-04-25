import AppKit
import CoreGraphics
import Foundation
import OpenFloCore

enum HistogramRenderer {
    static func image(from histogram: Histogram1D, height: Int = 640) -> NSImage {
        let width = histogram.width
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        let maxBin = max(histogram.maxBin, 1)

        for x in 0..<width {
            let normalized = log1p(Float(histogram[x])) / log1p(Float(maxBin))
            let barHeight = Int((normalized * Float(height - 1)).rounded(.down))
            for y in max(0, height - barHeight - 1)..<height {
                let offset = (y * width + x) * 4
                pixels[offset] = 0
                pixels[offset + 1] = 120
                pixels[offset + 2] = 210
                pixels[offset + 3] = 255
            }
        }

        for x in 0..<width {
            let offset = ((height - 1) * width + x) * 4
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 255
        }

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
}
