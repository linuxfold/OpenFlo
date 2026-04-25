import AppKit
import Foundation
import OpenFloCore
import SwiftUI

struct PlotWindowView: View {
    @ObservedObject var workspace: WorkspaceModel
    @StateObject private var model: AppModel
    @State private var selection: WorkspaceSelection
    @State private var activeGateSelection: WorkspaceSelection?

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
                gate: model.activeGate,
                gateTool: model.gateTool,
                plotMode: model.plotMode,
                xTransform: model.xTransform,
                yTransform: model.yTransform,
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
                onGate: createGate,
                onGateChanged: updateActiveGate,
                onGateEditEnded: finishGateEdit,
                onGateLabelMoved: { point in
                    model.moveGateLabel(to: point)
                },
                onOpenGate: { point in
                    guard let activeGateSelection, model.activeGate?.contains(x: point.x, y: point.y) == true else { return }
                    workspace.openPlotWindow(for: activeGateSelection)
                }
            )
            .background(Color.white)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                navigateUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Back to parent population")
            .disabled(workspace.parentSelection(of: selection) == nil)

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

            Button {
                model.clearGate()
                activeGateSelection = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Clear active gate")
            .disabled(model.gateMask == nil && model.activeGate == nil)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(.regularMaterial)
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

    private func navigateUp() {
        guard let parent = workspace.parentSelection(of: selection), let population = workspace.selectedPopulation(for: parent) else { return }
        let config = workspace.gateConfiguration(for: selection)
        selection = parent
        activeGateSelection = nil
        model.setPopulation(
            table: population.table,
            baseMask: population.mask,
            title: population.title,
            preferredXChannelName: config?.xChannelName ?? model.currentXChannelName,
            preferredYChannelName: config?.yChannelName ?? model.currentYChannelName,
            preferredXTransform: config?.xTransform,
            preferredYTransform: config?.yTransform
        )
    }
}

struct StandalonePlotPaneView: View {
    @ObservedObject var model: AppModel

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
                gate: model.activeGate,
                gateTool: model.gateTool,
                plotMode: model.plotMode,
                xTransform: model.xTransform,
                yTransform: model.yTransform,
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
                    model.applyGate(namedGate)
                    model.gateTool = .cursor
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
                onOpenGate: { point in
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
