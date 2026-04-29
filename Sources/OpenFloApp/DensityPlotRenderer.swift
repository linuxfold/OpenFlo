import AppKit
import Foundation
import OpenFloCore

enum DensityPlotStyle {
    case contour
    case density
    case zebra
    case heatmapStatistic
}

enum DensityPlotRenderer {
    private struct DensityComponent {
        let indices: [Int]
        let maximum: Float
    }

    static func image(from histogram: Histogram2D, style: DensityPlotStyle, levelPercent: Int) -> NSImage {
        let density = normalizedDensityField(from: histogram)
        switch style {
        case .contour:
            return contourImage(density: density, width: histogram.width, height: histogram.height, levelPercent: levelPercent)
        case .density:
            return densityImage(density: density, width: histogram.width, height: histogram.height)
        case .zebra:
            return zebraImage(density: density, width: histogram.width, height: histogram.height, levelPercent: levelPercent)
        case .heatmapStatistic:
            return heatmapStatisticImage(density: density, width: histogram.width, height: histogram.height)
        }
    }

    private static func normalizedDensityField(from histogram: Histogram2D) -> [Float] {
        let raw = smoothedDensities(from: histogram)
        let nonzero = raw.filter { $0 > 0 && $0.isFinite }.sorted()
        guard !nonzero.isEmpty else { return normalizedRawBins(from: histogram) }

        let low = max(percentile(0.02, in: nonzero), Float.leastNonzeroMagnitude)
        let high = max(percentile(0.995, in: nonzero), nonzero.last ?? low, low + Float.leastNonzeroMagnitude)
        let logLow = log1p(low)
        let denominator = max(log1p(high) - logLow, Float.leastNonzeroMagnitude)
        return raw.map { value in
            guard value > 0, value.isFinite else { return 0 }
            return min(max((log1p(min(max(value, low), high)) - logLow) / denominator, 0), 1)
        }
    }

    private static func normalizedRawBins(from histogram: Histogram2D) -> [Float] {
        let maximum = max(Float(histogram.maxBin), 1)
        return histogram.bins.map { count in
            guard count > 0 else { return 0 }
            return log1p(Float(count)) / log1p(maximum)
        }
    }

