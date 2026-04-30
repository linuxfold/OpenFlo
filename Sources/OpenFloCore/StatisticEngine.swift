import Foundation

public enum StatisticKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case count = "Count"
    case frequencyOfParent = "% Parent"
    case frequencyOfGrandparent = "% Grandparent"
    case frequencyOfPopulation = "% Of"
    case frequencyOfTotal = "% Total"
    case median = "Median"
    case mean = "Mean"
    case geometricMean = "Geometric Mean"
    case robustCV = "Robust CV"
    case robustSD = "Robust SD"
    case cv = "CV"
    case standardDeviation = "SD"
    case percentile = "Percentile"
    case mad = "MAD"
    case madPercent = "MADP"
    case mode = "Mode"

    public var id: String { rawValue }

    public var requiresChannel: Bool {
        switch self {
        case .count, .frequencyOfParent, .frequencyOfGrandparent, .frequencyOfPopulation, .frequencyOfTotal:
            return false
        case .median, .mean, .geometricMean, .robustCV, .robustSD, .cv, .standardDeviation, .percentile, .mad, .madPercent, .mode:
            return true
        }
    }

    public var requiresPercentile: Bool {
        self == .percentile
    }
}

public struct StatisticTransformSettings: Codable, Equatable, Sendable {
    public var transform: TransformKind
    public var minimum: Float?
    public var maximum: Float?
    public var cofactor: Float
    public var extraNegativeDecades: Float
    public var widthBasis: Float
    public var positiveDecades: Float

    public init(
        transform: TransformKind = .linear,
        minimum: Float? = nil,
        maximum: Float? = nil,
        cofactor: Float = 150,
        extraNegativeDecades: Float = 0,
        widthBasis: Float = 1,
        positiveDecades: Float = 4.5
    ) {
        self.transform = transform
        self.minimum = minimum
        self.maximum = maximum
        self.cofactor = cofactor
        self.extraNegativeDecades = extraNegativeDecades
        self.widthBasis = widthBasis
        self.positiveDecades = positiveDecades
    }

    public func apply(_ value: Float) -> Float {
        transform.apply(
            value,
            cofactor: cofactor,
            extraNegativeDecades: extraNegativeDecades,
            widthBasis: widthBasis,
            positiveDecades: positiveDecades
        )
    }

    public func inverse(_ graphValue: Float) -> Float? {
        transform.inverse(
            graphValue,
            cofactor: cofactor,
            extraNegativeDecades: extraNegativeDecades,
            widthBasis: widthBasis,
            positiveDecades: positiveDecades
        )
    }
}

public enum StatisticSpace: Codable, Equatable, Sendable {
    case exactScale
    case exactGraph(StatisticTransformSettings)
    case flowJoBinnedGraph(StatisticTransformSettings, bins: Int)
}

public struct PopulationReference: Codable, Equatable, Hashable, Sendable {
    public var id: UUID?
    public var pathNames: [String]
    public var siblingOrdinal: Int?

    public init(id: UUID? = nil, pathNames: [String] = [], siblingOrdinal: Int? = nil) {
        self.id = id
        self.pathNames = pathNames
        self.siblingOrdinal = siblingOrdinal
    }
}

public struct StatisticRequest: Codable, Equatable, Sendable {
    public var kind: StatisticKind
    public var channelName: String?
    public var percentile: Double?
    public var denominator: PopulationReference?
    public var space: StatisticSpace

    public init(
        kind: StatisticKind,
        channelName: String? = nil,
        percentile: Double? = nil,
        denominator: PopulationReference? = nil,
        space: StatisticSpace = .exactScale
    ) {
        self.kind = kind
        self.channelName = channelName
        self.percentile = percentile
        self.denominator = denominator
        self.space = space
    }
}

public enum StatValue: Equatable, Sendable {
    case number(Double)
    case missing
    case error(String)

    public var number: Double? {
        if case .number(let value) = self {
            value
        } else {
            nil
        }
    }
}

