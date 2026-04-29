import Foundation
import OpenFloCore

struct WorkspaceDocument: Codable, Sendable {
    var version: Int
    var samples: [WorkspaceSampleSnapshot]
    var groupGates: [WorkspaceGateSnapshot]
    var layouts: [WorkspaceLayout]
    var selectedLayoutID: UUID?

    init(
        version: Int = 1,
        samples: [WorkspaceSampleSnapshot],
        groupGates: [WorkspaceGateSnapshot],
        layouts: [WorkspaceLayout],
        selectedLayoutID: UUID?
    ) {
        self.version = version
        self.samples = samples
        self.groupGates = groupGates
        self.layouts = layouts
        self.selectedLayoutID = selectedLayoutID
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
