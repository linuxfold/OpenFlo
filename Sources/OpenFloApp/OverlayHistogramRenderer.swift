import AppKit
import CoreGraphics
import Foundation
import OpenFloCore

struct OverlayHistogramSeries {
    let histogram: Histogram1D
    let colorName: String
}

enum OverlayHistogramRenderer {
    static func image(
        series: [OverlayHistogramSeries],
        height: Int,
        yRange: ClosedRange<Float>,
        cumulative: Bool = false,
        smooth: Bool = true
    ) -> NSImage {
        guard let first = series.first else {
            return NSImage(size: NSSize(width: 1, height: max(height, 1)))
        }
        let width = first.histogram.width
        let ySpan = max(yRange.upperBound - yRange.lowerBound, Float.leastNonzeroMagnitude)
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
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)

            for item in series {
                let color = nsColor(named: item.colorName).usingColorSpace(.deviceRGB) ?? .black
                let points = cumulative
                    ? cumulativePoints(for: item.histogram, height: height, yRange: yRange, ySpan: ySpan)
                    : histogramPoints(for: item.histogram, height: height, yRange: yRange, ySpan: ySpan, smooth: smooth)

                if !cumulative {
                    fillHistogram(points: points, width: width, height: height, color: color, in: context)
                }
                stroke(points: points, color: color, in: context)
            }

            return context.makeImage()
        }

        guard let cgImage else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private static func histogramPoints(
        for histogram: Histogram1D,
        height: Int,
        yRange: ClosedRange<Float>,
        ySpan: Float,
        smooth: Bool
    ) -> [CGPoint] {
        let baseline = CGFloat(height - 1)
        let drawableHeight = CGFloat(height - 2)
        let bins = HistogramRenderer.displayedBins(for: histogram, smooth: smooth)
        return bins.enumerated().map { x, count in
            let normalized = min(max((count - yRange.lowerBound) / ySpan, 0), 1)
            return CGPoint(
                x: CGFloat(x),
                y: baseline - CGFloat(normalized) * drawableHeight
            )
        }
    }

    private static func cumulativePoints(
        for histogram: Histogram1D,
        height: Int,
        yRange: ClosedRange<Float>,
        ySpan: Float
    ) -> [CGPoint] {
        let total = histogram.bins.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0 else {
            return (0..<histogram.width).map { CGPoint(x: CGFloat($0), y: CGFloat(height - 1)) }
        }

        var cumulative = UInt64(0)
        return (0..<histogram.width).map { x in
            cumulative += UInt64(histogram[x])
            let fraction = Float(cumulative) / Float(total)
            let normalized = min(max((fraction - yRange.lowerBound) / ySpan, 0), 1)
            return CGPoint(
                x: CGFloat(x),
                y: CGFloat(height - 1) - CGFloat(normalized) * CGFloat(height - 2)
            )
        }
    }

    private static func fillHistogram(
        points: [CGPoint],
        width: Int,
        height: Int,
        color: NSColor,
        in context: CGContext
    ) {
        guard !points.isEmpty else { return }
        let baseline = CGFloat(height - 1)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: baseline))
        for point in points {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: CGFloat(width - 1), y: baseline))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color.withAlphaComponent(0.16).cgColor)
        context.fillPath()
    }

    private static func stroke(points: [CGPoint], color: NSColor, in context: CGContext) {
        guard let first = points.first else { return }
        let path = CGMutablePath()
        path.move(to: first)
        appendTopPath(to: path, points: points)
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.4)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    private static func appendTopPath(to path: CGMutablePath, points: [CGPoint]) {
        guard points.count > 1 else { return }
        path.addLine(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
    }
}
