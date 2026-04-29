import Foundation

public enum SingleCellDataError: Error, LocalizedError, Sendable {
    case unsupportedFileType(String)
    case malformedDelimitedMatrix
    case missingMatrixMarketCompanion(String)
    case malformedMatrixMarket
    case emptyMatrix

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let type):
            return "Unsupported single-cell file type: \(type)."
        case .malformedDelimitedMatrix:
            return "The single-cell delimited matrix is malformed."
        case .missingMatrixMarketCompanion(let name):
            return "The 10x Matrix Market dataset is missing \(name)."
        case .malformedMatrixMarket:
            return "The Matrix Market file is malformed."
        case .emptyMatrix:
            return "The single-cell matrix is empty."
        }
    }
}

public enum SingleCellMatrixOrientation: String, Equatable, Sendable {
    case genesByCells
    case cellsByGenes
}

public struct SingleCellFile: Sendable {
    public let table: EventTable
    public let cellIDs: [String]
    public let orientation: SingleCellMatrixOrientation
    public let sourceDescription: String
}

public enum SingleCellDataParser {
    public static func load(url: URL) throws -> SingleCellFile {
        if try isDirectory(url) {
            guard let matrixURL = matrixMarketURL(in: url) else {
                throw SingleCellDataError.missingMatrixMarketCompanion("matrix.mtx")
            }
            return try parseMatrixMarket(url: matrixURL)
        }

        switch url.pathExtension.lowercased() {
        case "csv", "tsv", "txt":
            return try parseDelimited(url: url)
        case "mtx":
            return try parseMatrixMarket(url: url)
        default:
            throw SingleCellDataError.unsupportedFileType(url.pathExtension)
        }
    }

    public static func parseDelimited(url: URL) throws -> SingleCellFile {
        let text = try String(contentsOf: url, encoding: .utf8)
        let preferredDelimiter: Character? = url.pathExtension.lowercased() == "csv" ? "," : nil
        let delimiter = DelimitedText.detectDelimiter(in: text, preferred: preferredDelimiter)
        let rows = try DelimitedText.parseRows(text, delimiter: delimiter)
        return try parseDelimited(rows: rows, sourceDescription: url.lastPathComponent)
    }

    public static func parseDelimited(rows: [[String]], sourceDescription: String = "single-cell matrix") throws -> SingleCellFile {
        guard rows.count >= 2, rows[0].count >= 2 else {
            throw SingleCellDataError.malformedDelimitedMatrix
        }

        let orientation = inferOrientation(header: rows[0], rowCount: rows.count - 1)
        switch orientation {
        case .genesByCells:
            return try parseGenesByCells(rows: rows, sourceDescription: sourceDescription)
        case .cellsByGenes:
            return try parseCellsByGenes(rows: rows, sourceDescription: sourceDescription)
        }
    }

    public static func parseMatrixMarket(url: URL, normalizeCounts: Bool = true) throws -> SingleCellFile {
        let featureURL = try companionURL(nextTo: url, candidates: ["features.tsv", "genes.tsv"], missingName: "features.tsv or genes.tsv")
        let barcodeURL = try companionURL(nextTo: url, candidates: ["barcodes.tsv"], missingName: "barcodes.tsv")
        let features = try readFeatureNames(url: featureURL)
        let barcodes = try readSingleColumn(url: barcodeURL)
        guard !features.isEmpty, !barcodes.isEmpty else { throw SingleCellDataError.emptyMatrix }

        let text = try String(contentsOf: url, encoding: .utf8)
        var dataLines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%") }

        guard !dataLines.isEmpty else { throw SingleCellDataError.malformedMatrixMarket }
        let dimensionParts = dataLines.removeFirst().split(whereSeparator: \.isWhitespace)
        guard dimensionParts.count >= 3,
              let geneCount = Int(dimensionParts[0]),
              let cellCount = Int(dimensionParts[1]),
              geneCount == features.count,
              cellCount == barcodes.count else {
            throw SingleCellDataError.malformedMatrixMarket
        }

        var columns = Array(repeating: Array(repeating: Float(0), count: cellCount), count: geneCount)
        var cellTotals = Array(repeating: Float(0), count: cellCount)
        for line in dataLines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3,
                  let oneBasedGene = Int(parts[0]),
                  let oneBasedCell = Int(parts[1]),
                  let value = Float(parts[2]),
                  oneBasedGene >= 1,
                  oneBasedGene <= geneCount,
                  oneBasedCell >= 1,
                  oneBasedCell <= cellCount else {
                throw SingleCellDataError.malformedMatrixMarket
            }
            let geneIndex = oneBasedGene - 1
            let cellIndex = oneBasedCell - 1
            columns[geneIndex][cellIndex] = value
            cellTotals[cellIndex] += value
        }

