import AppKit
import Foundation
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSelection: Equatable, Sendable {
    let sampleID: UUID
    let gateID: UUID?
}

struct WorkspaceRow: Identifiable, Equatable {
    let id: String
    let selection: WorkspaceSelection
    let depth: Int
    let name: String
    let count: Int?
    let role: String
    let isGate: Bool
}

final class WorkspaceGateNode: Identifiable, ObservableObject {
    let id: UUID
    var name: String
    var gate: PolygonGate
    var xChannelName: String
    var yChannelName: String
    var xTransform: TransformKind
    var yTransform: TransformKind
    @Published var count: Int?
    @Published var children: [WorkspaceGateNode]

    init(
        id: UUID = UUID(),
        name: String,
        gate: PolygonGate,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        count: Int? = nil,
        children: [WorkspaceGateNode] = []
    ) {
        self.id = id
        self.name = name
        self.gate = gate
        self.xChannelName = xChannelName
        self.yChannelName = yChannelName
        self.xTransform = xTransform
        self.yTransform = yTransform
        self.count = count
        self.children = children
    }

    func clone() -> WorkspaceGateNode {
        WorkspaceGateNode(
            name: name,
            gate: gate,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xTransform: xTransform,
            yTransform: yTransform,
            count: nil,
            children: children.map { $0.clone() }
        )
    }
}

final class WorkspaceSample: Identifiable, ObservableObject {
    let id: UUID
    let url: URL?
    @Published var name: String
    @Published var table: EventTable
    @Published var gates: [WorkspaceGateNode]

