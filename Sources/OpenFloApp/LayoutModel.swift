import Foundation
import OpenFloCore

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
    case fjmlText(LayoutTextObject)
    case shape(LayoutShapeKind)
    case table
    case statistic(LayoutStatisticObject)
    case reportTable(LayoutTableObject)
    case populationTable(LayoutPopulationTableObject)

    var displayName: String {
        switch self {
        case .plot(let descriptor):
            return descriptor.name
        case .text, .fjmlText:
            return "Text"
        case .shape(let shape):
            return shape.rawValue
        case .table, .reportTable:
            return "Statistics Table"
        case .statistic:
            return "Statistic"
        case .populationTable:
            return "Population Table"
        }
    }
}

struct LayoutTextObject: Codable, Equatable, Sendable {
    var segments: [FJMLSegment]
    var style: TextStyle

    init(segments: [FJMLSegment] = [.literal("Text")], style: TextStyle = TextStyle()) {
        self.segments = segments
        self.style = style
    }
}

enum FJMLSegment: Codable, Equatable, Sendable {
    case literal(String)
    case keyword(KeywordColumnSpec)
    case statistic(WorkspaceTableColumn)
    case equation(String)
    case annotation(LayoutAnnotation)
}

enum LayoutAnnotation: String, CaseIterable, Codable, Identifiable, Sendable {
    case date = "Date"
    case time = "Time"
    case version = "Version"

    var id: String { rawValue }
}

struct TextStyle: Codable, Equatable, Sendable {
    var fontSize: Double
    var colorName: String

    init(fontSize: Double = 15, colorName: String = "Black") {
        self.fontSize = fontSize
        self.colorName = colorName
    }
}

struct LayoutStatisticObject: Codable, Equatable, Sendable {
    var column: WorkspaceTableColumn
    var label: String
    var showLabel: Bool

    init(column: WorkspaceTableColumn, label: String? = nil, showLabel: Bool = true) {
        self.column = column
        self.label = label ?? column.name
        self.showLabel = showLabel
    }
}

struct LayoutTableObject: Codable, Equatable, Sendable {
    var source: LayoutTableSource
    var style: TableStyle

    init(source: LayoutTableSource = .template(Self.defaultColumns), style: TableStyle = TableStyle()) {
        self.source = source
        self.style = style
    }

    static var defaultColumns: [WorkspaceTableColumn] {
        [
            WorkspaceTableColumn(
                columnType: .keyword,
                sourceSelection: nil,
                gatePath: [],
                name: "Sample",
                keyword: KeywordColumnSpec(key: "Sample Name", scope: .derived)
            ),
            WorkspaceTableColumn(
                sourceSelection: nil,
                gatePath: [],
                name: "# Events",
                statistic: .count
            )
        ]
    }
}

enum LayoutTableSource: Codable, Equatable, Sendable {
    case snapshot(WorkspaceTableOutputSnapshot)
    case template([WorkspaceTableColumn])
}

struct WorkspaceTableOutputSnapshot: Codable, Equatable, Sendable {
    var columns: [WorkspaceTableColumn]
    var rows: [WorkspaceTableOutputSnapshotRow]
}

struct WorkspaceTableOutputSnapshotRow: Codable, Equatable, Sendable {
    var sampleName: String
    var values: [String]
}

struct LayoutPopulationTableObject: Codable, Equatable, Sendable {
    var sampleID: UUID?
    var populations: [PopulationReference]
    var statistics: [StatisticRequest]
    var style: TableStyle

    init(
        sampleID: UUID? = nil,
        populations: [PopulationReference] = [],
        statistics: [StatisticRequest] = [StatisticRequest(kind: .count)],
        style: TableStyle = TableStyle()
    ) {
        self.sampleID = sampleID
        self.populations = populations
        self.statistics = statistics
        self.style = style
    }
}

struct TableStyle: Codable, Equatable, Sendable {
    var fontSize: Double
    var showHeader: Bool
    var showGrid: Bool

    init(fontSize: Double = 11, showHeader: Bool = true, showGrid: Bool = true) {
        self.fontSize = fontSize
        self.showHeader = showHeader
        self.showGrid = showGrid
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
