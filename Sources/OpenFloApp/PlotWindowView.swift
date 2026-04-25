import AppKit
import Foundation
import OpenFloCore
import SwiftUI

struct PlotWindowView: View {
    @ObservedObject var workspace: WorkspaceModel
    @StateObject private var model: AppModel
    @State private var selection: WorkspaceSelection
    @State private var activeGateSelection: WorkspaceSelection?
    @State private var isActiveGateSelected = false

    init(workspace: WorkspaceModel, selection: WorkspaceSelection, model: AppModel) {
        self.workspace = workspace
        _selection = State(initialValue: selection)
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScatterPlotView(
                image: model.plotImage,
                xRange: model.xRange,
                yRange: model.yRange,
                gates: visibleGateOverlays,
                selectedGateID: isActiveGateSelected ? activeGateID : nil,
                gateTool: model.gateTool,
                plotMode: model.plotMode,
                xTransform: model.xTransform,
                yTransform: model.yTransform,
                isGateSelected: isActiveGateSelected,
                gateLabelPosition: model.gateLabelPosition,
                gatePercentText: model.gatePercentText,
                channels: model.channels,
                xChannel: model.xChannel,
                yChannel: model.yChannel,
                onXChannelChange: { channel in
                    model.xChannel = channel
                    axesChangedPreservingGate()
                },
                onYChannelChange: { channel in
                    model.plotMode = .scatter
                    model.yChannel = channel
                    axesChangedPreservingGate()
                },
                onPlotModeChange: { mode in
                    model.plotModeChanged(mode)
                },
                onGate: createGate,
                onGateSelected: { gateID in
                    selectGateInPlot(gateID)
                },
                onGateDeselected: {
                    isActiveGateSelected = false
                },
                onGateChanged: updateActiveGate,
                onGateEditEnded: finishGateEdit,
                onGateLabelMoved: { point in
                    model.moveGateLabel(to: point)
                },
                onOpenGate: { gateID, point in
                    guard let match = visibleGateMatches.first(where: { rowID(for: $0.selection) == gateID }),
                          match.gate.contains(x: point.x, y: point.y) else { return }
                    workspace.openPlotWindow(for: match.selection)
                }
            )
            .background(Color.white)
        }
        .onAppear {
            restoreGateForCurrentAxes()
        }
        .onChange(of: workspace.gateChangeVersion) {
            syncGateStateAfterWorkspaceChange()
        }
        .background(
            PlotDeleteKeyMonitor {
                deleteActiveGateFromPlot()
            }
        )
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Label(model.populationTitle, systemImage: "chart.dots.scatter")
                .font(.headline)
                .lineLimit(1)

            Divider()
                .frame(height: 24)

            GateToolStrip(selection: $model.gateTool)

            Spacer()

            Text(model.selectedCountText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button {
                    navigateUp()
                } label: {
                    Image(systemName: "arrowtriangle.up.fill")
                }
                .help("Back to parent population")
                .disabled(workspace.parentSelection(of: selection) == nil)

                Button {
                    navigateDown()
                } label: {
                    Image(systemName: "arrowtriangle.down.fill")
                }
                .help("Forward into active gate")
                .disabled(!canNavigateDown)

                Button {
                    navigateSample(offset: -1)
                } label: {
                    Image(systemName: "arrowtriangle.left.fill")
                }
                .help("Previous sample")
                .disabled(workspace.samples.count < 2)

                Button {
                    navigateSample(offset: 1)
                } label: {
                    Image(systemName: "arrowtriangle.right.fill")
                }
                .help("Next sample")
                .disabled(workspace.samples.count < 2)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(.regularMaterial)
    }

    private var canNavigateDown: Bool {
        guard let activeGateSelection else { return false }
        return workspace.parentSelection(of: activeGateSelection) == selection
    }

    private var activeGateID: String? {
        activeGateSelection.map(rowID(for:))
    }

    private var visibleGateMatches: [(selection: WorkspaceSelection, gate: PolygonGate)] {
        workspace.gatesForAxes(
            parentSelection: selection,
            xChannelName: model.currentXChannelName,
            yChannelName: model.currentYChannelName,
            xTransform: model.xTransform,
            yTransform: model.yTransform
        )
    }

