import Foundation

public struct SparseMatrixEntry: Equatable, Sendable {
    public let geneIndex: Int
    public let value: Float

    public init(geneIndex: Int, value: Float) {
        self.geneIndex = geneIndex
        self.value = value
    }
}

public struct SingleCellSparseMatrix: Sendable {
    public let geneCount: Int
    public let cellCount: Int
    public let nonZeroCount: Int
    private let cells: [[SparseMatrixEntry]]

    public init(geneCount: Int, cellCount: Int, cells: [[SparseMatrixEntry]]) {
        precondition(geneCount >= 0, "Gene count cannot be negative")
        precondition(cellCount >= 0, "Cell count cannot be negative")
        precondition(cells.count == cellCount, "Sparse cell blocks must match the cell count")
        self.geneCount = geneCount
        self.cellCount = cellCount
        self.cells = cells
        self.nonZeroCount = cells.reduce(0) { $0 + $1.count }
    }

    public var denseValueCount: Int64 {
        Int64(geneCount) * Int64(cellCount)
    }

    public var estimatedDenseByteCount: Int64 {
        denseValueCount * Int64(MemoryLayout<Float>.stride)
    }

    public func entriesForCell(_ cellIndex: Int) -> [SparseMatrixEntry] {
        precondition(cellIndex >= 0 && cellIndex < cellCount, "Cell index out of bounds")
        return cells[cellIndex]
    }

    public func denseColumns() -> [[Float]] {
        var columns = Array(
            repeating: Array(repeating: Float(0), count: cellCount),
            count: geneCount
        )
        for cellIndex in cells.indices {
            for entry in cells[cellIndex] where entry.geneIndex >= 0 && entry.geneIndex < geneCount {
                columns[entry.geneIndex][cellIndex] = entry.value
            }
        }
        return columns
    }
}

public struct SingleCellMatrixFile: Sendable {
    public let matrix: SingleCellSparseMatrix
    public let channels: [Channel]
    public let cellIDs: [String]
    public let orientation: SingleCellMatrixOrientation
    public let sourceDescription: String

    public init(
        matrix: SingleCellSparseMatrix,
        channels: [Channel],
        cellIDs: [String],
        orientation: SingleCellMatrixOrientation,
        sourceDescription: String
    ) {
        precondition(channels.count == matrix.geneCount, "Feature channels must match sparse matrix genes")
        precondition(cellIDs.count == matrix.cellCount, "Cell IDs must match sparse matrix cells")
        self.matrix = matrix
        self.channels = channels
        self.cellIDs = cellIDs
        self.orientation = orientation
        self.sourceDescription = sourceDescription
    }

    public func materializedTable() -> EventTable {
        EventTable(channels: channels, columns: matrix.denseColumns())
    }
}
