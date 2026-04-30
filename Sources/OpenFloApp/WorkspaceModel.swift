import AppKit
import Foundation
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSelection: Codable, Equatable, Hashable, Sendable {
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
    let compensationBadge: WorkspaceCompensationBadge?
}

struct WorkspaceCompensationBadge: Equatable {
    enum Style: Equatable {
        case assignedAcquisition
        case assignedUser
        case available
        case error
    }

    let matrixID: UUID?
    let style: Style
    let colorHex: String?
    let tooltip: String
}

struct WorkspaceLayout: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [WorkspaceLayoutItem]
    var zoom: Double
    var showGrid: Bool
    var showPageBreaks: Bool
    var iterationMode: LayoutIterationMode
    var iterationSampleID: UUID?
    var batchDestination: LayoutBatchDestination
    var batchAxis: LayoutBatchAxis
    var batchCount: Int
    var batchAcross: Bool

    init(
        id: UUID = UUID(),
        name: String,
        items: [WorkspaceLayoutItem] = [],
        zoom: Double = 1,
        showGrid: Bool = false,
        showPageBreaks: Bool = true,
        iterationMode: LayoutIterationMode = .off,
        iterationSampleID: UUID? = nil,
        batchDestination: LayoutBatchDestination = .layout,
        batchAxis: LayoutBatchAxis = .columns,
        batchCount: Int = 3,
        batchAcross: Bool = true
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.zoom = zoom
        self.showGrid = showGrid
        self.showPageBreaks = showPageBreaks
        self.iterationMode = iterationMode
        self.iterationSampleID = iterationSampleID
        self.batchDestination = batchDestination
        self.batchAxis = batchAxis
        self.batchCount = batchCount
        self.batchAcross = batchAcross
    }
}

struct WorkspaceProgress: Equatable {
    let title: String
    let detail: String
    let fraction: Double?
}

struct LayoutGateRenderStep: Sendable {
    let gate: PolygonGate
    let xIndex: Int
    let yIndex: Int
    let xAxisSettings: AxisDisplaySettings
    let yAxisSettings: AxisDisplaySettings
}

struct LayoutPlotRenderPayload: Sendable {
    let table: EventTable
    let sampleKind: WorkspaceSampleKind
    let mask: EventMask?
    let gateSteps: [LayoutGateRenderStep]
    let sampleName: String
    let populationName: String
    let eventCount: Int
    let xIndex: Int
    let yIndex: Int
    let xAxisSettings: AxisDisplaySettings
    let yAxisSettings: AxisDisplaySettings
    let mode: PlotMode
    let ancestry: [String]
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
    let kind: WorkspaceSampleKind
    @Published var name: String
    var rawTable: EventTable
    @Published var table: EventTable
    var metadata: FCSMetadata?
    @Published var compensationMatrixID: UUID?
    var acquisitionCompensationMatrixID: UUID?
    @Published var gates: [WorkspaceGateNode]

    init(
        id: UUID = UUID(),
        name: String,
        url: URL?,
        kind: WorkspaceSampleKind,
        rawTable: EventTable? = nil,
        table: EventTable,
        metadata: FCSMetadata? = nil,
        compensationMatrixID: UUID? = nil,
        acquisitionCompensationMatrixID: UUID? = nil,
        gates: [WorkspaceGateNode] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.kind = kind
        self.rawTable = rawTable ?? table
        self.table = table
        self.metadata = metadata
        self.compensationMatrixID = compensationMatrixID
        self.acquisitionCompensationMatrixID = acquisitionCompensationMatrixID
        self.gates = gates
    }
}

enum WorkspaceSampleKind: String, Codable, Equatable, Sendable {
    case fcs
    case singleCell