    private var visibleGateOverlays: [PlotGateOverlay] {
        visibleGateMatches.map { PlotGateOverlay(id: rowID(for: $0.selection), gate: $0.gate) }
    }

    private func rowID(for selection: WorkspaceSelection) -> String {
        workspace.rowID(sampleID: selection.sampleID, gateID: selection.gateID)
    }

    private func selectGateInPlot(_ gateID: String) {
        guard let match = visibleGateMatches.first(where: { rowID(for: $0.selection) == gateID }) else { return }
        activeGateSelection = match.selection
        isActiveGateSelected = true
        if model.activeGate != match.gate {
            model.restoreGateWhenReady(match.gate)
        }
    }

    private func createGate(_ gate: PolygonGate) {
        guard let namedGate = promptForGateName(gate) else {
            model.gateTool = .cursor
            return
        }
        let newSelection = workspace.addGateFromPlot(
            namedGate,
            xChannelName: model.currentXChannelName,
            yChannelName: model.currentYChannelName,
            xTransform: model.xTransform,
            yTransform: model.yTransform,
            parentSelection: selection
        )
        activeGateSelection = newSelection
        isActiveGateSelected = false
        model.applyGate(namedGate)
        model.gateTool = .cursor
    }

    private func updateActiveGate(_ gate: PolygonGate) {
        guard let activeGateSelection else {
            model.updateActiveGate(gate, reevaluate: false)
            return
        }
        workspace.updateGate(
            activeGateSelection,
            gate: gate,
            xChannelName: model.currentXChannelName,
            yChannelName: model.currentYChannelName,
            xTransform: model.xTransform,
            yTransform: model.yTransform
        )
        model.updateActiveGate(gate, reevaluate: false)
    }

    private func finishGateEdit(_ gate: PolygonGate) {
        updateActiveGate(gate)
        model.updateActiveGate(gate)
        if let activeGateSelection {
            workspace.refreshCount(for: activeGateSelection)
        }
    }

    private func deleteActiveGateFromPlot() -> Bool {
        guard isActiveGateSelected, let activeGateSelection, let gate = model.activeGate else { return false }
        guard confirmDeleteActiveGate(gate) else { return true }
        workspace.delete(activeGateSelection)
        self.activeGateSelection = nil
        isActiveGateSelected = false
        model.clearGate(recompute: false)
        return true
    }

    private func confirmDeleteActiveGate(_ gate: PolygonGate) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete gate \"\(gate.name)\"?"
        alert.informativeText = "This will remove the gate and any child gates from the workspace."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func axesChangedPreservingGate() {
        let xTransform = AppModel.defaultTransform(for: model.channels[model.xChannel])
        let yTransform = AppModel.defaultTransform(for: model.channels[model.yChannel])
        let match = gateForCurrentAxes(xTransform: xTransform, yTransform: yTransform)
        if let match {
            activeGateSelection = match.selection
        }
        isActiveGateSelected = false
        model.axesChanged(restoredGate: match?.gate)
    }

    private func restoreGateForCurrentAxes() {
        guard let match = gateForCurrentAxes() else { return }
        activeGateSelection = match.selection
        isActiveGateSelected = false
        model.restoreGateWhenReady(match.gate)
    }

    private func gateForCurrentAxes() -> (selection: WorkspaceSelection, gate: PolygonGate)? {
        gateForCurrentAxes(xTransform: model.xTransform, yTransform: model.yTransform)
    }

    private func gateForCurrentAxes(xTransform: TransformKind, yTransform: TransformKind) -> (selection: WorkspaceSelection, gate: PolygonGate)? {
        return workspace.gateForAxes(
            parentSelection: selection,
            preferredSelection: activeGateSelection,
            xChannelName: model.currentXChannelName,
            yChannelName: model.currentYChannelName,
            xTransform: xTransform,
            yTransform: yTransform
        )
    }

