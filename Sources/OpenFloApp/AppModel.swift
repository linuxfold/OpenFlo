import AppKit
import Foundation
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

enum GateTool: String, CaseIterable, Identifiable, Sendable {
    case cursor = "Cursor"
    case rectangle = "Rectangle"
    case oval = "Oval"
    case polygon = "Custom"
    case xCutoff = "X Cut"
    case quadrant = "Quadrant"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cursor:
            return "cursorarrow"
        case .rectangle:
            return "rectangle"
        case .oval:
            return "oval"
        case .polygon:
            return "pentagon"
        case .xCutoff:
            return "line.vertical"
        case .quadrant:
            return "plus"
        }
    }
}

enum PlotMode: String, CaseIterable, Identifiable, Sendable {
    case scatter = "Scatter"
    case histogram = "Histogram"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    private static var childWindowControllers: [NSWindowController] = []

    @Published private(set) var table: EventTable
    @Published private(set) var populationTitle: String
    @Published var xChannel: Int = 0
    @Published var yChannel: Int = 1
    @Published var xTransform: TransformKind = .linear
    @Published var yTransform: TransformKind = .linear
    @Published var gateTool: GateTool = .cursor
    @Published var plotMode: PlotMode = .scatter
    @Published private(set) var plotImage: NSImage?
    @Published private(set) var xRange: ClosedRange<Float> = 0...1
    @Published private(set) var yRange: ClosedRange<Float> = 0...1
    @Published private(set) var status: String = "Ready"
    @Published private(set) var activeGate: PolygonGate?
    @Published private(set) var gateMask: EventMask?
    @Published var gateLabelPosition: PlotPoint?

    private var baseMask: EventMask?
    private let renderQueue = DispatchQueue(label: "OpenFlo.render", qos: .userInitiated)
    private var projectedX: [Float] = []
    private var projectedY: [Float] = []
    private var renderGeneration = 0

    init(
        table: EventTable = EventTable.synthetic(events: 750_000),
        baseMask: EventMask? = nil,
        populationTitle: String = "All Events",
        xChannel: Int? = nil,
        yChannel: Int? = nil,
        xTransform: TransformKind = .linear,
        yTransform: TransformKind = .linear
    ) {
        self.table = table
        self.baseMask = baseMask
        self.populationTitle = populationTitle
        self.xTransform = xTransform
        self.yTransform = yTransform
        if let xChannel, let yChannel {
            self.xChannel = xChannel
            self.yChannel = yChannel
        } else {
            let axes = Self.defaultAxisSelection(for: table)
            self.xChannel = axes.x
            self.yChannel = axes.y
        }
        if xTransform == .linear {
            self.xTransform = Self.defaultTransform(for: table.channels[self.xChannel])
        }
        if yTransform == .linear {
            self.yTransform = Self.defaultTransform(for: table.channels[self.yChannel])
        }
        recomputePlot(reason: baseMask == nil ? "Synthetic data loaded" : "Population loaded")
    }

    var channels: [Channel] {
        table.channels
    }

    var selectedCountText: String {
        guard let gateMask else {
            return "No gate"
        }
        return "\(gateMask.selectedCount.formatted()) / \(visibleEventCount.formatted())  \(gatePercentText)"
    }

    var gatePercentText: String {
        guard let gateMask, visibleEventCount > 0 else { return "" }
        let percent = Double(gateMask.selectedCount) / Double(visibleEventCount) * 100
        return String(format: "%.1f%%", percent)
    }

    var visibleEventCount: Int {
        baseMask?.selectedCount ?? table.rowCount
    }

    var currentXChannelName: String {
        channels[xChannel].name
    }

    var currentYChannelName: String {
        channels[yChannel].name
    }

    func openFCSPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let fcsType = UTType(filenameExtension: "fcs") {
            panel.allowedContentTypes = [fcsType]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFCS(url: url)
    }

    func loadFCS(url: URL) {
        status = "Loading \(url.lastPathComponent)..."
        renderQueue.async {
            do {
                let file = try FCSParser.load(url: url)
                Task { @MainActor in
                    self.table = file.table
                    self.baseMask = nil
                    self.populationTitle = "All Events"
                    let axes = Self.defaultAxisSelection(for: file.table)
                    self.xChannel = axes.x
                    self.yChannel = axes.y
                    self.clearGate(recompute: false)
                    self.recomputePlot(reason: "Loaded \(url.lastPathComponent)")
                }
            } catch {
                Task { @MainActor in
                    self.status = error.localizedDescription
                }
            }
        }
    }

