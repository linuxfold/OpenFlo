import Foundation

public enum SeqtometryScoringError: Error, LocalizedError, Sendable {
    case noFeatureChannels
    case noVariableFeatureChannels
    case noSignatures

    public var errorDescription: String? {
        switch self {
        case .noFeatureChannels:
            return "No single-cell feature channels are available for Seqtometry scoring."
        case .noVariableFeatureChannels:
            return "No variable single-cell feature channels are available for Seqtometry scoring."
        case .noSignatures:
            return "No Seqtometry signatures were provided."
        }
    }
}

public struct SeqtometryScoringProgress: Equatable, Sendable {
    public let completedCells: Int
    public let totalCells: Int
    public let signatureCount: Int

    public var fractionCompleted: Double {
        guard totalCells > 0 else { return 1 }
        return min(max(Double(completedCells) / Double(totalCells), 0), 1)
    }
}

public enum SeqtometryScorer {
    public static func tableByAppendingScores(
        to table: EventTable,
        signatures: [SeqtometrySignature],
        minMaxScale: Bool = true,
        progress: ((SeqtometryScoringProgress) -> Void)? = nil
    ) throws -> EventTable {
        let scored = try scoreColumns(
            table: table,
            signatures: signatures,
            minMaxScale: minMaxScale,
            progress: progress
        )
        return table.replacingOrAppending(
            channels: scored.map(\.channel),
            columns: scored.map(\.values)
        )
    }

    public static func scoreColumns(
        table: EventTable,
        signatures: [SeqtometrySignature],
        minMaxScale: Bool = true,
        progress: ((SeqtometryScoringProgress) -> Void)? = nil
    ) throws -> [(channel: Channel, values: [Float])] {
        guard !signatures.isEmpty else { throw SeqtometryScoringError.noSignatures }

        let featureSourceIndices = table.channels.indices.filter { index in
            table.channels[index].kind != .seqtometrySignature
        }
        guard !featureSourceIndices.isEmpty else { throw SeqtometryScoringError.noFeatureChannels }

        let sourceColumns = featureSourceIndices.map { table.column($0) }
        let stats = sourceColumns.map(Self.meanAndStandardDeviation)
        let activeOrdinals = stats.indices.filter { stats[$0].standardDeviation > 0 }
        guard !activeOrdinals.isEmpty else { throw SeqtometryScoringError.noVariableFeatureChannels }

        let activeColumns = activeOrdinals.map { sourceColumns[$0] }
        let means = activeOrdinals.map { stats[$0].mean }
        let standardDeviations = activeOrdinals.map { stats[$0].standardDeviation }
        let geneIndex = buildGeneIndex(table: table, sourceIndices: featureSourceIndices, activeOrdinals: activeOrdinals)
        let signatureGeneIndices = signatures.map { signature in
            matchedGeneIndices(for: signature, in: geneIndex)
        }

        var scoreColumns = Array(
            repeating: Array(repeating: Float(0), count: table.rowCount),
            count: signatures.count
        )

        progress?(SeqtometryScoringProgress(completedCells: 0, totalCells: table.rowCount, signatureCount: signatures.count))
        let progressStep = max(1, table.rowCount / 100)
        for cellIndex in 0..<table.rowCount {
            let ranks = centeredGeneRanks(
                activeColumns: activeColumns,
                means: means,
                standardDeviations: standardDeviations,
                cellIndex: cellIndex
            )
            for signatureIndex in signatures.indices {
                scoreColumns[signatureIndex][cellIndex] = weightedKuiperScore(
                    geneRanks: ranks.ranks,
                    signatureGeneIndices: signatureGeneIndices[signatureIndex],
                    center: ranks.center,
                    startIndex: ranks.startIndex
                )
            }
            let completedCells = cellIndex + 1
            if completedCells == table.rowCount || completedCells.isMultiple(of: progressStep) {
                progress?(
                    SeqtometryScoringProgress(
                        completedCells: completedCells,
                        totalCells: table.rowCount,
                        signatureCount: signatures.count
                    )
                )
            }
        }

        if minMaxScale {
            scoreColumns = scoreColumns.map(minMaxScaled)
        }

        return signatures.indices.map { index in
            (
                channel: Channel(
                    name: signatures[index].name,
                    displayName: signatures[index].name,
                    markerName: signatures[index].name,
                    kind: .seqtometrySignature,
                    preferredTransform: .linear,
                    signatureGenes: signatures[index].genes
                ),
                values: scoreColumns[index]
            )
        }
    }

