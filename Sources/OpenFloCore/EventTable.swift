import Foundation

public struct Channel: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let bitWidth: Int?

    public init(name: String, displayName: String? = nil, bitWidth: Int? = nil) {
        self.name = name
        self.displayName = displayName ?? name
        self.bitWidth = bitWidth
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

    public static func synthetic(events: Int = 1_000_000) -> EventTable {
        let channels = [
            Channel(name: "FSC-A"),
            Channel(name: "SSC-A"),
            Channel(name: "CD3"),
            Channel(name: "CD4"),
            Channel(name: "CD8"),
            Channel(name: "CD19"),
            Channel(name: "Time")
        ]
        var columns = Array(repeating: Array(repeating: Float(0), count: events), count: channels.count)
        var rng = SeededGenerator(seed: 0x4f70656e466c6f)

        for event in 0..<events {
            let populationRoll = rng.unitFloat()
            let population: Int
            if populationRoll < 0.55 {
                population = 0
            } else if populationRoll < 0.85 {
                population = 1
            } else {
                population = 2
            }

            let fscCenter: Float = [82_000, 145_000, 210_000][population]
            let sscCenter: Float = [45_000, 95_000, 150_000][population]
            columns[0][event] = max(0, fscCenter + 18_000 * rng.normalFloat())
            columns[1][event] = max(0, sscCenter + 15_000 * rng.normalFloat())
            columns[2][event] = markerValue(active: population != 2, rng: &rng)
            columns[3][event] = markerValue(active: population == 0, rng: &rng)
            columns[4][event] = markerValue(active: population == 1, rng: &rng)
            columns[5][event] = markerValue(active: population == 2, rng: &rng)
            columns[6][event] = Float(event)
        }

        return EventTable(channels: channels, columns: columns)
    }

    private static func markerValue(active: Bool, rng: inout SeededGenerator) -> Float {
        let center: Float = active ? 55_000 : 1_500
        let spread: Float = active ? 16_000 : 750
        return max(0, center + spread * rng.normalFloat())
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unitFloat() -> Float {
        let value = next() >> 40
        return Float(value) / Float(1 << 24)
    }

    mutating func normalFloat() -> Float {
        let u1 = max(unitFloat(), Float.leastNonzeroMagnitude)
        let u2 = unitFloat()
        let radius = sqrt(-2 * log(u1))
        let theta = 2 * Float.pi * u2
        return radius * cos(theta)
    }
}
