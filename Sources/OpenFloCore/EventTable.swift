import Foundation

public struct Channel: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let bitWidth: Int?
    public let markerName: String?
    public let fluorochromeName: String?

    public init(
        name: String,
        displayName: String? = nil,
        bitWidth: Int? = nil,
        markerName: String? = nil,
        fluorochromeName: String? = nil
    ) {
        self.name = name
        self.bitWidth = bitWidth
        self.markerName = markerName
        self.fluorochromeName = fluorochromeName

        if let displayName {
            self.displayName = displayName
        } else if let markerName, let fluorochromeName {
            self.displayName = "\(markerName) (\(fluorochromeName))"
        } else if let markerName {
            self.displayName = markerName
        } else {
            self.displayName = name
        }
    }
}

public final class EventTable: @unchecked Sendable {
    public let channels: [Channel]
    public let rowCount: Int
    private let columns: [[Float]]

    public init(channels: [Channel], columns: [[Float]]) {
        precondition(!channels.isEmpty, "At least one channel is required")
        precondition(channels.count == columns.count, "Channel and column counts must match")
        let rowCount = columns.first?.count ?? 0
        precondition(columns.allSatisfy { $0.count == rowCount }, "Columns must have equal lengths")
        self.channels = channels
        self.columns = columns
        self.rowCount = rowCount
    }

    public var channelCount: Int {
        channels.count
    }

    public func column(_ index: Int) -> [Float] {
        precondition(index >= 0 && index < columns.count, "Channel index out of bounds")
        return columns[index]
    }

    public func value(event: Int, channel: Int) -> Float {
        precondition(event >= 0 && event < rowCount, "Event index out of bounds")
        precondition(channel >= 0 && channel < columns.count, "Channel index out of bounds")
        return columns[channel][event]
    }

    public func range(for channel: Int, mask: EventMask? = nil) -> ClosedRange<Float> {
        Self.range(values: columns[channel], mask: mask)
    }

    public func focusedRange(
        for channel: Int,
        mask: EventMask? = nil,
        lowerQuantile: Float = 0.125,
        upperQuantile: Float = 0.875,
        maxSamples: Int = 200_000
    ) -> ClosedRange<Float> {
        Self.focusedRange(
            values: columns[channel],
            mask: mask,
            lowerQuantile: lowerQuantile,
            upperQuantile: upperQuantile,
            maxSamples: maxSamples
        )
    }

    public static func range(values: [Float], mask: EventMask? = nil) -> ClosedRange<Float> {
        guard !values.isEmpty else { return 0...1 }
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var foundValue = false

        if let mask {
            guard mask.count == values.count else { return 0...1 }
            for index in values.indices where mask[index] {
                let value = values[index]
                guard value.isFinite else { continue }
                foundValue = true
                minimum = Swift.min(minimum, value)
                maximum = Swift.max(maximum, value)
            }
        } else {
            for value in values where value.isFinite {
                foundValue = true
                minimum = Swift.min(minimum, value)
                maximum = Swift.max(maximum, value)
            }
        }

        guard foundValue, minimum.isFinite, maximum.isFinite else { return 0...1 }
        if minimum == maximum {
            let pad = max(abs(minimum) * 0.05, 1)
            return (minimum - pad)...(maximum + pad)
        }
        let pad = max((maximum - minimum) * 0.025, .leastNonzeroMagnitude)
        return (minimum - pad)...(maximum + pad)
    }

    public static func focusedRange(
        values: [Float],
        mask: EventMask? = nil,
        lowerQuantile: Float = 0.125,
        upperQuantile: Float = 0.875,
        maxSamples: Int = 200_000
    ) -> ClosedRange<Float> {
        precondition(lowerQuantile >= 0 && lowerQuantile < upperQuantile, "Lower quantile must be below upper quantile")
        precondition(upperQuantile <= 1, "Upper quantile cannot exceed one")
        if let mask {
            guard mask.count == values.count else { return 0...1 }
        }

        let selectedCount = mask?.selectedCount ?? values.count
        guard selectedCount > 0 else { return range(values: values, mask: mask) }

        let sampleStride = max(1, selectedCount / max(1, maxSamples))
        var samples: [Float] = []
        samples.reserveCapacity(min(selectedCount, maxSamples))

        if let mask {
            var selectedIndex = 0
            for index in values.indices where mask[index] {
                defer { selectedIndex += 1 }
                guard selectedIndex % sampleStride == 0 else { continue }
                let value = values[index]
                if value.isFinite {
                    samples.append(value)
                }
            }
        } else {
            for index in stride(from: values.startIndex, to: values.endIndex, by: sampleStride) {
                let value = values[index]
                if value.isFinite {
                    samples.append(value)
                }
            }
        }

        guard !samples.isEmpty else { return 0...1 }
        samples.sort()
        let lowerIndex = quantileIndex(lowerQuantile, count: samples.count)
        let upperIndex = quantileIndex(upperQuantile, count: samples.count)
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]

        guard lower.isFinite, upper.isFinite else { return range(values: values, mask: mask) }
        if lower == upper {
            let pad = max(abs(lower) * 0.05, 1)
            return (lower - pad)...(upper + pad)
        }

        let pad = max((upper - lower) * 0.05, .leastNonzeroMagnitude)
        return (lower - pad)...(upper + pad)
    }

    private static func quantileIndex(_ quantile: Float, count: Int) -> Int {
        let position = Float(max(0, count - 1)) * quantile
        return min(max(Int(position.rounded(.toNearestOrAwayFromZero)), 0), count - 1)
    }

}
