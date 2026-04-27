import Foundation
import OpenFloCore

enum PlotAxis: String, Identifiable, Sendable {
    case x
    case y

    var id: String { rawValue }

    var title: String {
        switch self {
        case .x: return "X Axis"
        case .y: return "Y Axis"
        }
    }
}

enum AxisRangeBound: Sendable {
    case minimum
    case maximum
}

struct AxisDisplaySettings: Equatable, Sendable {
    var transform: TransformKind
    var minimum: Float?
    var maximum: Float?
    var extraNegativeDecades: Float = 0
    var widthBasis: Float = 1
    var positiveDecades: Float = 4.5

    var hasCustomRange: Bool {
        minimum != nil && maximum != nil
    }

    func matchesTransformParameters(_ other: AxisDisplaySettings) -> Bool {
        transform == other.transform
            && extraNegativeDecades == other.extraNegativeDecades
            && widthBasis == other.widthBasis
            && positiveDecades == other.positiveDecades
    }

    func resolvedRange(auto: ClosedRange<Float>) -> ClosedRange<Float> {
        if let minimum, let maximum, minimum.isFinite, maximum.isFinite, maximum > minimum {
            return minimum...maximum
        }

        guard transform.usesDecadeRange else {
            return auto
        }

        let lower = transform == .logarithmic
            ? min(auto.lowerBound, 0)
            : min(auto.lowerBound, -max(0, extraNegativeDecades))
        let upper = max(auto.upperBound, max(1, positiveDecades))
        guard upper > lower else { return auto }
        return lower...upper
    }
}