    var rowLabel: String {
        switch self {
        case .fcs:
            return "Events"
        case .singleCell:
            return "Cells"
        }
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var groupGates: [WorkspaceGateNode] = []
    @Published var samples: [WorkspaceSample] = []
    @Published var compensationMatrices: [CompensationMatrix] = []
    @Published var autoApplyAcquisitionCompensation = true
    @Published var selected: WorkspaceSelection?
    @Published var layouts: [WorkspaceLayout] = [WorkspaceLayout(name: "Layout")]
    @Published var selectedLayoutID: UUID?
    @Published private(set) var status: String = "Drop .fcs or single-cell files here or add samples."
    @Published private(set) var progress: WorkspaceProgress?
    @Published private(set) var gateChangeVersion = 0 {
        didSet {
            layoutPlotSnapshotCache.removeAll()
        }
    }
    private var lastCreatedGate: WorkspaceSelection?
    private var plotWindowControllers: [NSWindowController] = []
    private var layoutWindowControllers: [NSWindowController] = []
    private var tableWindowControllers: [NSWindowController] = []
    private var layoutPlotSnapshotCache: [String: LayoutPlotSnapshot] = [:]
    private var gateMaskCache: [String: EventMask] = [:]
    private var channelIndexLookupCache: [ObjectIdentifier: [String: Int]] = [:]
    private var signatureChannelNameCache: [ObjectIdentifier: [String]] = [:]
    private var lastGraphDisplayStateBySelectionKey: [String: WorkspaceGraphDisplayState] = [:]
    private var loadedSignatures: [SeqtometrySignature] = []
    private var activeProgressID: UUID?

    var rows: [WorkspaceRow] {
        samples.flatMap { sample in
            var output = [
                WorkspaceRow(
                    id: rowID(sampleID: sample.id, gateID: nil),
                    selection: WorkspaceSelection(sampleID: sample.id, gateID: nil),
                    depth: 0,
                    name: sample.name,
                    count: sample.table.rowCount,
                    role: sample.kind.rowLabel,
                    isGate: false,
                    isGroupGate: false,
                    isSynced: sampleMatchesAllTemplates(sample),
                    compensationBadge: compensationBadge(for: sample)
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

    var compensationGroupSampleCount: Int {
        samples.filter(isCompensationControlSample).count
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
            let progressID = beginProgress(
                title: "Loading Sample",
                detail: "Reading \(url.lastPathComponent)",
                fraction: nil
            )
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try FCSParser.load(url: url)
                    Task { @MainActor in
                        let sample = WorkspaceSample(
                            name: url.lastPathComponent,
                            url: url,
                            kind: .fcs,
                            rawTable: file.table,
                            table: file.table,
                            metadata: file.metadata
                        )
                        self.samples.append(sample)
                        var compensationStatus = ""
                        if let acquisition = file.acquisitionCompensation {
                            let matrixID = self.addOrReuseMatrix(acquisition)
                            sample.acquisitionCompensationMatrixID = matrixID
                            if self.autoApplyAcquisitionCompensation {
                                do {
                                    try self.assignCompensation(matrixID, to: sample.id)
                                    compensationStatus = " Acquisition compensation applied."
                                } catch {
                                    compensationStatus = " Acquisition compensation could not be applied: \(error.localizedDescription)"
                                }
                            } else {
                                compensationStatus = " Acquisition compensation is available."
                            }
                        }
                        if !self.groupGates.isEmpty {
                            self.applyGroupTemplatesToSamples()
                        }
                        if self.selected == nil {
                            self.selected = WorkspaceSelection(sampleID: sample.id, gateID: nil)
                        }
                        self.finishProgress(progressID, status: "Loaded \(url.lastPathComponent).\(compensationStatus)")
                    }
                } catch {
                    Task { @MainActor in
                        self.finishProgress(progressID, status: "Could not load \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func addDataURLs(_ urls: [URL]) {
        let fcsURLs = urls.filter { $0.pathExtension.lowercased() == "fcs" }
        let signatureURLs = urls.filter { SeqtometrySignatureParser.isLikelySignatureFile(url: $0) }
        let singleCellURLs = urls.filter { url in
            !fcsURLs.contains(url) && !signatureURLs.contains(url)
        }

        addFCSURLs(fcsURLs)
        addSignatureURLs(signatureURLs)
        addSingleCellURLs(singleCellURLs)
    }

    func addSingleCellURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let signatureSet = chooseSignaturesForSingleCellLoad(matrixURLs: urls) else {
            status = "Single-cell import canceled."
            return
        }
        mergeSignatures(signatureSet.addedSignatures)
        let signatures = signatureSet.signatures
        status = "Loading \(urls.count) single-cell file(s)..."

        for url in urls {
            let progressID = beginProgress(
                title: "Loading Single-Cell Sample",
                detail: "Reading \(url.lastPathComponent)",
                fraction: nil
            )
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try SingleCellDataParser.load(url: url)
                    Task { @MainActor in
                        self.updateProgress(
                            progressID,
                            title: "Loading Single-Cell Sample",
                            detail: "Parsed \(file.table.rowCount.formatted()) cells and \(file.table.channelCount.formatted()) genes",
                            fraction: signatures.isEmpty ? 0.75 : 0.25
                        )
                    }
                    let table = signatures.isEmpty
                        ? file.table
                        : try SeqtometryScorer.tableByAppendingScores(
                            to: file.table,
                            signatures: signatures,
                            progress: { progress in
                                Task { @MainActor in
                                    self.updateScoringProgress(
                                        progressID,
                                        sampleName: url.lastPathComponent,
                                        progress: progress,
                                        lowerBound: 0.25,
                                        upperBound: 0.96
                                    )
                                }
                            }
                        )
                    Task { @MainActor in
                        let sample = WorkspaceSample(name: url.lastPathComponent, url: url, kind: .singleCell, table: table)
                        self.samples.append(sample)
                        if !self.groupGates.isEmpty {
                            self.applyGroupTemplatesToSamples()
                        }
                        if self.selected == nil {
                            self.selected = WorkspaceSelection(sampleID: sample.id, gateID: nil)
                        }
                        if signatures.isEmpty {
                            self.finishProgress(
                                progressID,
                                status: "Loaded \(url.lastPathComponent). Drop a Seqtometry signature file to add score channels."
                            )
                        } else {
                            let source = signatureSet.sourceName.map { " from \($0)" } ?? ""
                            self.finishProgress(
                                progressID,
                                status: "Loaded \(url.lastPathComponent) with \(signatures.count) signature score channel(s)\(source)."
                            )
                        }
                    }
                } catch {
                    Task { @MainActor in
                        self.finishProgress(progressID, status: "Could not load \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func addSignatureURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        status = "Loading \(urls.count) Seqtometry signature file(s)..."

        for url in urls {
            do {
                let signatures = try SeqtometrySignatureParser.load(url: url)
                mergeSignatures(signatures)
                applySignaturesToSingleCellSamples(signatures, sourceName: url.lastPathComponent)
            } catch {
                status = "Could not load \(url.lastPathComponent): \(error.localizedDescription)"
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

    func openSingleCellPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        addSingleCellURLs(panel.urls)
    }

    func openSignaturePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let types = ["tsv", "csv", "txt", "gmt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return }
        addSignatureURLs(panel.urls)
    }

    func downloadSeqtometryDemo() {
        let progressID = beginProgress(
            title: "Loading Demo Dataset",
            detail: "Downloading PBMC3k demo data",
            fraction: nil
        )
        Task {
            do {
                let signatures = try bundledSeqtometrySignatures()
                mergeSignatures(signatures)
                let matrixDirectory = try await SeqtometryDemoDownloader.pbmc3kMatrixDirectory()
                updateProgress(
                    progressID,
                    title: "Loading Demo Dataset",
                    detail: "Reading PBMC3k matrix",
                    fraction: 0.18
                )
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let file = try SingleCellDataParser.load(url: matrixDirectory)
                        let table = try SeqtometryScorer.tableByAppendingScores(
                            to: file.table,
                            signatures: signatures,
                            progress: { progress in
                                Task { @MainActor in
                                    self.updateScoringProgress(
                                        progressID,
                                        sampleName: "PBMC3k demo",
                                        progress: progress,
                                        lowerBound: 0.25,
                                        upperBound: 0.96
                                    )
                                }
                            }
                        )
                        Task { @MainActor in
                            let sample = WorkspaceSample(
                                name: "PBMC3k Seqtometry Demo",
                                url: matrixDirectory,
                                kind: .singleCell,
                                rawTable: table,
                                table: table
                            )
                            self.samples.append(sample)
                            if !self.groupGates.isEmpty {
                                self.applyGroupTemplatesToSamples()
                            }
                            if self.selected == nil {
                                self.selected = WorkspaceSelection(sampleID: sample.id, gateID: nil)
                            }
                            self.finishProgress(
                                progressID,
                                status: "Loaded PBMC3k demo with \(signatures.count) signature score channel(s)."
                            )
                        }
                    } catch {
                        Task { @MainActor in
                            self.finishProgress(progressID, status: "Could not load PBMC3k demo: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                finishProgress(progressID, status: "Could not load PBMC3k demo: \(error.localizedDescription)")
            }
        }
    }

    func newWorkspace() {
        groupGates.removeAll()
        samples.removeAll()
        compensationMatrices.removeAll()
        selected = nil
        layouts = [WorkspaceLayout(name: "Layout")]
        selectedLayoutID = layouts.first?.id
        lastCreatedGate = nil
        layoutPlotSnapshotCache.removeAll()
        gateMaskCache.removeAll()
        lastGraphDisplayStateBySelectionKey.removeAll()
        loadedSignatures.removeAll()
        progress = nil
        activeProgressID = nil
        gateChangeVersion += 1
        status = "Started a new workspace."
    }

    func saveWorkspacePanel() {
        let panel = NSSavePanel()
        panel.title = "Save OpenFlo Workspace"
        panel.nameFieldStringValue = "OpenFlo Workspace.openflo"
        panel.allowedContentTypes = [UTType(filenameExtension: "openflo") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saveWorkspace(url: url)
            status = "Saved workspace \(url.lastPathComponent)."
        } catch {
            status = "Could not save workspace: \(error.localizedDescription)"
        }
    }

    func openWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.title = "Open OpenFlo Workspace"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "openflo") ?? .json, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadWorkspace(url: url)
    }

    func saveWorkspace(url: URL) throws {
        let document = WorkspaceDocument(
            samples: samples.map { sample in
                WorkspaceSampleSnapshot(
                    id: sample.id,
                    name: sample.name,
                    urlPath: sample.url?.path,
                    kind: sample.kind,
                    gates: sample.gates.map { WorkspaceGateSnapshot(node: $0) },
                    compensationMatrixID: sample.compensationMatrixID
                )
            },
            groupGates: groupGates.map { WorkspaceGateSnapshot(node: $0) },
            layouts: layouts,
            selectedLayoutID: selectedLayoutID,
            lastGraphDisplayStates: lastGraphDisplayStateBySelectionKey,
            compensationMatrices: compensationMatrices
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    func loadWorkspace(url: URL) {
        status = "Opening \(url.lastPathComponent)..."
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let document = try JSONDecoder().decode(WorkspaceDocument.self, from: data)
                var loadedSamples: [WorkspaceSample] = []
                var loadedMatrices = document.compensationMatrices
                var missingSamples: [String] = []
                var compensationWarnings: [String] = []

                func addOrReuseLocalMatrix(_ matrix: CompensationMatrix) -> UUID {
                    if let existing = loadedMatrices.first(where: {
                        $0.parameters == matrix.parameters
                            && $0.percent == matrix.percent
                            && $0.source == matrix.source
                            && $0.locked == matrix.locked
                    }) {
                        return existing.id
                    }
                    loadedMatrices.append(matrix)
                    return matrix.id
                }

                for sampleSnapshot in document.samples {
                    guard let path = sampleSnapshot.urlPath else {
                        missingSamples.append(sampleSnapshot.name)
                        continue
                    }
                    let sampleURL = URL(fileURLWithPath: path)
                    do {
                        let rawTable: EventTable
                        var effectiveTable: EventTable
                        var metadata: FCSMetadata?
                        var acquisitionMatrixID: UUID?
                        switch sampleSnapshot.kind {
                        case .fcs:
                            let file = try FCSParser.load(url: sampleURL)
                            rawTable = file.table
                            effectiveTable = file.table
                            metadata = file.metadata
                            if let acquisition = file.acquisitionCompensation {
                                acquisitionMatrixID = addOrReuseLocalMatrix(acquisition)
                            }
                        case .singleCell:
                            rawTable = try SingleCellDataParser.load(url: sampleURL).table
                            effectiveTable = rawTable
                        }

                        var compensationMatrixID = sampleSnapshot.compensationMatrixID
                        if let matrixID = compensationMatrixID {
                            if let matrix = loadedMatrices.first(where: { $0.id == matrixID }) {
                                do {
                                    effectiveTable = try CompensationEngine.apply(matrix, to: rawTable)
                                } catch {
                                    compensationMatrixID = nil
                                    compensationWarnings.append("\(sampleSnapshot.name): \(error.localizedDescription)")
                                }
                            } else {
                                compensationMatrixID = nil
                                compensationWarnings.append("\(sampleSnapshot.name): saved compensation matrix was missing")
                            }
                        }
                        let sample = WorkspaceSample(
                            id: sampleSnapshot.id,
                            name: sampleSnapshot.name,
                            url: sampleURL,
                            kind: sampleSnapshot.kind,
                            rawTable: rawTable,
                            table: effectiveTable,
                            metadata: metadata,
                            compensationMatrixID: compensationMatrixID,
                            acquisitionCompensationMatrixID: acquisitionMatrixID,
                            gates: sampleSnapshot.gates.map { $0.node() }
                        )
                        loadedSamples.append(sample)
                    } catch {
                        missingSamples.append(sampleSnapshot.name)
                    }
                }

                Task { @MainActor in
                    self.groupGates = document.groupGates.map { $0.node() }
                    self.samples = loadedSamples
                    self.compensationMatrices = loadedMatrices
                    self.layouts = document.layouts.isEmpty ? [WorkspaceLayout(name: "Layout")] : document.layouts
                    self.selectedLayoutID = document.selectedLayoutID ?? self.layouts.first?.id
                    self.selected = self.samples.first.map { WorkspaceSelection(sampleID: $0.id, gateID: nil) }
                    for sample in self.samples {
                        self.refreshCounts(in: sample)
                    }
                    self.lastGraphDisplayStateBySelectionKey = document.lastGraphDisplayStates
                    self.gateChangeVersion += 1
                    if !compensationWarnings.isEmpty {
                        self.status = "Opened workspace with \(compensationWarnings.count) compensation warning\(compensationWarnings.count == 1 ? "" : "s")."
                    } else if missingSamples.isEmpty {
                        self.status = "Opened workspace \(url.lastPathComponent)."
                    } else {
                        self.status = "Opened workspace with \(missingSamples.count) missing sample reference\(missingSamples.count == 1 ? "" : "s")."
                    }
                }
            } catch {
                Task { @MainActor in
                    self.status = "Could not open workspace: \(error.localizedDescription)"
                }
            }
        }
    }

    func createGroup() {
        status = "All Samples is ready for group gate templates."
    }

    func openTableEditor() {
        let root = TableEditorView(workspace: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenFlo Tables"
        window.center()
        window.contentView = NSHostingView(rootView: root)
        let controller = NSWindowController(window: window)
        tableWindowControllers.append(controller)
        controller.showWindow(nil)
    }

    func openPreferences() {
        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = "Acquisition compensation is currently applied automatically when an FCS file contains $SPILL or $SPILLOVER."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func openCompensationForSelectedSample() {
        guard let selected else {
            openCompensationEditor(matrixID: compensationMatrices.first?.id, sampleID: samples.first?.id)
            return
        }
        openCompensationEditor(for: selected)
    }

    func openExistingCompensationForEditing(for selection: WorkspaceSelection) {
        guard !selection.isAllSamples, let sample = sample(id: selection.sampleID) else {
            if let sample = samples.first(where: { existingCompensationMatrixID(for: $0) != nil }) {
                openExistingCompensationForEditing(for: WorkspaceSelection(sampleID: sample.id, gateID: nil))
            } else {
                status = "Select an FCS sample that already has a compensation matrix."
            }
            return
        }
        guard let matrixID = existingCompensationMatrixID(for: sample),
              let matrix = compensationMatrix(id: matrixID) else {
            status = "\(sample.name) has no acquisition or assigned compensation matrix to edit."
            return
        }

        openCompensationEditor(matrixID: matrix.id, sampleID: sample.id)
    }

    func canEditExistingCompensation(for selection: WorkspaceSelection?) -> Bool {
        if let selection, !selection.isAllSamples, let sample = sample(id: selection.sampleID) {
            return existingCompensationMatrixID(for: sample) != nil
        }
        return samples.contains { existingCompensationMatrixID(for: $0) != nil }
    }

    func openCompensationEditor(for selection: WorkspaceSelection) {
        guard !selection.isAllSamples, let sample = sample(id: selection.sampleID) else {
            openCompensationEditor(matrixID: compensationMatrices.first?.id, sampleID: samples.first?.id)
            return
        }
        let matrixID = sample.compensationMatrixID
            ?? sample.acquisitionCompensationMatrixID
            ?? compensationMatrices.first?.id
        openCompensationEditor(matrixID: matrixID, sampleID: sample.id)
    }

    func openCompensationEditor(matrixID: UUID?, sampleID: UUID?) {
        let root = CompensationMatrixEditorView(
            workspace: self,
            initialMatrixID: matrixID,
            initialSampleID: sampleID
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Compensation Matrix Editor"
        window.center()
        window.contentView = NSHostingView(rootView: root)
        let controller = NSWindowController(window: window)
        plotWindowControllers.append(controller)
        controller.showWindow(nil)
    }

    @discardableResult
    func addOrReuseMatrix(_ matrix: CompensationMatrix) -> UUID {
        if let existing = compensationMatrices.first(where: {
            $0.parameters == matrix.parameters
                && $0.percent == matrix.percent
                && $0.source == matrix.source
                && $0.locked == matrix.locked
        }) {
            return existing.id
        }
        compensationMatrices.append(matrix)
        return matrix.id
    }

    func compensationMatrix(id: UUID?) -> CompensationMatrix? {
        guard let id else { return nil }
        return compensationMatrices.first { $0.id == id }
    }

    func compensationMatrixValue(matrixID: UUID, source: Int, target: Int) -> Double {
        guard let matrix = compensationMatrix(id: matrixID),
              matrix.percent.indices.contains(source),
              matrix.percent[source].indices.contains(target) else {
            return 0
        }
        return matrix.percent[source][target]
    }

    func renameMatrix(_ matrixID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = compensationMatrices.firstIndex(where: { $0.id == matrixID }) else { return }
        compensationMatrices[index].name = trimmed
        compensationMatrices[index].modifiedAt = Date()
        objectWillChange.send()
        status = "Renamed compensation matrix."
    }

    @discardableResult
    func updateMatrixValue(matrixID: UUID, source: Int, target: Int, percent: Double) -> Bool {
        guard let index = compensationMatrices.firstIndex(where: { $0.id == matrixID }),
              compensationMatrices[index].percent.indices.contains(source),
              compensationMatrices[index].percent[source].indices.contains(target) else {
            return false
        }
        guard !compensationMatrices[index].locked else {
            status = "Create an editable copy before changing an acquisition-defined matrix."
            return false
        }
        guard source != target else {
            status = "Diagonal compensation values stay at 100%."
            return false
        }
        guard percent.isFinite else {
            status = "Compensation values must be finite numbers."
            return false
        }

        var updatedMatrix = compensationMatrices[index]
        updatedMatrix.percent[source][target] = percent
        updatedMatrix.modifiedAt = Date()

        do {
            _ = try CompensationEngine.invert(CompensationEngine.spilloverFractions(from: updatedMatrix))
            let assignedSamples = samples.filter { $0.compensationMatrixID == matrixID }
            let updatedTables = try assignedSamples.map { sample in
                (sample.id, try CompensationEngine.apply(updatedMatrix, to: sample.rawTable))
            }
            compensationMatrices[index] = updatedMatrix
            objectWillChange.send()
            for (sampleID, table) in updatedTables {
                guard let sample = sample(id: sampleID) else { continue }
                sample.table = table
                refreshCounts(in: sample)
            }
            invalidateAnalysisAfterCompensationChange()
            status = "Updated \(updatedMatrix.parameters[source]) -> \(updatedMatrix.parameters[target]) compensation."
            return true
        } catch {
            status = "Could not update compensation: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func duplicateMatrixForEditing(_ matrixID: UUID, assignTo sampleID: UUID? = nil) -> UUID? {
        guard let copy = editableDraftCopy(of: matrixID) else { return nil }
        compensationMatrices.append(copy)
        if let sampleID {
            do {
                try assignCompensation(copy.id, to: sampleID)
            } catch {
                status = "Created editable copy, but could not apply it: \(error.localizedDescription)"
            }
        } else {
            status = "Created \(copy.name)."
        }
        return copy.id
    }

    func editableDraftCopy(of matrixID: UUID) -> CompensationMatrix? {
        guard let source = compensationMatrix(id: matrixID) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueMatrixName("\(source.name)-copy")
        copy.locked = false
        copy.originalMatrixID = source.locked || source.originalMatrixID != nil ? (source.originalMatrixID ?? source.id) : nil
        copy.source = source.locked ? .acquisitionCopy : source.source
        copy.colorHex = nextMatrixColorHex()
        copy.createdAt = Date()
        copy.modifiedAt = copy.createdAt
        return copy
    }

    func saveEditedMatrixCopy(_ matrix: CompensationMatrix) throws -> UUID {
        _ = try CompensationEngine.invert(CompensationEngine.spilloverFractions(from: matrix))
        var saved = matrix
        if compensationMatrices.contains(where: { $0.id == saved.id }) {
            saved.id = UUID()
        }
        saved.name = uniqueMatrixName(saved.name)
        saved.locked = false
        saved.createdAt = Date()
        saved.modifiedAt = saved.createdAt
        compensationMatrices.append(saved)
        status = "Saved \(saved.name). Drag it with M or Apply to All Samples."
        return saved.id
    }

    @discardableResult
    func createIdentityMatrixForSelectedSample() -> UUID? {
        guard let sample = selected.flatMap({ sample(id: $0.sampleID) }) ?? samples.first else {
            status = "Load a sample before creating a compensation matrix."
            return nil
        }
        let parameters = defaultCompensationParameters(for: sample)
        guard parameters.count >= 2 else {
            status = "Could not find enough fluorescence channels for a matrix."
            return nil
        }
        let matrix = CompensationMatrix.identity(
            name: uniqueMatrixName("Manual Compensation"),
            parameters: parameters,
            colorHex: nextMatrixColorHex()
        )
        compensationMatrices.append(matrix)
        status = "Created \(matrix.name)."
        return matrix.id
    }

    func resetMatrix(_ matrixID: UUID) {
        guard let index = compensationMatrices.firstIndex(where: { $0.id == matrixID }) else { return }
        guard let originalID = compensationMatrices[index].originalMatrixID,
              let original = compensationMatrix(id: originalID) else {
            status = "This matrix has no acquisition original to reset from."
            return
        }
        var reset = compensationMatrices[index]
        reset.percent = original.percent
        reset.modifiedAt = Date()
        compensationMatrices[index] = reset
        reapplyMatrixToAssignedSamples(reset)
        status = "Reset \(reset.name) to its original acquisition values."
    }

    func assignCompensation(_ matrixID: UUID?, to sampleID: UUID) throws {
        guard let sample = sample(id: sampleID) else { return }
        objectWillChange.send()
        if let matrixID {
            guard let matrix = compensationMatrix(id: matrixID) else { return }
            sample.table = try CompensationEngine.apply(matrix, to: sample.rawTable)
            sample.compensationMatrixID = matrixID
            status = "Applied \(matrix.name) to \(sample.name)."
        } else {
            sample.table = sample.rawTable
            sample.compensationMatrixID = nil
            status = "Showing \(sample.name) uncompensated."
        }
        refreshCounts(in: sample)
        invalidateAnalysisAfterCompensationChange()
    }

    func assignCompensationToAllCompatible(_ matrixID: UUID?) {
        guard let matrixID else {
            for sample in samples {
                try? assignCompensation(nil, to: sample.id)
            }
            status = "Showing all samples uncompensated."
            return
        }
        guard let matrix = compensationMatrix(id: matrixID) else { return }
        var appliedCount = 0
        var failedCount = 0
        for sample in samples where sample.kind == .fcs {
            do {
                try assignCompensation(matrixID, to: sample.id)
                appliedCount += 1
            } catch {
                failedCount += 1
            }
        }
        if failedCount == 0 {
            status = "Applied \(matrix.name) to \(appliedCount) sample\(appliedCount == 1 ? "" : "s")."
        } else {
            status = "Applied \(matrix.name) to \(appliedCount) sample\(appliedCount == 1 ? "" : "s"); \(failedCount) incompatible."
        }
    }

    func applyAcquisitionCompensation(for selection: WorkspaceSelection) {
        guard !selection.isAllSamples,
              let sample = sample(id: selection.sampleID),
              let matrixID = sample.acquisitionCompensationMatrixID else {
            status = "No acquisition compensation matrix is available for that sample."
            return
        }
        do {
            try assignCompensation(matrixID, to: sample.id)
        } catch {
            status = "Could not apply acquisition compensation: \(error.localizedDescription)"
        }
    }

    func editCompensationCopy(for selection: WorkspaceSelection) {
        guard !selection.isAllSamples,
              let sample = sample(id: selection.sampleID),
              let matrixID = existingCompensationMatrixID(for: sample) else {
            status = "No compensation matrix is available to copy."
            return
        }
        openCompensationEditor(matrixID: matrixID, sampleID: sample.id)
    }

    func hasCompensationMatrix(for selection: WorkspaceSelection) -> Bool {
        guard !selection.isAllSamples, let sample = sample(id: selection.sampleID) else { return false }
        return existingCompensationMatrixID(for: sample) != nil
    }

    func compensationDragPayload(matrixID: UUID) -> String {
        "compensation:\(matrixID.uuidString)"
    }

    func copyCompensation(dragPayload payload: String, to target: WorkspaceSelection) -> Bool {
        guard payload.hasPrefix("compensation:"),
              let matrixID = UUID(uuidString: String(payload.dropFirst("compensation:".count))) else {
            return false
        }
        if target.isAllSamples {
            assignCompensationToAllCompatible(matrixID)
            return true
        }
        do {
            try assignCompensation(matrixID, to: target.sampleID)
        } catch {
            status = "Could not apply compensation: \(error.localizedDescription)"
        }
        return true
    }

    func exportMatrixCSV(_ matrixID: UUID, to url: URL) throws {
        guard let matrix = compensationMatrix(id: matrixID) else { return }
        var rows: [String] = []
        rows.append(([""] + matrix.parameters).map(csvEscape).joined(separator: ","))
        for source in matrix.parameters.indices {
            let values = matrix.percent[source].map { String(format: "%.6g", $0) }
            rows.append(([matrix.parameters[source]] + values).map(csvEscape).joined(separator: ","))
        }
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        status = "Saved \(matrix.name) as CSV."
    }

    func exportMatrixXML(_ matrixID: UUID, to url: URL) throws {
        guard let matrix = compensationMatrix(id: matrixID) else { return }
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<CompensationMatrix name=\"\(xmlEscape(matrix.name))\" units=\"percent\">",
            "  <Parameters>"
        ]
        for parameter in matrix.parameters {
            lines.append("    <Parameter name=\"\(xmlEscape(parameter))\" />")
        }
        lines.append("  </Parameters>")
        lines.append("  <Coefficients>")
        for source in matrix.parameters.indices {
            for target in matrix.parameters.indices {
                lines.append(
                    "    <Coefficient source=\"\(xmlEscape(matrix.parameters[source]))\" target=\"\(xmlEscape(matrix.parameters[target]))\" value=\"\(String(format: "%.12g", matrix.percent[source][target]))\" />"
                )
            }
        }
        lines.append("  </Coefficients>")
        lines.append("</CompensationMatrix>")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        status = "Saved \(matrix.name) as XML."
    }

    func addLayout() {
        let nextNumber = layouts.count + 1
        let layout = WorkspaceLayout(name: "Layout \(nextNumber)")
        layouts.append(layout)
        selectedLayoutID = layout.id
        status = "Added \(layout.name)."
    }

    func duplicateSelectedLayout() {
        guard let layout = selectedLayout else { return }
        var duplicate = layout
        duplicate = WorkspaceLayout(
            name: "\(layout.name) Copy",
            items: layout.items,
            zoom: layout.zoom,
            showGrid: layout.showGrid,
            showPageBreaks: layout.showPageBreaks,
            iterationMode: layout.iterationMode,
            iterationSampleID: layout.iterationSampleID,
            batchDestination: layout.batchDestination,
            batchAxis: layout.batchAxis,
            batchCount: layout.batchCount,
            batchAcross: layout.batchAcross
        )
        layouts.append(duplicate)
        selectedLayoutID = duplicate.id
        status = "Duplicated \(layout.name)."
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

    func renameSelectedLayout(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let selectedLayoutID,
              let index = layouts.firstIndex(where: { $0.id == selectedLayoutID }) else { return }
        layouts[index].name = trimmed
        status = "Renamed layout to \(trimmed)."
    }

    func addLayoutItem(_ item: WorkspaceLayoutItem) {
        guard let index = selectedLayoutIndex else { return }
        layouts[index].items.append(item)
        status = "Added \(item.kind.displayName) to \(layouts[index].name)."
    }

    func updateLayoutItem(_ item: WorkspaceLayoutItem) {
        guard let layoutIndex = selectedLayoutIndex,
              let itemIndex = layouts[layoutIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
        layouts[layoutIndex].items[itemIndex] = item
    }

    func deleteLayoutItem(id: UUID) {
        guard let layoutIndex = selectedLayoutIndex else { return }
        layouts[layoutIndex].items.removeAll { $0.id == id }
        status = "Deleted layout item."
    }

    func createBatchLayout(from layoutID: UUID) {
        guard let source = layouts.first(where: { $0.id == layoutID }) else { return }
        let samplesForBatch = samples
        guard !samplesForBatch.isEmpty else {
            status = "Load samples before creating a batch report."
            return
        }
        let count = max(1, source.batchCount)
        let columns = source.batchAxis == .columns ? count : max(1, Int(ceil(Double(samplesForBatch.count) / Double(count))))
        let tileWidth = 300.0
        let tileHeight = 260.0
        var batchedItems: [WorkspaceLayoutItem] = []

        for (sampleIndex, sample) in samplesForBatch.enumerated() {
            let row: Int
            let column: Int
            if source.batchAxis == .columns {
                column = source.batchAcross ? sampleIndex % columns : sampleIndex / max(1, count)
                row = source.batchAcross ? sampleIndex / columns : sampleIndex % max(1, count)
            } else {
                row = source.batchAcross ? sampleIndex % count : sampleIndex / columns
                column = source.batchAcross ? sampleIndex / count : sampleIndex % columns
            }
            let dx = Double(column) * (tileWidth + 36)
            let dy = Double(row) * (tileHeight + 52)

            for item in source.items {
                var copy = item
                copy.id = UUID()
                copy.frame = LayoutFrame(
                    x: 48 + dx + (item.frame.x - 72) * 0.72,
                    y: 48 + dy + (item.frame.y - 72) * 0.72,
                    width: item.frame.width * 0.72,
                    height: item.frame.height * 0.72
                )
                if case .plot(var descriptor) = copy.kind {
                    descriptor = batchResolvedDescriptor(descriptor, for: sample)
                    copy.kind = .plot(descriptor)
                }
                batchedItems.append(copy)
            }

            batchedItems.append(
                WorkspaceLayoutItem(
                    frame: LayoutFrame(x: 48 + dx, y: 48 + dy + tileHeight - 28, width: tileWidth, height: 28),
                    kind: .text(sample.name),
                    strokeColorName: "None",
                    fillColorName: "None",
                    lineWidth: 0
                )
            )
        }

        let batch = WorkspaceLayout(
            name: "\(source.name)-Batch",
            items: batchedItems,
            zoom: source.zoom,
            showGrid: source.showGrid,
            showPageBreaks: source.showPageBreaks,
            iterationMode: .off,
            batchDestination: source.batchDestination,
            batchAxis: source.batchAxis,
            batchCount: source.batchCount,
            batchAcross: source.batchAcross
        )
        layouts.append(batch)
        selectedLayoutID = batch.id
        status = "Created \(batch.name) with \(samplesForBatch.count) sample tile\(samplesForBatch.count == 1 ? "" : "s")."
    }

    private func batchResolvedDescriptor(_ descriptor: WorkspacePlotDescriptor, for sample: WorkspaceSample) -> WorkspacePlotDescriptor {
        var copy = descriptor
        if copy.sourceIsControl {
            copy.lockedSourceSelection = copy.lockedSourceSelection ?? copy.sourceSelection
        } else {
            copy.sourceSelection = selectionMatchingForBatch(gatePath: copy.gatePath, sample: sample)
        }

        copy.overlays = copy.overlays.map { overlay in
            var layer = overlay
            if layer.isControl {
                layer.lockedSourceSelection = layer.lockedSourceSelection ?? layer.sourceSelection
            } else {
                layer.sourceSelection = selectionMatchingForBatch(gatePath: layer.gatePath, sample: sample)
            }
            return layer
        }
        return copy
    }

    private func selectionMatchingForBatch(gatePath: [String], sample: WorkspaceSample) -> WorkspaceSelection {
        guard !gatePath.isEmpty else {
            return WorkspaceSelection(sampleID: sample.id, gateID: nil)
        }
        let gate = gateMatchingPath(gatePath, in: sample.gates)
        return WorkspaceSelection(sampleID: sample.id, gateID: gate?.id)
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

    private var selectedLayoutIndex: Int? {
        guard let selectedLayoutID else { return layouts.indices.first }
        return layouts.firstIndex { $0.id == selectedLayoutID }
    }

    private var selectedLayout: WorkspaceLayout? {
        selectedLayoutIndex.map { layouts[$0] }
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
        let gateMask = evaluate(
            gate: gate,
            sample: sample,
            base: parentMask,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xAxisSettings: resolvedXSettings,
            yAxisSettings: resolvedYSettings
        )
        let inserted = insertGate(
            gate,
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            xTransform: xTransform,
            yTransform: yTransform,
            xAxisSettings: resolvedXSettings,
            yAxisSettings: resolvedYSettings,
            count: gateMask.selectedCount,
            parentSelection: target,
            sample: sample
        )
        if let gateID = inserted?.gateID {
            storeGateMask(gateMask, sample: sample, gateID: gateID)
        }
        return inserted
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
        if copyCompensation(dragPayload: dragPayload, to: target) {
            return
        }
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
        let selections = selectedRows
            .filter { $0.isGate || !$0.selection.isAllSamples }
            .map(\.selection)
        guard !selections.isEmpty else { return nil }

        let populations = selections.map { selection in
            WorkspacePopulationDragItem(
                selection: selection,
                displayState: lastGraphDisplayState(for: selection)
            )
        }
        if let encoded = WorkspacePopulationDragPayload(populations: populations).encodedString() {
            return encoded
        }

        let gateIDs = selections.compactMap(\.gateID)
        if row.isGate, !gateIDs.isEmpty {
            if gateIDs.count == 1, let gateID = gateIDs.first {
                return "gate:\(gateID.uuidString)"
            }
            return "gates:\(gateIDs.map(\.uuidString).joined(separator: ","))"
        }

        let sampleIDs = selections
            .filter { !$0.isAllSamples }
            .map(\.sampleID)
        guard !sampleIDs.isEmpty else { return nil }
        if sampleIDs.count == 1, let sampleID = sampleIDs.first {
            return "sample:\(sampleID.uuidString)"
        }
        return "samples:\(sampleIDs.map(\.uuidString).joined(separator: ","))"
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

    func recordLastGraphDisplayState(
        for selection: WorkspaceSelection,
        xChannelName: String?,
        yChannelName: String?,
        plotMode: PlotMode,
        xAxisSettings: AxisDisplaySettings?,
        yAxisSettings: AxisDisplaySettings?
    ) {
        guard contains(selection) else { return }
        lastGraphDisplayStateBySelectionKey[selectionKey(selection)] = WorkspaceGraphDisplayState(
            xChannelName: xChannelName,
            yChannelName: yChannelName,
            plotMode: plotMode,
            xAxisSettings: xAxisSettings,
            yAxisSettings: yAxisSettings
        )
        layoutPlotSnapshotCache.removeAll()
    }

    func lastGraphDisplayState(for selection: WorkspaceSelection) -> WorkspaceGraphDisplayState? {
        lastGraphDisplayStateBySelectionKey[selectionKey(selection)]
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
            layoutPlotSnapshotCache.removeAll()
            gateMaskCache.removeAll()
            gateChangeVersion += 1
            status = "Deleted all-samples gate."
            return
        }
        guard let sampleIndex = samples.firstIndex(where: { $0.id == selection.sampleID }) else { return }
        objectWillChange.send()
        if let gateID = selection.gateID {
            _ = removeGate(gateID, from: &samples[sampleIndex].gates)
            selected = WorkspaceSelection(sampleID: samples[sampleIndex].id, gateID: nil)
            layoutPlotSnapshotCache.removeAll()
            gateMaskCache.removeAll()
            gateChangeVersion += 1
            status = "Deleted gate."
        } else {
            samples.remove(at: sampleIndex)
            selected = samples.first.map { WorkspaceSelection(sampleID: $0.id, gateID: nil) }
            lastCreatedGate = nil
            layoutPlotSnapshotCache.removeAll()
            gateMaskCache.removeAll()
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

    private func selectionKey(_ selection: WorkspaceSelection) -> String {
        rowID(sampleID: selection.sampleID, gateID: selection.gateID)
    }

    func selections(fromDragPayload payload: String) -> [WorkspaceSelection] {
        if let structuredPayload = WorkspacePopulationDragPayload.decode(from: payload) {
            return structuredPayload.populations.map(\.selection)
        }
        let gateSelections = gateIDs(fromDragPayload: payload).compactMap { selection(containingGateID: $0) }
        if !gateSelections.isEmpty {
            return gateSelections
        }
        return sampleIDs(fromDragPayload: payload).compactMap { sampleID in
            guard sample(id: sampleID) != nil else { return nil }
            return WorkspaceSelection(sampleID: sampleID, gateID: nil)
        }
    }

    func tableColumns(fromDragPayload payload: String) -> [WorkspaceTableColumn] {
        selections(fromDragPayload: payload).compactMap { selection in
            let path = gatePathNames(for: selection)
            let name = path.last ?? displayName(for: selection)
            return WorkspaceTableColumn(
                sourceSelection: selection,
                gatePath: path,
                name: name,
                statistic: .count,
                channelName: defaultStatisticChannelName(for: selection)
            )
        }
    }

    func plotDescriptors(fromDragPayload payload: String) -> [WorkspacePlotDescriptor] {
        if let structuredPayload = WorkspacePopulationDragPayload.decode(from: payload) {
            return structuredPayload.populations.compactMap { item in
                guard var descriptor = plotDescriptor(for: item.selection) else { return nil }
                if let displayState = item.displayState {
                    descriptor.applyDisplayState(displayState)
                }
                return descriptor
            }
        }
        return selections(fromDragPayload: payload).compactMap { selection in
            guard let descriptor = plotDescriptor(for: selection) else { return nil }
            return descriptor
        }
    }

    func plotOverlayDescriptors(fromDragPayload payload: String, startingAt colorIndex: Int) -> [WorkspacePlotOverlayDescriptor] {
        selections(fromDragPayload: payload).enumerated().compactMap { index, selection in
            let path = gatePathNames(for: selection)
            let samplePrefix = sampleName(for: selection.sampleID)
            let population = path.last ?? displayName(for: selection)
            return WorkspacePlotOverlayDescriptor(
                sourceSelection: selection,
                gatePath: path,
                name: "\(samplePrefix) • \(population)",
                colorName: layoutOverlayColorName(at: colorIndex + index)
            )
        }
    }

    func displayName(for selection: WorkspaceSelection) -> String {
        if selection.isAllSamples {
            guard let gateID = selection.gateID, let node = gate(id: gateID, in: groupGates) else {
                return "All Samples"
            }
            return node.name
        }
        guard let sample = sample(id: selection.sampleID) else { return "Missing Sample" }
        guard let gateID = selection.gateID else { return sample.name }
        return gate(id: gateID, in: sample.gates)?.name ?? "Missing Gate"
    }

    func gatePathNames(for selection: WorkspaceSelection) -> [String] {
        if selection.isAllSamples {
            guard let gateID = selection.gateID, let path = gatePath(gateID, in: groupGates) else { return [] }
            return path.map(\.name)
        }
        guard let sample = sample(id: selection.sampleID),
              let gateID = selection.gateID,
              let path = gatePath(gateID, in: sample.gates) else {
            return []
        }
        return path.map(\.name)
    }

    func availableStatisticChannelNames(for selection: WorkspaceSelection? = nil) -> [String] {
        let table = tableForSelection(selection)
        guard let table else { return [] }
        return table.channels.map(\.displayName)
    }

    func layoutChannelOptions(
        for selection: WorkspaceSelection?,
        including requestedNames: [String?],
        limit: Int = 320
    ) -> WorkspaceChannelOptions {
        guard let table = tableForSelection(selection) else {
            return WorkspaceChannelOptions(names: [], totalCount: 0, isLimited: false)
        }
        guard table.channelCount > limit else {
            return WorkspaceChannelOptions(
                names: table.channels.map(\.displayName),
                totalCount: table.channelCount,
                isLimited: false
            )
        }

        var names: [String] = []
        var seen = Set<String>()
        func append(_ name: String?) {
            guard let name, !name.isEmpty, !seen.contains(name) else { return }
            names.append(name)
            seen.insert(name)
        }

        for requestedName in requestedNames {
            append(requestedName)
        }

        for name in signatureChannelNames(for: table) {
            append(name)
            guard names.count < limit else {
                return WorkspaceChannelOptions(names: names, totalCount: table.channelCount, isLimited: true)
            }
        }

        for channel in table.channels {
            append(channel.displayName)
            guard names.count < limit else { break }
        }

        return WorkspaceChannelOptions(names: names, totalCount: table.channelCount, isLimited: true)
    }

    func tableOutput(for columns: [WorkspaceTableColumn]) -> WorkspaceTableOutput {
        let rows = samples.map { sample in
            WorkspaceTableOutputRow(
                sampleName: sample.name,
                values: columns.map { tableValue(for: $0, sample: sample) }
            )
        }
        return WorkspaceTableOutput(columns: columns, rows: rows)
    }

    func plotDescriptor(for selection: WorkspaceSelection) -> WorkspacePlotDescriptor? {
        let gatePath = gatePathNames(for: selection)
        let configuration = gateConfiguration(for: selection)
        if selection.isAllSamples {
            if let gateID = selection.gateID, gate(id: gateID, in: groupGates) == nil {
                return nil
            }
        } else {
            guard let sample = sample(id: selection.sampleID) else { return nil }
            if let gateID = selection.gateID, gate(id: gateID, in: sample.gates) == nil {
                return nil
            }
        }
        var descriptor = WorkspacePlotDescriptor(
            sourceSelection: selection,
            gatePath: gatePath,
            name: displayName(for: selection),
            xChannelName: configuration?.xChannelName,
            yChannelName: configuration?.yChannelName,
            plotMode: .pseudocolor,
            xAxisSettings: configuration?.xAxisSettings,
            yAxisSettings: configuration?.yAxisSettings
        )
        if let displayState = lastGraphDisplayState(for: selection) {
            descriptor.applyDisplayState(displayState)
        }
        return descriptor
    }

    func matchingSelection(for descriptor: WorkspacePlotDescriptor, sampleID: UUID?) -> WorkspaceSelection? {
        if let sampleID, let sample = sample(id: sampleID) {
            if descriptor.gatePath.isEmpty {
                return WorkspaceSelection(sampleID: sample.id, gateID: nil)
            }
            guard let gate = gateMatchingPath(descriptor.gatePath, in: sample.gates) else {
                return nil
            }
            return WorkspaceSelection(sampleID: sample.id, gateID: gate.id)
        }
        guard let sample = sample(id: descriptor.sourceSelection.sampleID) else {
            return nil
        }
        if descriptor.gatePath.isEmpty {
            return WorkspaceSelection(sampleID: sample.id, gateID: nil)
        }
        if let gateID = descriptor.sourceSelection.gateID, gate(id: gateID, in: sample.gates) != nil {
            return descriptor.sourceSelection
        }
        guard let gate = gateMatchingPath(descriptor.gatePath, in: sample.gates) else {
            return nil
        }
        return WorkspaceSelection(sampleID: sample.id, gateID: gate.id)
    }

    func layoutPlotSnapshot(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> LayoutPlotSnapshot? {
        let cacheKey = layoutPlotSnapshotCacheKey(for: descriptor, iterationSampleID: iterationSampleID)
        if let cached = layoutPlotSnapshotCache[cacheKey] {
            return cached
        }

        let snapshot = uncachedLayoutPlotSnapshot(for: descriptor, iterationSampleID: iterationSampleID)
        if let snapshot {
            layoutPlotSnapshotCache[cacheKey] = snapshot
        }
        return snapshot
    }

    func cachedLayoutPlotSnapshot(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> LayoutPlotSnapshot? {
        layoutPlotSnapshotCache[layoutPlotSnapshotCacheKey(for: descriptor, iterationSampleID: iterationSampleID)]
    }

    func storeLayoutPlotSnapshot(_ snapshot: LayoutPlotSnapshot, for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) {
        layoutPlotSnapshotCache[layoutPlotSnapshotCacheKey(for: descriptor, iterationSampleID: iterationSampleID)] = snapshot
    }

    func layoutPlotSnapshotRenderID(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> String {
        layoutPlotSnapshotCacheKey(for: descriptor, iterationSampleID: iterationSampleID)
    }

    private enum LayoutPlotResolutionFailure: Error, Equatable {
        case noPopulation(String)
        case missingParameter(String)
        case missingSample

        var message: String {
            switch self {
            case .noPopulation(let path):
                return "No population: \(path)"
            case .missingParameter(let name):
                return "Missing parameter \(name)"
            case .missingSample:
                return "Missing sample"
            }
        }
    }

    private func uncachedLayoutPlotSnapshot(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> LayoutPlotSnapshot? {
        if !descriptor.overlays.isEmpty {
            return layoutOverlayPlotSnapshot(for: descriptor, iterationSampleID: iterationSampleID)
        }

        switch layoutPlotRenderPayloadResult(for: descriptor, iterationSampleID: iterationSampleID) {
        case .success(let payload):
            return Self.renderLayoutPlotSnapshot(from: payload)
        case .failure(let failure):
            return placeholderSnapshot(
                message: failure.message,
                descriptor: descriptor,
                iterationSampleID: iterationSampleID
            )
        }
    }

    func layoutPlotRenderPayload(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> LayoutPlotRenderPayload? {
        guard descriptor.overlays.isEmpty else {
            return nil
        }
        guard case .success(let payload) = layoutPlotRenderPayloadResult(for: descriptor, iterationSampleID: iterationSampleID) else {
            return nil
        }
        return payload
    }

    private func layoutPlotRenderPayloadResult(
        for descriptor: WorkspacePlotDescriptor,
        iterationSampleID: UUID?
    ) -> Result<LayoutPlotRenderPayload, LayoutPlotResolutionFailure> {
        let selectionResult = resolvedSelection(
            sourceSelection: descriptor.sourceSelection,
            gatePath: descriptor.gatePath,
            isControl: descriptor.sourceIsControl,
            lockedSelection: descriptor.lockedSourceSelection,
            iterationSampleID: iterationSampleID
        )
        let selection: WorkspaceSelection
        switch selectionResult {
        case .success(let resolvedSelection):
            selection = resolvedSelection
        case .failure(let failure):
            return .failure(failure)
        }

        guard let sample = sample(id: selection.sampleID) else { return .failure(.missingSample) }
        let path = selection.gateID.flatMap { gatePath($0, in: sample.gates) } ?? []
        let table = sample.table
        let axes = AppModel.defaultAxisSelection(for: table)
        let configuration = gateConfiguration(for: selection)
        let xIndex: Int
        switch graphChannelIndex(
            descriptor.xChannelName,
            in: table,
            fallback: configuration.flatMap { channelIndex(named: $0.xChannelName, in: table) } ?? axes.x
        ) {
        case .success(let index):
            xIndex = index
        case .failure(let failure):
            return .failure(failure)
        }
        let yIndex: Int
        if descriptor.plotMode.isOneDimensional {
            yIndex = xIndex
        } else {
            switch graphChannelIndex(
                descriptor.yChannelName,
                in: table,
                fallback: configuration.flatMap { channelIndex(named: $0.yChannelName, in: table) } ?? axes.y
            ) {
            case .success(let index):
                yIndex = index
            case .failure(let failure):
                return .failure(failure)
            }
        }
        let xSettings = descriptor.xAxisSettings
            ?? configuration?.xAxisSettings
            ?? AxisDisplaySettings(transform: AppModel.defaultTransform(for: table.channels[xIndex]))
        let ySettings = descriptor.yAxisSettings
            ?? configuration?.yAxisSettings
            ?? AxisDisplaySettings(transform: AppModel.defaultTransform(for: table.channels[yIndex]))
        let gateSteps = path.map { node in
            LayoutGateRenderStep(
                gate: node.gate,
                xIndex: channelIndex(named: node.xChannelName, in: table) ?? axes.x,
                yIndex: channelIndex(named: node.yChannelName, in: table) ?? axes.y,
                xAxisSettings: node.xAxisSettings,
                yAxisSettings: node.yAxisSettings
            )
        }
        let eventCount = path.last?.count ?? selection.gateID.flatMap { cachedGateMask(sample: sample, gateID: $0)?.selectedCount } ?? table.rowCount
        let mask = selection.gateID.flatMap { cachedGateMask(sample: sample, gateID: $0) }

        if sample.kind == .singleCell {
            return .success(sampledSingleCellLayoutPlotRenderPayload(
                table: table,
                mask: mask,
                gateSteps: gateSteps,
                sampleName: sample.name,
                populationName: path.last?.name ?? sample.name,
                eventCount: eventCount,
                xIndex: xIndex,
                yIndex: yIndex,
                xAxisSettings: xSettings,
                yAxisSettings: ySettings,
                mode: descriptor.plotMode,
                ancestry: path.map(\.name)
            ))
        }

        return .success(LayoutPlotRenderPayload(
            table: table,
            sampleKind: sample.kind,
            mask: mask,
            gateSteps: gateSteps,
            sampleName: sample.name,
            populationName: path.last?.name ?? sample.name,
            eventCount: eventCount,
            xIndex: xIndex,
            yIndex: yIndex,
            xAxisSettings: xSettings,
            yAxisSettings: ySettings,
            mode: descriptor.plotMode,
            ancestry: path.map(\.name)
        ))
    }

    private func resolvedSelection(
        sourceSelection: WorkspaceSelection,
        gatePath: [String],
        isControl: Bool,
        lockedSelection: WorkspaceSelection?,
        iterationSampleID: UUID?
    ) -> Result<WorkspaceSelection, LayoutPlotResolutionFailure> {
        if isControl {
            return exactSelection(lockedSelection ?? sourceSelection, gatePath: gatePath)
        }

        if let iterationSampleID {
            return selectionMatching(gatePath: gatePath, sampleID: iterationSampleID)
        }

        if sourceSelection.isAllSamples {
            return .failure(.noPopulation(populationPathDescription(gatePath)))
        }

        return exactSelection(sourceSelection, gatePath: gatePath)
    }

    private func exactSelection(
        _ selection: WorkspaceSelection,
        gatePath: [String]
    ) -> Result<WorkspaceSelection, LayoutPlotResolutionFailure> {
        guard !selection.isAllSamples, let sample = sample(id: selection.sampleID) else {
            return .failure(.missingSample)
        }
        if gatePath.isEmpty {
            return .success(WorkspaceSelection(sampleID: sample.id, gateID: nil))
        }
        if let gateID = selection.gateID, gate(id: gateID, in: sample.gates) != nil {
            return .success(selection)
        }
        guard let gate = gateMatchingPath(gatePath, in: sample.gates) else {
            return .failure(.noPopulation(populationPathDescription(gatePath)))
        }
        return .success(WorkspaceSelection(sampleID: sample.id, gateID: gate.id))
    }

    private func selectionMatching(
        gatePath: [String],
        sampleID: UUID
    ) -> Result<WorkspaceSelection, LayoutPlotResolutionFailure> {
        guard let sample = sample(id: sampleID) else {
            return .failure(.missingSample)
        }
        guard !gatePath.isEmpty else {
            return .success(WorkspaceSelection(sampleID: sample.id, gateID: nil))
        }
        guard let gate = gateMatchingPath(gatePath, in: sample.gates) else {
            return .failure(.noPopulation(populationPathDescription(gatePath)))
        }
        return .success(WorkspaceSelection(sampleID: sample.id, gateID: gate.id))
    }

    private func graphChannelIndex(
        _ channelName: String?,
        in table: EventTable,
        fallback: Int
    ) -> Result<Int, LayoutPlotResolutionFailure> {
        if let channelName, !channelName.isEmpty {
            guard let index = channelIndex(named: channelName, in: table) else {
                return .failure(.missingParameter(channelName))
            }
            return .success(index)
        }
        return .success(min(max(fallback, 0), max(table.channelCount - 1, 0)))
    }

    private func placeholderSnapshot(
        message: String,
        descriptor: WorkspacePlotDescriptor,
        iterationSampleID: UUID?
    ) -> LayoutPlotSnapshot {
        let sampleName: String
        if let iterationSampleID, let sample = sample(id: iterationSampleID) {
            sampleName = sample.name
        } else if let sample = sample(id: descriptor.sourceSelection.sampleID) {
            sampleName = sample.name
        } else {
            sampleName = "Missing sample"
        }
        return LayoutPlotSnapshot(
            image: nil,
            placeholderMessage: message,
            sampleName: sampleName,
            populationName: descriptor.gatePath.last ?? descriptor.name,
            eventCount: 0,
            xAxisTitle: descriptor.xChannelName ?? "X Axis",
            yAxisTitle: descriptor.plotMode.isOneDimensional ? descriptor.plotMode.rawValue : (descriptor.yChannelName ?? "Y Axis"),
            xAxisRange: nil,
            yAxisRange: nil,
            ancestry: descriptor.gatePath,
            legend: []
        )
    }

    private func populationPathDescription(_ gatePath: [String]) -> String {
        gatePath.isEmpty ? "All Events" : "/" + gatePath.joined(separator: "/")
    }

    private func sampledSingleCellLayoutPlotRenderPayload(
        table: EventTable,
        mask: EventMask?,
        gateSteps: [LayoutGateRenderStep],
        sampleName: String,
        populationName: String,
        eventCount: Int,
        xIndex: Int,
        yIndex: Int,
        xAxisSettings: AxisDisplaySettings,
        yAxisSettings: AxisDisplaySettings,
        mode: PlotMode,
        ancestry: [String]
    ) -> LayoutPlotRenderPayload {
        let maxRows = 4_000
        let indices: [Int]
        let previewMask: EventMask?

        if let mask {
            indices = Self.sampledIndices(rowCount: table.rowCount, mask: mask, maxRows: maxRows)
            previewMask = nil
        } else {
            indices = Self.sampledIndices(rowCount: table.rowCount, mask: nil, maxRows: maxRows)
            previewMask = Self.evaluateLayoutGateSteps(gateSteps, table: table, indices: indices)
        }

        let previewTable = EventTable(
            channels: [table.channels[xIndex], table.channels[yIndex]],
            columns: [
                Self.sampledColumn(table, xIndex, indices: indices),
                Self.sampledColumn(table, yIndex, indices: indices)
            ]
        )

        return LayoutPlotRenderPayload(
            table: previewTable,
            sampleKind: .singleCell,
            mask: previewMask,
            gateSteps: [],
            sampleName: sampleName,
            populationName: populationName,
            eventCount: eventCount,
            xIndex: 0,
            yIndex: 1,
            xAxisSettings: xAxisSettings,
            yAxisSettings: yAxisSettings,
            mode: mode,
            ancestry: ancestry
        )
    }

    nonisolated static func renderLayoutPlotSnapshot(from payload: LayoutPlotRenderPayload) -> LayoutPlotSnapshot {
        if payload.sampleKind == .singleCell {
            return renderSampledSingleCellLayoutPlotSnapshot(from: payload)
        }

        let mask = payload.mask ?? evaluateLayoutGateSteps(payload.gateSteps, table: payload.table)
        let xValues = applyTransform(payload.xAxisSettings, to: payload.table.column(payload.xIndex))
        let yValues = applyTransform(payload.yAxisSettings, to: payload.table.column(payload.yIndex))
        let xRange = payload.xAxisSettings.resolvedRange(auto: EventTable.range(values: xValues, mask: mask))
        let yRange = payload.yAxisSettings.resolvedRange(auto: EventTable.range(values: yValues, mask: mask))
        let mode = payload.mode
        let image: NSImage
        let displayYRange: ClosedRange<Float>

        if mode.isOneDimensional {
            let histogram = Histogram1D.build(values: xValues, mask: mask, width: 420, xRange: xRange)
            if mode == .cdf {
                displayYRange = 0...1
                image = CDFRenderer.image(from: histogram, yRange: displayYRange)
            } else {
                displayYRange = AppModel.histogramPreviewRange(maxBin: histogram.maxBin)
                image = HistogramRenderer.image(from: histogram, height: 420, yRange: displayYRange)
            }
        } else if mode == .dot {
            displayYRange = yRange
            image = DotPlotRenderer.image(
                xValues: xValues,
                yValues: yValues,
                mask: mask,
                width: 420,
                height: 420,
                xRange: xRange,
                yRange: yRange,
                maxDots: 35_000
            )
        } else {
            displayYRange = yRange
            let histogram = Histogram2D.build(
                xValues: xValues,
                yValues: yValues,
                mask: mask,
                width: 420,
                height: 420,
                xRange: xRange,
                yRange: yRange
            )
            switch mode {
            case .contour:
                image = DensityPlotRenderer.image(from: histogram, style: .contour, levelPercent: 5)
            case .density:
                image = DensityPlotRenderer.image(from: histogram, style: .density, levelPercent: 5)
            case .zebra:
                image = DensityPlotRenderer.image(from: histogram, style: .zebra, levelPercent: 5)
            case .pseudocolor:
                image = HeatmapRenderer.image(from: histogram)
            case .heatmapStatistic:
                image = DensityPlotRenderer.image(from: histogram, style: .heatmapStatistic, levelPercent: 5)
            case .dot, .histogram, .cdf:
                image = HeatmapRenderer.image(from: histogram)
            }
        }

        return LayoutPlotSnapshot(
            image: image,
            placeholderMessage: nil,
            sampleName: payload.sampleName,
            populationName: payload.populationName,
            eventCount: payload.eventCount,
            xAxisTitle: payload.table.channels[payload.xIndex].displayName,
            yAxisTitle: mode.isOneDimensional ? mode.rawValue : payload.table.channels[payload.yIndex].displayName,
            xAxisRange: xRange,
            yAxisRange: displayYRange,
            ancestry: payload.ancestry,
            legend: []
        )
    }

    private nonisolated static func renderSampledSingleCellLayoutPlotSnapshot(from payload: LayoutPlotRenderPayload) -> LayoutPlotSnapshot {
        let maxRows = 4_000
        let indices: [Int]
        let sampledMask: EventMask?

        if let mask = payload.mask {
            indices = sampledIndices(rowCount: payload.table.rowCount, mask: mask, maxRows: maxRows)
            sampledMask = nil
        } else {
            indices = sampledIndices(rowCount: payload.table.rowCount, mask: nil, maxRows: maxRows)
            sampledMask = evaluateLayoutGateSteps(payload.gateSteps, table: payload.table, indices: indices)
        }

        let xValues = applyTransform(payload.xAxisSettings, to: sampledColumn(payload.table, payload.xIndex, indices: indices))
        let yValues = applyTransform(payload.yAxisSettings, to: sampledColumn(payload.table, payload.yIndex, indices: indices))
        let xRange = payload.xAxisSettings.resolvedRange(auto: EventTable.range(values: xValues, mask: sampledMask))
        let yRange = payload.yAxisSettings.resolvedRange(auto: EventTable.range(values: yValues, mask: sampledMask))
        let mode = payload.mode
        let image: NSImage
        let displayYRange: ClosedRange<Float>

        if mode.isOneDimensional {
            let histogram = Histogram1D.build(values: xValues, mask: sampledMask, width: 420, xRange: xRange)
            if mode == .cdf {
                displayYRange = 0...1
                image = CDFRenderer.image(from: histogram, yRange: displayYRange)
            } else {
                displayYRange = AppModel.histogramPreviewRange(maxBin: histogram.maxBin)
                image = HistogramRenderer.image(from: histogram, height: 420, yRange: displayYRange)
            }
        } else if mode == .dot {
            displayYRange = yRange
            image = DotPlotRenderer.image(
                xValues: xValues,
                yValues: yValues,
                mask: sampledMask,
                width: 420,
                height: 420,
                xRange: xRange,
                yRange: yRange,
                maxDots: maxRows
            )
        } else {
            displayYRange = yRange
            let histogram = Histogram2D.build(
                xValues: xValues,
                yValues: yValues,
                mask: sampledMask,
                width: 420,
                height: 420,
                xRange: xRange,
                yRange: yRange
            )
            switch mode {
            case .contour:
                image = DensityPlotRenderer.image(from: histogram, style: .contour, levelPercent: 5)
            case .density:
                image = DensityPlotRenderer.image(from: histogram, style: .density, levelPercent: 5)
            case .zebra:
                image = DensityPlotRenderer.image(from: histogram, style: .zebra, levelPercent: 5)
            case .pseudocolor:
                image = HeatmapRenderer.image(from: histogram)
            case .heatmapStatistic:
                image = DensityPlotRenderer.image(from: histogram, style: .heatmapStatistic, levelPercent: 5)
            case .dot, .histogram, .cdf:
                image = HeatmapRenderer.image(from: histogram)
            }
        }

        return LayoutPlotSnapshot(
            image: image,
            placeholderMessage: nil,
            sampleName: payload.sampleName,
            populationName: payload.populationName,
            eventCount: payload.eventCount,
            xAxisTitle: payload.table.channels[payload.xIndex].displayName,
            yAxisTitle: mode.isOneDimensional ? mode.rawValue : payload.table.channels[payload.yIndex].displayName,
            xAxisRange: xRange,
            yAxisRange: displayYRange,
            ancestry: payload.ancestry,
            legend: []
        )
    }

    private nonisolated static func sampledIndices(rowCount: Int, mask: EventMask?, maxRows: Int) -> [Int] {
        guard rowCount > 0, maxRows > 0 else { return [] }
        if let mask {
            guard mask.count == rowCount else { return [] }
            let selectedCount = mask.selectedCount
            guard selectedCount > 0 else { return [] }
            if selectedCount <= maxRows {
                return sampledSelectedIndices(mask, selectedCount: selectedCount, maxRows: maxRows)
            }

            let rowStride = max(1, rowCount / maxRows)
            var output: [Int] = []
            output.reserveCapacity(maxRows)

            for index in stride(from: 0, to: rowCount, by: rowStride) where mask[index] {
                output.append(index)
                if output.count >= maxRows {
                    return output
                }
            }

            if output.count >= maxRows / 2 {
                return output
            }
            return sampledSelectedIndices(mask, selectedCount: selectedCount, maxRows: maxRows)
        }

        guard rowCount > maxRows else {
            return Array(0..<rowCount)
        }

        let rowStride = max(1, rowCount / maxRows)
        var output: [Int] = []
        output.reserveCapacity(maxRows)

        for index in stride(from: 0, to: rowCount, by: rowStride) {
            output.append(index)
            if output.count >= maxRows {
                break
            }
        }
        return output
    }

    private nonisolated static func sampledSelectedIndices(
        _ mask: EventMask,
        selectedCount: Int,
        maxRows: Int
    ) -> [Int] {
        let selectedStride = max(1, selectedCount / maxRows)
        var selectedOrdinal = 0
        var output: [Int] = []
        output.reserveCapacity(min(selectedCount, maxRows))

        for wordIndex in mask.words.indices {
            var word = mask.words[wordIndex]
            while word != 0 {
                let bitIndex = word.trailingZeroBitCount
                let rowIndex = wordIndex * 64 + bitIndex
                if rowIndex < mask.count, selectedOrdinal % selectedStride == 0 {
                    output.append(rowIndex)
                    if output.count >= maxRows {
                        return output
                    }
                }
                selectedOrdinal += 1
                word &= word - 1
            }
        }

        return output
    }

    private nonisolated static func sampledColumn(_ table: EventTable, _ channel: Int, indices: [Int]) -> [Float] {
        let column = table.column(channel)
        return indices.map { column[$0] }
    }

    private nonisolated static func evaluateLayoutGateSteps(
        _ steps: [LayoutGateRenderStep],
        table: EventTable,
        indices: [Int]
    ) -> EventMask? {
        guard !steps.isEmpty else { return nil }
        var mask: EventMask?
        for step in steps {
            let xValues = applyTransform(step.xAxisSettings, to: sampledColumn(table, step.xIndex, indices: indices))
            let yValues = applyTransform(step.yAxisSettings, to: sampledColumn(table, step.yIndex, indices: indices))
            mask = step.gate.evaluate(xValues: xValues, yValues: yValues, base: mask)
        }
        return mask
    }

    private nonisolated static func evaluateLayoutGateSteps(_ steps: [LayoutGateRenderStep], table: EventTable) -> EventMask? {
        var mask: EventMask?
        for step in steps {
            let xValues = applyTransform(step.xAxisSettings, to: table.column(step.xIndex))
            let yValues = applyTransform(step.yAxisSettings, to: table.column(step.yIndex))
            mask = step.gate.evaluate(xValues: xValues, yValues: yValues, base: mask)
        }
        return mask
    }

    private func layoutPlotSnapshotCacheKey(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> String {
        let resolvedSelection = matchingSelection(
            for: descriptor,
            sampleID: descriptor.sourceSelection.isAllSamples ? iterationSampleID : iterationSampleID ?? descriptor.sourceSelection.sampleID
        )
        let sampleFingerprint: String
        if let resolvedSelection, let sample = sample(id: resolvedSelection.sampleID) {
            sampleFingerprint = "\(sample.id.uuidString):\(sample.table.rowCount):\(sample.table.channelCount)"
        } else {
            sampleFingerprint = "no-sample"
        }
        let overlayKey = descriptor.overlays.map { overlay in
            [
                overlay.sourceSelection.sampleID.uuidString,
                overlay.sourceSelection.gateID?.uuidString ?? "root",
                overlay.lockedSourceSelection?.sampleID.uuidString ?? "no-lock",
                overlay.lockedSourceSelection?.gateID?.uuidString ?? "root",
                overlay.isControl ? "control" : "unlocked",
                overlay.name,
                overlay.gatePath.joined(separator: ">"),
                overlay.colorName
            ].joined(separator: ":")
        }.joined(separator: "|")
        return [
            "\(gateChangeVersion)",
            sampleFingerprint,
            iterationSampleID?.uuidString ?? "no-iteration",
            descriptor.sourceSelection.sampleID.uuidString,
            descriptor.sourceSelection.gateID?.uuidString ?? "root",
            descriptor.lockedSourceSelection?.sampleID.uuidString ?? "no-lock",
            descriptor.lockedSourceSelection?.gateID?.uuidString ?? "root",
            descriptor.sourceIsControl ? "source-control" : "source-unlocked",
            descriptor.name,
            descriptor.gatePath.joined(separator: ">"),
            descriptor.xChannelName ?? "auto-x",
            descriptor.yChannelName ?? "auto-y",
            descriptor.plotMode.rawValue,
            descriptor.showAxes ? "axes" : "no-axes",
            axisSettingsCacheKey(descriptor.xAxisSettings),
            axisSettingsCacheKey(descriptor.yAxisSettings),
            overlayKey
        ].joined(separator: "::")
    }

    private func axisSettingsCacheKey(_ settings: AxisDisplaySettings?) -> String {
        guard let settings else { return "auto-axis" }
        return [
            settings.transform.rawValue,
            settings.minimum.map { String($0) } ?? "auto-min",
            settings.maximum.map { String($0) } ?? "auto-max",
            String(settings.extraNegativeDecades),
            String(settings.widthBasis),
            String(settings.positiveDecades)
        ].joined(separator: ",")
    }

    private struct OverlayResolvedSeries {
        var xValues: [Float]
        var yValues: [Float]
        var mask: EventMask?
        var colorName: String
        var eventCount: Int
    }

    private func layoutOverlayPlotSnapshot(for descriptor: WorkspacePlotDescriptor, iterationSampleID: UUID?) -> LayoutPlotSnapshot? {
        var series: [OverlayResolvedSeries] = []
        var legend: [LayoutPlotLegendEntry] = []
        var xRange: ClosedRange<Float>?
        var yRange: ClosedRange<Float>?
        var firstFailure: LayoutPlotResolutionFailure?
        var xAxisTitle = descriptor.xChannelName ?? "X Axis"
        var yAxisTitle = descriptor.plotMode.isOneDimensional ? descriptor.plotMode.rawValue : (descriptor.yChannelName ?? "Y Axis")
        var ancestry = descriptor.gatePath

        func appendFailure(
            _ failure: LayoutPlotResolutionFailure,
            layerID: UUID?,
            isBaseLayer: Bool,
            colorName: String,
            isControl: Bool
        ) {
            if firstFailure == nil {
                firstFailure = failure
            }
            legend.append(
                LayoutPlotLegendEntry(
                    layerID: layerID,
                    isBaseLayer: isBaseLayer,
                    name: failure.message,
                    colorName: colorName,
                    eventCount: 0,
                    isControl: isControl
                )
            )
        }

        func appendLayer(
            sourceSelection: WorkspaceSelection,
            layerGatePath: [String],
            name: String?,
            colorName: String,
            isControl: Bool,
            lockedSelection: WorkspaceSelection?,
            layerID: UUID?,
            isBaseLayer: Bool
        ) {
            let selectionResult = resolvedSelection(
                sourceSelection: sourceSelection,
                gatePath: layerGatePath,
                isControl: isControl,
                lockedSelection: lockedSelection,
                iterationSampleID: iterationSampleID
            )
            let selection: WorkspaceSelection
            switch selectionResult {
            case .success(let resolvedSelection):
                selection = resolvedSelection
            case .failure(let failure):
                appendFailure(failure, layerID: layerID, isBaseLayer: isBaseLayer, colorName: colorName, isControl: isControl)
                return
            }

            guard let sample = sample(id: selection.sampleID) else {
                appendFailure(.missingSample, layerID: layerID, isBaseLayer: isBaseLayer, colorName: colorName, isControl: isControl)
                return
            }

            let table = sample.table
            let axes = AppModel.defaultAxisSelection(for: table)
            let path = selection.gateID.flatMap { gatePath($0, in: sample.gates) } ?? []
            let xIndex: Int
            switch graphChannelIndex(descriptor.xChannelName, in: table, fallback: axes.x) {
            case .success(let index):
                xIndex = index
                xAxisTitle = table.channels[index].displayName
            case .failure(let failure):
                appendFailure(failure, layerID: layerID, isBaseLayer: isBaseLayer, colorName: colorName, isControl: isControl)
                return
            }

            let yIndex: Int
            if descriptor.plotMode.isOneDimensional {
                yIndex = xIndex
                yAxisTitle = descriptor.plotMode.rawValue
            } else {
                switch graphChannelIndex(descriptor.yChannelName, in: table, fallback: axes.y) {
                case .success(let index):
                    yIndex = index
                    yAxisTitle = table.channels[index].displayName
                case .failure(let failure):
                    appendFailure(failure, layerID: layerID, isBaseLayer: isBaseLayer, colorName: colorName, isControl: isControl)
                    return
                }
            }

            let xSettings = descriptor.xAxisSettings ?? AxisDisplaySettings(transform: AppModel.defaultTransform(for: table.channels[xIndex]))
            let ySettings = descriptor.yAxisSettings ?? AxisDisplaySettings(transform: AppModel.defaultTransform(for: table.channels[yIndex]))
            let eventCount: Int
            let xValues: [Float]
            let yValues: [Float]
            let mask: EventMask?

            if sample.kind == .singleCell {
                let cachedMask = selection.gateID.flatMap { cachedGateMask(sample: sample, gateID: $0) }
                let gateSteps = path.map { node in
                    LayoutGateRenderStep(
                        gate: node.gate,
                        xIndex: channelIndex(named: node.xChannelName, in: table) ?? axes.x,
                        yIndex: channelIndex(named: node.yChannelName, in: table) ?? axes.y,
                        xAxisSettings: node.xAxisSettings,
                        yAxisSettings: node.yAxisSettings
                    )
                }
                let indices: [Int]
                if let cachedMask {
                    indices = Self.sampledIndices(rowCount: table.rowCount, mask: cachedMask, maxRows: 4_000)
                    mask = nil
                    eventCount = cachedMask.selectedCount
                } else {
                    indices = Self.sampledIndices(rowCount: table.rowCount, mask: nil, maxRows: 4_000)
                    mask = Self.evaluateLayoutGateSteps(gateSteps, table: table, indices: indices)
                    eventCount = path.last?.count ?? mask?.selectedCount ?? table.rowCount
                }
                xValues = Self.applyTransform(xSettings, to: Self.sampledColumn(table, xIndex, indices: indices))
                yValues = descriptor.plotMode.isOneDimensional
                    ? xValues
                    : Self.applyTransform(ySettings, to: Self.sampledColumn(table, yIndex, indices: indices))
            } else {
                guard let population = selectedPopulation(for: selection) else {
                    appendFailure(.noPopulation(populationPathDescription(layerGatePath)), layerID: layerID, isBaseLayer: isBaseLayer, colorName: colorName, isControl: isControl)
                    return
                }
                mask = population.mask
                eventCount = population.mask?.selectedCount ?? population.table.rowCount
                xValues = Self.applyTransform(xSettings, to: population.table.column(xIndex))
                yValues = descriptor.plotMode.isOneDimensional
                    ? xValues
                    : Self.applyTransform(ySettings, to: population.table.column(yIndex))
            }

            xRange = union(xRange, EventTable.range(values: xValues, mask: mask))
            if !descriptor.plotMode.isOneDimensional {
                yRange = union(yRange, EventTable.range(values: yValues, mask: mask))
            }
            series.append(
                OverlayResolvedSeries(
                    xValues: xValues,
                    yValues: yValues,
                    mask: mask,
                    colorName: colorName,
                    eventCount: eventCount
                )
            )
            let layerName = name ?? "\(sample.name) • \(path.last?.name ?? sample.name)"
            legend.append(
                LayoutPlotLegendEntry(
                    layerID: layerID,
                    isBaseLayer: isBaseLayer,
                    name: layerName,
                    colorName: colorName,
                    eventCount: eventCount,
                    isControl: isControl
                )
            )
            if isBaseLayer {
                ancestry = path.map(\.name)
            }
        }

        appendLayer(
            sourceSelection: descriptor.sourceSelection,
            layerGatePath: descriptor.gatePath,
            name: nil,
            colorName: layoutOverlayColorName(at: 0),
            isControl: descriptor.sourceIsControl,
            lockedSelection: descriptor.lockedSourceSelection,
            layerID: nil,
            isBaseLayer: true
        )

        for overlay in descriptor.overlays {
            appendLayer(
                sourceSelection: overlay.sourceSelection,
                layerGatePath: overlay.gatePath,
                name: overlay.name,
                colorName: overlay.colorName,
                isControl: overlay.isControl,
                lockedSelection: overlay.lockedSourceSelection,
                layerID: overlay.id,
                isBaseLayer: false
            )
        }

        guard !series.isEmpty else {
            return placeholderSnapshot(
                message: firstFailure?.message ?? "No overlay populations",
                descriptor: descriptor,
                iterationSampleID: iterationSampleID
            )
        }

        let image: NSImage
        let resolvedXRange = descriptor.xAxisSettings?.resolvedRange(auto: xRange ?? 0...1) ?? (xRange ?? 0...1)
        let resolvedYRange: ClosedRange<Float>
        if descriptor.plotMode.isOneDimensional {
            let histograms = series.map { item in
                OverlayHistogramSeries(
                    histogram: Histogram1D.build(values: item.xValues, mask: item.mask, width: 420, xRange: resolvedXRange),
                    colorName: item.colorName
                )
            }
            if descriptor.plotMode == .cdf {
                resolvedYRange = 0...1
                image = OverlayHistogramRenderer.image(series: histograms, height: 420, yRange: resolvedYRange, cumulative: true)
            } else {
                let maxBin = histograms.map(\.histogram.maxBin).max() ?? 0
                resolvedYRange = AppModel.histogramPreviewRange(maxBin: maxBin)
                image = OverlayHistogramRenderer.image(series: histograms, height: 420, yRange: resolvedYRange)
            }
        } else {
            resolvedYRange = descriptor.yAxisSettings?.resolvedRange(auto: yRange ?? 0...1) ?? (yRange ?? 0...1)
            image = OverlayDotPlotRenderer.image(
                series: series.map {
                    OverlayDotPlotSeries(
                        xValues: $0.xValues,
                        yValues: $0.yValues,
                        mask: $0.mask,
                        colorName: $0.colorName
                    )
                },
                width: 420,
                height: 420,
                xRange: resolvedXRange,
                yRange: resolvedYRange
            )
        }

        return LayoutPlotSnapshot(
            image: image,
            placeholderMessage: nil,
            sampleName: "Overlay (\(legend.count) populations)",
            populationName: descriptor.name,
            eventCount: series.reduce(0) { $0 + $1.eventCount },
            xAxisTitle: xAxisTitle,
            yAxisTitle: yAxisTitle,
            xAxisRange: resolvedXRange,
            yAxisRange: resolvedYRange,
            ancestry: ancestry,
            legend: legend
        )
    }

    private func union(_ lhs: ClosedRange<Float>?, _ rhs: ClosedRange<Float>) -> ClosedRange<Float> {
        guard let lhs else { return rhs }
        return min(lhs.lowerBound, rhs.lowerBound)...max(lhs.upperBound, rhs.upperBound)
    }

    func sampleName(for id: UUID?) -> String {
        guard let id, let sample = sample(id: id) else { return "Off" }
        return sample.name
    }

    private func gateIDs(fromDragPayload payload: String) -> [UUID] {
        if let structuredPayload = WorkspacePopulationDragPayload.decode(from: payload) {
            return structuredPayload.populations.compactMap(\.selection.gateID)
        }
        if payload.hasPrefix("gates:") {
            return payload
                .dropFirst(6)
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        }
        if payload.hasPrefix("gate:"), let gateID = UUID(uuidString: String(payload.dropFirst(5))) {
            return [gateID]
        }
        return []
    }

    private func sampleIDs(fromDragPayload payload: String) -> [UUID] {
        if let structuredPayload = WorkspacePopulationDragPayload.decode(from: payload) {
            return structuredPayload.populations
                .filter { !$0.selection.isAllSamples && $0.selection.gateID == nil }
                .map(\.selection.sampleID)
        }
        if payload.hasPrefix("samples:") {
            return payload
                .dropFirst(8)
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        }
        if payload.hasPrefix("sample:"), let sampleID = UUID(uuidString: String(payload.dropFirst(7))) {
            return [sampleID]
        }
        return []
    }

    private func selection(containingGateID gateID: UUID) -> WorkspaceSelection? {
        if gate(id: gateID, in: groupGates) != nil {
            return WorkspaceSelection(sampleID: WorkspaceSelection.allSamplesID, gateID: gateID)
        }
        for sample in samples where gate(id: gateID, in: sample.gates) != nil {
            return WorkspaceSelection(sampleID: sample.id, gateID: gateID)
        }
        return nil
    }

    private func defaultStatisticChannelName(for selection: WorkspaceSelection) -> String? {
        if let configuration = gateConfiguration(for: selection) {
            return configuration.xChannelName
        }
        let table = tableForSelection(selection)
        guard let table else { return nil }
        let axes = AppModel.defaultAxisSelection(for: table)
        return table.channels[axes.x].displayName
    }

    private func tableValue(for column: WorkspaceTableColumn, sample: WorkspaceSample) -> Double? {
        let path = column.gatePath.isEmpty ? [] : gatePathMatching(column.gatePath, in: sample.gates)
        if !column.gatePath.isEmpty, path.isEmpty {
            return nil
        }
        let mask = path.isEmpty
            ? EventMask(count: sample.table.rowCount, fill: true)
            : evaluate(path: path, sample: sample)
        switch column.statistic {
        case .count:
            return Double(mask.selectedCount)
        case .percentParent:
            let parentCount = parentCount(for: path, sample: sample)
            guard parentCount > 0 else { return nil }
            return Double(mask.selectedCount) / Double(parentCount) * 100
        case .percentTotal:
            guard sample.table.rowCount > 0 else { return nil }
            return Double(mask.selectedCount) / Double(sample.table.rowCount) * 100
        case .median, .mean, .geometricMean:
            guard let channelIndex = statisticChannelIndex(named: column.channelName, in: sample.table) else { return nil }
            let values = selectedFiniteValues(sample.table.column(channelIndex), mask: mask)
            guard !values.isEmpty else { return nil }
            switch column.statistic {
            case .median:
                return Double(median(values))
            case .mean:
                return Double(values.reduce(Float(0), +) / Float(values.count))
            case .geometricMean:
                let positive = values.filter { $0 > 0 }
                guard !positive.isEmpty else { return nil }
                let logMean = positive.map { log(Double($0)) }.reduce(0, +) / Double(positive.count)
                return exp(logMean)
            case .count, .percentParent, .percentTotal:
                return nil
            }
        }
    }

    private func gatePathMatching(_ names: [String], in gates: [WorkspaceGateNode]) -> [WorkspaceGateNode] {
        guard let firstName = names.first else { return [] }
        for gate in gates where gate.name == firstName {
            if names.count == 1 {
                return [gate]
            }
            let childPath = gatePathMatching(Array(names.dropFirst()), in: gate.children)
            if !childPath.isEmpty {
                return [gate] + childPath
            }
        }
        return []
    }

    private func parentCount(for path: [WorkspaceGateNode], sample: WorkspaceSample) -> Int {
        guard path.count > 1 else { return sample.table.rowCount }
        return evaluate(path: Array(path.dropLast()), sample: sample).selectedCount
    }

    private func statisticChannelIndex(named name: String?, in table: EventTable) -> Int? {
        if let name, let index = channelIndex(named: name, in: table) {
            return index
        }
        if let name {
            let normalizedName = normalizedChannelName(name)
            if let index = table.channels.firstIndex(where: { normalizedChannelName($0.displayName) == normalizedName }) {
                return index
            }
        }
        return AppModel.defaultAxisSelection(for: table).x
    }

    private func selectedFiniteValues(_ values: [Float], mask: EventMask) -> [Float] {
        guard mask.count == values.count else { return [] }
        var output: [Float] = []
        output.reserveCapacity(mask.selectedCount)
        for index in values.indices where mask[index] {
            let value = values[index]
            if value.isFinite {
                output.append(value)
            }
        }
        return output
    }

    private func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func tableForSelection(_ selection: WorkspaceSelection?) -> EventTable? {
        guard let selection else { return samples.first?.table }
        if selection.isAllSamples {
            return samples.first?.table
        }
        return sample(id: selection.sampleID)?.table
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
                    isSynced: isGroup ? allSamplesMatchTemplate(path: currentPath) : sampleGateMatchesTemplate(path: currentPath),
                    compensationBadge: nil
                )
            )
            appendGateRows(gate.children, sampleID: sampleID, depth: depth + 1, output: &output, isGroup: isGroup, path: currentPath)
        }
    }

    private func sample(id: UUID) -> WorkspaceSample? {
        samples.first { $0.id == id }
    }

    private func compensationBadge(for sample: WorkspaceSample) -> WorkspaceCompensationBadge? {
        if let matrix = compensationMatrix(id: sample.compensationMatrixID) {
            let style: WorkspaceCompensationBadge.Style = matrix.locked ? .assignedAcquisition : .assignedUser
            return WorkspaceCompensationBadge(
                matrixID: matrix.id,
                style: style,
                colorHex: matrix.colorHex,
                tooltip: "\(matrix.name) assigned"
            )
        }
        if let matrix = compensationMatrix(id: sample.acquisitionCompensationMatrixID) {
            return WorkspaceCompensationBadge(
                matrixID: matrix.id,
                style: .available,
                colorHex: matrix.colorHex,
                tooltip: "\(matrix.name) available"
            )
        }
        return nil
    }

    private func existingCompensationMatrixID(for sample: WorkspaceSample) -> UUID? {
        if let matrixID = sample.compensationMatrixID, compensationMatrix(id: matrixID) != nil {
            return matrixID
        }
        if let matrixID = sample.acquisitionCompensationMatrixID, compensationMatrix(id: matrixID) != nil {
            return matrixID
        }
        return nil
    }

    private func reapplyMatrixToAssignedSamples(_ matrix: CompensationMatrix) {
        do {
            let updatedTables = try samples
                .filter { $0.compensationMatrixID == matrix.id }
                .map { sample in
                    (sample.id, try CompensationEngine.apply(matrix, to: sample.rawTable))
                }
            objectWillChange.send()
            for (sampleID, table) in updatedTables {
                guard let sample = sample(id: sampleID) else { continue }
                sample.table = table
                refreshCounts(in: sample)
            }
            invalidateAnalysisAfterCompensationChange()
        } catch {
            status = "Could not reapply compensation: \(error.localizedDescription)"
        }
    }

    private func invalidateAnalysisAfterCompensationChange() {
        gateMaskCache.removeAll()
        layoutPlotSnapshotCache.removeAll()
        channelIndexLookupCache.removeAll()
        signatureChannelNameCache.removeAll()
        gateChangeVersion += 1
    }

    private func uniqueMatrixName(_ baseName: String) -> String {
        let existing = Set(compensationMatrices.map(\.name))
        guard existing.contains(baseName) else { return baseName }
        var index = 2
        while existing.contains("\(baseName) \(index)") {
            index += 1
        }
        return "\(baseName) \(index)"
    }

    private func nextMatrixColorHex() -> String {
        let colors = ["#007AFF", "#FF3B30", "#30B0C7", "#AF52DE", "#FF9500", "#34C759"]
        let assigned = Set(compensationMatrices.compactMap(\.colorHex))
        return colors.first { !assigned.contains($0) } ?? colors[compensationMatrices.count % colors.count]
    }

    private func defaultCompensationParameters(for sample: WorkspaceSample) -> [String] {
        let candidates = sample.rawTable.channels.map(\.name).filter { name in
            let upper = name.uppercased()
            return !upper.hasPrefix("FSC")
                && !upper.hasPrefix("SSC")
                && upper != "TIME"
                && !upper.contains("WIDTH")
        }
        let areaChannels = candidates.filter { $0.uppercased().hasSuffix("-A") }
        return areaChannels.count >= 2 ? areaChannels : candidates
    }

    private func isCompensationControlSample(_ sample: WorkspaceSample) -> Bool {
        guard sample.kind == .fcs else { return false }
        var haystack = sample.name
        if let fileName = sample.metadata?.keywords["$FIL"] ?? sample.metadata?.keywords["FIL"] {
            haystack += " \(fileName)"
        }
        if let sampleID = sample.metadata?.keywords["$SMNO"] ?? sample.metadata?.keywords["SMNO"] {
            haystack += " \(sampleID)"
        }
        let normalized = haystack.lowercased()
        return normalized.contains("comp") || normalized.contains("unstained")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func beginProgress(title: String, detail: String, fraction: Double?) -> UUID {
        let id = UUID()
        activeProgressID = id
        progress = WorkspaceProgress(title: title, detail: detail, fraction: fraction)
        status = detail
        return id
    }

    private func updateProgress(_ id: UUID, title: String, detail: String, fraction: Double?) {
        guard activeProgressID == id else { return }
        let resolvedFraction = fraction.map { min(max($0, 0), 1) }
        progress = WorkspaceProgress(title: title, detail: detail, fraction: resolvedFraction)
        status = detail
    }

    private func updateScoringProgress(
        _ id: UUID,
        sampleName: String,
        progress scoringProgress: SeqtometryScoringProgress,
        lowerBound: Double,
        upperBound: Double
    ) {
        let fraction = lowerBound + scoringProgress.fractionCompleted * (upperBound - lowerBound)
        let percent = Int((scoringProgress.fractionCompleted * 100).rounded())
        updateProgress(
            id,
            title: "Computing Signatures",
            detail: "Scoring \(scoringProgress.signatureCount) signature(s) for \(sampleName): \(scoringProgress.completedCells.formatted()) / \(scoringProgress.totalCells.formatted()) cells (\(percent)%)",
            fraction: fraction
        )
    }

    private func finishProgress(_ id: UUID, status: String) {
        guard activeProgressID == id else { return }
        progress = nil
        activeProgressID = nil
        self.status = status
    }

    private func mergeSignatures(_ signatures: [SeqtometrySignature]) {
        for signature in signatures {
            if let index = loadedSignatures.firstIndex(where: { $0.name == signature.name }) {
                loadedSignatures[index] = signature
            } else {
                loadedSignatures.append(signature)
            }
        }
    }

    private func chooseSignaturesForSingleCellLoad(matrixURLs: [URL]) -> SignatureSelectionResult? {
        SignatureSelectionDialog.present(
            matrixURLs: matrixURLs,
            sources: signatureSelectionSources()
        )
    }

    private func signatureSelectionSources() -> [SignatureSelectionSource] {
        var sources: [SignatureSelectionSource] = []

        if !loadedSignatures.isEmpty {
            sources.append(
                SignatureSelectionSource(
                    name: "Loaded signatures",
                    signatures: loadedSignatures,
                    isSelectedByDefault: true
                )
            )
        }

        if let pbmcSignatures = try? bundledSeqtometrySignatures() {
            sources.append(
                SignatureSelectionSource(
                    name: "PBMC bundled signatures",
                    signatures: pbmcSignatures,
                    isSelectedByDefault: loadedSignatures.isEmpty
                )
            )
        }

        if let defaultSignatures = try? bundledDefaultImmuneSignatures() {
            sources.append(
                SignatureSelectionSource(
                    name: "Default immune signatures",
                    signatures: defaultSignatures,
                    isSelectedByDefault: false
                )
            )
        }

        return sources
    }

    private func bundledSeqtometrySignatures() throws -> [SeqtometrySignature] {
        guard let signatureURL = Bundle.main.url(
            forResource: "SeqtometryPBMCSignatures",
            withExtension: "tsv"
        ) else {
            throw SeqtometrySignatureError.noSignatures
        }
        return try SeqtometrySignatureParser.load(url: signatureURL)
    }

    private func bundledDefaultImmuneSignatures() throws -> [SeqtometrySignature] {
        guard let signatureURL = Bundle.main.url(
            forResource: "DefaultImmuneSignatures",
            withExtension: "tsv"
        ) else {
            throw SeqtometrySignatureError.noSignatures
        }
        return try SeqtometrySignatureParser.load(url: signatureURL)
    }

    private func applySignaturesToSingleCellSamples(_ signatures: [SeqtometrySignature], sourceName: String) {
        let targetSamples = samples.filter { $0.kind == .singleCell }
        guard !targetSamples.isEmpty else {
            status = "Loaded \(signatures.count) signature(s) from \(sourceName). Drop a single-cell matrix to score it."
            return
        }

        status = "Applying \(signatures.count) Seqtometry signature(s) to \(targetSamples.count) sample(s)..."
        for sample in targetSamples {
            let sampleID = sample.id
            let sampleName = sample.name
            let table = sample.table
            let progressID = beginProgress(
                title: "Computing Signatures",
                detail: "Scoring \(signatures.count) signature(s) for \(sampleName)",
                fraction: 0
            )
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let scoredTable = try SeqtometryScorer.tableByAppendingScores(
                        to: table,
                        signatures: signatures,
                        progress: { progress in
                            Task { @MainActor in
                                self.updateScoringProgress(
                                    progressID,
                                    sampleName: sampleName,
                                    progress: progress,
                                    lowerBound: 0,
                                    upperBound: 0.96
                                )
                            }
                        }
                    )
                    Task { @MainActor in
                        guard let target = self.sample(id: sampleID) else { return }
                        self.gateMaskCache.removeAll()
                        target.rawTable = scoredTable
                        target.table = scoredTable
                        self.refreshCounts(in: target)
                        self.gateChangeVersion += 1
                        self.finishProgress(progressID, status: "Applied \(signatures.count) signature score channel(s) from \(sourceName).")
                    }
                } catch {
                    Task { @MainActor in
                        self.finishProgress(progressID, status: "Could not apply \(sourceName) to \(sampleName): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func refreshCounts(in sample: WorkspaceSample) {
        for gate in sample.gates {
            refreshCounts(for: gate, in: sample)
        }
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
                guard templateTree(template, isCompatibleWith: sample.table) else { continue }
                let node = upsertTemplate(template, into: &sample.gates)
                refreshCounts(for: node, in: sample)
            }
        }
    }

    private func applyGroupTemplatesToSamples(_ templates: [WorkspaceGateNode]) {
        for template in templates {
            guard let templatePath = gatePath(template.id, in: groupGates), !templatePath.isEmpty else { continue }
            for sample in samples {
                guard templatePath.allSatisfy({ templateTree($0, isCompatibleWith: sample.table) }) else { continue }
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

    private func templateTree(_ node: WorkspaceGateNode, isCompatibleWith table: EventTable) -> Bool {
        channelIndex(named: node.xChannelName, in: table) != nil
            && channelIndex(named: node.yChannelName, in: table) != nil
            && node.children.allSatisfy { templateTree($0, isCompatibleWith: table) }
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
        guard let lastGate = path.last else {
            return EventMask(count: sample.table.rowCount, fill: true)
        }
        if let cached = cachedGateMask(sample: sample, gateID: lastGate.id) {
            return cached
        }

        var mask: EventMask?
        var startIndex = path.startIndex
        for index in path.indices.reversed() {
            if let cached = cachedGateMask(sample: sample, gateID: path[index].id) {
                mask = cached
                startIndex = path.index(after: index)
                break
            }
        }

        for node in path[startIndex...] {
            mask = evaluate(
                gate: node.gate,
                sample: sample,
                base: mask,
                xChannelName: node.xChannelName,
                yChannelName: node.yChannelName,
                xAxisSettings: node.xAxisSettings,
                yAxisSettings: node.yAxisSettings
            )
            if let mask {
                storeGateMask(mask, sample: sample, gateID: node.id)
            }
        }
        return mask ?? EventMask(count: sample.table.rowCount, fill: true)
    }

    private func cachedGateMask(sample: WorkspaceSample, gateID: UUID) -> EventMask? {
        gateMaskCache[gateMaskCacheKey(sample: sample, gateID: gateID)]
    }

    private func storeGateMask(_ mask: EventMask, sample: WorkspaceSample, gateID: UUID) {
        gateMaskCache[gateMaskCacheKey(sample: sample, gateID: gateID)] = mask
    }

    private func gateMaskCacheKey(sample: WorkspaceSample, gateID: UUID) -> String {
        [
            sample.id.uuidString,
            gateID.uuidString,
            "\(sample.table.rowCount)",
            "\(sample.table.channelCount)"
        ].joined(separator: "::")
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
        let lookup = channelIndexLookup(for: table)
        if let exact = lookup[name] {
            return exact
        }
        return lookup[normalizedChannelName(name)]
    }

    private func channelIndexLookup(for table: EventTable) -> [String: Int] {
        let key = ObjectIdentifier(table)
        if let cached = channelIndexLookupCache[key] {
            return cached
        }

        var lookup: [String: Int] = [:]
        lookup.reserveCapacity(table.channelCount * 3)

        func insert(_ name: String, index: Int) {
            guard !name.isEmpty, lookup[name] == nil else { return }
            lookup[name] = index
        }

        for (index, channel) in table.channels.enumerated() {
            insert(channel.name, index: index)
            insert(channel.displayName, index: index)
            insert(normalizedChannelName(channel.name), index: index)
            insert(normalizedChannelName(channel.displayName), index: index)
        }

        channelIndexLookupCache[key] = lookup
        return lookup
    }

    private func signatureChannelNames(for table: EventTable) -> [String] {
        let key = ObjectIdentifier(table)
        if let cached = signatureChannelNameCache[key] {
            return cached
        }
        let names = table.channels.compactMap { channel in
            channel.kind == .seqtometrySignature ? channel.displayName : nil
        }
        signatureChannelNameCache[key] = names
        return names
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
