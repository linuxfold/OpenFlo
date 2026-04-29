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

struct WorkspacePlotDescriptor: Codable, Equatable, Sendable {
    var sourceSelection: WorkspaceSelection
    var gatePath: [String]
    var name: String
    var xChannelName: String?
    var yChannelName: String?
    var plotMode: PlotMode
    var showGrid: Bool
    var showAncestry: Bool
    var axisFontSize: Double
    var axisColorName: String
    var overlays: [WorkspacePlotOverlayDescriptor]

    init(
        sourceSelection: WorkspaceSelection,
        gatePath: [String],
        name: String,
        xChannelName: String? = nil,
        yChannelName: String? = nil,
        plotMode: PlotMode = .pseudocolor,
        showGrid: Bool = false,
        showAncestry: Bool = false,
        axisFontSize: Double = 12,
        axisColorName: String = "Black",
        overlays: [WorkspacePlotOverlayDescriptor] = []
    ) {
        self.sourceSelection = sourceSelection
        self.gatePath = gatePath
        self.name = name
        self.xChannelName = xChannelName
        self.yChannelName = yChannelName
        self.plotMode = plotMode
        self.showGrid = showGrid
        self.showAncestry = showAncestry
        self.axisFontSize = axisFontSize
        self.axisColorName = axisColorName
        self.overlays = overlays
    }

    private enum CodingKeys: String, CodingKey {
        case sourceSelection
        case gatePath
        case name
        case xChannelName
        case yChannelName
        case plotMode
        case showGrid
        case showAncestry
        case axisFontSize
        case axisColorName
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
        showGrid = try container.decode(Bool.self, forKey: .showGrid)
        showAncestry = try container.decode(Bool.self, forKey: .showAncestry)
        axisFontSize = try container.decode(Double.self, forKey: .axisFontSize)
        axisColorName = try container.decode(String.self, forKey: .axisColorName)
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
        try container.encode(showGrid, forKey: .showGrid)
        try container.encode(showAncestry, forKey: .showAncestry)
        try container.encode(axisFontSize, forKey: .axisFontSize)
        try container.encode(axisColorName, forKey: .axisColorName)
        try container.encode(overlays, forKey: .overlays)
    }
}

struct WorkspacePlotOverlayDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var sourceSelection: WorkspaceSelection
    var gatePath: [String]
    var name: String
    var colorName: String

    init(
        id: UUID = UUID(),
        sourceSelection: WorkspaceSelection,
        gatePath: [String],
        name: String,
        colorName: String
    ) {
        self.id = id
        self.sourceSelection = sourceSelection
        self.gatePath = gatePath
        self.name = name
        self.colorName = colorName
    }
}

struct LayoutPlotSnapshot {
    var image: NSImage?
    var sampleName: String
    var populationName: String
    var eventCount: Int
    var xAxisTitle: String
    var yAxisTitle: String
    var ancestry: [String]
    var legend: [LayoutPlotLegendEntry]
}

struct LayoutPlotLegendEntry: Equatable, Identifiable {
    var id: String { "\(name)-\(colorName)-\(eventCount)" }
    var name: String
    var colorName: String
    var eventCount: Int
}
