import AppKit
import CoreGraphics
import Foundation
import OpenFloCore

enum HistogramRenderer {
    static func image(
        from histogram: Histogram1D,
        width requestedWidth: Int? = nil,
        height: Int = 640,
        yRange: ClosedRange<Float>,
        smooth: Bool = true
    ) -> NSImage {
        let width = max(requestedWidth ?? histogram.width, 1)
        let counts = displayCounts(for: histogram, width: width, smooth: smooth)
        let ySpan = max(yRange.upperBound - yRange.lowerBound, Float.leastNonzeroMagnitude)
        let baseline = CGFloat(height - 1)
        let drawableHeight = CGFloat(max(height - 2, 1))
        let topPoints = counts.enumerated().map { x, count in
            let normalized = min(max((count - yRange.lowerBound) / ySpan, 0), 1)
            return CGPoint(
                x: CGFloat(x),
                y: baseline - CGFloat(normalized) * drawableHeight
            )
        }

        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        let cgImage = pixels.withUnsafeMutableBytes { rawBuffer -> CGImage? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)

            let fillPath = CGMutablePath()
            fillPath.move(to: CGPoint(x: 0, y: baseline))
            for point in topPoints {
                fillPath.addLine(to: point)
            }
            fillPath.addLine(to: CGPoint(x: CGFloat(width - 1), y: baseline))
            fillPath.closeSubpath()

            context.addPath(fillPath)
            context.setFillColor(NSColor(calibratedWhite: 0.70, alpha: 1).cgColor)
            context.fillPath()

            let outlinePath = CGMutablePath()
            if let first = topPoints.first {
                outlinePath.move(to: first)
                for point in topPoints.dropFirst() {
                    outlinePath.addLine(to: point)
                }
            }
            context.addPath(outlinePath)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(max(2.4, min(3.4, CGFloat(width) / 210)))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()

            return context.makeImage()
        }

        guard let cgImage else {
            return NSImage(size: NSSize(width: width, height: height))
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    static func displayedBins(for histogram: Histogram1D, smooth: Bool) -> [Float] {
        let rawBins = histogram.bins.map { Float($0) }
        guard smooth else { return rawBins }
        return gaussianSmoothed(rawBins)
    }

    static func displayMaximum(for histogram: Histogram1D, smooth: Bool) -> Float {
        max(displayedBins(for: histogram, smooth: smooth).max() ?? 0, 1)
    }

    static func displayCounts(for histogram: Histogram1D, width: Int, smooth: Bool) -> [Float] {
        let bins = displayedBins(for: histogram, smooth: smooth)
        guard width > 0 else { return [] }
        guard bins.count > 1, width > 1 else { return Array(repeating: bins.first ?? 0, count: width) }

        return (0..<width).map { x in
            let binPosition = Float(x) / Float(width - 1) * Float(bins.count - 1)
            let lowerIndex = min(max(Int(floor(binPosition)), 0), bins.count - 1)
            let upperIndex = min(lowerIndex + 1, bins.count - 1)
            let fraction = binPosition - Float(lowerIndex)
            return bins[lowerIndex] + (bins[upperIndex] - bins[lowerIndex]) * fraction
        }
    }

    private static func gaussianSmoothed(_ values: [Float]) -> [Float] {
        guard values.count > 2 else { return values }
        let sigma = max(Float(1.25), min(Float(2.25), Float(values.count) / 160))
        let radius = max(2, Int(ceil(sigma * 2.5)))
        let weights = (-radius...radius).map { offset -> Float in
            let distance = Float(offset)
            return exp(-(distance * distance) / (2 * sigma * sigma))
        }
        let weightSum = weights.reduce(0, +)

        return values.indices.map { index in
            var total: Float = 0
            for offset in -radius...radius {
                let sourceIndex = min(max(index + offset, 0), values.count - 1)
                total += values[sourceIndex] * weights[offset + radius]
            }
            return total / max(weightSum, Float.leastNonzeroMagnitude)
        }
    }

}
