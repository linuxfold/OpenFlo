import Foundation

public enum CompensationError: Error, LocalizedError, Equatable, Sendable {
    case nonSquareMatrix
    case parameterCountMismatch
    case missingChannel(String)
    case singularMatrix
    case nonFiniteValue

    public var errorDescription: String? {
        switch self {
        case .nonSquareMatrix:
            return "The compensation matrix must be square."
        case .parameterCountMismatch:
            return "The compensation matrix size does not match its parameter list."
        case .missingChannel(let name):
            return "The sample is missing compensation channel \(name)."
        case .singularMatrix:
            return "The compensation matrix cannot be inverted."
        case .nonFiniteValue:
            return "The compensation matrix contains a non-finite value."
        }
    }
}

public enum CompensationEngine {
    public static func apply(_ matrix: CompensationMatrix, to table: EventTable) throws -> EventTable {
        let indices = try matrix.parameters.map { name in
            guard let index = table.channels.firstIndex(where: { $0.name == name }) else {
                throw CompensationError.missingChannel(name)
            }
            return index
        }

        let spill = try spilloverFractions(from: matrix)
        let inverse = try invert(spill)
        let rowCount = table.rowCount
        let count = indices.count
        let inputColumns = indices.map { table.column($0).map(Double.init) }
        var outputColumns = Array(
            repeating: Array(repeating: Float(0), count: rowCount),
            count: count
        )

        for event in 0..<rowCount {
            for target in 0..<count {
                var value = 0.0
                for source in 0..<count {
                    value += inputColumns[source][event] * inverse[source][target]
                }
                guard value.isFinite else { throw CompensationError.nonFiniteValue }
                outputColumns[target][event] = Float(value)
            }
        }

        let compensatedChannels = indices.map { table.channels[$0] }
        return table.replacingOrAppending(channels: compensatedChannels, columns: outputColumns)
    }

    public static func spilloverFractions(from matrix: CompensationMatrix) throws -> [[Double]] {
        let count = matrix.parameters.count
        guard matrix.percent.count == count else { throw CompensationError.parameterCountMismatch }
        guard matrix.percent.allSatisfy({ $0.count == count }) else { throw CompensationError.nonSquareMatrix }

        return try matrix.percent.map { row in
            try row.map { value in
                guard value.isFinite else { throw CompensationError.nonFiniteValue }
                return value / 100.0
            }
        }
    }

    public static func invert(_ matrix: [[Double]]) throws -> [[Double]] {
        let count = matrix.count
        guard count > 0, matrix.allSatisfy({ $0.count == count }) else {
            throw CompensationError.nonSquareMatrix
        }

        var augmented = Array(
            repeating: Array(repeating: 0.0, count: count * 2),
            count: count
        )

        for row in 0..<count {
            for column in 0..<count {
                let value = matrix[row][column]
                guard value.isFinite else { throw CompensationError.nonFiniteValue }
                augmented[row][column] = value
            }
            augmented[row][count + row] = 1.0
        }

        for pivotColumn in 0..<count {
            var pivotRow = pivotColumn
            var pivotMagnitude = abs(augmented[pivotRow][pivotColumn])
            for candidate in (pivotColumn + 1)..<count {
                let magnitude = abs(augmented[candidate][pivotColumn])
                if magnitude > pivotMagnitude {
                    pivotRow = candidate
                    pivotMagnitude = magnitude
                }
            }

            guard pivotMagnitude > Double.ulpOfOne else {
                throw CompensationError.singularMatrix
            }

            if pivotRow != pivotColumn {
                augmented.swapAt(pivotRow, pivotColumn)
            }

            let pivot = augmented[pivotColumn][pivotColumn]
            for column in 0..<(count * 2) {
                augmented[pivotColumn][column] /= pivot
            }

            for row in 0..<count where row != pivotColumn {
                let factor = augmented[row][pivotColumn]
                guard factor != 0 else { continue }
                for column in 0..<(count * 2) {
                    augmented[row][column] -= factor * augmented[pivotColumn][column]
                }
            }
        }

        return augmented.map { row in
            Array(row[count..<(count * 2)])
        }
    }
}
