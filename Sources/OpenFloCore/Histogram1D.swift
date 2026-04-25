import Foundation

public struct Histogram1D: Equatable, Sendable {
    public let width: Int
    public let bins: [UInt32]
    public let maxBin: UInt32
    public let xRange: ClosedRange<Float>

    public init(width: Int, bins: [UInt32], xRange: ClosedRange<Float>) {
        precondition(width > 0, "Histogram width must be positive")
        precondition(bins.count == width, "Bin count must match width")
        self.width = width
        self.bins = bins
        self.maxBin = bins.max() ?? 0
        self.xRange = xRange
    }

    public subscript(x: Int) -> UInt32 {
        bins[x]
    }

    public static func build(
        values: [Float],
        mask: EventMask? = nil,
        width: Int = 640,
        xRange: ClosedRange<Float>? = nil
    ) -> Histogram1D {
        if let mask {
            precondition(mask.count == values.count, "Mask count must match values count")
        }
        let resolvedRange = xRange ?? EventTable.range(values: values, mask: mask)
        let xMin = resolvedRange.lowerBound
        let xSpan = max(resolvedRange.upperBound - resolvedRange.lowerBound, Float.leastNonzeroMagnitude)
        let maxBin = Float(width - 1)
        var bins = Array(repeating: UInt32(0), count: width)

        for index in values.indices {
            if let mask, !mask[index] {
                continue
            }
            let value = values[index]
            guard value.isFinite, value >= resolvedRange.lowerBound, value <= resolvedRange.upperBound else { continue }
            let bin = Int(((value - xMin) / xSpan * maxBin).rounded(.down))
            bins[bin] &+= 1
        }

        return Histogram1D(width: width, bins: bins, xRange: resolvedRange)
    }
}
