import Foundation

public enum TransformKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case linear = "Linear"
    case arcsinh = "Arcsinh"
    case pseudoLog = "PseudoLog"

    public var id: String { rawValue }

    public func apply(_ value: Float, cofactor: Float = 150) -> Float {
        switch self {
        case .linear:
            return value
        case .arcsinh:
            return asinh(value / cofactor)
        case .pseudoLog:
            let magnitude = log10(1 + abs(value))
            return value < 0 ? -magnitude : magnitude
        }
    }

    public func apply(to values: [Float], cofactor: Float = 150) -> [Float] {
        switch self {
        case .linear:
            return values
        case .arcsinh:
            return values.map { asinh($0 / cofactor) }
        case .pseudoLog:
            return values.map { apply($0, cofactor: cofactor) }
        }
    }
}
