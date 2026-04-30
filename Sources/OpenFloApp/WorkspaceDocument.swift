import Foundation
import OpenFloCore

struct WorkspaceDocument: Codable, Sendable {
    var version: Int
    var samples: [WorkspaceSampleSnapshot]
    var groupGates: [WorkspaceGateSnapshot]
    var layouts: [WorkspaceLayout]
    var tableTemplates: [WorkspaceTableTemplate]
    var selectedLayoutID: UUID?
    var lastGraphDisplayStates: [String: WorkspaceGraphDisplayState]
    var compensationMatrices: [CompensationMatrix]

    init(
        version: Int = 2,
        samples: [WorkspaceSampleSnapshot],
        groupGates: [WorkspaceGateSnapshot],
        layouts: [WorkspaceLayout],
        tableTemplates: [WorkspaceTableTemplate] = [],
        selectedLayoutID: UUID?,
        lastGraphDisplayStates: [String: WorkspaceGraphDisplayState] = [:],
        compensationMatrices: [CompensationMatrix] = []
    ) {
        self.version = version
        self.samples = samples
        self.groupGates = groupGates
        self.layouts = layouts
        self.tableTemplates = tableTemplates
        self.selectedLayoutID = selectedLayoutID
        self.lastGraphDisplayStates = lastGraphDisplayStates
        self.compensationMatrices = compensationMatrices
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case samples
        case groupGates
        case layouts
        case tableTemplates
        case selectedLayoutID
        case lastGraphDisplayStates
        case compensationMatrices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        samples = try container.decode([WorkspaceSampleSnapshot].self, forKey: .samples)
        groupGates = try container.decode([WorkspaceGateSnapshot].self, forKey: .groupGates)
        layouts = try container.decode([WorkspaceLayout].self, forKey: .layouts)
        tableTemplates = try container.decodeIfPresent([WorkspaceTableTemplate].self, forKey: .tableTemplates) ?? []
        selectedLayoutID = try container.decodeIfPresent(UUID.self, forKey: .selectedLayoutID)
        lastGraphDisplayStates = try container.decodeIfPresent(
            [String: WorkspaceGraphDisplayState].self,
            forKey: .lastGraphDisplayStates
        ) ?? [:]
        compensationMatrices = try container.decodeIfPresent(
            [CompensationMatrix].self,
            forKey: .compensationMatrices
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(samples, forKey: .samples)
        try container.encode(groupGates, forKey: .groupGates)
        try container.encode(layouts, forKey: .layouts)
        try container.encode(tableTemplates, forKey: .tableTemplates)
        try container.encodeIfPresent(selectedLayoutID, forKey: .selectedLayoutID)
        try container.encode(lastGraphDisplayStates, forKey: .lastGraphDisplayStates)
        try container.encode(compensationMatrices, forKey: .compensationMatrices)
    }
}

struct WorkspaceSampleSnapshot: Codable, Sendable {
    var id: UUID
    var name: String
    var urlPath: String?
    var kind: WorkspaceSampleKind
    var gates: [WorkspaceGateSnapshot]
    var compensationMatrixID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case urlPath
        case kind
        case gates
        case compensationMatrixID
    }

    init(
        id: UUID,
        name: String,
        urlPath: String?,
        kind: WorkspaceSampleKind,
        gates: [WorkspaceGateSnapshot],
        compensationMatrixID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.urlPath = urlPath
        self.kind = kind
        self.gates = gates
        self.compensationMatrixID = compensationMatrixID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath)
        kind = try container.decode(WorkspaceSampleKind.self, forKey: .kind)
        gates = try container.decode([WorkspaceGateSnapshot].self, forKey: .gates)
        compensationMatrixID = try container.decodeIfPresent(UUID.self, forKey: .compensationMatrixID)
    }
}

struct WorkspaceGateSnapshot: Codable, Sendable {
    var id: UUID
    var name: String
    var gate: PolygonGate
    var xChannelName: String
    var yChannelName: String
    var xTransform: TransformKind
    var yTransform: TransformKind
    var xAxisSettings: AxisDisplaySettings
    var yAxisSettings: AxisDisplaySettings
    var children: [WorkspaceGateSnapshot]
}

extension WorkspaceGateSnapshot {
    init(node: WorkspaceGateNode) {
        self.id = node.id
        self.name = node.name
        self.gate = node.gate
        self.xChannelName = node.xChannelName
        self.yChannelName = node.yChannelName
        self.xTransform = node.xTransform
        self.yTransform = node.yTransform
        self.xAxisSettings = node.xAxisSettings
        self.yAxisSettings = node.yAxisSettings
        self.children = node.children.map { WorkspaceGateSnapshot(node: $0) }
    }

    func node(count: Int? = nil) -> WorkspaceGateNode {
        WorkspaceGateNode(
            id: id,
            name: name,
            gate: gate,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xTransform: xTransform,
            yTransform: yTransform,
            xAxisSettings: xAxisSettings,
            yAxisSettings: yAxisSettings,
            count: count,
            children: children.map { $0.node() }
        )
    }
}
