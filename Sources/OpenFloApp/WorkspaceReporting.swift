import AppKit
import Foundation
import OpenFloCore

enum WorkspaceStatisticKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case count = "Count"
    case percentParent = "% Parent"
    case percentTotal = "% Total"
    case median = "Median"
    case mean = "Mean"
    case geometricMean = "Geometric Mean"

    var id: String { rawValue }

    var requiresChannel: Bool {
        switch self {
        case .count, .percentParent, .percentTotal:
            return false
        case .median, .mean, .geometricMean:
            return true
        }
    }
}

struct WorkspaceTableColumn: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var sourceSelection: WorkspaceSelection?
    var gatePath: [String]
    var name: String
    var statistic: WorkspaceStatisticKind
    var channelName: String?
    var heatMapped: Bool

    init(
        id: UUID = UUID(),
        sourceSelection: WorkspaceSelection?,
        gatePath: [String],
        name: String,
        statistic: WorkspaceStatisticKind = .count,
        channelName: String? = nil,
        heatMapped: Bool = false
    ) {
        self.id = id
        self.sourceSelection = sourceSelection
        self.gatePath = gatePath
        self.name = name
        self.statistic = statistic
        self.channelName = channelName
        self.heatMapped = heatMapped
    }
}

struct WorkspaceTableOutput: Equatable, Sendable {
    var columns: [WorkspaceTableColumn]
    var rows: [WorkspaceTableOutputRow]
}

struct WorkspaceTableOutputRow: Equatable, Identifiable, Sendable {
    var id: UUID
    var sampleName: String
    var values: [Double?]

    init(id: UUID = UUID(), sampleName: String, values: [Double?]) {
        self.id = id
        self.sampleName = sampleName
        self.values = values
    }
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

    init(
        xChannelName: String?,
        yChannelName: String?,
        plotMode: PlotMode,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil
    ) {
        self.xChannelName = xChannelName
        self.yChannelName = yChannelName
        self.plotMode = plotMode
        self.xAxisSettings = xAxisSettings
        self.yAxisSettings = yAxisSettings
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
            yAxisSettings: yAxisSettings
        )
    }

    mutating func applyDisplayState(_ state: WorkspaceGraphDisplayState) {
        xChannelName = state.xChannelName
        yChannelName = state.yChannelName
        plotMode = state.plotMode
        xAxisSettings = state.xAxisSettings
        yAxisSettings = state.yAxisSettings
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
