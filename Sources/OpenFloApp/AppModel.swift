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
    private static var axisWindowControllers: [NSWindowController] = []

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
    @Published private var axisSettingsByChannelName: [String: AxisDisplaySettings] = [:]

    private var baseMask: EventMask?
    private let renderQueue = DispatchQueue(label: "OpenFlo.render", qos: .userInitiated)
    private var projectedX: [Float] = []
    private var projectedY: [Float] = []
    private var renderGeneration = 0
    private var pendingGateEvaluation: PolygonGate?

    init(
        table: EventTable,
        baseMask: EventMask? = nil,
        populationTitle: String = "All Events",
        xChannel: Int? = nil,
        yChannel: Int? = nil,
        xTransform: TransformKind = .linear,
        yTransform: TransformKind = .linear,
        xAxisSettings: AxisDisplaySettings? = nil,
        yAxisSettings: AxisDisplaySettings? = nil
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
        if let xAxisSettings {
            saveAxisSettings(xAxisSettings, forChannel: self.xChannel)
            self.xTransform = xAxisSettings.transform
        }
        if let yAxisSettings {
            saveAxisSettings(yAxisSettings, forChannel: self.yChannel)
            self.yTransform = yAxisSettings.transform
        }
        if xTransform == .linear {
            self.xTransform = Self.defaultTransform(for: table.channels[self.xChannel])
        } else {
            self.xTransform = xTransform
        }
        if yTransform == .linear {
            self.yTransform = Self.defaultTransform(for: table.channels[self.yChannel])
        } else {
            self.yTransform = yTransform
        }
        syncCurrentTransformsFromSettings()
        recomputePlot(reason: baseMask == nil ? "Plot loaded" : "Population loaded")
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
        guard let baseMask else { return table.rowCount }
        guard baseMask.count == table.rowCount else { return 0 }
        return baseMask.selectedCount
    }

    var currentXChannelName: String {
        channels[xChannel].name
    }

    var currentYChannelName: String {
        channels[yChannel].name
    }

    func axisSettings(for axis: PlotAxis) -> AxisDisplaySettings {
        axisSettings(forChannel: channelIndex(for: axis))
    }

    func axisRange(for axis: PlotAxis) -> ClosedRange<Float> {
        switch axis {
        case .x:
            return xRange
        case .y:
            return plotMode == .histogram ? xRange : yRange
        }
    }

    func channelIndex(for axis: PlotAxis) -> Int {
        switch axis {
        case .x:
            return xChannel
        case .y:
            return plotMode == .histogram ? xChannel : yChannel
        }
    }

    func setAxisTransform(_ transform: TransformKind, for axis: PlotAxis) {
        let channelIndex = channelIndex(for: axis)
        var settings = axisSettings(forChannel: channelIndex)
        settings.transform = transform
        settings.minimum = nil
        settings.maximum = nil
        saveAxisSettings(settings, forChannel: channelIndex)
        syncCurrentTransformsFromSettings()
        clearGate(recompute: false)
        recomputePlot(reason: "\(axis.title) set to \(transform.displayName)")
    }

    func resetAxis(_ axis: PlotAxis) {
        let channelName = channels[channelIndex(for: axis)].name
        axisSettingsByChannelName[channelName] = nil
        syncCurrentTransformsFromSettings()
        clearGate(recompute: false)
        recomputePlot(reason: "\(axis.title) reset")
    }

    func applyAxisSettings(_ settings: AxisDisplaySettings, toChannelIndices channelIndices: Set<Int>) {
        guard !channelIndices.isEmpty else { return }
        for index in channelIndices where channels.indices.contains(index) {
            saveAxisSettings(settings, forChannel: index)
        }
        syncCurrentTransformsFromSettings()
        clearGate(recompute: false)
        recomputePlot(reason: "Axis settings applied")
    }

    func automaticRange(forChannel channelIndex: Int, settings: AxisDisplaySettings) -> ClosedRange<Float> {
        guard channels.indices.contains(channelIndex) else { return 0...1 }
        let values = Self.applyTransform(settings, to: table.column(channelIndex))
        return settings.resolvedRange(auto: EventTable.range(values: values, mask: baseMask))
    }

    func previewHistogram(
        channelIndex: Int,
        settings: AxisDisplaySettings,
        range: ClosedRange<Float>,
        binCount: Int = 220,
        maxSamples: Int = 200_000
    ) -> [UInt32] {
        guard channels.indices.contains(channelIndex), binCount > 0 else { return [] }
        let rawValues = table.column(channelIndex)
        guard !rawValues.isEmpty else { return Array(repeating: 0, count: binCount) }
        let selectedCount = baseMask?.selectedCount ?? rawValues.count
        let sampleStride = max(1, selectedCount / max(1, maxSamples))
        let span = range.upperBound - range.lowerBound
        guard span.isFinite, span > 0 else { return Array(repeating: 0, count: binCount) }

        var bins = Array(repeating: UInt32(0), count: binCount)
        var selectedIndex = 0
        for index in rawValues.indices {
            if let baseMask {
                guard baseMask.count == rawValues.count, baseMask[index] else { continue }
            }
            defer { selectedIndex += 1 }
            guard selectedIndex % sampleStride == 0 else { continue }
            let value = Self.applyTransform(settings, to: rawValues[index])
            guard value.isFinite, value >= range.lowerBound, value <= range.upperBound else { continue }
            let fraction = (value - range.lowerBound) / span
            let bin = min(max(Int(fraction * Float(binCount)), 0), binCount - 1)
            bins[bin] = bins[bin].addingReportingOverflow(1).partialValue
        }
        return bins
    }

    func openAxisCustomizationWindow(for axis: PlotAxis) {
        let channel = channels[channelIndex(for: axis)]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transform of \(populationTitle): \(channel.displayName)"
        window.center()
        window.contentView = NSHostingView(
            rootView: AxisTransformEditorView(model: self, axis: axis)
        )
        let controller = NSWindowController(window: window)
        Self.axisWindowControllers.append(controller)
        controller.showWindow(nil)
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
                    self.axisSettingsByChannelName = [:]
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

    func axesChanged(restoredGate: PolygonGate? = nil) {
        syncCurrentTransformsFromSettings()
        pendingGateEvaluation = restoredGate
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
        syncCurrentTransformsFromSettings()
        let generation = renderGeneration + 1
        renderGeneration = generation
        status = "Rendering..."

        let table = self.table
        let xChannel = self.xChannel
        let yChannel = self.yChannel
        let xSettings = axisSettings(forChannel: xChannel)
        let ySettings = axisSettings(forChannel: yChannel)
        let plotMode = self.plotMode
        let baseMask: EventMask?
        let repairedPopulationMask: Bool
        if let currentBaseMask = self.baseMask, currentBaseMask.count != table.rowCount {
            baseMask = EventMask(count: table.rowCount)
            self.baseMask = baseMask
            repairedPopulationMask = true
        } else {
            baseMask = self.baseMask
            repairedPopulationMask = false
        }

        renderQueue.async {
            let xValues = Self.applyTransform(xSettings, to: table.column(xChannel))
            let yValues = Self.applyTransform(ySettings, to: table.column(yChannel))
            let resolvedXRange = xSettings.resolvedRange(auto: EventTable.range(values: xValues, mask: baseMask))
            let resolvedYRange: ClosedRange<Float>
            let image: NSImage
            if plotMode == .histogram {
                let histogram = Histogram1D.build(values: xValues, mask: baseMask, width: 640, xRange: resolvedXRange)
                resolvedYRange = Self.histogramYRange(maxBin: histogram.maxBin)
                image = HistogramRenderer.image(from: histogram, yRange: resolvedYRange)
            } else {
                resolvedYRange = ySettings.resolvedRange(auto: EventTable.range(values: yValues, mask: baseMask))
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
                if repairedPopulationMask {
                    self.status = "\(reason). Population mask no longer matched this sample; showing 0 visible events."
                } else {
                    self.status = "\(reason). \(self.visibleEventCount.formatted()) visible events, \(table.channelCount) channels."
                }
                if let pendingGate = self.pendingGateEvaluation {
                    self.pendingGateEvaluation = nil
                    self.applyGate(pendingGate)
                }
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
        preferredYTransform: TransformKind? = nil,
        preferredXAxisSettings: AxisDisplaySettings? = nil,
        preferredYAxisSettings: AxisDisplaySettings? = nil,
        restoredGate: PolygonGate? = nil
    ) {
        self.table = table
        self.baseMask = baseMask
        self.populationTitle = title
        pendingGateEvaluation = restoredGate
        projectedX = []
        projectedY = []
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
        if let preferredXAxisSettings {
            saveAxisSettings(preferredXAxisSettings, forChannel: xChannel)
        } else if let preferredXTransform {
            saveAxisSettings(AxisDisplaySettings(transform: preferredXTransform), forChannel: xChannel)
        }
        if let preferredYAxisSettings {
            saveAxisSettings(preferredYAxisSettings, forChannel: yChannel)
        } else if let preferredYTransform {
            saveAxisSettings(AxisDisplaySettings(transform: preferredYTransform), forChannel: yChannel)
        }
        xTransform = preferredXAxisSettings?.transform ?? preferredXTransform ?? axisSettings(forChannel: xChannel).transform
        yTransform = preferredYAxisSettings?.transform ?? preferredYTransform ?? axisSettings(forChannel: yChannel).transform
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

    func showGateOverlay(_ gate: PolygonGate) {
        activeGate = gate
        gateMask = nil
        gateLabelPosition = defaultLabelPosition(for: gate)
    }

    func restoreGateWhenReady(_ gate: PolygonGate) {
        if projectedX.count == table.rowCount, projectedY.count == table.rowCount {
            applyGate(gate)
        } else {
            pendingGateEvaluation = gate
        }
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
            yTransform: yTransform,
            xAxisSettings: axisSettings(for: .x),
            yAxisSettings: axisSettings(for: .y)
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

    private func axisSettings(forChannel channelIndex: Int) -> AxisDisplaySettings {
        guard channels.indices.contains(channelIndex) else {
            return AxisDisplaySettings(transform: .linear)
        }
        let channel = channels[channelIndex]
        return axisSettingsByChannelName[channel.name] ?? AxisDisplaySettings(transform: Self.defaultTransform(for: channel))
    }

    private func saveAxisSettings(_ settings: AxisDisplaySettings, forChannel channelIndex: Int) {
        guard channels.indices.contains(channelIndex) else { return }
        axisSettingsByChannelName[channels[channelIndex].name] = settings
    }

    private func syncCurrentTransformsFromSettings() {
        if channels.indices.contains(xChannel) {
            xTransform = axisSettings(forChannel: xChannel).transform
        }
        if channels.indices.contains(yChannel) {
            yTransform = axisSettings(forChannel: yChannel).transform
        }
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

    private nonisolated static func applyTransform(_ settings: AxisDisplaySettings, to value: Float) -> Float {
        settings.transform.apply(
            value,
            cofactor: pow(Float(10), settings.widthBasis),
            extraNegativeDecades: settings.extraNegativeDecades,
            widthBasis: settings.widthBasis,
            positiveDecades: settings.positiveDecades
        )
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
        return .logicle
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
        let normalizedName = normalizedChannelName(name)
        return table.channels.firstIndex { channel in
            channel.name == name
                || channel.displayName == name
                || normalizedChannelName(channel.name) == normalizedName
                || normalizedChannelName(channel.displayName) == normalizedName
        }
    }

    private func normalizedChannelName(_ name: String) -> String {
        name.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private nonisolated static func histogramYRange(maxBin: UInt32) -> ClosedRange<Float> {
        let maximum = max(Float(maxBin), 1)
        let exponent = floor(log10(maximum))
        let magnitude = pow(Float(10), exponent)
        let fraction = maximum / magnitude
        let niceFraction: Float
        if fraction <= 1 {
            niceFraction = 1
        } else if fraction <= 2 {
            niceFraction = 2
        } else if fraction <= 2.5 {
            niceFraction = 2.5
        } else if fraction <= 5 {
            niceFraction = 5
        } else {
            niceFraction = 10
        }
        return 0...(niceFraction * magnitude)
    }

    private func defaultLabelPosition(for gate: PolygonGate) -> PlotPoint {
        let x = gate.vertices.map(\.x).reduce(0, +) / Float(gate.vertices.count)
        let y = gate.vertices.map(\.y).reduce(0, +) / Float(gate.vertices.count)
        return PlotPoint(x: x, y: y)
    }
}