    private func syncGateStateAfterWorkspaceChange() {
        if !workspace.contains(selection) {
            let rootSelection = WorkspaceSelection(sampleID: selection.sampleID, gateID: nil)
            guard workspace.contains(rootSelection),
                  let population = workspace.selectedPopulation(for: rootSelection) else {
                activeGateSelection = nil
                isActiveGateSelected = false
                model.clearGate(recompute: false)
                return
            }
            selection = rootSelection
            activeGateSelection = nil
            isActiveGateSelected = false
            model.setPopulation(
                table: population.table,
                baseMask: population.mask,
                title: population.title,
                preferredXChannelName: model.currentXChannelName,
                preferredYChannelName: model.currentYChannelName,
                preferredXTransform: model.xTransform,
                preferredYTransform: model.yTransform
            )
            restoreGateForCurrentAxes()
            return
        }

        if let activeGateSelection, !workspace.contains(activeGateSelection) {
            self.activeGateSelection = nil
            isActiveGateSelected = false
            model.clearGate(recompute: false)
        }

        if selection.gateID != nil {
            refreshCurrentPopulationFromWorkspace()
        } else {
            syncActiveGateForCurrentAxes()
        }
    }

    private func refreshCurrentPopulationFromWorkspace() {
        guard let population = workspace.selectedPopulation(for: selection) else { return }
        let match = gateForCurrentAxes()
        if match?.selection != activeGateSelection {
            isActiveGateSelected = false
        }
        activeGateSelection = match?.selection
        model.setPopulation(
            table: population.table,
            baseMask: population.mask,
            title: population.title,
            preferredXChannelName: model.currentXChannelName,
            preferredYChannelName: model.currentYChannelName,
            preferredXTransform: model.xTransform,
            preferredYTransform: model.yTransform,
            restoredGate: match?.gate
        )
    }

    private func syncActiveGateForCurrentAxes() {
        guard let match = gateForCurrentAxes() else {
            if activeGateSelection != nil || model.activeGate != nil {
                activeGateSelection = nil
                isActiveGateSelected = false
                model.clearGate(recompute: false)
            }
            return
        }

        if match.selection != activeGateSelection {
            isActiveGateSelected = false
        }
        activeGateSelection = match.selection
        if model.activeGate != match.gate {
            model.restoreGateWhenReady(match.gate)
        }
    }

    private func navigateUp() {
        guard let parent = workspace.parentSelection(of: selection), let population = workspace.selectedPopulation(for: parent) else { return }
        let previousSelection = selection
        let previousGate = workspace.gateDefinition(for: previousSelection)
        let config = workspace.gateConfiguration(for: selection)
        selection = parent
        activeGateSelection = previousSelection
        isActiveGateSelected = false
        model.setPopulation(
            table: population.table,
            baseMask: population.mask,
            title: population.title,
            preferredXChannelName: config?.xChannelName ?? model.currentXChannelName,
            preferredYChannelName: config?.yChannelName ?? model.currentYChannelName,
            preferredXTransform: config?.xTransform,
            preferredYTransform: config?.yTransform,
            restoredGate: previousGate
        )
    }

    private func navigateDown() {
        guard canNavigateDown, let activeGateSelection else { return }
        navigate(to: activeGateSelection, restoredGate: nil)
    }

    private func navigateSample(offset: Int) {
        guard let target = workspace.adjacentSampleSelection(from: selection, offset: offset) else { return }
        navigate(to: target, restoredGate: nil)
    }

    private func navigate(to target: WorkspaceSelection, restoredGate: PolygonGate?) {
        guard let population = workspace.selectedPopulation(for: target) else { return }
        let match = workspace.gateForAxes(
            parentSelection: target,
            preferredSelection: nil,
            xChannelName: model.currentXChannelName,
            yChannelName: model.currentYChannelName,
            xTransform: model.xTransform,
            yTransform: model.yTransform
        )
        selection = target
        activeGateSelection = match?.selection
        isActiveGateSelected = false
        model.setPopulation(
            table: population.table,
            baseMask: population.mask,
            title: population.title,
            preferredXChannelName: model.currentXChannelName,
            preferredYChannelName: model.currentYChannelName,
            preferredXTransform: model.xTransform,
            preferredYTransform: model.yTransform,
            restoredGate: restoredGate ?? match?.gate
        )
    }
}

