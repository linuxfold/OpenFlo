import AppKit
import Foundation
import OpenFloCore

enum CDFRenderer {
    static func image(from histogram: Histogram1D, height: Int = 640, yRange: ClosedRange<Float>) -> NSImage {
        let width = histogram.width
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        let total = histogram.bins.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0 else {
            return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
        }

        var cumulative = UInt64(0)
        var previous: CGPoint?
        for x in 0..<width {
            cumulative += UInt64(histogram[x])
            let fraction = Float(cumulative) / Float(total)
            let normalizedY = (fraction - yRange.lowerBound) / max(yRange.upperBound - yRange.lowerBound, Float.leastNonzeroMagnitude)
            let y = CGFloat(height - 1) - CGFloat(min(max(normalizedY, 0), 1)) * CGFloat(height - 2)
            let point = CGPoint(x: CGFloat(x), y: y)
            if let previous {
                RasterImageUtilities.drawLine(
                    from: previous,
                    to: point,
                    color: (0, 0, 0, 255),
                    width: width,
                    height: height,
                    pixels: &pixels
                )
            }
            previous = point
        }

        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }
}
