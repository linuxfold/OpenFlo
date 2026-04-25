import Foundation

public struct Histogram2D: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bins: [UInt32]
    public let maxBin: UInt32
    public let xRange: ClosedRange<Float>
    public let yRange: ClosedRange<Float>

    public init(width: Int, height: Int, bins: [UInt32], xRange: ClosedRange<Float>, yRange: ClosedRange<Float>) {
        precondition(width > 0 && height > 0, "Histogram dimensions must be positive")
        precondition(bins.count == width * height, "Bin count must match dimensions")
        self.width = width
        self.height = height
        self.bins = bins
        self.maxBin = bins.max() ?? 0
        self.xRange = xRange
        self.yRange = yRange
    }

    public subscript(x: Int, y: Int) -> UInt32 {
        bins[y * width + x]
    }

    public static func build(
        xValues: [Float],
        yValues: [Float],
        mask: EventMask? = nil,
        width: Int = 512,
        height: Int = 512,
        xRange: ClosedRange<Float>? = nil,
        yRange: ClosedRange<Float>? = nil
    ) -> Histogram2D {
        precondition(xValues.count == yValues.count, "X and Y arrays must have the same count")
        if let mask {
            precondition(mask.count == xValues.count, "Mask count must match values count")
        }

        let resolvedXRange = xRange ?? EventTable.range(values: xValues, mask: mask)
        let resolvedYRange = yRange ?? EventTable.range(values: yValues, mask: mask)
        let eventCount = xValues.count
        let binCount = width * height
        guard eventCount > 0 else {
            return Histogram2D(width: width, height: height, bins: Array(repeating: 0, count: binCount), xRange: resolvedXRange, yRange: resolvedYRange)
        }

        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, eventCount))
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        final class PartialStore: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [[UInt32]] = []

            func append(_ partial: [UInt32]) {
                lock.lock()
                storage.append(partial)
                lock.unlock()
            }

            func values() -> [[UInt32]] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
        }
        let partialStore = PartialStore()

        let xMin = resolvedXRange.lowerBound
        let yMin = resolvedYRange.lowerBound
        let xSpan = max(resolvedXRange.upperBound - resolvedXRange.lowerBound, Float.leastNonzeroMagnitude)
        let ySpan = max(resolvedYRange.upperBound - resolvedYRange.lowerBound, Float.leastNonzeroMagnitude)
        let maxXBin = Float(width - 1)
        let maxYBin = Float(height - 1)

        for worker in 0..<workers {
            let start = worker * eventCount / workers
            let end = (worker + 1) * eventCount / workers
            group.enter()
            queue.async {
                var local = Array(repeating: UInt32(0), count: binCount)
                for event in start..<end {
                    if let mask, !mask[event] {
                        continue
                    }

                    let xValue = xValues[event]
                    let yValue = yValues[event]
                    guard xValue.isFinite, yValue.isFinite else { continue }
                    guard xValue >= resolvedXRange.lowerBound, xValue <= resolvedXRange.upperBound else { continue }
                    guard yValue >= resolvedYRange.lowerBound, yValue <= resolvedYRange.upperBound else { continue }

                    let xBin = Int(((xValue - xMin) / xSpan * maxXBin).rounded(.down))
                    let yBin = Int(((yValue - yMin) / ySpan * maxYBin).rounded(.down))
                    local[yBin * width + xBin] &+= 1
                }

                partialStore.append(local)
                group.leave()
            }
        }

        group.wait()

        var bins = Array(repeating: UInt32(0), count: binCount)
        for partial in partialStore.values() {
            for index in bins.indices {
                bins[index] &+= partial[index]
            }
        }

        return Histogram2D(width: width, height: height, bins: bins, xRange: resolvedXRange, yRange: resolvedYRange)
    }
}
