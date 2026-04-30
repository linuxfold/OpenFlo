import AppKit
import Foundation
import OpenFloCore

typealias WorkspaceStatisticKind = StatisticKind

extension StatisticKind {
    static var percentParent: StatisticKind { .frequencyOfParent }
    static var percentTotal: StatisticKind { .frequencyOfTotal }
}

enum ReportColumnType: String, CaseIterable, Codable, Identifiable, Sendable {
    case statistic = "Statistic"
    case keyword = "Keyword"
    case formula = "Formula"

    var id: String { rawValue }
}

enum KeywordScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case sample = "Sample"
    case parameter = "Parameter"
    case workspace = "Workspace"
    case derived = "Derived"

    var id: String { rawValue }
}

struct KeywordColumnSpec: Codable, Equatable, Sendable {
    var key: String
    var scope: KeywordScope
    var parameterName: String?

    init(key: String = "$FIL", scope: KeywordScope = .sample, parameterName: String? = nil) {
        self.key = key
        self.scope = scope
        self.parameterName = parameterName
    }
}

struct FormulaColumnSpec: Codable, Equatable, Sendable {
    var expression: String

    init(expression: String = "") {
        self.expression = expression
    }
}

enum ColumnFormatting: Codable, Equatable, Sendable {
    case none
    case heatMap(HeatMapSpec)
    case standardDeviationBands(SDBandSpec)
    case expectedRange(ExpectedRangeSpec)

    var isHeatMapped: Bool {
        if case .heatMap = self {
            true
        } else {
            false
        }
    }
}

struct HeatMapSpec: Codable, Equatable, Sendable {
    var lowColorName: String
    var highColorName: String

    init(lowColorName: String = "Blue", highColorName: String = "Red") {
        self.lowColorName = lowColorName
        self.highColorName = highColorName
    }
}

struct SDBandSpec: Codable, Equatable, Sendable {
    var warningBand: Double
    var criticalBand: Double

    init(warningBand: Double = 1, criticalBand: Double = 2) {
        self.warningBand = warningBand
        self.criticalBand = criticalBand
    }
}

struct ExpectedRangeSpec: Codable, Equatable, Sendable {
    var minimum: Double?
    var maximum: Double?