public enum StatisticEngine {
    public static func evaluate(
        request: StatisticRequest,
        table: EventTable,
        population: EventMask,
        parent: EventMask?,
        grandparent: EventMask?,
        denominator: EventMask? = nil,
        totalCount: Int,
        channelResolver: (String) -> Int?
    ) -> StatValue {
        guard population.count == table.rowCount else {
            return .error("Population mask does not match table row count")
        }

        switch request.kind {
        case .count:
            return .number(Double(population.selectedCount))
        case .frequencyOfParent:
            return frequency(population.selectedCount, over: parent?.selectedCount ?? totalCount)
        case .frequencyOfGrandparent:
            return frequency(population.selectedCount, over: grandparent?.selectedCount ?? totalCount)
        case .frequencyOfPopulation:
            guard let denominator else { return .missing }
            return frequency(population.selectedCount, over: denominator.selectedCount)
        case .frequencyOfTotal:
            return frequency(population.selectedCount, over: totalCount)
        case .median, .mean, .geometricMean, .robustCV, .robustSD, .cv, .standardDeviation, .percentile, .mad, .madPercent, .mode:
            guard let channelName = request.channelName, let channelIndex = channelResolver(channelName) else {
                return .missing
            }
            return evaluateChannelStatistic(
                request: request,
                values: table.column(channelIndex),
                mask: population
            )
        }
    }

    public static func evaluateChannelStatistic(
        request: StatisticRequest,
        values: [Float],
        mask: EventMask
    ) -> StatValue {
        guard mask.count == values.count else {
            return .error("Mask does not match value count")
        }

        let selected = selectedFiniteValues(values, mask: mask, space: request.space)
        guard !selected.isEmpty else { return .missing }

        switch request.kind {
        case .median:
            return .number(percentile(sorted: selected.sorted(), percent: 50))
        case .mean:
            return .number(mean(selected))
        case .geometricMean:
            return geometricMean(selected)
        case .robustCV:
            let sorted = selected.sorted()
            let median = percentile(sorted: sorted, percent: 50)
            guard median != 0, median.isFinite else { return .missing }
            let p8413 = percentile(sorted: sorted, percent: 84.13)
            let p1587 = percentile(sorted: sorted, percent: 15.87)
            return .number(100 * 0.5 * (p8413 - p1587) / median)
        case .robustSD:
            let sorted = selected.sorted()
            let p8413 = percentile(sorted: sorted, percent: 84.13)
            let p1587 = percentile(sorted: sorted, percent: 15.87)
            return .number((p8413 - p1587) / 2)
        case .cv:
            let average = mean(selected)
            guard average != 0, average.isFinite else { return .missing }
            return .number(100 * standardDeviation(selected) / average)
        case .standardDeviation:
            return .number(standardDeviation(selected))
        case .percentile:
            guard let percent = request.percentile, percent.isFinite else { return .missing }
            return .number(percentile(sorted: selected.sorted(), percent: percent))
        case .mad:
            let sorted = selected.sorted()
            let medianValue = percentile(sorted: sorted, percent: 50)
            let deviations = selected.map { abs($0 - medianValue) }.sorted()
            return .number(percentile(sorted: deviations, percent: 50))
        case .madPercent:
            let sorted = selected.sorted()
            let medianValue = percentile(sorted: sorted, percent: 50)
            guard medianValue != 0, medianValue.isFinite else { return .missing }
            let deviations = selected.map { abs($0 - medianValue) }.sorted()
            let mad = percentile(sorted: deviations, percent: 50)
            return .number(100 * mad / medianValue)
        case .mode:
            return .number(mode(selected))
        case .count, .frequencyOfParent, .frequencyOfGrandparent, .frequencyOfPopulation, .frequencyOfTotal:
            return .missing
        }
    }

    private static func frequency(_ numerator: Int, over denominator: Int) -> StatValue {
        guard denominator > 0 else { return .missing }
        return .number(Double(numerator) / Double(denominator) * 100)
    }

    private static func selectedFiniteValues(_ values: [Float], mask: EventMask, space: StatisticSpace) -> [Double] {
        var selected: [Double] = []
        selected.reserveCapacity(mask.selectedCount)

        switch space {
        case .exactScale:
            for index in values.indices where mask[index] {
                let value = values[index]
                if value.isFinite {
                    selected.append(Double(value))
                }
            }
        case .exactGraph(let settings):
            for index in values.indices where mask[index] {
                let value = settings.apply(values[index])
                if value.isFinite {
                    selected.append(Double(value))
                }
            }
        case .flowJoBinnedGraph(let settings, let bins):
            selected = binnedGraphValues(values, mask: mask, settings: settings, bins: max(1, bins))
        }

        return selected
    }

