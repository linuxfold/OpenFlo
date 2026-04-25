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
                Image(systemName: "arrow.up")
            }
            .help("Show parent population")
            .disabled(workspace.parentSelection(of: selection) == nil)

            Label(model.populationTitle, systemImage: "chart.dots.scatter")
                .font(.headline)
                .lineLimit(1)

            Divider()
                .frame(height: 24)

            Picker("Gate Tool", selection: $model.gateTool) {
                ForEach(GateTool.allCases) { tool in
                    Label(tool.rawValue, systemImage: tool.systemImage)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 540)

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
        let newSelection = workspace.addGateFromPlot(
            gate,
            xChannelName: model.currentXChannelName,
            yChannelName: model.currentYChannelName,
            xTransform: model.xTransform,
            yTransform: model.yTransform,
            parentSelection: selection
        )
        activeGateSelection = newSelection
        model.applyGate(gate)
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
                Picker("Gate Tool", selection: $model.gateTool) {
                    ForEach(GateTool.allCases) { tool in
                        Label(tool.rawValue, systemImage: tool.systemImage)
                            .tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
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
                    model.applyGate(gate)
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
