import Foundation
import OpenFloCore

struct WorkspaceDocument: Codable, Sendable {
    var version: Int
    var samples: [WorkspaceSampleSnapshot]
    var groupGates: [WorkspaceGateSnapshot]
    var layouts: [WorkspaceLayout]
    var selectedLayoutID: UUID?
    var lastGraphDisplayStates: [String: WorkspaceGraphDisplayState]

    init(
        version: Int = 1,
        samples: [WorkspaceSampleSnapshot],
        groupGates: [WorkspaceGateSnapshot],
        layouts: [WorkspaceLayout],
        selectedLayoutID: UUID?,
        lastGraphDisplayStates: [String: WorkspaceGraphDisplayState] = [:]
    ) {
        self.version = version
        self.samples = samples
        self.groupGates = groupGates
        self.layouts = layouts
        self.selectedLayoutID = selectedLayoutID
        self.lastGraphDisplayStates = lastGraphDisplayStates
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case samples
        case groupGates
        case layouts
        case selectedLayoutID
        case lastGraphDisplayStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        samples = try container.decode([WorkspaceSampleSnapshot].self, forKey: .samples)
        groupGates = try container.decode([WorkspaceGateSnapshot].self, forKey: .groupGates)
        layouts = try container.decode([WorkspaceLayout].self, forKey: .layouts)
        selectedLayoutID = try container.decodeIfPresent(UUID.self, forKey: .selectedLayoutID)
        lastGraphDisplayStates = try container.decodeIfPresent(
            [String: WorkspaceGraphDisplayState].self,
            forKey: .lastGraphDisplayStates
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(samples, forKey: .samples)
        try container.encode(groupGates, forKey: .groupGates)
        try container.encode(layouts, forKey: .layouts)
        try container.encodeIfPresent(selectedLayoutID, forKey: .selectedLayoutID)
        try container.encode(lastGraphDisplayStates, forKey: .lastGraphDisplayStates)
    }
}

struct WorkspaceSampleSnapshot: Codable, Sendable {
    var id: UUID
    var name: String
    var urlPath: String?
    var kind: WorkspaceSampleKind
    var gates: [WorkspaceGateSnapshot]
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