private struct PlotDeleteKeyMonitor: NSViewRepresentable {
    var onDelete: () -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onDelete = onDelete
    }

    final class MonitorView: NSView {
        var onDelete: (() -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else {
                installMonitor()
            }
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.isEmpty, event.keyCode == 51 || event.keyCode == 117 else { return event }
                return self.onDelete?() == true ? nil : event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

struct StandalonePlotPaneView: View {
    @ObservedObject var model: AppModel
    @State private var isGateSelected = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(model.populationTitle, systemImage: "chart.dots.scatter")
                    .font(.headline)
                Spacer()
                GateToolStrip(selection: $model.gateTool)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(.regularMaterial)

            ScatterPlotView(
                image: model.plotImage,
                xRange: model.xRange,
                yRange: model.yRange,
                gates: model.activeGate.map { [PlotGateOverlay(id: "active", gate: $0)] } ?? [],
                selectedGateID: isGateSelected ? "active" : nil,
                gateTool: model.gateTool,
                plotMode: model.plotMode,
                xTransform: model.xTransform,
                yTransform: model.yTransform,
                isGateSelected: isGateSelected,
                gateLabelPosition: model.gateLabelPosition,
                gatePercentText: model.gatePercentText,
                channels: model.channels,
                xChannel: model.xChannel,
                yChannel: model.yChannel,
                onXChannelChange: { channel in
                    model.xChannel = channel
                    model.axesChanged()
                },
                onYChannelChange: { channel in
                    model.plotMode = .scatter
                    model.yChannel = channel
                    model.axesChanged()
                },
                onPlotModeChange: { mode in
                    model.plotModeChanged(mode)
                },
                onGate: { gate in
                    guard let namedGate = promptForGateName(gate) else {
                        model.gateTool = .cursor
                        return
                    }
                    isGateSelected = false
                    model.applyGate(namedGate)
                    model.gateTool = .cursor
                },
                onGateSelected: { _ in
                    isGateSelected = true
                },
                onGateDeselected: {
                    isGateSelected = false
                },
                onGateChanged: { gate in
                    model.updateActiveGate(gate, reevaluate: false)
                },
                onGateEditEnded: { gate in
                    model.updateActiveGate(gate)
                },
                onGateLabelMoved: { point in
                    model.moveGateLabel(to: point)
                },
                onOpenGate: { _, point in
                    model.openGateWindowIfPointIsInside(point)
                }
            )
        }
    }
}

@MainActor
private func promptForGateName(_ gate: PolygonGate) -> PolygonGate? {
    let alert = NSAlert()
    alert.messageText = "Name Gate"
    alert.informativeText = "Enter a name for the new gate."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")

    let textField = NSTextField(string: gate.name)
    textField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    textField.selectText(nil)
    alert.accessoryView = textField

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return nil }
    let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = trimmed.isEmpty ? gate.name : trimmed
    return PolygonGate(name: name, vertices: gate.vertices, kind: gate.kind)
}

private struct GateToolStrip: View {
    @Binding var selection: GateTool

    private let tools: [GateTool] = [.cursor, .rectangle, .quadrant, .oval, .polygon]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tools) { tool in
                Button {
                    selection = tool
                } label: {
                    GateToolGlyph(tool: tool)
                        .frame(width: 27, height: 27)
                        .frame(width: 42, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(selection == tool ? Color(nsColor: .selectedControlColor).opacity(0.24) : Color(nsColor: .controlBackgroundColor))
                .overlay(Rectangle().stroke(Color.black.opacity(selection == tool ? 0.45 : 0.22), lineWidth: 1))
                .help(tool.rawValue)
                .accessibilityLabel(tool.rawValue)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.25), lineWidth: 1))
        .fixedSize()
    }
}

private struct GateToolGlyph: View {
    let tool: GateTool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            switch tool {
            case .cursor:
                drawCursor(context: context, rect: rect)
            case .rectangle:
                context.stroke(Path(rect), with: .color(.black), lineWidth: 2)
            case .quadrant:
                var path = Path()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.stroke(path, with: .color(.black), lineWidth: 2.4)
            case .oval:
                context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: 2)
            case .polygon:
                drawCustomShape(context: context, rect: rect)
            case .xCutoff:
                var path = Path()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                context.stroke(path, with: .color(.black), lineWidth: 2.4)
            }
        }
    }

    private func drawCursor(context: GraphicsContext, rect: CGRect) {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.54, y: rect.maxY - rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.42))
        path.closeSubpath()
        context.fill(path, with: .color(.black))
    }

    private func drawCustomShape(context: GraphicsContext, rect: CGRect) {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
        path.closeSubpath()
        context.stroke(path, with: .color(.black), lineWidth: 2)
    }
}
