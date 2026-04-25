import AppKit
import CoreGraphics
import Foundation
import OpenFloCore

enum HeatmapRenderer {
    static func image(from histogram: Histogram2D) -> NSImage {
        var pixels = Array(repeating: UInt8(0), count: histogram.width * histogram.height * 4)
        let densities = areaDensities(from: histogram)
        let scale = densityScale(for: densities)
        let denominator = log1p(max(scale.high - scale.floor, 1))

        for y in 0..<histogram.height {
            for x in 0..<histogram.width {
                let sourceY = histogram.height - 1 - y
                let density = densities[sourceY * histogram.width + x]
                let color: (r: UInt8, g: UInt8, b: UInt8)
                if density <= scale.floor {
                    color = (255, 255, 255)
                } else {
                    let normalized = log1p(min(density, scale.high) - scale.floor) / denominator
                    color = colorMap(normalized)
                }
                let offset = (y * histogram.width + x) * 4
                pixels[offset] = color.r
                pixels[offset + 1] = color.g
                pixels[offset + 2] = color.b
                pixels[offset + 3] = 255
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
                densities[y * width + x] = Float(max(areaCount, 0))
            }
        }

        return densities
    }

    private static func densityScale(for densities: [Float]) -> (floor: Float, high: Float) {
        var nonzero = densities.filter { $0 > 0 && $0.isFinite }
        guard !nonzero.isEmpty else { return (1, 1) }
        nonzero.sort()

        let high = max(percentile(0.99, in: nonzero), 1)
        let floor = max(2, high * 0.004)
        return (min(floor, high - 1), high)
    }

    private static func percentile(_ percentile: Float, in sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = max(0, min(1, percentile))
        let index = Int((Float(sortedValues.count - 1) * clamped).rounded(.toNearestOrAwayFromZero))
        return sortedValues[index]
    }

    private static func colorMap(_ value: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let t = max(0, min(1, value))
        let heat = smoothstep(edge0: 0.08, edge1: 1.0, x: t)
        let r = 1.0
        let g = 1.0 - 0.92 * heat
        let b = 1.0 - 0.96 * heat
        return (
            UInt8(max(0, min(255, r * 255))),
            UInt8(max(0, min(255, g * 255))),
            UInt8(max(0, min(255, b * 255)))
        )
    }

    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
