import AppKit
import Foundation
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSelection: Equatable, Sendable {
    static let allSamplesID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let allSamples = WorkspaceSelection(sampleID: allSamplesID, gateID: nil)

    let sampleID: UUID
    let gateID: UUID?

    var isAllSamples: Bool {
        sampleID == Self.allSamplesID
    }
}

struct WorkspaceRow: Identifiable, Equatable {
    let id: String
    let selection: WorkspaceSelection
    let depth: Int
    let name: String
    let count: Int?
    let role: String
    let isGate: Bool
    let isGroupGate: Bool
    let isSynced: Bool
}

struct WorkspaceLayout: Identifiable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

final class WorkspaceGateNode: Identifiable, ObservableObject {
    let id: UUID
    var name: String
    var gate: PolygonGate
    var xChannelName: String
    var yChannelName: String
    var xTransform: TransformKind
    var yTransform: TransformKind
    var xAxisSettings: AxisDisplaySettings
    var yAxisSettings: AxisDisplaySettings
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
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil,
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
        self.xAxisSettings = xAxisSettings ?? AxisDisplaySettings(transform: xTransform)
        self.yAxisSettings = yAxisSettings ?? AxisDisplaySettings(transform: yTransform)
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
            xAxisSettings: xAxisSettings,
            yAxisSettings: yAxisSettings,
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
    @Published var groupGates: [WorkspaceGateNode] = []
    @Published var samples: [WorkspaceSample] = []
    @Published var selected: WorkspaceSelection?
    @Published var layouts: [WorkspaceLayout] = [WorkspaceLayout(name: "Layout")]
    @Published var selectedLayoutID: UUID?
    @Published private(set) var status: String = "Drop .fcs files here or add samples."
    @Published private(set) var gateChangeVersion = 0
    private var lastCreatedGate: WorkspaceSelection?
    private var plotWindowControllers: [NSWindowController] = []
    private var layoutWindowControllers: [NSWindowController] = []

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
                    isGate: false,
                    isGroupGate: false,
                    isSynced: sampleMatchesAllTemplates(sample)
                )
            ]
            appendGateRows(sample.gates, sampleID: sample.id, depth: 1, output: &output, isGroup: false)
            return output
        }
    }

    var groupRows: [WorkspaceRow] {
        var output: [WorkspaceRow] = []
        appendGateRows(groupGates, sampleID: WorkspaceSelection.allSamplesID, depth: 1, output: &output, isGroup: true)
        return output
    }

    init() {
        selectedLayoutID = layouts.first?.id
    }

    func selectedPopulation(for selection: WorkspaceSelection? = nil) -> (table: EventTable, mask: EventMask?, title: String)? {
        let resolved = selection ?? selected
        guard resolved?.isAllSamples != true else { return nil }
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
                        if !self.groupGates.isEmpty {
                            self.applyGroupTemplatesToSamples()
                        }
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

    func newWorkspace() {
        groupGates.removeAll()
        samples.removeAll()
        selected = nil
        layouts = [WorkspaceLayout(name: "Layout")]
        selectedLayoutID = layouts.first?.id
        lastCreatedGate = nil
        gateChangeVersion += 1
        status = "Started a new workspace."
    }

    func createGroup() {
        status = "All Samples is ready for group gate templates."
    }

    func openTableEditor() {
        let alert = NSAlert()
        alert.messageText = "Table Editor"
        alert.informativeText = "The workspace table is already editable for names, gates, counts, and drag-to-apply gate templates."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func openPreferences() {
        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = "Preferences will appear here as OpenFlo grows."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func addLayout() {
        let nextNumber = layouts.count + 1
        let layout = WorkspaceLayout(name: "Layout \(nextNumber)")
        layouts.append(layout)
        selectedLayoutID = layout.id
        status = "Added \(layout.name)."
    }

    func deleteSelectedLayout() {
        guard layouts.count > 1 else {
            status = "Keep at least one layout."
            return
        }
        let deleteID = selectedLayoutID ?? layouts.last?.id
        guard let deleteID, let index = layouts.firstIndex(where: { $0.id == deleteID }) else { return }
        let deletedName = layouts[index].name
        layouts.remove(at: index)
        selectedLayoutID = layouts[min(index, layouts.count - 1)].id
        status = "Deleted \(deletedName)."
    }

    func openLayoutEditor() {
        let root = LayoutEditorView(workspace: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenFlo Layouts"
        window.center()
        window.contentView = NSHostingView(rootView: root)
        let controller = NSWindowController(window: window)
        layoutWindowControllers.append(controller)
        controller.showWindow(nil)
    }

    func addGateFromPlot(
        _ gate: PolygonGate,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil,
        parentSelection: WorkspaceSelection? = nil
    ) -> WorkspaceSelection? {
        let target = parentSelection ?? selected
        guard let target, let sample = sample(id: target.sampleID) else { return nil }
        let parentMask = parentMask(for: target, in: sample)
        let resolvedXSettings = xAxisSettings ?? AxisDisplaySettings(transform: xTransform)
        let resolvedYSettings = yAxisSettings ?? AxisDisplaySettings(transform: yTransform)
        let count = evaluate(
            gate: gate,
            sample: sample,
            base: parentMask,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xAxisSettings: resolvedXSettings,
            yAxisSettings: resolvedYSettings
        ).selectedCount
        return insertGate(
            gate,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xTransform: xTransform,
            yTransform: yTransform,
            xAxisSettings: resolvedXSettings,
            yAxisSettings: resolvedYSettings,
            count: count,
            parentSelection: target,
            sample: sample
        )
    }

    private func insertGate(
        _ gate: PolygonGate,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings,
        yAxisSettings: AxisDisplaySettings,
        count: Int,
        parentSelection target: WorkspaceSelection,
        sample: WorkspaceSample
    ) -> WorkspaceSelection? {
        guard !target.isAllSamples else { return nil }
        let node = WorkspaceGateNode(
            name: uniqueGateName(gate.name, under: target),
            gate: gate,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xTransform: xTransform,
            yTransform: yTransform,
            xAxisSettings: xAxisSettings,
            yAxisSettings: yAxisSettings,
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
        gateChangeVersion += 1
        status = "Added \(node.name) gate."
        return newSelection
    }

    func applySelectedGateToAllSamples() {
        let sourceSelection = selected?.gateID == nil ? lastCreatedGate : selected
        guard let sourceSelection, let gateID = sourceSelection.gateID else {
            status = "Select a gate to apply it to all samples."
            return
        }
        copyGatesToAllSamples([gateID], target: .allSamples)
    }

    func copyGate(dragPayload: String, to target: WorkspaceSelection) {
        let gateIDs: [UUID]
        if dragPayload.hasPrefix("gates:") {
            gateIDs = dragPayload
                .dropFirst(6)
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        } else if dragPayload.hasPrefix("gate:"), let gateID = UUID(uuidString: String(dragPayload.dropFirst(5))) {
            gateIDs = [gateID]
        } else {
            return
        }
        if target.isAllSamples {
            copyGatesToAllSamples(gateIDs, target: target)
            return
        }
        copyGates(gateIDs, to: target)
    }

    private func copyGates(_ gateIDs: [UUID], to target: WorkspaceSelection) {
        let uniqueGateIDs = gateIDs.reduce(into: [UUID]()) { output, gateID in
            if !output.contains(gateID) {
                output.append(gateID)
            }
        }
        guard !uniqueGateIDs.isEmpty else { return }
        guard let targetSample = sample(id: target.sampleID) else { return }
        let selectedIDs = Set(uniqueGateIDs)
        let sourcePaths = uniqueGateIDs.enumerated().compactMap { index, gateID -> (index: Int, gateID: UUID, path: [WorkspaceGateNode])? in
            guard let source = gateSourcePath(containing: gateID) else { return nil }
            return (index: index, gateID: gateID, path: source.path)
        }
        let orderedPaths = sourcePaths.sorted {
            if $0.path.count == $1.path.count {
                return $0.index < $1.index
            }
            return $0.path.count < $1.path.count
        }
        guard !orderedPaths.isEmpty else { return }

        var copiedSelections: [UUID: WorkspaceSelection] = [:]
        for source in orderedPaths {
            guard let node = source.path.last else { continue }
            let copiedParentID = source.path.dropLast().reversed().first { selectedIDs.contains($0.id) }.flatMap { copiedSelections[$0.id]?.gateID }
            let parentSelection = WorkspaceSelection(sampleID: targetSample.id, gateID: copiedParentID ?? target.gateID)
            guard let copiedSelection = addGateFromPlot(
                node.gate,
                xChannelName: node.xChannelName,
                yChannelName: node.yChannelName,
                xTransform: node.xTransform,
                yTransform: node.yTransform,
                xAxisSettings: node.xAxisSettings,
                yAxisSettings: node.yAxisSettings,
                parentSelection: parentSelection
            ) else {
                continue
            }
            copiedSelections[source.gateID] = copiedSelection
        }
        if let selectedCopy = uniqueGateIDs.reversed().lazy.compactMap({ copiedSelections[$0] }).first {
            selected = selectedCopy
        }
        let appliedName = selectedIDs.count == 1 ? (sourcePaths.first?.path.last?.name ?? "gate") : "\(copiedSelections.count) gates"
        status = "Applied \(appliedName) to \(targetSample.name)."
    }

    private func copyGatesToAllSamples(_ gateIDs: [UUID], target: WorkspaceSelection) {
        let uniqueGateIDs = gateIDs.reduce(into: [UUID]()) { output, gateID in
            if !output.contains(gateID) {
                output.append(gateID)
            }
        }
        guard !uniqueGateIDs.isEmpty else { return }
        let selectedIDs = Set(uniqueGateIDs)
        let sourcePaths = uniqueGateIDs.enumerated().compactMap { index, gateID -> (index: Int, gateID: UUID, path: [WorkspaceGateNode])? in
            guard let source = gateSourcePath(containing: gateID) else { return nil }
            return (index: index, gateID: gateID, path: source.path)
        }
        let orderedPaths = sourcePaths.sorted {
            if $0.path.count == $1.path.count {
                return $0.index < $1.index
            }
            return $0.path.count < $1.path.count
        }
        guard !orderedPaths.isEmpty else { return }

        objectWillChange.send()
        var groupNodesBySourceID: [UUID: WorkspaceGateNode] = [:]
        var groupNodesToApply: [WorkspaceGateNode] = []
        for source in orderedPaths {
            guard let node = source.path.last else { continue }
            var parentGateID = target.gateID
            if let selectedAncestor = source.path.dropLast().reversed().first(where: { selectedIDs.contains($0.id) }),
               let copiedAncestor = groupNodesBySourceID[selectedAncestor.id] {
                parentGateID = copiedAncestor.id
            } else if target.gateID == nil {
                for ancestor in source.path.dropLast() {
                    let groupAncestor = upsertGroupGate(ancestor, parentGateID: parentGateID)
                    parentGateID = groupAncestor.id
                }
            }
            let groupNode = upsertGroupGate(node, parentGateID: parentGateID)
            groupNodesBySourceID[source.gateID] = groupNode
            if !groupNodesToApply.contains(where: { $0.id == groupNode.id }) {
                groupNodesToApply.append(groupNode)
            }
        }
        applyGroupTemplatesToSamples(groupNodesToApply)
        if let selectedGroupGate = uniqueGateIDs.reversed().lazy.compactMap({ groupNodesBySourceID[$0] }).first {
            selected = WorkspaceSelection(sampleID: WorkspaceSelection.allSamplesID, gateID: selectedGroupGate.id)
        }
        gateChangeVersion += 1
        let appliedName = selectedIDs.count == 1 ? (sourcePaths.first?.path.last?.name ?? "gate") : "\(groupNodesBySourceID.count) gates"
        status = "Applied \(appliedName) to all samples."
    }

    func dragPayload(for row: WorkspaceRow, selectedRows: [WorkspaceRow]) -> String? {
        let gateIDs = selectedRows.compactMap(\.selection.gateID)
        guard row.isGate, !gateIDs.isEmpty else { return nil }
        if gateIDs.count == 1, let gateID = gateIDs.first {
            return "gate:\(gateID.uuidString)"
        }
        return "gates:\(gateIDs.map(\.uuidString).joined(separator: ","))"
    }

    func openPlotWindow(for selection: WorkspaceSelection) {
        guard !selection.isAllSamples else { return }
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
            yTransform: config?.yTransform ?? AppModel.defaultTransform(for: sample.table.channels[yIndex]),
            xAxisSettings: config?.xAxisSettings,
            yAxisSettings: config?.yAxisSettings
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
        if selection.isAllSamples {
            guard let gateID = selection.gateID else { return nil }
            if let parentGateID = parentGateID(of: gateID, in: groupGates, parent: nil) {
                return WorkspaceSelection(sampleID: WorkspaceSelection.allSamplesID, gateID: parentGateID)
            }
            return .allSamples
        }
        guard let gateID = selection.gateID, let sample = sample(id: selection.sampleID) else { return nil }
        if let parentGateID = parentGateID(of: gateID, in: sample.gates, parent: nil) {
            return WorkspaceSelection(sampleID: sample.id, gateID: parentGateID)
        }
        return WorkspaceSelection(sampleID: sample.id, gateID: nil)
    }

    func adjacentSampleSelection(from selection: WorkspaceSelection, offset: Int) -> WorkspaceSelection? {
        guard samples.count > 1,
              let currentIndex = samples.firstIndex(where: { $0.id == selection.sampleID }) else {
            return nil
        }
        let targetIndex = (currentIndex + offset + samples.count) % samples.count
        let targetSample = samples[targetIndex]
        guard let gateID = selection.gateID,
              let sourceSample = sample(id: selection.sampleID),
              let sourcePath = gatePath(gateID, in: sourceSample.gates) else {
            return WorkspaceSelection(sampleID: targetSample.id, gateID: nil)
        }
        let matchedGate = gateMatchingPath(sourcePath.map(\.name), in: targetSample.gates)
        return WorkspaceSelection(sampleID: targetSample.id, gateID: matchedGate?.id)
    }

    func gateConfiguration(for selection: WorkspaceSelection) -> (
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings,
        yAxisSettings: AxisDisplaySettings
    )? {
        if selection.isAllSamples {
            guard let gateID = selection.gateID, let node = gate(id: gateID, in: groupGates) else { return nil }
            return (node.xChannelName, node.yChannelName, node.xTransform, node.yTransform, node.xAxisSettings, node.yAxisSettings)
        }
        guard let gateID = selection.gateID, let sample = sample(id: selection.sampleID), let node = gate(id: gateID, in: sample.gates) else {
            return nil
        }
        return (node.xChannelName, node.yChannelName, node.xTransform, node.yTransform, node.xAxisSettings, node.yAxisSettings)
    }

    func gateDefinition(for selection: WorkspaceSelection) -> PolygonGate? {
        if selection.isAllSamples {
            guard let gateID = selection.gateID, let node = gate(id: gateID, in: groupGates) else { return nil }
            return node.gate
        }
        guard let gateID = selection.gateID, let sample = sample(id: selection.sampleID), let node = gate(id: gateID, in: sample.gates) else {
            return nil
        }
        return node.gate
    }

    func contains(_ selection: WorkspaceSelection) -> Bool {
        if selection.isAllSamples {
            guard let gateID = selection.gateID else { return true }
            return gate(id: gateID, in: groupGates) != nil
        }
        guard let sample = sample(id: selection.sampleID) else { return false }
        guard let gateID = selection.gateID else { return true }
        return gate(id: gateID, in: sample.gates) != nil
    }

    func gateForAxes(
        parentSelection: WorkspaceSelection,
        preferredSelection: WorkspaceSelection?,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil
    ) -> (selection: WorkspaceSelection, gate: PolygonGate)? {
        guard !parentSelection.isAllSamples else { return nil }
        guard let sample = sample(id: parentSelection.sampleID) else { return nil }
        if let preferredSelection,
           self.parentSelection(of: preferredSelection) == parentSelection,
           let gateID = preferredSelection.gateID,
           let preferredGate = gate(id: gateID, in: sample.gates),
           gateMatchesAxes(
               preferredGate,
               xChannelName: xChannelName,
               yChannelName: yChannelName,
               xTransform: xTransform,
               yTransform: yTransform,
               xAxisSettings: xAxisSettings,
               yAxisSettings: yAxisSettings
           ) {
            return (preferredSelection, preferredGate.gate)
        }

        let candidates: [WorkspaceGateNode]
        if let parentGateID = parentSelection.gateID, let parent = gate(id: parentGateID, in: sample.gates) {
            candidates = parent.children
        } else {
            candidates = sample.gates
        }
        guard let match = candidates.last(where: {
            gateMatchesAxes(
                $0,
                xChannelName: xChannelName,
                yChannelName: yChannelName,
                xTransform: xTransform,
                yTransform: yTransform,
                xAxisSettings: xAxisSettings,
                yAxisSettings: yAxisSettings
            )
        }) else {
            return nil
        }
        return (WorkspaceSelection(sampleID: sample.id, gateID: match.id), match.gate)
    }

    func gatesForAxes(
        parentSelection: WorkspaceSelection,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil
    ) -> [(selection: WorkspaceSelection, gate: PolygonGate)] {
        guard !parentSelection.isAllSamples else { return [] }
        guard let sample = sample(id: parentSelection.sampleID) else { return [] }
        let candidates: [WorkspaceGateNode]
        if let parentGateID = parentSelection.gateID, let parent = gate(id: parentGateID, in: sample.gates) {
            candidates = parent.children
        } else {
            candidates = sample.gates
        }
        return candidates.compactMap { node in
            guard gateMatchesAxes(
                node,
                xChannelName: xChannelName,
                yChannelName: yChannelName,
                xTransform: xTransform,
                yTransform: yTransform,
                xAxisSettings: xAxisSettings,
                yAxisSettings: yAxisSettings
            ) else {
                return nil
            }
            return (WorkspaceSelection(sampleID: sample.id, gateID: node.id), node.gate)
        }
    }

    func rename(_ selection: WorkspaceSelection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection.isAllSamples {
            guard !trimmed.isEmpty, let gateID = selection.gateID, let gate = gate(id: gateID, in: groupGates) else { return }
            objectWillChange.send()
            gate.name = trimmed
            applyGroupTemplatesToSamples()
            gateChangeVersion += 1
            status = "Renamed all-samples gate."
            return
        }
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
        if selection.isAllSamples {
            guard let gateID = selection.gateID else { return }
            objectWillChange.send()
            _ = removeGate(gateID, from: &groupGates)
            selected = nil
            gateChangeVersion += 1
            status = "Deleted all-samples gate."
            return
        }
        guard let sampleIndex = samples.firstIndex(where: { $0.id == selection.sampleID }) else { return }
        objectWillChange.send()
        if let gateID = selection.gateID {
            _ = removeGate(gateID, from: &samples[sampleIndex].gates)
            selected = WorkspaceSelection(sampleID: samples[sampleIndex].id, gateID: nil)
            gateChangeVersion += 1
            status = "Deleted gate."
        } else {
            samples.remove(at: sampleIndex)
            selected = samples.first.map { WorkspaceSelection(sampleID: $0.id, gateID: nil) }
            gateChangeVersion += 1
            status = "Removed sample."
        }
    }

    func updateGate(
        _ selection: WorkspaceSelection,
        gate updatedGate: PolygonGate,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil
    ) {
        guard !selection.isAllSamples else { return }
        guard let sample = sample(id: selection.sampleID), let gateID = selection.gateID, let node = gate(id: gateID, in: sample.gates) else { return }
        objectWillChange.send()
        node.gate = updatedGate
        node.xChannelName = xChannelName
        node.yChannelName = yChannelName
        node.xTransform = xTransform
        node.yTransform = yTransform
        node.xAxisSettings = xAxisSettings ?? AxisDisplaySettings(transform: xTransform)
        node.yAxisSettings = yAxisSettings ?? AxisDisplaySettings(transform: yTransform)
        gateChangeVersion += 1
    }

    func refreshCount(for selection: WorkspaceSelection) {
        guard !selection.isAllSamples else { return }
        guard let sample = sample(id: selection.sampleID), let gateID = selection.gateID, let node = gate(id: gateID, in: sample.gates) else { return }
        refreshCount(for: node, in: sample)
    }

    func rowID(sampleID: UUID, gateID: UUID?) -> String {
        if let gateID {
            return "\(sampleID.uuidString):\(gateID.uuidString)"
        }
        return sampleID.uuidString
    }

    private func appendGateRows(
        _ gates: [WorkspaceGateNode],
        sampleID: UUID,
        depth: Int,
        output: inout [WorkspaceRow],
        isGroup: Bool,
        path: [WorkspaceGateNode] = []
    ) {
        for gate in gates {
            let currentPath = path + [gate]
            output.append(
                WorkspaceRow(
                    id: rowID(sampleID: sampleID, gateID: gate.id),
                    selection: WorkspaceSelection(sampleID: sampleID, gateID: gate.id),
                    depth: depth,
                    name: gate.name,
                    count: isGroup ? nil : gate.count,
                    role: isGroup ? "Template" : "Gate",
                    isGate: true,
                    isGroupGate: isGroup,
                    isSynced: isGroup ? allSamplesMatchTemplate(path: currentPath) : sampleGateMatchesTemplate(path: currentPath)
                )
            )
            appendGateRows(gate.children, sampleID: sampleID, depth: depth + 1, output: &output, isGroup: isGroup, path: currentPath)
        }
    }

    private func sample(id: UUID) -> WorkspaceSample? {
        samples.first { $0.id == id }
    }

    private func upsertGroupGate(_ source: WorkspaceGateNode, parentGateID: UUID?) -> WorkspaceGateNode {
        let siblings: [WorkspaceGateNode]
        if let parentGateID, let parent = gate(id: parentGateID, in: groupGates) {
            siblings = parent.children
        } else {
            siblings = groupGates
        }
        if let existing = siblings.first(where: { $0.name == source.name }) {
            update(existing, from: source)
            return existing
        }
        let node = shallowClone(source, count: nil)
        if let parentGateID, let parent = gate(id: parentGateID, in: groupGates) {
            parent.children.append(node)
        } else {
            groupGates.append(node)
        }
        return node
    }

    private func applyGroupTemplatesToSamples() {
        guard !groupGates.isEmpty else { return }
        for sample in samples {
            for template in groupGates {
                let node = upsertTemplate(template, into: &sample.gates)
                refreshCounts(for: node, in: sample)
            }
        }
    }

    private func applyGroupTemplatesToSamples(_ templates: [WorkspaceGateNode]) {
        for template in templates {
            guard let templatePath = gatePath(template.id, in: groupGates), !templatePath.isEmpty else { continue }
            for sample in samples {
                _ = upsertTemplatePath(templatePath, into: &sample.gates)
                if let rootTemplate = templatePath.first,
                   let rootGate = gateMatchingPath([rootTemplate.name], in: sample.gates) {
                    refreshCounts(for: rootGate, in: sample)
                }
            }
        }
    }

    private func upsertTemplate(_ template: WorkspaceGateNode, into siblings: inout [WorkspaceGateNode]) -> WorkspaceGateNode {
        if let index = siblings.firstIndex(where: { $0.name == template.name }) {
            let node = siblings[index]
            update(node, from: template)
            for childTemplate in template.children {
                _ = upsertTemplate(childTemplate, into: &node.children)
            }
            return node
        }
        let node = template.clone()
        clearCounts(in: node)
        siblings.append(node)
        return node
    }

    private func upsertTemplatePath(_ path: [WorkspaceGateNode], into siblings: inout [WorkspaceGateNode]) -> WorkspaceGateNode? {
        guard let template = path.first else { return nil }
        if path.count == 1 {
            return upsertTemplateNode(template, into: &siblings)
        }
        let parent: WorkspaceGateNode
        if let index = siblings.firstIndex(where: { $0.name == template.name }) {
            parent = siblings[index]
        } else {
            parent = shallowClone(template, count: nil)
            siblings.append(parent)
        }
        return upsertTemplatePath(Array(path.dropFirst()), into: &parent.children)
    }

    private func upsertTemplateNode(_ template: WorkspaceGateNode, into siblings: inout [WorkspaceGateNode]) -> WorkspaceGateNode {
        if let index = siblings.firstIndex(where: { $0.name == template.name }) {
            let node = siblings[index]
            update(node, from: template)
            return node
        }
        let node = shallowClone(template, count: nil)
        siblings.append(node)
        return node
    }

    private func shallowClone(_ source: WorkspaceGateNode, count: Int?) -> WorkspaceGateNode {
        WorkspaceGateNode(
            name: source.name,
            gate: source.gate,
            xChannelName: source.xChannelName,
            yChannelName: source.yChannelName,
            xTransform: source.xTransform,
            yTransform: source.yTransform,
            xAxisSettings: source.xAxisSettings,
            yAxisSettings: source.yAxisSettings,
            count: count
        )
    }

    private func update(_ node: WorkspaceGateNode, from source: WorkspaceGateNode) {
        node.gate = source.gate
        node.xChannelName = source.xChannelName
        node.yChannelName = source.yChannelName
        node.xTransform = source.xTransform
        node.yTransform = source.yTransform
        node.xAxisSettings = source.xAxisSettings
        node.yAxisSettings = source.yAxisSettings
        node.count = nil
    }

    private func clearCounts(in node: WorkspaceGateNode) {
        node.count = nil
        for child in node.children {
            clearCounts(in: child)
        }
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

    private func gateMatchingPath(_ names: [String], in gates: [WorkspaceGateNode]) -> WorkspaceGateNode? {
        guard let firstName = names.first else { return nil }
        for gate in gates where gate.name == firstName {
            if names.count == 1 {
                return gate
            }
            if let match = gateMatchingPath(Array(names.dropFirst()), in: gate.children) {
                return match
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

    private func gateSourcePath(containing id: UUID) -> (isGroup: Bool, path: [WorkspaceGateNode])? {
        if let path = gatePath(id, in: groupGates) {
            return (true, path)
        }
        if let source = sampleAndGatePath(containing: id) {
            return (false, source.path)
        }
        return nil
    }

    private func cloneIncludedSubtree(
        _ node: WorkspaceGateNode,
        includedIDs: Set<UUID>,
        clonesBySourceID: inout [UUID: WorkspaceGateNode]
    ) -> WorkspaceGateNode? {
        let children = node.children.compactMap { child in
            cloneIncludedSubtree(child, includedIDs: includedIDs, clonesBySourceID: &clonesBySourceID)
        }
        guard includedIDs.contains(node.id) || !children.isEmpty else { return nil }
        let clone = WorkspaceGateNode(
            name: node.name,
            gate: node.gate,
            xChannelName: node.xChannelName,
            yChannelName: node.yChannelName,
            xTransform: node.xTransform,
            yTransform: node.yTransform,
            xAxisSettings: node.xAxisSettings,
            yAxisSettings: node.yAxisSettings,
            count: nil,
            children: children
        )
        clonesBySourceID[node.id] = clone
        return clone
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
                xAxisSettings: node.xAxisSettings,
                yAxisSettings: node.yAxisSettings
            )
        }
        return mask ?? EventMask(count: sample.table.rowCount, fill: true)
    }

    private func parentMask(for selection: WorkspaceSelection, in sample: WorkspaceSample) -> EventMask? {
        selection.gateID.flatMap { gateID in
            gatePath(gateID, in: sample.gates).map { evaluate(path: $0, sample: sample) }
        }
    }

    private func evaluate(
        gate: PolygonGate,
        sample: WorkspaceSample,
        base: EventMask?,
        xChannelName: String,
        yChannelName: String,
        xAxisSettings: AxisDisplaySettings,
        yAxisSettings: AxisDisplaySettings
    ) -> EventMask {
        let xIndex = channelIndex(named: xChannelName, in: sample.table) ?? AppModel.defaultAxisSelection(for: sample.table).x
        let yIndex = channelIndex(named: yChannelName, in: sample.table) ?? AppModel.defaultAxisSelection(for: sample.table).y
        let xValues = Self.applyTransform(xAxisSettings, to: sample.table.column(xIndex))
        let yValues = Self.applyTransform(yAxisSettings, to: sample.table.column(yIndex))
        return gate.evaluate(xValues: xValues, yValues: yValues, base: base)
    }

    private nonisolated static func applyTransform(_ settings: AxisDisplaySettings, to values: [Float]) -> [Float] {
        settings.transform.apply(
            to: values,
            cofactor: pow(Float(10), settings.widthBasis),
            extraNegativeDecades: settings.extraNegativeDecades,
            widthBasis: settings.widthBasis,
            positiveDecades: settings.positiveDecades
        )
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

    private func sampleMatchesAllTemplates(_ sample: WorkspaceSample) -> Bool {
        guard !groupGates.isEmpty else { return false }
        return groupGates.allSatisfy { template in
            guard let sampleGate = gateMatchingPath([template.name], in: sample.gates) else { return false }
            return gateEquivalent(sampleGate, template)
        }
    }

    private func sampleGateMatchesTemplate(path: [WorkspaceGateNode]) -> Bool {
        guard let template = gateMatchingPath(path.map(\.name), in: groupGates), let sampleGate = path.last else { return false }
        return gateEquivalent(sampleGate, template)
    }

    private func allSamplesMatchTemplate(path: [WorkspaceGateNode]) -> Bool {
        guard !samples.isEmpty, let template = path.last else { return false }
        let names = path.map(\.name)
        return samples.allSatisfy { sample in
            guard let sampleGate = gateMatchingPath(names, in: sample.gates) else { return false }
            return gateEquivalent(sampleGate, template)
        }
    }

    private func gateEquivalent(_ lhs: WorkspaceGateNode, _ rhs: WorkspaceGateNode) -> Bool {
        lhs.gate == rhs.gate
            && channelNamesMatch(lhs.xChannelName, rhs.xChannelName)
            && channelNamesMatch(lhs.yChannelName, rhs.yChannelName)
            && lhs.xTransform == rhs.xTransform
            && lhs.yTransform == rhs.yTransform
            && lhs.xAxisSettings.matchesTransformParameters(rhs.xAxisSettings)
            && lhs.yAxisSettings.matchesTransformParameters(rhs.yAxisSettings)
    }

    private func gateMatchesAxes(
        _ node: WorkspaceGateNode,
        xChannelName: String,
        yChannelName: String,
        xTransform: TransformKind,
        yTransform: TransformKind,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil
    ) -> Bool {
        let resolvedXSettings = xAxisSettings ?? AxisDisplaySettings(transform: xTransform)
        let resolvedYSettings = yAxisSettings ?? AxisDisplaySettings(transform: yTransform)
        return channelNamesMatch(node.xChannelName, xChannelName)
            && channelNamesMatch(node.yChannelName, yChannelName)
            && node.xTransform == xTransform
            && node.yTransform == yTransform
            && node.xAxisSettings.matchesTransformParameters(resolvedXSettings)
            && node.yAxisSettings.matchesTransformParameters(resolvedYSettings)
    }

    private func channelIndex(named name: String, in table: EventTable) -> Int? {
        let normalizedName = normalizedChannelName(name)
        return table.channels.firstIndex { channel in
            channel.name == name
                || channel.displayName == name
                || normalizedChannelName(channel.name) == normalizedName
                || normalizedChannelName(channel.displayName) == normalizedName
        }
    }

    private func channelNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || normalizedChannelName(lhs) == normalizedChannelName(rhs)
    }

    private func normalizedChannelName(_ name: String) -> String {
        name.uppercased().filter { $0.isLetter || $0.isNumber }
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
