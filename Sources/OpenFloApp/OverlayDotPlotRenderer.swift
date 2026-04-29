import AppKit
import Foundation
import OpenFloCore

struct OverlayDotPlotSeries {
    let xValues: [Float]
    let yValues: [Float]
    let mask: EventMask?
    let colorName: String
}

enum OverlayDotPlotRenderer {
    static func image(
        series: [OverlayDotPlotSeries],
        width: Int,
        height: Int,
        xRange: ClosedRange<Float>,
        yRange: ClosedRange<Float>,
        maxDotsPerSeries: Int = 85_000
    ) -> NSImage {
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        let xSpan = max(xRange.upperBound - xRange.lowerBound, Float.leastNonzeroMagnitude)
        let ySpan = max(yRange.upperBound - yRange.lowerBound, Float.leastNonzeroMagnitude)

        for item in series {
            let selectedCount = item.mask?.selectedCount ?? item.xValues.count
            let sampleStride = max(1, selectedCount / max(1, maxDotsPerSeries))
            let color = rgbaColor(named: item.colorName)
            var selectedIndex = 0

            for index in item.xValues.indices {
                if let mask = item.mask {
                    guard mask[index] else { continue }
                }
                defer { selectedIndex += 1 }
                guard selectedIndex % sampleStride == 0 else { continue }

                let xValue = item.xValues[index]
                let yValue = item.yValues[index]
                guard xValue.isFinite, yValue.isFinite else { continue }
                guard xValue >= xRange.lowerBound, xValue <= xRange.upperBound else { continue }
                guard yValue >= yRange.lowerBound, yValue <= yRange.upperBound else { continue }

                let x = Int(((xValue - xRange.lowerBound) / xSpan * Float(width - 1)).rounded())
                let y = height - 1 - Int(((yValue - yRange.lowerBound) / ySpan * Float(height - 1)).rounded())
                drawDot(x: x, y: y, color: color, width: width, height: height, pixels: &pixels)
            }
        }

        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }

    private static func drawDot(
        x: Int,
        y: Int,
        color: (UInt8, UInt8, UInt8, UInt8),
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        RasterImageUtilities.setPixel(x: x, y: y, color: color, width: width, height: height, pixels: &pixels)
        RasterImageUtilities.setPixel(x: x + 1, y: y, color: color, width: width, height: height, pixels: &pixels)
        RasterImageUtilities.setPixel(x: x, y: y + 1, color: color, width: width, height: height, pixels: &pixels)
    }
}