    func loadSynthetic(events: Int) {
        status = "Generating \(events.formatted()) synthetic events..."
        renderQueue.async {
            let table = EventTable.synthetic(events: events)
            Task { @MainActor in
                self.table = table
                self.baseMask = nil
                self.populationTitle = "All Events"
                self.xChannel = 0
                self.yChannel = 1
                self.clearGate(recompute: false)
                self.recomputePlot(reason: "Synthetic data loaded")
            }
        }
    }

    func axesChanged() {
        xTransform = Self.defaultTransform(for: channels[xChannel])
        yTransform = Self.defaultTransform(for: channels[yChannel])
        clearGate(recompute: false)
        recomputePlot(reason: "Axes updated")
    }

    func plotModeChanged(_ mode: PlotMode) {
        guard plotMode != mode else { return }
        plotMode = mode
        clearGate(recompute: false)
        recomputePlot(reason: "\(mode.rawValue) view")
    }

    func transformsChanged() {
        clearGate(recompute: false)
        recomputePlot(reason: "Transform updated")
    }

    func recomputePlot(reason: String = "Plot updated") {
        let generation = renderGeneration + 1
        renderGeneration = generation
        status = "Rendering..."

        let table = self.table
        let xChannel = self.xChannel
        let yChannel = self.yChannel
        let xTransform = self.xTransform
        let yTransform = self.yTransform
        let plotMode = self.plotMode
        let baseMask = self.baseMask

        renderQueue.async {
            let xValues = xTransform.apply(to: table.column(xChannel))
            let yValues = yTransform.apply(to: table.column(yChannel))
            let resolvedXRange = EventTable.range(values: xValues, mask: baseMask)
            let resolvedYRange: ClosedRange<Float>
            let image: NSImage
            if plotMode == .histogram {
                let histogram = Histogram1D.build(values: xValues, mask: baseMask, width: 640, xRange: resolvedXRange)
                resolvedYRange = 0...Float(max(histogram.maxBin, 1))
                image = HistogramRenderer.image(from: histogram)
            } else {
                resolvedYRange = EventTable.range(values: yValues, mask: baseMask)
                let histogram = Histogram2D.build(
                    xValues: xValues,
                    yValues: yValues,
                    mask: baseMask,
                    width: 640,
                    height: 640,
                    xRange: resolvedXRange,
                    yRange: resolvedYRange
                )
                image = HeatmapRenderer.image(from: histogram)
            }

            Task { @MainActor in
                guard generation == self.renderGeneration else { return }
                self.projectedX = xValues
                self.projectedY = yValues
                self.xRange = resolvedXRange
                self.yRange = resolvedYRange
                self.plotImage = image
                self.status = "\(reason). \(self.visibleEventCount.formatted()) visible events, \(table.channelCount) channels."
            }
        }
    }

    func setPopulation(
        table: EventTable,
        baseMask: EventMask?,
        title: String,
        preferredXChannelName: String? = nil,
        preferredYChannelName: String? = nil,
        preferredXTransform: TransformKind? = nil,
        preferredYTransform: TransformKind? = nil
    ) {
        self.table = table
        self.baseMask = baseMask
        self.populationTitle = title
        if let preferredXChannelName, let index = channelIndex(named: preferredXChannelName, in: table) {
            xChannel = index
        } else if xChannel >= table.channelCount {
            xChannel = Self.defaultAxisSelection(for: table).x
        }
        if let preferredYChannelName, let index = channelIndex(named: preferredYChannelName, in: table), index != xChannel {
            yChannel = index
        } else if yChannel >= table.channelCount || yChannel == xChannel {
            yChannel = Self.defaultAxisSelection(for: table).y
        }
        xTransform = preferredXTransform ?? Self.defaultTransform(for: table.channels[xChannel])
        yTransform = preferredYTransform ?? Self.defaultTransform(for: table.channels[yChannel])
        clearGate(recompute: false)
        recomputePlot(reason: "Population selected")
    }

    func applyRectangleGate(xRange: ClosedRange<Float>, yRange: ClosedRange<Float>) {
        let gate = PolygonGate.rectangle(name: "Rectangle", xRange: xRange, yRange: yRange)
        applyGate(gate)
    }