        if normalizeCounts {
            for geneIndex in columns.indices {
                for cellIndex in columns[geneIndex].indices {
                    let total = cellTotals[cellIndex]
                    guard total > 0 else { continue }
                    columns[geneIndex][cellIndex] = log1p(columns[geneIndex][cellIndex] * 10_000 / total)
                }
            }
        }

        let channels = makeChannels(featureNames: features)
        return SingleCellFile(
            table: EventTable(channels: channels, columns: columns),
            cellIDs: barcodes,
            orientation: .genesByCells,
            sourceDescription: normalizeCounts ? "10x Matrix Market LogCP10K" : "10x Matrix Market"
        )
    }

    private static func parseGenesByCells(rows: [[String]], sourceDescription: String) throws -> SingleCellFile {
        let cellIDs = rows[0].dropFirst().enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Cell \(index + 1)" : trimmed
        }
        guard !cellIDs.isEmpty else { throw SingleCellDataError.malformedDelimitedMatrix }

        var featureNames: [String] = []
        var columns: [[Float]] = []
        for row in rows.dropFirst() {
            guard let rawFeatureName = row.first else { continue }
            let featureName = rawFeatureName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !featureName.isEmpty else { continue }
            featureNames.append(featureName)
            columns.append((0..<cellIDs.count).map { value(row, at: $0 + 1) })
        }
        guard !columns.isEmpty else { throw SingleCellDataError.emptyMatrix }

        return SingleCellFile(
            table: EventTable(channels: makeChannels(featureNames: featureNames), columns: columns),
            cellIDs: cellIDs,
            orientation: .genesByCells,
            sourceDescription: sourceDescription
        )
    }

    private static func parseCellsByGenes(rows: [[String]], sourceDescription: String) throws -> SingleCellFile {
        let featureNames = rows[0].dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !featureNames.isEmpty else { throw SingleCellDataError.malformedDelimitedMatrix }

        var cellIDs: [String] = []
        var columns = Array(repeating: [Float](), count: featureNames.count)
        for row in rows.dropFirst() {
            guard let rawCellID = row.first else { continue }
            let cellID = rawCellID.trimmingCharacters(in: .whitespacesAndNewlines)
            cellIDs.append(cellID.isEmpty ? "Cell \(cellIDs.count + 1)" : cellID)
            for geneIndex in featureNames.indices {
                columns[geneIndex].append(value(row, at: geneIndex + 1))
            }
        }
        guard !cellIDs.isEmpty else { throw SingleCellDataError.emptyMatrix }

        return SingleCellFile(
            table: EventTable(channels: makeChannels(featureNames: featureNames), columns: columns),
            cellIDs: cellIDs,
            orientation: .cellsByGenes,
            sourceDescription: sourceDescription
        )
    }

    private static func inferOrientation(header: [String], rowCount: Int) -> SingleCellMatrixOrientation {
        let leadingHeader = normalizedLabel(header.first ?? "")
        let featureLabels = Set(["gene", "genes", "symbol", "genesymbol", "feature", "features"])
        let cellLabels = Set(["cell", "cells", "barcode", "barcodes", "cellid", "id"])
        if featureLabels.contains(leadingHeader) {
            return .genesByCells
        }
        if cellLabels.contains(leadingHeader) {
            return .cellsByGenes
        }

        let valueColumnCount = max(0, header.count - 1)
        return rowCount >= valueColumnCount ? .genesByCells : .cellsByGenes
    }

    private static func makeChannels(featureNames: [String]) -> [Channel] {
        var usedNames: [String: Int] = [:]
        return featureNames.enumerated().map { index, rawName in
            let displayName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = displayName.isEmpty ? "Gene \(index + 1)" : displayName
            let count = (usedNames[baseName] ?? 0) + 1
            usedNames[baseName] = count
            let uniqueName = count == 1 ? baseName : "\(baseName) #\(count)"
            return Channel(
                name: uniqueName,
                displayName: baseName,
                markerName: baseName,
                kind: .singleCellFeature,
                preferredTransform: .linear
            )
        }
    }

    private static func value(_ row: [String], at index: Int) -> Float {
        guard row.indices.contains(index) else { return 0 }
        let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return Float(trimmed) ?? 0
    }

    private static func normalizedLabel(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func readFeatureNames(url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .split(whereSeparator: \.isNewline)
            .map { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                if parts.count >= 2 {
                    return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func readSingleColumn(url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .split(whereSeparator: \.isNewline)
            .map { line in
                String(line.split(separator: "\t", omittingEmptySubsequences: false).first ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func companionURL(nextTo url: URL, candidates: [String], missingName: String) throws -> URL {
        for candidate in candidates {
            let sibling = url.deletingLastPathComponent().appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
        }
        throw SingleCellDataError.missingMatrixMarketCompanion(missingName)
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func matrixMarketURL(in directory: URL) -> URL? {
        let direct = directory.appendingPathComponent("matrix.mtx")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator where url.lastPathComponent == "matrix.mtx" {
            return url
        }
        return nil
    }
}
