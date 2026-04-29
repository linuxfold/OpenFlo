import Foundation

struct LayoutFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultPlot = LayoutFrame(x: 72, y: 72, width: 360, height: 300)
    static let defaultText = LayoutFrame(x: 90, y: 410, width: 280, height: 58)
    static let defaultShape = LayoutFrame(x: 480, y: 90, width: 140, height: 100)

    func offsetBy(dx: Double, dy: Double) -> LayoutFrame {
        LayoutFrame(x: x + dx, y: y + dy, width: width, height: height)
    }
}

enum LayoutShapeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case rectangle = "Rectangle"
    case oval = "Oval"
    case line = "Line"
    case diamond = "Diamond"
    case triangle = "Triangle"

    var id: String { rawValue }
}

enum LayoutItemKind: Codable, Equatable, Sendable {
    case plot(WorkspacePlotDescriptor)
    case text(String)
    case shape(LayoutShapeKind)
    case table

    var displayName: String {
        switch self {
        case .plot(let descriptor):
            return descriptor.name
        case .text:
            return "Text"
        case .shape(let shape):
            return shape.rawValue
        case .table:
            return "Statistics Table"
        }
    }
}

struct WorkspaceLayoutItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var frame: LayoutFrame
    var kind: LayoutItemKind
    var strokeColorName: String
    var fillColorName: String
    var lineWidth: Double

    init(
        id: UUID = UUID(),
        frame: LayoutFrame,
        kind: LayoutItemKind,
        strokeColorName: String = "Black",
        fillColorName: String = "None",
        lineWidth: Double = 2
    ) {
        self.id = id
        self.frame = frame
        self.kind = kind
        self.strokeColorName = strokeColorName
        self.fillColorName = fillColorName
        self.lineWidth = lineWidth
    }
}

enum LayoutIterationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off = "Off"
    case sample = "Sample"

    var id: String { rawValue }
}

enum LayoutBatchDestination: String, CaseIterable, Codable, Identifiable, Sendable {
    case layout = "Layout"
    case webPage = "Web Page"

    var id: String { rawValue }
}

enum LayoutBatchAxis: String, CaseIterable, Codable, Identifiable, Sendable {
    case columns = "Columns"
    case rows = "Rows"

    var id: String { rawValue }
}