    private static func meanAndStandardDeviation(_ values: [Float]) -> (mean: Float, standardDeviation: Float) {
        guard !values.isEmpty else { return (0, 0) }
        let finiteValues = values.filter(\.isFinite)
        guard !finiteValues.isEmpty else { return (0, 0) }
        let mean = finiteValues.reduce(Float(0), +) / Float(finiteValues.count)
        guard finiteValues.count > 1 else { return (mean, 0) }
        let sumOfSquares = finiteValues.reduce(Float(0)) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        }
        return (mean, sqrt(sumOfSquares / Float(finiteValues.count - 1)))
    }

    private static func buildGeneIndex(
        table: EventTable,
        sourceIndices: [Int],
        activeOrdinals: [Int]
    ) -> [String: [Int]] {
        var output: [String: [Int]] = [:]
        for activeIndex in activeOrdinals.indices {
            let sourceIndex = sourceIndices[activeOrdinals[activeIndex]]
            let channel = table.channels[sourceIndex]
            for name in [channel.name, channel.displayName, channel.markerName].compactMap({ $0 }) {
                let key = normalizedGeneName(name)
                guard !key.isEmpty else { continue }
                output[key, default: []].append(activeIndex)
            }
        }
        return output
    }

    private static func matchedGeneIndices(
        for signature: SeqtometrySignature,
        in geneIndex: [String: [Int]]
    ) -> [Int] {
        var output: [Int] = []
        var seen: Set<Int> = []
        for gene in signature.genes {
            let key = normalizedGeneName(gene)
            guard let matches = geneIndex[key] else { continue }
            for match in matches where !seen.contains(match) {
                seen.insert(match)
                output.append(match)
            }
        }
        return output
    }

    private static func centeredGeneRanks(
        activeColumns: [[Float]],
        means: [Float],
        standardDeviations: [Float],
        cellIndex: Int
    ) -> (ranks: [Int], center: Int, startIndex: Int) {
        let geneCount = activeColumns.count
        let sortedOrdinals = activeColumns.indices.sorted { left, right in
            let leftZ = zScore(activeColumns[left][cellIndex], mean: means[left], standardDeviation: standardDeviations[left])
            let rightZ = zScore(activeColumns[right][cellIndex], mean: means[right], standardDeviation: standardDeviations[right])
            if leftZ == rightZ {
                return left < right
            }
            return leftZ < rightZ
        }

        let baseCenter = geneCount / 2
        let center: Int
        let startIndex: Int
        if geneCount.isMultiple(of: 2) {
            center = baseCenter
            startIndex = center + 1
        } else {
            center = baseCenter + 1
            startIndex = center
        }

        var ranks = Array(repeating: 0, count: geneCount)
        for sortedIndex in sortedOrdinals.indices {
            ranks[sortedOrdinals[sortedIndex]] = sortedIndex + 1 - center
        }
        return (ranks, center, startIndex)
    }

    private static func zScore(_ value: Float, mean: Float, standardDeviation: Float) -> Float {
        guard value.isFinite else { return -.infinity }
        return (value - mean) / standardDeviation
    }

    private static func weightedKuiperScore(
        geneRanks: [Int],
        signatureGeneIndices: [Int],
        center: Int,
        startIndex: Int
    ) -> Float {
        guard !signatureGeneIndices.isEmpty else { return -1 }
        let nonSignatureCount = geneRanks.count - signatureGeneIndices.count
        guard nonSignatureCount > 0 else { return 1 }

        let decrementNorm = 1 / Double(nonSignatureCount)
        var signatureRanks: [Int] = []
        signatureRanks.reserveCapacity(signatureGeneIndices.count)
        var incrementDenominator = 0
        for geneIndex in signatureGeneIndices {
            let rank = geneRanks[geneIndex]
            incrementDenominator += abs(rank)
            signatureRanks.append(rank)
        }
        guard incrementDenominator > 0 else { return 0 }

        signatureRanks.sort(by: >)
        var currentIndex = startIndex
        var minimum = 0.0
        var maximum = 0.0
        var runningSum = 0.0

        for rank in signatureRanks {
            let stride = currentIndex - rank - 1
            currentIndex = rank
            runningSum -= Double(stride) * decrementNorm
            minimum = min(minimum, runningSum)
            runningSum += Double(abs(rank)) / Double(incrementDenominator)
            maximum = max(maximum, runningSum)
        }

        let finalStride = currentIndex + center - 1
        runningSum -= Double(finalStride) * decrementNorm
        minimum = min(minimum, runningSum)
        return Float(minimum + maximum)
    }

    private static func minMaxScaled(_ values: [Float]) -> [Float] {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(),
              let maximum = finiteValues.max(),
              maximum > minimum else {
            return Array(repeating: 0, count: values.count)
        }
        let span = maximum - minimum
        return values.map { value in
            guard value.isFinite else { return 0 }
            return (value - minimum) / span
        }
    }

    private static func normalizedGeneName(_ name: String) -> String {
        name.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }
}