    init(minimum: Double? = nil, maximum: Double? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

struct WorkspaceTableColumn: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var columnType: ReportColumnType
    var sourceSelection: WorkspaceSelection?
    var gatePath: [String]
    var denominatorGatePath: [String]
    var name: String
    var statistic: WorkspaceStatisticKind
    var channelName: String?
    var percentile: Double?
    var statisticSpace: StatisticSpace
    var keyword: KeywordColumnSpec
    var formula: FormulaColumnSpec
    var showValues: Bool
    var defineAsControl: Bool
    var formatting: ColumnFormatting

    var heatMapped: Bool {
        get { formatting.isHeatMapped }
        set { formatting = newValue ? .heatMap(HeatMapSpec()) : .none }
    }

    init(
        id: UUID = UUID(),
        columnType: ReportColumnType = .statistic,
        sourceSelection: WorkspaceSelection?,
        gatePath: [String],
        denominatorGatePath: [String] = [],
        name: String,
        statistic: WorkspaceStatisticKind = .count,
        channelName: String? = nil,
        percentile: Double? = nil,
        statisticSpace: StatisticSpace = .exactScale,
        keyword: KeywordColumnSpec = KeywordColumnSpec(),
        formula: FormulaColumnSpec = FormulaColumnSpec(),
        showValues: Bool = true,
        defineAsControl: Bool = false,
        formatting: ColumnFormatting = .none,
        heatMapped: Bool = false
    ) {
        self.id = id
        self.columnType = columnType
        self.sourceSelection = sourceSelection
        self.gatePath = gatePath
        self.denominatorGatePath = denominatorGatePath
        self.name = name
        self.statistic = statistic
        self.channelName = channelName
        self.percentile = percentile
        self.statisticSpace = statisticSpace
        self.keyword = keyword
        self.formula = formula
        self.showValues = showValues
        self.defineAsControl = defineAsControl
        self.formatting = heatMapped ? .heatMap(HeatMapSpec()) : formatting
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case columnType
        case sourceSelection
        case gatePath
        case denominatorGatePath
        case name
        case statistic
        case channelName
        case percentile
        case statisticSpace
        case keyword
        case formula
        case showValues
        case defineAsControl
        case formatting
        case heatMapped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        columnType = try container.decodeIfPresent(ReportColumnType.self, forKey: .columnType) ?? .statistic
        sourceSelection = try container.decodeIfPresent(WorkspaceSelection.self, forKey: .sourceSelection)
        gatePath = try container.decodeIfPresent([String].self, forKey: .gatePath) ?? []
        denominatorGatePath = try container.decodeIfPresent([String].self, forKey: .denominatorGatePath) ?? []
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Column"
        statistic = try container.decodeIfPresent(WorkspaceStatisticKind.self, forKey: .statistic) ?? .count
        channelName = try container.decodeIfPresent(String.self, forKey: .channelName)
        percentile = try container.decodeIfPresent(Double.self, forKey: .percentile)
        statisticSpace = try container.decodeIfPresent(StatisticSpace.self, forKey: .statisticSpace) ?? .exactScale
        keyword = try container.decodeIfPresent(KeywordColumnSpec.self, forKey: .keyword) ?? KeywordColumnSpec()
        formula = try container.decodeIfPresent(FormulaColumnSpec.self, forKey: .formula) ?? FormulaColumnSpec()
        showValues = try container.decodeIfPresent(Bool.self, forKey: .showValues) ?? true
        defineAsControl = try container.decodeIfPresent(Bool.self, forKey: .defineAsControl) ?? false
        if let decodedFormatting = try container.decodeIfPresent(ColumnFormatting.self, forKey: .formatting) {
            formatting = decodedFormatting
        } else if (try container.decodeIfPresent(Bool.self, forKey: .heatMapped)) == true {
            formatting = .heatMap(HeatMapSpec())
        } else {
            formatting = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(columnType, forKey: .columnType)
        try container.encodeIfPresent(sourceSelection, forKey: .sourceSelection)
        try container.encode(gatePath, forKey: .gatePath)
        try container.encode(denominatorGatePath, forKey: .denominatorGatePath)
        try container.encode(name, forKey: .name)
        try container.encode(statistic, forKey: .statistic)
        try container.encodeIfPresent(channelName, forKey: .channelName)
        try container.encodeIfPresent(percentile, forKey: .percentile)
        try container.encode(statisticSpace, forKey: .statisticSpace)
        try container.encode(keyword, forKey: .keyword)
        try container.encode(formula, forKey: .formula)
        try container.encode(showValues, forKey: .showValues)
        try container.encode(defineAsControl, forKey: .defineAsControl)
        try container.encode(formatting, forKey: .formatting)
    }
}

struct WorkspaceTableTemplate: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var columns: [WorkspaceTableColumn]
    var iteration: TableIterationSpec
    var outputPreferences: TableOutputPreferences

    init(
        id: UUID = UUID(),
        name: String,
        columns: [WorkspaceTableColumn],
        iteration: TableIterationSpec = .sample(groupID: nil),
        outputPreferences: TableOutputPreferences = TableOutputPreferences()
    ) {
        self.id = id
        self.name = name
        self.columns = columns
        self.iteration = iteration
        self.outputPreferences = outputPreferences
    }
}

enum TableIterationSpec: Codable, Equatable, Sendable {
    case sample(groupID: UUID?)
    case panel(groupID: UUID?, tubeCount: Int, discriminatorIndex: Int?)
    case keyword(groupID: UUID?, iterateBy: String, discriminator: String)
}

struct TableOutputPreferences: Codable, Equatable, Sendable {
    var includeSampleColumn: Bool
    var includeHiddenColumnsInFormulas: Bool