    private static func binnedGraphValues(
        _ values: [Float],
        mask: EventMask,
        settings: StatisticTransformSettings,
        bins: Int
    ) -> [Double] {
        var transformed: [Float] = []
        transformed.reserveCapacity(mask.selectedCount)
        for index in values.indices where mask[index] {
            let value = settings.apply(values[index])
            if value.isFinite {
                transformed.append(value)
            }
        }
        guard !transformed.isEmpty else { return [] }

        let lower = settings.minimum ?? transformed.min() ?? 0
        let upper = settings.maximum ?? transformed.max() ?? 1
        guard lower.isFinite, upper.isFinite, upper > lower else {
            return transformed.map(Double.init)
        }

        let width = (upper - lower) / Float(bins)
        guard width > 0, width.isFinite else {
            return transformed.map(Double.init)
        }

        return transformed.map { value in
            let clamped = min(max(value, lower), upper)
            let rawIndex = Int(((clamped - lower) / width).rounded(.down))
            let binIndex = min(max(rawIndex, 0), bins - 1)
            let graphCenter = lower + (Float(binIndex) + 0.5) * width
            return Double(settings.inverse(graphCenter) ?? graphCenter)
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        var sum = 0.0
        var correction = 0.0
        for value in values {
            let y = value - correction
            let t = sum + y
            correction = (t - sum) - y
            sum = t
        }
        return sum / Double(values.count)
    }

    private static func geometricMean(_ values: [Double]) -> StatValue {
        let positives = values.filter { $0 > 0 && $0.isFinite }
        guard !positives.isEmpty else { return .missing }
        let logMean = positives.reduce(0) { $0 + log($1) } / Double(positives.count)
        return .number(exp(logMean))
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        var count = 0.0
        var mean = 0.0
        var m2 = 0.0
        for value in values {
            count += 1
            let delta = value - mean
            mean += delta / count
            let delta2 = value - mean
            m2 += delta * delta2
        }
        return sqrt(m2 / count)
    }

    private static func percentile(sorted values: [Double], percent: Double) -> Double {
        guard !values.isEmpty else { return .nan }
        let clamped = min(max(percent, 0), 100)
        guard values.count > 1 else { return values[0] }
        let position = (clamped / 100) * Double(values.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return values[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return values[lowerIndex] + (values[upperIndex] - values[lowerIndex]) * fraction
    }

    private static func mode(_ values: [Double]) -> Double {
        guard values.count > 1 else { return values[0] }
        let sorted = values.sorted()
        if sorted.allSatisfy({ $0.rounded() == $0 }) {
            var bestValue = sorted[0]
            var bestCount = 1
            var currentValue = sorted[0]
            var currentCount = 1
            for value in sorted.dropFirst() {
                if value == currentValue {
                    currentCount += 1
                } else {
                    if currentCount > bestCount {
                        bestCount = currentCount
                        bestValue = currentValue
                    }
                    currentValue = value
                    currentCount = 1
                }
            }
            if currentCount > bestCount {
                bestValue = currentValue
            }
            return bestValue
        }

        let binCount = min(512, max(16, Int(sqrt(Double(values.count)))))
        guard let minimum = sorted.first, let maximum = sorted.last, minimum < maximum else {
            return sorted[0]
        }
        let width = (maximum - minimum) / Double(binCount)
        guard width > 0, width.isFinite else { return sorted[0] }

        var counts = Array(repeating: 0, count: binCount)
        for value in sorted {
            let rawIndex = Int(((value - minimum) / width).rounded(.down))
            counts[min(max(rawIndex, 0), binCount - 1)] += 1
        }

        guard let bestIndex = counts.indices.max(by: { counts[$0] < counts[$1] }) else {
            return sorted[0]
        }
        return minimum + (Double(bestIndex) + 0.5) * width
    }
}