    func applyGate(_ gate: PolygonGate, resetLabel: Bool = true) {
        let xValues = projectedX
        let yValues = projectedY
        let baseMask = self.baseMask
        activeGate = gate
        gateMask = nil
        if resetLabel || gateLabelPosition == nil {
            gateLabelPosition = defaultLabelPosition(for: gate)
        }
        status = "Evaluating gate..."

        renderQueue.async {
            let mask = gate.evaluate(xValues: xValues, yValues: yValues, base: baseMask)
            Task { @MainActor in
                self.gateMask = mask
                self.status = "\(gate.name) gate selected \(mask.selectedCount.formatted()) of \(self.visibleEventCount.formatted()) events."
            }
        }
    }

    func updateActiveGate(_ gate: PolygonGate, reevaluate: Bool = true) {
        activeGate = gate
        guard reevaluate else { return }
        applyGate(gate, resetLabel: false)
    }

    func moveGateLabel(to point: PlotPoint) {
        gateLabelPosition = point
    }

    func openActiveGateWindow() {
        guard let gate = activeGate, let gateMask, gateMask.selectedCount > 0 else { return }
        let child = AppModel(
            table: table,
            baseMask: gateMask,
            populationTitle: gate.name,
            xChannel: xChannel,
            yChannel: yChannel,
            xTransform: xTransform,
            yTransform: yTransform
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenFlo - \(gate.name) (\(gateMask.selectedCount.formatted()) events)"
        window.center()
        window.contentView = NSHostingView(
            rootView: StandalonePlotPaneView(model: child)
        )
        let controller = NSWindowController(window: window)
        Self.childWindowControllers.append(controller)
        controller.showWindow(nil)
        status = "Opened \(gate.name) population window."
    }

    func openGateWindowIfPointIsInside(_ point: PlotPoint) {
        guard let activeGate, activeGate.contains(x: point.x, y: point.y) else { return }
        openActiveGateWindow()
    }

    func clearGate(recompute: Bool = true) {
        activeGate = nil
        gateMask = nil
        gateLabelPosition = nil
        if recompute {
            recomputePlot(reason: "Gate cleared")
        }
    }

    static func defaultAxisSelection(for table: EventTable) -> (x: Int, y: Int) {
        let names = table.channels.map { $0.name.uppercased() }

        let x = firstIndex(in: names, exactly: "FSC-A")
            ?? firstIndex(in: names, containingAll: ["FSC", "-A"])
            ?? firstIndex(in: names, containingAll: ["FSC"])
            ?? firstNonTimeIndex(in: names, excluding: nil)
            ?? 0

        let y = firstIndex(in: names, exactly: "SSC-A", excluding: x)
            ?? firstIndex(in: names, containingAll: ["SSC", "-A"], excluding: x)
            ?? firstIndex(in: names, containingAll: ["SSC"], excluding: x)
            ?? firstNonTimeIndex(in: names, excluding: x)
            ?? min(1, max(0, table.channelCount - 1))

        return (x, y == x ? min(x + 1, max(0, table.channelCount - 1)) : y)
    }

    static func defaultTransform(for channel: Channel) -> TransformKind {
        let name = "\(channel.name) \(channel.displayName)".uppercased()
        if name.contains("FSC") || name.contains("SSC") || channel.name.uppercased() == "TIME" {
            return .linear
        }
        return .pseudoLog
    }

    private static func firstIndex(in names: [String], exactly target: String, excluding excluded: Int? = nil) -> Int? {
        names.indices.first { index in
            index != excluded && names[index] == target
        }
    }

    private static func firstIndex(in names: [String], containingAll parts: [String], excluding excluded: Int? = nil) -> Int? {
        names.indices.first { index in
            index != excluded && parts.allSatisfy { names[index].contains($0) }
        }
    }

    private static func firstNonTimeIndex(in names: [String], excluding excluded: Int?) -> Int? {
        names.indices.first { index in
            index != excluded && names[index] != "TIME"
        }
    }

    private func channelIndex(named name: String, in table: EventTable) -> Int? {
        table.channels.firstIndex { channel in
            channel.name == name || channel.displayName == name
        }
    }

    private func defaultLabelPosition(for gate: PolygonGate) -> PlotPoint {
        let x = gate.vertices.map(\.x).reduce(0, +) / Float(gate.vertices.count)
        let y = gate.vertices.map(\.y).reduce(0, +) / Float(gate.vertices.count)
        return PlotPoint(x: x, y: y)
    }
}