    init(includeSampleColumn: Bool = true, includeHiddenColumnsInFormulas: Bool = true) {
        self.includeSampleColumn = includeSampleColumn
        self.includeHiddenColumnsInFormulas = includeHiddenColumnsInFormulas
    }
}

struct WorkspaceTableOutput: Equatable, Sendable {
    var columns: [WorkspaceTableColumn]
    var rows: [WorkspaceTableOutputRow]
}

struct WorkspaceTableOutputRow: Equatable, Identifiable, Sendable {
    var id: UUID
    var sampleName: String
    var values: [ReportValue]

    init(id: UUID = UUID(), sampleName: String, values: [ReportValue]) {
        self.id = id
        self.sampleName = sampleName
        self.values = values
    }
}

enum ReportValue: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case missing
    case error(String)

    init(_ statValue: StatValue) {
        switch statValue {
        case .number(let value):
            self = .number(value)
        case .missing:
            self = .missing
        case .error(let message):
            self = .error(message)
        }
    }

    var number: Double? {
        if case .number(let value) = self {
            value
        } else {
            nil
        }
    }

    var displayString: String {
        switch self {
        case .number(let value):
            return formatReportNumber(value)
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "TRUE" : "FALSE"
        case .missing:
            return ""
        case .error(let message):
            return "#ERROR: \(message)"
        }
    }
}

func formatReportNumber(_ value: Double) -> String {
    guard value.isFinite else { return "" }
    if abs(value.rounded() - value) < 0.0001 {
        return Int(value.rounded()).formatted()
    }
    if abs(value) >= 100 {
        return String(format: "%.1f", value)
    }
    return String(format: "%.3g", value)
}

struct WorkspaceChannelOptions: Equatable {
    var names: [String]
    var totalCount: Int
    var isLimited: Bool
}

struct WorkspaceGraphDisplayState: Codable, Equatable, Sendable {
    var xChannelName: String?
    var yChannelName: String?
    var plotMode: PlotMode
    var xAxisSettings: AxisDisplaySettings?
    var yAxisSettings: AxisDisplaySettings?
    var histogramSmooth: Bool

    init(
        xChannelName: String?,
        yChannelName: String?,
        plotMode: PlotMode,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil,
        histogramSmooth: Bool = true
    ) {
        self.xChannelName = xChannelName
        self.yChannelName = yChannelName
        self.plotMode = plotMode
        self.xAxisSettings = xAxisSettings
        self.yAxisSettings = yAxisSettings
        self.histogramSmooth = histogramSmooth
    }

    private enum CodingKeys: String, CodingKey {
        case xChannelName
        case yChannelName
        case plotMode
        case xAxisSettings
        case yAxisSettings
        case histogramSmooth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xChannelName = try container.decodeIfPresent(String.self, forKey: .xChannelName)
        yChannelName = try container.decodeIfPresent(String.self, forKey: .yChannelName)
        plotMode = try container.decode(PlotMode.self, forKey: .plotMode)
        xAxisSettings = try container.decodeIfPresent(AxisDisplaySettings.self, forKey: .xAxisSettings)
        yAxisSettings = try container.decodeIfPresent(AxisDisplaySettings.self, forKey: .yAxisSettings)
        histogramSmooth = try container.decodeIfPresent(Bool.self, forKey: .histogramSmooth) ?? true
    }
}

struct WorkspacePopulationDragPayload: Codable, Sendable {
    static let prefix = "openflo-populations-v1:"

    var populations: [WorkspacePopulationDragItem]

    init(populations: [WorkspacePopulationDragItem]) {
        self.populations = populations
    }

    func encodedString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.prefix + json
    }

    static func decode(from string: String) -> WorkspacePopulationDragPayload? {
        guard string.hasPrefix(prefix) else { return nil }
        let json = String(string.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkspacePopulationDragPayload.self, from: data)
    }
}

struct WorkspacePopulationDragItem: Codable, Sendable {
    var selection: WorkspaceSelection
    var displayState: WorkspaceGraphDisplayState?

    init(selection: WorkspaceSelection, displayState: WorkspaceGraphDisplayState?) {
        self.selection = selection
        self.displayState = displayState
    }
}