    init(id: UUID = UUID(), name: String, url: URL?, table: EventTable, gates: [WorkspaceGateNode] = []) {
        self.id = id
        self.name = name
        self.url = url
        self.table = table
        self.gates = gates
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var samples: [WorkspaceSample] = []
    @Published var selected: WorkspaceSelection?
    @Published private(set) var status: String = "Drop .fcs files here or add samples."
    private var lastCreatedGate: WorkspaceSelection?
    private var plotWindowControllers: [NSWindowController] = []

    var rows: [WorkspaceRow] {
        samples.flatMap { sample in
            var output = [
                WorkspaceRow(
                    id: rowID(sampleID: sample.id, gateID: nil),
                    selection: WorkspaceSelection(sampleID: sample.id, gateID: nil),
                    depth: 0,
                    name: sample.name,
                    count: sample.table.rowCount,
                    role: "Sample",
                    isGate: false
                )
            ]
            appendGateRows(sample.gates, sampleID: sample.id, depth: 1, output: &output)
            return output
        }
    }

    init() {}

    func selectedPopulation(for selection: WorkspaceSelection? = nil) -> (table: EventTable, mask: EventMask?, title: String)? {
        let resolved = selection ?? selected
        guard let resolved, let sample = sample(id: resolved.sampleID) else { return nil }
        if let gateID = resolved.gateID {
            guard let path = gatePath(gateID, in: sample.gates) else { return nil }
            let mask = evaluate(path: path, sample: sample)
            return (sample.table, mask, path.last?.name ?? sample.name)
        }
        return (sample.table, nil, sample.name)
    }

    func addFCSURLs(_ urls: [URL]) {
        let fcsURLs = urls.filter { $0.pathExtension.lowercased() == "fcs" }
        guard !fcsURLs.isEmpty else { return }
        status = "Loading \(fcsURLs.count) FCS file(s)..."

        for url in fcsURLs {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try FCSParser.load(url: url)
                    Task { @MainActor in
                        let sample = WorkspaceSample(name: url.lastPathComponent, url: url, table: file.table)
                        self.samples.append(sample)
                        if self.selected == nil {
                            self.selected = WorkspaceSelection(sampleID: sample.id, gateID: nil)
                        }
                        self.status = "Loaded \(url.lastPathComponent)."
                    }
                } catch {
                    Task { @MainActor in
                        self.status = "Could not load \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func openFCSPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let fcsType = UTType(filenameExtension: "fcs") {
            panel.allowedContentTypes = [fcsType]
        }
        guard panel.runModal() == .OK else { return }
        addFCSURLs(panel.urls)
    }

    func addSynthetic(events: Int) {
        status = "Generating \(events.formatted()) synthetic events..."
        DispatchQueue.global(qos: .userInitiated).async {
            let table = EventTable.synthetic(events: events)
            Task { @MainActor in
                let sample = WorkspaceSample(name: "Synthetic \(events.formatted())", url: nil, table: table)
                self.samples.append(sample)
                if self.selected == nil {
                    self.selected = WorkspaceSelection(sampleID: sample.id, gateID: nil)
                }
                self.status = "Added synthetic sample."
            }
        }
    }

    func addGateFromPlot(
        _ gate: PolygonGate,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        parentSelection: WorkspaceSelection? = nil
    ) -> WorkspaceSelection? {
        let target = parentSelection ?? selected
        guard let target, let sample = sample(id: target.sampleID) else { return nil }
        let parentMask = target.gateID.flatMap { gateID in
            gatePath(gateID, in: sample.gates).map { evaluate(path: $0, sample: sample) }
        }
        let count = evaluate(gate: gate, sample: sample, base: parentMask, xChannelName: xChannelName, yChannelName: yChannelName, xTransform: xTransform, yTransform: yTransform).selectedCount
        let node = WorkspaceGateNode(
            name: uniqueGateName(gate.name, under: target),
            gate: gate,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xTransform: xTransform,
            yTransform: yTransform,
            count: count
        )

        objectWillChange.send()
        if let gateID = target.gateID, let parent = self.gate(id: gateID, in: sample.gates) {
            parent.children.append(node)
        } else {
            sample.gates.append(node)
        }
        let newSelection = WorkspaceSelection(sampleID: sample.id, gateID: node.id)
        lastCreatedGate = newSelection
        status = "Added \(node.name) gate."
        return newSelection
    }

    func applySelectedGateToAllSamples() {
        let sourceSelection = selected?.gateID == nil ? lastCreatedGate : selected
        guard let sourceSelection, let sourceSample = sample(id: sourceSelection.sampleID), let gateID = sourceSelection.gateID, let sourceGate = gate(id: gateID, in: sourceSample.gates) else {
            status = "Select a gate to apply it to all samples."
            return
        }

        objectWillChange.send()
        for sample in samples where sample.id != sourceSample.id {
            let clone = sourceGate.clone()
            clone.name = uniqueGateName(clone.name, in: sample.gates)
            sample.gates.append(clone)
            refreshCount(for: clone, in: sample)
        }
        status = "Applied \(sourceGate.name) to \(max(0, samples.count - 1)) sample(s)."
    }

    func copyGate(dragPayload: String, to target: WorkspaceSelection) {
        guard dragPayload.hasPrefix("gate:"), let sourceGateID = UUID(uuidString: String(dragPayload.dropFirst(5))) else { return }
        guard let source = sampleAndGatePath(containing: sourceGateID), let sourceGate = source.path.last else { return }
        guard let targetSample = sample(id: target.sampleID) else { return }

        objectWillChange.send()
        let insertedRoot: WorkspaceGateNode
        let insertedSelection: WorkspaceGateNode
        if let targetGateID = target.gateID, let targetGate = gate(id: targetGateID, in: targetSample.gates) {
            let clone = sourceGate.clone()
            clone.name = uniqueGateName(clone.name, under: target)
            targetGate.children.append(clone)
            insertedRoot = clone
            insertedSelection = clone
        } else if source.path.count > 1 {
            let clonedPath = cloneGatePath(source.path)
            clonedPath.root.name = uniqueGateName(clonedPath.root.name, in: targetSample.gates)
            targetSample.gates.append(clonedPath.root)
            insertedRoot = clonedPath.root
            insertedSelection = clonedPath.leaf
        } else {
            let clone = sourceGate.clone()
            clone.name = uniqueGateName(clone.name, under: target)
            targetSample.gates.append(clone)
            insertedRoot = clone
            insertedSelection = clone
        }
        refreshCounts(for: insertedRoot, in: targetSample)
        selected = WorkspaceSelection(sampleID: targetSample.id, gateID: insertedSelection.id)
        if source.path.count > 1, target.gateID == nil {
            status = "Copied \(sourceGate.name) with parent gates to \(targetSample.name)."
        } else {
            status = "Copied \(sourceGate.name) to \(targetSample.name)."
        }
    }

    func dragPayload(for row: WorkspaceRow) -> String? {
        guard row.isGate, let gateID = row.selection.gateID else { return nil }
        return "gate:\(gateID.uuidString)"
    }

    func openPlotWindow(for selection: WorkspaceSelection) {
        guard let population = selectedPopulation(for: selection), let sample = sample(id: selection.sampleID) else { return }
        let axes = AppModel.defaultAxisSelection(for: sample.table)
        let config = gateConfiguration(for: selection)
        let xIndex = config.flatMap { channelIndex(named: $0.xChannelName, in: sample.table) } ?? axes.x
        let yIndex = config.flatMap { channelIndex(named: $0.yChannelName, in: sample.table) } ?? axes.y
        let model = AppModel(
            table: population.table,
            baseMask: population.mask,
            populationTitle: population.title,
            xChannel: xIndex,
            yChannel: yIndex,
            xTransform: config?.xTransform ?? AppModel.defaultTransform(for: sample.table.channels[xIndex]),
            yTransform: config?.yTransform ?? AppModel.defaultTransform(for: sample.table.channels[yIndex])
        )
        let root = PlotWindowView(workspace: self, selection: selection, model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(population.title) - OpenFlo"
        window.center()
        window.contentView = NSHostingView(rootView: root)
        let controller = NSWindowController(window: window)
        plotWindowControllers.append(controller)
        controller.showWindow(nil)
    }

    func parentSelection(of selection: WorkspaceSelection) -> WorkspaceSelection? {
        guard let gateID = selection.gateID, let sample = sample(id: selection.sampleID) else { return nil }
        if let parentGateID = parentGateID(of: gateID, in: sample.gates, parent: nil) {
            return WorkspaceSelection(sampleID: sample.id, gateID: parentGateID)
        }
        return WorkspaceSelection(sampleID: sample.id, gateID: nil)
    }

    func gateConfiguration(for selection: WorkspaceSelection) -> (xChannelName: String, yChannelName: String, xTransform: TransformKind, yTransform: TransformKind)? {
        guard let gateID = selection.gateID, let sample = sample(id: selection.sampleID), let node = gate(id: gateID, in: sample.gates) else {
            return nil
        }
        return (node.xChannelName, node.yChannelName, node.xTransform, node.yTransform)
    }

    func rename(_ selection: WorkspaceSelection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sample = sample(id: selection.sampleID) else { return }
        objectWillChange.send()
        if let gateID = selection.gateID, let gate = gate(id: gateID, in: sample.gates) {
            gate.name = trimmed
            status = "Renamed gate."
        } else {
            sample.name = trimmed
            status = "Renamed sample."
        }
    }

    func delete(_ selection: WorkspaceSelection) {
        guard let sampleIndex = samples.firstIndex(where: { $0.id == selection.sampleID }) else { return }
        objectWillChange.send()
        if let gateID = selection.gateID {
            _ = removeGate(gateID, from: &samples[sampleIndex].gates)
            selected = WorkspaceSelection(sampleID: samples[sampleIndex].id, gateID: nil)
            status = "Deleted gate."
        } else {
            samples.remove(at: sampleIndex)
            selected = samples.first.map { WorkspaceSelection(sampleID: $0.id, gateID: nil) }
            status = "Removed sample."
        }
    }

    func updateGate(
        _ selection: WorkspaceSelection,
        gate updatedGate: PolygonGate,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind
    ) {
        guard let sample = sample(id: selection.sampleID), let gateID = selection.gateID, let node = gate(id: gateID, in: sample.gates) else { return }
        objectWillChange.send()
        node.gate = updatedGate
        node.xChannelName = xChannelName
        node.yChannelName = yChannelName
        node.xTransform = xTransform
        node.yTransform = yTransform
    }

    func refreshCount(for selection: WorkspaceSelection) {
        guard let sample = sample(id: selection.sampleID), let gateID = selection.gateID, let node = gate(id: gateID, in: sample.gates) else { return }
        refreshCount(for: node, in: sample)
    }

    func rowID(sampleID: UUID, gateID: UUID?) -> String {
        if let gateID {
            return "\(sampleID.uuidString):\(gateID.uuidString)"
        }
        return sampleID.uuidString
    }

    private func appendGateRows(_ gates: [WorkspaceGateNode], sampleID: UUID, depth: Int, output: inout [WorkspaceRow]) {
        for gate in gates {
            output.append(
                WorkspaceRow(
                    id: rowID(sampleID: sampleID, gateID: gate.id),
                    selection: WorkspaceSelection(sampleID: sampleID, gateID: gate.id),
                    depth: depth,
                    name: gate.name,
                    count: gate.count,
                    role: "Gate",
                    isGate: true
                )
            )
            appendGateRows(gate.children, sampleID: sampleID, depth: depth + 1, output: &output)
        }
    }

    private func sample(id: UUID) -> WorkspaceSample? {
        samples.first { $0.id == id }
    }

    private func gate(id: UUID, in gates: [WorkspaceGateNode]) -> WorkspaceGateNode? {
        for gate in gates {
            if gate.id == id {
                return gate
            }
            if let found = self.gate(id: id, in: gate.children) {
                return found
            }
        }
        return nil
    }

    private func gatePath(_ id: UUID, in gates: [WorkspaceGateNode]) -> [WorkspaceGateNode]? {
        for gate in gates {
            if gate.id == id {
                return [gate]
            }
            if let childPath = gatePath(id, in: gate.children) {
                return [gate] + childPath
            }
        }
        return nil
    }

    private func sampleAndGatePath(containing id: UUID) -> (sample: WorkspaceSample, path: [WorkspaceGateNode])? {
        for sample in samples {
            if let path = gatePath(id, in: sample.gates) {
                return (sample, path)
            }
        }
        return nil
    }

    private func cloneGatePath(_ path: [WorkspaceGateNode]) -> (root: WorkspaceGateNode, leaf: WorkspaceGateNode) {
        let leaf = path.last!.clone()
        var root = leaf
        for node in path.dropLast().reversed() {
            root = WorkspaceGateNode(
                name: node.name,
                gate: node.gate,
                xChannelName: node.xChannelName,
                yChannelName: node.yChannelName,
                xTransform: node.xTransform,
                yTransform: node.yTransform,
                count: nil,
                children: [root]
            )
        }
        return (root, leaf)
    }

    private func parentGateID(of id: UUID, in gates: [WorkspaceGateNode], parent: UUID?) -> UUID? {
        for gate in gates {
            if gate.id == id {
                return parent
            }
            if let found = parentGateID(of: id, in: gate.children, parent: gate.id) {
                return found
            }
        }
        return nil
    }

    private func removeGate(_ id: UUID, from gates: inout [WorkspaceGateNode]) -> Bool {
        if let index = gates.firstIndex(where: { $0.id == id }) {
            gates.remove(at: index)
            return true
        }
        for index in gates.indices {
            if removeGate(id, from: &gates[index].children) {
                return true
            }
        }
        return false
    }

    private func evaluate(path: [WorkspaceGateNode], sample: WorkspaceSample) -> EventMask {
        var mask: EventMask?
        for node in path {
            mask = evaluate(
                gate: node.gate,
                sample: sample,
                base: mask,
                xChannelName: node.xChannelName,
                yChannelName: node.yChannelName,
                xTransform: node.xTransform,
                yTransform: node.yTransform
            )
        }
        return mask ?? EventMask(count: sample.table.rowCount, fill: true)
    }

    private func evaluate(
        gate: PolygonGate,
        sample: WorkspaceSample,
        base: EventMask?,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind
    ) -> EventMask {
        let xIndex = channelIndex(named: xChannelName, in: sample.table) ?? AppModel.defaultAxisSelection(for: sample.table).x
        let yIndex = channelIndex(named: yChannelName, in: sample.table) ?? AppModel.defaultAxisSelection(for: sample.table).y
        let xValues = xTransform.apply(to: sample.table.column(xIndex))
        let yValues = yTransform.apply(to: sample.table.column(yIndex))
        return gate.evaluate(xValues: xValues, yValues: yValues, base: base)
    }

    private func refreshCount(for node: WorkspaceGateNode, in sample: WorkspaceSample) {
        if let path = gatePath(node.id, in: sample.gates) {
            objectWillChange.send()
            node.count = evaluate(path: path, sample: sample).selectedCount
        }
    }

    private func refreshCounts(for node: WorkspaceGateNode, in sample: WorkspaceSample) {
        refreshCount(for: node, in: sample)
        for child in node.children {
            refreshCounts(for: child, in: sample)
        }
    }

    private func channelIndex(named name: String, in table: EventTable) -> Int? {
        table.channels.firstIndex { channel in
            channel.name == name || channel.displayName == name
        }
    }

    private func uniqueGateName(_ base: String, under selection: WorkspaceSelection) -> String {
        guard let sample = sample(id: selection.sampleID) else { return base }
        let siblings: [WorkspaceGateNode]
        if let gateID = selection.gateID, let parent = gate(id: gateID, in: sample.gates) {
            siblings = parent.children
        } else {
            siblings = sample.gates
        }
        return uniqueGateName(base, in: siblings)
    }

    private func uniqueGateName(_ base: String, in siblings: [WorkspaceGateNode]) -> String {
        let names = Set(siblings.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}
