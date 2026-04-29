import AppKit
import Foundation
import OpenFloCore

enum DotPlotRenderer {
    static func image(
        xValues: [Float],
        yValues: [Float],
        mask: EventMask?,
        width: Int,
        height: Int,
        xRange: ClosedRange<Float>,
        yRange: ClosedRange<Float>,
        maxDots: Int = 220_000
    ) -> NSImage {
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        let selectedCount = mask?.selectedCount ?? xValues.count
        let sampleStride = max(1, selectedCount / max(1, maxDots))
        let xSpan = max(xRange.upperBound - xRange.lowerBound, Float.leastNonzeroMagnitude)
        let ySpan = max(yRange.upperBound - yRange.lowerBound, Float.leastNonzeroMagnitude)
        var selectedIndex = 0

        for index in xValues.indices {
            if let mask {
                guard mask[index] else { continue }
            }
            defer { selectedIndex += 1 }
            guard selectedIndex % sampleStride == 0 else { continue }
            let xValue = xValues[index]
            let yValue = yValues[index]
            guard xValue.isFinite, yValue.isFinite else { continue }
            guard xValue >= xRange.lowerBound, xValue <= xRange.upperBound else { continue }
            guard yValue >= yRange.lowerBound, yValue <= yRange.upperBound else { continue }

            let x = Int(((xValue - xRange.lowerBound) / xSpan * Float(width - 1)).rounded())
            let y = height - 1 - Int(((yValue - yRange.lowerBound) / ySpan * Float(height - 1)).rounded())
            drawDot(x: x, y: y, width: width, height: height, pixels: &pixels)
        }

        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }

    private static func drawDot(x: Int, y: Int, width: Int, height: Int, pixels: inout [UInt8]) {
        for dy in -1...1 {
            for dx in -1...1 {
                let distance = abs(dx) + abs(dy)
                let gray: UInt8 = distance == 0 ? 0 : 70
                RasterImageUtilities.setPixel(
                    x: x + dx,
                    y: y + dy,
                    color: (gray, gray, gray, 255),
                    width: width,
                    height: height,
                    pixels: &pixels
                )
            }
        }
    }
}