struct WorkspacePlotDescriptor: Codable, Equatable, Sendable {
    var sourceSelection: WorkspaceSelection
    var gatePath: [String]
    var name: String
    var xChannelName: String?
    var yChannelName: String?
    var plotMode: PlotMode
    var xAxisSettings: AxisDisplaySettings?
    var yAxisSettings: AxisDisplaySettings?
    var showAxes: Bool
    var showGrid: Bool
    var showAncestry: Bool
    var axisFontSize: Double
    var axisColorName: String
    var histogramSmooth: Bool
    var sourceIsControl: Bool
    var lockedSourceSelection: WorkspaceSelection?
    var overlays: [WorkspacePlotOverlayDescriptor]

    init(
        sourceSelection: WorkspaceSelection,
        gatePath: [String],
        name: String,
        xChannelName: String? = nil,
        yChannelName: String? = nil,
        plotMode: PlotMode = .pseudocolor,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil,
        showAxes: Bool = true,
        showGrid: Bool = false,
        showAncestry: Bool = false,
        axisFontSize: Double = 12,
        axisColorName: String = "Black",
        histogramSmooth: Bool = true,
        sourceIsControl: Bool = false,
        lockedSourceSelection: WorkspaceSelection? = nil,
        overlays: [WorkspacePlotOverlayDescriptor] = []
    ) {
        self.sourceSelection = sourceSelection
        self.gatePath = gatePath
        self.name = name
        self.xChannelName = xChannelName
        self.yChannelName = yChannelName
        self.plotMode = plotMode
        self.xAxisSettings = xAxisSettings
        self.yAxisSettings = yAxisSettings
        self.showAxes = showAxes
        self.showGrid = showGrid
        self.showAncestry = showAncestry
        self.axisFontSize = axisFontSize
        self.axisColorName = axisColorName
        self.histogramSmooth = histogramSmooth
        self.sourceIsControl = sourceIsControl
        self.lockedSourceSelection = lockedSourceSelection
        self.overlays = overlays
    }

    var displayState: WorkspaceGraphDisplayState {
        WorkspaceGraphDisplayState(
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            plotMode: plotMode,
            xAxisSettings: xAxisSettings,
            yAxisSettings: yAxisSettings,
            histogramSmooth: histogramSmooth
        )
    }

    mutating func applyDisplayState(_ state: WorkspaceGraphDisplayState) {
        xChannelName = state.xChannelName
        yChannelName = state.yChannelName
        plotMode = state.plotMode
        xAxisSettings = state.xAxisSettings
        yAxisSettings = state.yAxisSettings
        histogramSmooth = state.histogramSmooth
    }

