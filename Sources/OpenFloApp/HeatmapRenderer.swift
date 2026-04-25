import AppKit
import CoreGraphics
import Foundation
import OpenFloCore

enum HeatmapRenderer {
    private static let densityCoolingGamma: Float = 1.32
    private static let redDensityMultiplier: Float = 1.18

    static func image(from histogram: Histogram2D) -> NSImage {
        var pixels = Array(repeating: UInt8(255), count: histogram.width * histogram.height * 4)
        var paintedDensities = Array(repeating: Float(0), count: histogram.width * histogram.height)
        let densities = areaDensities(from: histogram)
        let scale = densityScale(for: densities, occupiedBins: histogram.bins)
        let low = log1p(max(scale.low, Float.leastNonzeroMagnitude))
        let high = log1p(max(scale.high, scale.low + Float.leastNonzeroMagnitude))
        let denominator = max(high - low, Float.leastNonzeroMagnitude)

        for sourceY in 0..<histogram.height {
            for x in 0..<histogram.width {
                let sourceIndex = sourceY * histogram.width + x
                guard histogram.bins[sourceIndex] > 0 else { continue }
                let density = min(max(densities[sourceIndex], scale.low), scale.high)
                let normalized = (log1p(density) - low) / denominator
                let cooled = powf(normalized, densityCoolingGamma)
                let color = colorMap(cooled)
                paintSquare(
                    centerX: x,
                    centerY: histogram.height - 1 - sourceY,
                    color: color,
                    density: normalized,
                    width: histogram.width,
                    height: histogram.height,
                    pixels: &pixels,
                    paintedDensities: &paintedDensities
                )
            }
        }

        let providerData = Data(pixels) as CFData
        guard
            let provider = CGDataProvider(data: providerData),
            let image = CGImage(
                width: histogram.width,
                height: histogram.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: histogram.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return NSImage(size: NSSize(width: histogram.width, height: histogram.height))
        }

        return NSImage(cgImage: image, size: NSSize(width: histogram.width, height: histogram.height))
    }

    private static func paintSquare(
        centerX: Int,
        centerY: Int,
        color: (r: UInt8, g: UInt8, b: UInt8),
        density: Float,
        width: Int,
        height: Int,
        pixels: inout [UInt8],
        paintedDensities: inout [Float]
    ) {
        let xStart = min(max(0, centerX), max(0, width - 2))
        let yStart = min(max(0, centerY), max(0, height - 2))
        for y in yStart...min(height - 1, yStart + 1) {
            for x in xStart...min(width - 1, xStart + 1) {
                let pixelIndex = y * width + x
                guard density >= paintedDensities[pixelIndex] else { continue }
                paintedDensities[pixelIndex] = density
                let offset = pixelIndex * 4
                pixels[offset] = color.r
                pixels[offset + 1] = color.g
                pixels[offset + 2] = color.b
                pixels[offset + 3] = 255
            }
        }
    }

    private static func areaDensities(from histogram: Histogram2D) -> [Float] {
        let width = histogram.width
        let height = histogram.height
        let radius = max(3, min(width, height) / 160)
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

    private static func densityScale(for densities: [Float], occupiedBins: [UInt32]) -> (low: Float, high: Float) {
        var nonzero: [Float] = []
        nonzero.reserveCapacity(min(densities.count, 4096))
        for index in densities.indices where occupiedBins[index] > 0 {
            let density = densities[index]
            if density > 0, density.isFinite {
                nonzero.append(density)
            }
        }
        guard !nonzero.isEmpty else { return (0, 1) }
        nonzero.sort()

        let low = max(percentile(0.02, in: nonzero), Float.leastNonzeroMagnitude)
        let high = max(percentile(0.995, in: nonzero) * redDensityMultiplier, low + Float.leastNonzeroMagnitude)
        return (min(low, high), high)
    }

    private static func percentile(_ percentile: Float, in sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = max(0, min(1, percentile))
        let index = Int((Float(sortedValues.count - 1) * clamped).rounded(.toNearestOrAwayFromZero))
        return sortedValues[index]
    }

    private static func colorMap(_ value: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let t = max(0, min(1, value))
        let stops: [(Float, Float, Float, Float)] = [
            (0.00, 0.00, 0.05, 1.00),
            (0.38, 0.00, 0.90, 0.12),
            (0.68, 1.00, 0.92, 0.00),
            (1.00, 1.00, 0.00, 0.00)
        ]
        for index in 0..<(stops.count - 1) {
            let start = stops[index]
            let end = stops[index + 1]
            guard t >= start.0, t <= end.0 else { continue }
            let local = smoothstep(edge0: start.0, edge1: end.0, x: t)
            return (
                channel(start.1 + (end.1 - start.1) * local),
                channel(start.2 + (end.2 - start.2) * local),
                channel(start.3 + (end.3 - start.3) * local)
            )
        }
        return (255, 0, 0)
    }

    private static func channel(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, value * 255)))
    }

    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
