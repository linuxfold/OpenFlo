import Foundation

public enum TransformKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case linear = "Linear"
    case logarithmic = "Logarithmic"
    case biexponential = "Biex"
    case arcsinh = "Arcsinh"
    case hyperlog = "Hyperlog"
    case logicle = "Logicle"
    case miltenyi = "Miltenyi"
    case pseudoLog = "PseudoLog"

    public var id: String { rawValue }

    public static var flowScaleOptions: [TransformKind] {
        [.linear, .logarithmic, .biexponential, .arcsinh, .hyperlog, .logicle, .miltenyi]
    }

    public var displayName: String {
        switch self {
        case .arcsinh:
            return "ArcSinh"
        case .biexponential:
            return "Biex"
        default:
            return rawValue
        }
    }

    public var usesTransformSliders: Bool {
        switch self {
        case .linear, .logarithmic:
            return false
        case .arcsinh, .biexponential, .hyperlog, .logicle, .miltenyi, .pseudoLog:
            return true
        }
    }

    public var usesDecadeRange: Bool {
        switch self {
        case .linear, .arcsinh:
            return false
        case .logarithmic, .biexponential, .hyperlog, .logicle, .miltenyi, .pseudoLog:
            return true
        }
    }

    public func apply(
        _ value: Float,
        cofactor: Float = 150,
        extraNegativeDecades: Float = 0,
        widthBasis: Float = 1,
        positiveDecades: Float = 4.5
    ) -> Float {
        switch self {
        case .linear:
            return value
        case .logarithmic:
            return log10(max(value, 1))
        case .biexponential:
            return signedLogicle(value, widthBasis: widthBasis * 0.85)
        case .arcsinh:
            return asinh(value / max(cofactor, 1))
        case .hyperlog:
            return signedLogicle(value, widthBasis: widthBasis)
        case .logicle, .pseudoLog:
            return signedLogicle(value, widthBasis: widthBasis + extraNegativeDecades * 0.2)
        case .miltenyi:
            return signedLogicle(value, widthBasis: max(0.1, widthBasis * 0.65))
        }
    }

    public func apply(
        to values: [Float],
        cofactor: Float = 150,
        extraNegativeDecades: Float = 0,
        widthBasis: Float = 1,
        positiveDecades: Float = 4.5
    ) -> [Float] {
        switch self {
        case .linear:
            return values
        case .arcsinh:
            let resolvedCofactor = max(cofactor, 1)
            return values.map { asinh($0 / resolvedCofactor) }
        case .logarithmic:
            return values.map { log10(max($0, 1)) }
        case .biexponential:
            let resolvedWidth = widthBasis * 0.85
            return values.map { Self.signedLogicle($0, widthBasis: resolvedWidth) }
        case .hyperlog:
            return values.map { Self.signedLogicle($0, widthBasis: widthBasis) }
        case .logicle, .pseudoLog:
            let resolvedWidth = widthBasis + extraNegativeDecades * 0.2
            return values.map { Self.signedLogicle($0, widthBasis: resolvedWidth) }
        case .miltenyi:
            let resolvedWidth = max(0.1, widthBasis * 0.65)
            return values.map { Self.signedLogicle($0, widthBasis: resolvedWidth) }
        }
    }

    private static func signedLogicle(_ value: Float, widthBasis: Float) -> Float {
        let scale = max(pow(Float(10), widthBasis), 1)
        let magnitude = log10(1 + abs(value) / scale)
        return value < 0 ? -magnitude : magnitude
    }

    private func signedLogicle(_ value: Float, widthBasis: Float) -> Float {
        Self.signedLogicle(value, widthBasis: widthBasis)
    }

    public func legacyApply(to values: [Float], cofactor: Float = 150) -> [Float] {
        apply(to: values, cofactor: cofactor)
    }
}