    private enum CodingKeys: String, CodingKey {
        case sourceSelection
        case gatePath
        case name
        case xChannelName
        case yChannelName
        case plotMode
        case xAxisSettings
        case yAxisSettings
        case showAxes
        case showGrid
        case showAncestry
        case axisFontSize
        case axisColorName
        case histogramSmooth
        case sourceIsControl
        case lockedSourceSelection
        case overlays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceSelection = try container.decode(WorkspaceSelection.self, forKey: .sourceSelection)
        gatePath = try container.decode([String].self, forKey: .gatePath)
        name = try container.decode(String.self, forKey: .name)
        xChannelName = try container.decodeIfPresent(String.self, forKey: .xChannelName)
        yChannelName = try container.decodeIfPresent(String.self, forKey: .yChannelName)
        plotMode = try container.decode(PlotMode.self, forKey: .plotMode)
        xAxisSettings = try container.decodeIfPresent(AxisDisplaySettings.self, forKey: .xAxisSettings)
        yAxisSettings = try container.decodeIfPresent(AxisDisplaySettings.self, forKey: .yAxisSettings)
        showAxes = try container.decodeIfPresent(Bool.self, forKey: .showAxes) ?? true
        showGrid = try container.decodeIfPresent(Bool.self, forKey: .showGrid) ?? false
        showAncestry = try container.decodeIfPresent(Bool.self, forKey: .showAncestry) ?? false
        axisFontSize = try container.decodeIfPresent(Double.self, forKey: .axisFontSize) ?? 12
        axisColorName = try container.decodeIfPresent(String.self, forKey: .axisColorName) ?? "Black"
        histogramSmooth = try container.decodeIfPresent(Bool.self, forKey: .histogramSmooth) ?? true
        sourceIsControl = try container.decodeIfPresent(Bool.self, forKey: .sourceIsControl) ?? false
        lockedSourceSelection = try container.decodeIfPresent(WorkspaceSelection.self, forKey: .lockedSourceSelection)
        overlays = try container.decodeIfPresent([WorkspacePlotOverlayDescriptor].self, forKey: .overlays) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceSelection, forKey: .sourceSelection)
        try container.encode(gatePath, forKey: .gatePath)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(xChannelName, forKey: .xChannelName)
        try container.encodeIfPresent(yChannelName, forKey: .yChannelName)
        try container.encode(plotMode, forKey: .plotMode)
        try container.encodeIfPresent(xAxisSettings, forKey: .xAxisSettings)
        try container.encodeIfPresent(yAxisSettings, forKey: .yAxisSettings)
        try container.encode(showAxes, forKey: .showAxes)
        try container.encode(showGrid, forKey: .showGrid)
        try container.encode(showAncestry, forKey: .showAncestry)
        try container.encode(axisFontSize, forKey: .axisFontSize)
        try container.encode(axisColorName, forKey: .axisColorName)
        try container.encode(histogramSmooth, forKey: .histogramSmooth)
        try container.encode(sourceIsControl, forKey: .sourceIsControl)
        try container.encodeIfPresent(lockedSourceSelection, forKey: .lockedSourceSelection)
        try container.encode(overlays, forKey: .overlays)
    }
}

struct WorkspacePlotOverlayDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var sourceSelection: WorkspaceSelection
    var gatePath: [String]
    var name: String
    var colorName: String
    var isControl: Bool
    var lockedSourceSelection: WorkspaceSelection?

    init(
        id: UUID = UUID(),
        sourceSelection: WorkspaceSelection,
        gatePath: [String],
        name: String,
        colorName: String,
        isControl: Bool = false,
        lockedSourceSelection: WorkspaceSelection? = nil
    ) {
        self.id = id
        self.sourceSelection = sourceSelection
        self.gatePath = gatePath
        self.name = name
        self.colorName = colorName
        self.isControl = isControl
        self.lockedSourceSelection = lockedSourceSelection
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceSelection
        case gatePath
        case name
        case colorName
        case isControl
        case lockedSourceSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceSelection = try container.decode(WorkspaceSelection.self, forKey: .sourceSelection)
        gatePath = try container.decode([String].self, forKey: .gatePath)
        name = try container.decode(String.self, forKey: .name)
        colorName = try container.decode(String.self, forKey: .colorName)
        isControl = try container.decodeIfPresent(Bool.self, forKey: .isControl) ?? false
        lockedSourceSelection = try container.decodeIfPresent(WorkspaceSelection.self, forKey: .lockedSourceSelection)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceSelection, forKey: .sourceSelection)
        try container.encode(gatePath, forKey: .gatePath)
        try container.encode(name, forKey: .name)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(isControl, forKey: .isControl)
        try container.encodeIfPresent(lockedSourceSelection, forKey: .lockedSourceSelection)
    }
}

struct LayoutPlotSnapshot {
    var image: NSImage?
    var placeholderMessage: String?
    var sampleName: String
    var populationName: String
    var eventCount: Int
    var xAxisTitle: String
    var yAxisTitle: String
    var xAxisRange: ClosedRange<Float>?
    var yAxisRange: ClosedRange<Float>?
    var ancestry: [String]
    var legend: [LayoutPlotLegendEntry]
}

struct LayoutPlotLegendEntry: Equatable, Identifiable {
    var id: String { "\(layerID?.uuidString ?? "base")-\(name)-\(colorName)-\(eventCount)-\(isControl)" }
    var layerID: UUID?
    var isBaseLayer: Bool
    var name: String
    var colorName: String
    var eventCount: Int
    var isControl: Bool
}
