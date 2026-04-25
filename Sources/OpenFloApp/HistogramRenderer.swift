import AppKit
import CoreGraphics
import Foundation
import OpenFloCore

enum HistogramRenderer {
    static func image(from histogram: Histogram1D, height: Int = 640, yRange: ClosedRange<Float>) -> NSImage {
        let width = histogram.width
        let yMaximum = max(yRange.upperBound, 1)
        let baseline = CGFloat(height - 1)
        let drawableHeight = CGFloat(height - 2)
        let topPoints = (0..<width).map { x in
            let normalized = min(max(Float(histogram[x]) / yMaximum, 0), 1)
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
            context.setFillColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
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
            context.setLineWidth(3)
            context.setLineJoin(.round)
            context.strokePath()

            return context.makeImage()
        }

        guard let cgImage else {
            return NSImage(size: NSSize(width: width, height: height))
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