    private static func densityImage(density: [Float], width: Int, height: Int) -> NSImage {
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = density[y * width + x]
                guard value > 0 else { continue }
                let emphasized = powf(min(max(value, 0), 1), 0.48)
                let gray = UInt8(max(22, min(244, 244 - emphasized * 222)))
                let imageY = height - 1 - y
                RasterImageUtilities.setPixel(
                    x: x,
                    y: imageY,
                    color: (gray, gray, gray, 255),
                    width: width,
                    height: height,
                    pixels: &pixels
                )
            }
        }
        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }

    private static func zebraImage(density: [Float], width: Int, height: Int, levelPercent: Int) -> NSImage {
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        let bands = max(4, min(40, 100 / max(1, levelPercent)))
        for y in 0..<height {
            for x in 0..<width {
                let value = density[y * width + x]
                guard value > 0 else { continue }
                let emphasized = powf(min(max(value, 0), 1), 0.55)
                let band = min(bands - 1, Int(emphasized * Float(bands)))
                let gray: UInt8 = band.isMultiple(of: 2) ? 38 : 232
                let imageY = height - 1 - y
                RasterImageUtilities.setPixel(
                    x: x,
                    y: imageY,
                    color: (gray, gray, gray, 255),
                    width: width,
                    height: height,
                    pixels: &pixels
                )
            }
        }
        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }

    private static func heatmapStatisticImage(density: [Float], width: Int, height: Int) -> NSImage {
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = density[y * width + x]
                guard value > 0 else { continue }
                let color = heatmapStatisticColor(powf(min(max(value, 0), 1), 0.55))
                let imageY = height - 1 - y
                RasterImageUtilities.setPixel(
                    x: x,
                    y: imageY,
                    color: (color.0, color.1, color.2, 255),
                    width: width,
                    height: height,
                    pixels: &pixels
                )
            }
        }
        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }

    private static func contourImage(density: [Float], width: Int, height: Int, levelPercent: Int) -> NSImage {
        let components = densityComponents(in: density, width: width, height: height)
        guard !components.isEmpty else {
            return densityImage(density: density, width: width, height: height)
        }

        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        var drewContour = false
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
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(0.72)
            context.setStrokeColor(NSColor.black.cgColor)

            for component in components {
                let levels = contourLevels(for: component, levelPercent: levelPercent)
                guard !levels.isEmpty else { continue }

                var componentDensity = Array(repeating: Float(0), count: density.count)
                for index in component.indices {
                    componentDensity[index] = density[index]
                }

                for level in levels {
                    let path = contourPath(level: level, density: componentDensity, width: width, height: height)
                    if !path.isEmpty {
                        drewContour = true
                    }
                    context.addPath(path)
                    context.strokePath()
                }
            }

            return context.makeImage()
        }

        guard drewContour else {
            return densityImage(density: density, width: width, height: height)
        }
        if let cgImage {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        return RasterImageUtilities.image(width: width, height: height, pixels: pixels)
    }

    private static func densityComponents(in density: [Float], width: Int, height: Int) -> [DensityComponent] {
        guard density.count == width * height, width > 1, height > 1 else { return [] }

        let nonzero = density.filter { $0 > 0 && $0.isFinite }.sorted()
        guard nonzero.count > 3, let maximum = nonzero.last, maximum > 0 else { return [] }

        let threshold = max(percentile(0.36, in: nonzero), maximum * 0.08)
        let minimumPixelCount = max(4, density.count / 90_000)
        var visited = Array(repeating: false, count: density.count)
        var components: [DensityComponent] = []
        var stack: [Int] = []

        for startIndex in density.indices {
            guard !visited[startIndex], density[startIndex] >= threshold else { continue }

            visited[startIndex] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(startIndex)
            var indices: [Int] = []
            var localMaximum = density[startIndex]

            while let index = stack.popLast() {
                indices.append(index)
                localMaximum = max(localMaximum, density[index])
                let x = index % width
                let y = index / width
                let minX = max(0, x - 1)
                let maxX = min(width - 1, x + 1)
                let minY = max(0, y - 1)
                let maxY = min(height - 1, y + 1)

                for neighborY in minY...maxY {
                    for neighborX in minX...maxX where neighborX != x || neighborY != y {
                        let neighborIndex = neighborY * width + neighborX
                        guard !visited[neighborIndex], density[neighborIndex] >= threshold else { continue }
                        visited[neighborIndex] = true
                        stack.append(neighborIndex)
                    }
                }
            }

            guard indices.count >= minimumPixelCount, localMaximum > threshold else { continue }
            components.append(DensityComponent(indices: indices, maximum: localMaximum))
        }

        let sorted = components.sorted { left, right in
            let leftScore = Double(left.maximum) * log(Double(left.indices.count) + 1)
            let rightScore = Double(right.maximum) * log(Double(right.indices.count) + 1)
            return leftScore > rightScore
        }
        return Array(sorted.prefix(96))
    }

    private static func contourLevels(for component: DensityComponent, levelPercent: Int) -> [Float] {
        guard component.maximum > 0 else { return [] }

        let requestedLevel = max(1, min(25, levelPercent))
        let levelCount = max(3, min(7, Int((42.0 / Double(requestedLevel)).rounded(.toNearestOrAwayFromZero))))
        guard levelCount > 1 else { return [component.maximum * 0.5] }

        let lowFraction: Float = component.indices.count < 16 ? 0.34 : 0.22
        let highFraction: Float = 0.86
        return (0..<levelCount).map { index in
            let fraction = Float(index) / Float(levelCount - 1)
            let eased = powf(fraction, 0.78)
            return component.maximum * (lowFraction + (highFraction - lowFraction) * eased)
        }
    }

    private static func contourPath(level: Float, density: [Float], width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        guard width > 1, height > 1 else { return path }
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let bottomLeft = density[y * width + x]
                let bottomRight = density[y * width + x + 1]
                let topRight = density[(y + 1) * width + x + 1]
                let topLeft = density[(y + 1) * width + x]

                var points: [CGPoint] = []
                appendCrossing(
                    from: CGPoint(x: x, y: y),
                    value: bottomLeft,
                    to: CGPoint(x: x + 1, y: y),
                    otherValue: bottomRight,
                    level: level,
                    output: &points
                )
                appendCrossing(
                    from: CGPoint(x: x + 1, y: y),
                    value: bottomRight,
                    to: CGPoint(x: x + 1, y: y + 1),
                    otherValue: topRight,
                    level: level,
                    output: &points
                )
                appendCrossing(
                    from: CGPoint(x: x + 1, y: y + 1),
                    value: topRight,
                    to: CGPoint(x: x, y: y + 1),
                    otherValue: topLeft,
                    level: level,
                    output: &points
                )
                appendCrossing(
                    from: CGPoint(x: x, y: y + 1),
                    value: topLeft,
                    to: CGPoint(x: x, y: y),
                    otherValue: bottomLeft,
                    level: level,
                    output: &points
                )

                guard points.count >= 2 else { continue }
                appendContourSegment(points[0], points[1], to: path)
                if points.count >= 4 {
                    appendContourSegment(points[2], points[3], to: path)
                }
            }
        }
        return path
    }

    private static func appendCrossing(
        from start: CGPoint,
        value startValue: Float,
        to end: CGPoint,
        otherValue endValue: Float,
        level: Float,
        output: inout [CGPoint]
    ) {
        guard (startValue < level && endValue >= level) || (startValue >= level && endValue < level) else {
            return
        }
        let denominator = endValue - startValue
        guard abs(denominator) > Float.leastNonzeroMagnitude else { return }
        let t = CGFloat(min(max((level - startValue) / denominator, 0), 1))
        output.append(
            CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        )
    }

    private static func appendContourSegment(
        _ start: CGPoint,
        _ end: CGPoint,
        to path: CGMutablePath
    ) {
        let imageStart = CGPoint(x: start.x, y: start.y)
        let imageEnd = CGPoint(x: end.x, y: end.y)
        path.move(to: imageStart)
        path.addLine(to: imageEnd)
    }

    private static func smoothedDensities(from histogram: Histogram2D) -> [Float] {
        let area = areaDensities(from: histogram)
        return gaussianBlurredValues(area, width: histogram.width, height: histogram.height)
    }

    private static func areaDensities(from histogram: Histogram2D) -> [Float] {
        let width = histogram.width
        let height = histogram.height
        let radius = max(3, min(width, height) / 170)
        let stride = width + 1
        var integral = Array(repeating: Int64(0), count: (width + 1) * (height + 1))

        for y in 0..<height {
            var rowSum = Int64(0)
            for x in 0..<width {
                rowSum += Int64(histogram[x, y])
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum
            }
        }

        var densities = Array(repeating: Float(0), count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - radius)
            let y1 = min(height - 1, y + radius)
            for x in 0..<width {
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                let areaCount = integral[(y1 + 1) * stride + x1 + 1]
                    - integral[y0 * stride + x1 + 1]
                    - integral[(y1 + 1) * stride + x0]
                    + integral[y0 * stride + x0]
                let area = max(1, (x1 - x0 + 1) * (y1 - y0 + 1))
                densities[y * width + x] = Float(max(areaCount, 0)) / Float(area)
            }
        }

        return densities
    }

    private static func gaussianBlurredValues(_ source: [Float], width: Int, height: Int) -> [Float] {
        let sigma = max(Float(4.5), Float(min(width, height)) / 78)
        let radius = max(3, Int((sigma * 3).rounded(.up)))
        let kernel = gaussianKernel(sigma: sigma, radius: radius)
        var horizontal = Array(repeating: Float(0), count: width * height)
        var output = Array(repeating: Float(0), count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                var value = Float(0)
                for offset in -radius...radius {
                    let clampedX = min(max(x + offset, 0), width - 1)
                    value += source[y * width + clampedX] * kernel[offset + radius]
                }
                horizontal[y * width + x] = value
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                var value = Float(0)
                for offset in -radius...radius {
                    let clampedY = min(max(y + offset, 0), height - 1)
                    value += horizontal[clampedY * width + x] * kernel[offset + radius]
                }
                output[y * width + x] = value
            }
        }

        return output
    }

    private static func gaussianKernel(sigma: Float, radius: Int) -> [Float] {
        var kernel: [Float] = []
        kernel.reserveCapacity(radius * 2 + 1)
        let denominator = 2 * sigma * sigma
        for offset in -radius...radius {
            let distance = Float(offset * offset)
            kernel.append(exp(-distance / denominator))
        }
        let total = max(kernel.reduce(0, +), Float.leastNonzeroMagnitude)
        return kernel.map { $0 / total }
    }

    private static func percentile(_ percentile: Float, in sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = max(0, min(1, percentile))
        let index = Int((Float(sortedValues.count - 1) * clamped).rounded(.toNearestOrAwayFromZero))
        return sortedValues[index]
    }

    private static func heatmapStatisticColor(_ value: Float) -> (UInt8, UInt8, UInt8) {
        let t = max(0, min(1, value))
        let r = UInt8(max(0, min(255, 255 * t)))
        let g = UInt8(max(0, min(255, 255 * (1 - abs(t - 0.55) / 0.55))))
        let b = UInt8(max(0, min(255, 255 * (1 - t))))
        return (r, g, b)
    }
}
