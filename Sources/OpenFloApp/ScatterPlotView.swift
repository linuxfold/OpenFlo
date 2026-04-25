import AppKit
import OpenFloCore
import SwiftUI

struct ScatterPlotView: View {
    let image: NSImage?
    let xRange: ClosedRange<Float>
    let yRange: ClosedRange<Float>
    let gate: PolygonGate?
    let gateTool: GateTool
    let plotMode: PlotMode
    let xTransform: TransformKind
    let yTransform: TransformKind
    let gateLabelPosition: PlotPoint?
    let gatePercentText: String
    let channels: [Channel]
    let xChannel: Int
    let yChannel: Int
    let onXChannelChange: (Int) -> Void
    let onYChannelChange: (Int) -> Void
    let onPlotModeChange: (PlotMode) -> Void
    let onGate: (PolygonGate) -> Void
    let onGateChanged: (PolygonGate) -> Void
    let onGateEditEnded: (PolygonGate) -> Void
    let onGateLabelMoved: (PlotPoint) -> Void
    let onOpenGate: (PlotPoint) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var polygonVertices: [PlotPoint] = []
    @State private var editState: GateEditState?

    private enum GateEditState {
        case vertex(index: Int)
        case move(start: PlotPoint, originalVertices: [PlotPoint])
        case label
    }

    private struct AxisTick {
        let value: Float
        let label: String
    }

    var body: some View {
        GeometryReader { geometry in
            let plotRect = squarePlotRect(in: geometry.size)

            ZStack {
                Color(nsColor: .white)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: plotRect.width, height: plotRect.height)
                        .position(x: plotRect.midX, y: plotRect.midY)
                }

                Canvas { context, size in
                    drawGate(context: context, plotRect: plotRect)
                    drawDrag(context: context, plotRect: plotRect)
                    drawPolygonDraft(context: context, plotRect: plotRect)
                    drawAxes(context: context, plotRect: plotRect)
                }

                if let gateLabelPosition, !gatePercentText.isEmpty {
                    let center = labelCenter(for: gateLabelPosition, in: plotRect)
                    Text(gatePercentText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.88), in: Capsule())
                        .overlay(Capsule().stroke(.black.opacity(0.3), lineWidth: 1))
                        .position(center)
                        .allowsHitTesting(false)
                }

                PlotInteractionOverlay(
                    onMouseDown: { point, clickCount in
                        handleMouseDown(point, clickCount: clickCount, plotRect: plotRect)
                    },
                    onMouseDragged: { point in
                        handleMouseDragged(point, plotRect: plotRect)
                    },
                    onMouseUp: { point in
                        handleMouseUp(point, plotRect: plotRect)
                    }
                )

                axisMenu(
                    label: channels[xChannel].displayName,
                    selected: xChannel,
                    includeHistogram: false,
                    onSelect: onXChannelChange,
                    onHistogram: {}
                )
                .position(x: plotRect.midX, y: min(geometry.size.height - 16, plotRect.maxY + 50))

                axisMenu(
                    label: plotMode == .histogram ? "Histogram" : channels[yChannel].displayName,
                    selected: plotMode == .histogram ? nil : yChannel,
                    includeHistogram: true,
                    onSelect: onYChannelChange,
                    onHistogram: {
                        onPlotModeChange(.histogram)
                    }
                )
                .rotationEffect(.degrees(-90))
                .position(x: max(18, plotRect.minX - 70), y: plotRect.midY)
            }
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .onChange(of: gateTool) {
                polygonVertices.removeAll()
                dragStart = nil
                dragCurrent = nil
            }
            .onChange(of: xChannel) {
                polygonVertices.removeAll()
            }
            .onChange(of: yChannel) {
                polygonVertices.removeAll()
            }
            .onChange(of: plotMode) {
                polygonVertices.removeAll()
                dragStart = nil
                dragCurrent = nil
            }
        }
    }

    private func squarePlotRect(in size: CGSize) -> CGRect {
        let leftMargin: CGFloat = 108
        let rightMargin: CGFloat = 34
        let topMargin: CGFloat = 22
        let bottomMargin: CGFloat = 76
        let availableWidth = max(1, size.width - leftMargin - rightMargin)
        let availableHeight = max(1, size.height - topMargin - bottomMargin)
        let side = max(1, min(availableWidth, availableHeight))
        return CGRect(
            x: leftMargin + (availableWidth - side) / 2,
            y: topMargin + (availableHeight - side) / 2,
            width: side,
            height: side
        )
    }

    private func dataPoint(for point: CGPoint, in plotRect: CGRect) -> PlotPoint {
        let xFraction = Float((point.x - plotRect.minX) / plotRect.width)
        let yFraction = Float(1 - (point.y - plotRect.minY) / plotRect.height)
        let x = xRange.lowerBound + xFraction * (xRange.upperBound - xRange.lowerBound)
        let y = yRange.lowerBound + yFraction * (yRange.upperBound - yRange.lowerBound)
        return PlotPoint(x: x, y: y)
    }

    private func handleSingleClick(_ location: CGPoint, plotRect: CGRect) {
        guard gateTool == .polygon, plotRect.contains(location) else { return }
        polygonVertices.append(dataPoint(for: clamp(location, to: plotRect), in: plotRect))
    }

    private func handleDoubleClick(_ location: CGPoint, plotRect: CGRect) {
        guard plotRect.contains(location) else { return }
        let point = dataPoint(for: clamp(location, to: plotRect), in: plotRect)

        if gateTool == .polygon, !polygonVertices.isEmpty {
            if polygonVertices.count < 3 {
                polygonVertices.append(point)
            }
            if polygonVertices.count >= 3 {
                onGate(PolygonGate(name: "Custom", vertices: polygonVertices))
            }
            polygonVertices.removeAll()
            return
        }

        onOpenGate(point)
    }

    private func handleMouseDown(_ location: CGPoint, clickCount: Int, plotRect: CGRect) {
        guard plotRect.contains(location) else { return }
        if clickCount >= 2 {
            dragStart = nil
            dragCurrent = nil
            editState = nil
            handleDoubleClick(location, plotRect: plotRect)
            return
        }

        switch gateTool {
        case .cursor:
            beginGateEdit(at: location, plotRect: plotRect)
        case .polygon:
            handleSingleClick(location, plotRect: plotRect)
        case .rectangle, .oval:
            let point = clamp(location, to: plotRect)
            dragStart = point
            dragCurrent = point
        case .xCutoff:
            let point = dataPoint(for: clamp(location, to: plotRect), in: plotRect)
            onGate(PolygonGate.xCutoff(threshold: point.x, xUpper: xRange.upperBound, yRange: yRange))
        case .quadrant:
            let point = dataPoint(for: clamp(location, to: plotRect), in: plotRect)
            onGate(PolygonGate.quadrant(origin: point, xUpper: xRange.upperBound, yUpper: yRange.upperBound))
        }
    }

    private func handleMouseDragged(_ location: CGPoint, plotRect: CGRect) {
        if gateTool == .cursor {
            updateGateEdit(at: location, plotRect: plotRect)
            return
        }
        guard gateTool != .polygon, gateTool != .xCutoff, gateTool != .quadrant, dragStart != nil else { return }
        dragCurrent = clamp(location, to: plotRect)
    }

    private func handleMouseUp(_ location: CGPoint, plotRect: CGRect) {
        if gateTool == .cursor {
            if let editState, let gate {
                switch editState {
                case .vertex, .move:
                    onGateEditEnded(gate)
                case .label:
                    break
                }
            }
            editState = nil
            return
        }
        guard gateTool != .polygon, gateTool != .xCutoff, gateTool != .quadrant, let dragStart else { return }
        let end = clamp(location, to: plotRect)
        let startData = dataPoint(for: dragStart, in: plotRect)
        let endData = dataPoint(for: end, in: plotRect)
        let xLower = min(startData.x, endData.x)
        let xUpper = max(startData.x, endData.x)
        let yLower = min(startData.y, endData.y)
        let yUpper = max(startData.y, endData.y)
        self.dragStart = nil
        self.dragCurrent = nil

        guard abs(end.x - dragStart.x) > 4, abs(end.y - dragStart.y) > 4 else { return }
        switch gateTool {
        case .rectangle:
            onGate(PolygonGate.rectangle(name: "Rectangle", xRange: xLower...xUpper, yRange: yLower...yUpper))
        case .oval:
            onGate(PolygonGate.ellipse(name: "Oval", xRange: xLower...xUpper, yRange: yLower...yUpper))
        case .cursor, .polygon, .xCutoff, .quadrant:
            break
        }
    }

    private func beginGateEdit(at location: CGPoint, plotRect: CGRect) {
        guard let gate else { return }
        if labelFrame(in: plotRect)?.contains(location) == true {
            editState = .label
            return
        }

        if let vertexIndex = nearestVertex(to: location, gate: gate, plotRect: plotRect) {
            editState = .vertex(index: vertexIndex)
            return
        }

        let point = dataPoint(for: clamp(location, to: plotRect), in: plotRect)
        if gate.contains(x: point.x, y: point.y) {
            editState = .move(start: point, originalVertices: gate.vertices)
        }
    }

    private func updateGateEdit(at location: CGPoint, plotRect: CGRect) {
        guard let editState, let gate else { return }
        let point = dataPoint(for: clamp(location, to: plotRect), in: plotRect)
        switch editState {
        case .vertex(let index):
            guard gate.vertices.indices.contains(index) else { return }
            var vertices = gate.vertices
            vertices[index] = point
            onGateChanged(PolygonGate(name: gate.name, vertices: vertices, kind: gate.kind))
        case .move(let start, let originalVertices):
            let dx = point.x - start.x
            let dy = point.y - start.y
            let moved = originalVertices.map { PlotPoint(x: $0.x + dx, y: $0.y + dy) }
            onGateChanged(PolygonGate(name: gate.name, vertices: moved, kind: gate.kind))
        case .label:
            onGateLabelMoved(point)
        }
    }

    private func nearestVertex(to location: CGPoint, gate: PolygonGate, plotRect: CGRect) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, vertex) in gate.vertices.enumerated() {
            let point = viewPoint(for: vertex, in: plotRect)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance <= 12, best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    private func viewPoint(for point: PlotPoint, in plotRect: CGRect) -> CGPoint {
        let xFraction = CGFloat((point.x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound))
        let yFraction = CGFloat((point.y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound))
        return CGPoint(
            x: plotRect.minX + xFraction * plotRect.width,
            y: plotRect.maxY - yFraction * plotRect.height
        )
    }

    private func labelCenter(for point: PlotPoint, in plotRect: CGRect) -> CGPoint {
        let raw = viewPoint(for: point, in: plotRect)
        return CGPoint(
            x: min(max(raw.x, plotRect.minX + 32), plotRect.maxX - 32),
            y: min(max(raw.y, plotRect.minY + 14), plotRect.maxY - 14)
        )
    }

    private func labelFrame(in plotRect: CGRect) -> CGRect? {
        guard let gateLabelPosition, !gatePercentText.isEmpty else { return nil }
        let center = labelCenter(for: gateLabelPosition, in: plotRect)
        let width = max(CGFloat(54), CGFloat(gatePercentText.count * 7 + 18))
        let height: CGFloat = 24
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func drawGate(context: GraphicsContext, plotRect: CGRect) {
        guard let gate else { return }
        var path = Path()
        for (index, vertex) in gate.vertices.enumerated() {
            let point = viewPoint(for: vertex, in: plotRect)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        context.fill(path, with: .color(.cyan.opacity(0.12)))
        context.stroke(path, with: .color(.cyan.opacity(0.9)), lineWidth: 2)

        if gateTool == .cursor {
            for vertex in gate.vertices {
                let point = viewPoint(for: vertex, in: plotRect)
                let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.95)), lineWidth: 1.5)
            }
        }
    }

    private func drawDrag(context: GraphicsContext, plotRect: CGRect) {
        guard let dragStart, let dragCurrent else { return }
        let rect = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        ).intersection(plotRect)
        switch gateTool {
        case .rectangle:
            context.fill(Path(rect), with: .color(.black.opacity(0.08)))
            context.stroke(Path(rect), with: .color(.black), lineWidth: 1.5)
        case .oval:
            context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.08)))
            context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: 1.5)
        case .cursor, .polygon, .xCutoff, .quadrant:
            break
        }
    }

    private func drawPolygonDraft(context: GraphicsContext, plotRect: CGRect) {
        guard !polygonVertices.isEmpty else { return }
        var path = Path()
        for (index, vertex) in polygonVertices.enumerated() {
            let point = viewPoint(for: vertex, in: plotRect)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
            context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(.black))
        }
        context.stroke(path, with: .color(.black), lineWidth: 1.5)
    }

    private func drawAxes(context: GraphicsContext, plotRect: CGRect) {
        context.stroke(Path(plotRect), with: .color(.black.opacity(0.82)), lineWidth: 1.2)

        for tick in ticks(for: xRange, transform: xTransform, targetCount: 7) {
            guard let x = xPosition(for: tick.value, in: plotRect) else { continue }
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: plotRect.maxY))
            tickPath.addLine(to: CGPoint(x: x, y: plotRect.maxY + 7))
            context.stroke(tickPath, with: .color(.black), lineWidth: 1.2)

            let text = context.resolve(
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(.black)
            )
            context.draw(text, at: CGPoint(x: x, y: plotRect.maxY + 11), anchor: .top)
        }

        let yAxisTicks = plotMode == .histogram
            ? linearTicks(in: yRange, targetCount: 6)
            : ticks(for: yRange, transform: yTransform, targetCount: 6)
        for tick in yAxisTicks {
            guard let y = yPosition(for: tick.value, in: plotRect) else { continue }
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: plotRect.minX - 7, y: y))
            tickPath.addLine(to: CGPoint(x: plotRect.minX, y: y))
            context.stroke(tickPath, with: .color(.black), lineWidth: 1.2)

            let text = context.resolve(
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(.black)
            )
            context.draw(text, at: CGPoint(x: plotRect.minX - 10, y: y), anchor: .trailing)
        }
    }

    private func xPosition(for value: Float, in plotRect: CGRect) -> CGFloat? {
        let span = xRange.upperBound - xRange.lowerBound
        guard span.isFinite, span > 0 else { return nil }
        let fraction = CGFloat((value - xRange.lowerBound) / span)
        guard fraction.isFinite, fraction >= -0.001, fraction <= 1.001 else { return nil }
        return plotRect.minX + min(max(fraction, 0), 1) * plotRect.width
    }

    private func yPosition(for value: Float, in plotRect: CGRect) -> CGFloat? {
        let span = yRange.upperBound - yRange.lowerBound
        guard span.isFinite, span > 0 else { return nil }
        let fraction = CGFloat((value - yRange.lowerBound) / span)
        guard fraction.isFinite, fraction >= -0.001, fraction <= 1.001 else { return nil }
        return plotRect.maxY - min(max(fraction, 0), 1) * plotRect.height
    }

    private func ticks(for range: ClosedRange<Float>, transform: TransformKind, targetCount: Int) -> [AxisTick] {
        switch transform {
        case .pseudoLog:
            let pseudoLogTicks = pseudoLogAxisTicks(in: range, targetCount: targetCount)
            return pseudoLogTicks.count >= 2 ? pseudoLogTicks : linearTicks(in: range, targetCount: targetCount)
        case .linear, .arcsinh:
            return linearTicks(in: range, targetCount: targetCount)
        }
    }

    private func pseudoLogAxisTicks(in range: ClosedRange<Float>, targetCount: Int) -> [AxisTick] {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, range.upperBound > range.lowerBound else {
            return []
        }

        let lowerPower = Int(ceil(range.lowerBound))
        let upperPower = Int(floor(range.upperBound))
        guard lowerPower <= upperPower else { return [] }
        let powers = Array(lowerPower...upperPower)
        let stride = max(1, Int(ceil(Double(max(1, powers.count)) / Double(max(2, targetCount)))))

        return powers.compactMap { power in
            guard power == 0 || abs(power) % stride == 0 else { return nil }
            let value = Float(power)
            guard value >= range.lowerBound, value <= range.upperBound else { return nil }
            return AxisTick(value: value, label: pseudoLogLabel(forPower: power))
        }
    }

    private func pseudoLogLabel(forPower power: Int) -> String {
        if power == 0 {
            return "0"
        }
        if power < 0 {
            return "-10^\(abs(power))"
        }
        return "10^\(power)"
    }

    private func linearTicks(in range: ClosedRange<Float>, targetCount: Int) -> [AxisTick] {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, range.upperBound > range.lowerBound else {
            return [AxisTick(value: range.lowerBound, label: formatLinearTick(range.lowerBound))]
        }

        let span = range.upperBound - range.lowerBound
        let step = niceStep(span / Float(max(1, targetCount - 1)))
        let first = ceil(range.lowerBound / step) * step
        var value = first
        var output: [AxisTick] = []
        let end = range.upperBound + step * 0.25

        while value <= end, output.count < 16 {
            if value >= range.lowerBound - step * 0.25 {
                let normalized = abs(value) < step * 0.0001 ? 0 : value
                output.append(AxisTick(value: normalized, label: formatLinearTick(normalized)))
            }
            value += step
        }

        return output.isEmpty ? [AxisTick(value: range.lowerBound, label: formatLinearTick(range.lowerBound))] : output
    }

    private func niceStep(_ value: Float) -> Float {
        guard value.isFinite, value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let magnitude = pow(Float(10), exponent)
        let fraction = value / magnitude
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
        return niceFraction * magnitude
    }

    private func formatLinearTick(_ value: Float) -> String {
        guard value.isFinite else { return "" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 {
            return Int(rounded).formatted()
        }
        if abs(value) >= 100 {
            return String(format: "%.0f", Double(value))
        }
        if abs(value) >= 10 {
            return String(format: "%.1f", Double(value))
        }
        return String(format: "%.2g", Double(value))
    }

    private func axisMenu(
        label: String,
        selected: Int?,
        includeHistogram: Bool,
        onSelect: @escaping (Int) -> Void,
        onHistogram: @escaping () -> Void
    ) -> some View {
        Menu {
            if includeHistogram {
                Button {
                    onHistogram()
                } label: {
                    if selected == nil {
                        Label("Histogram", systemImage: "checkmark")
                    } else {
                        Label("Histogram", systemImage: "chart.bar")
                    }
                }
                Divider()
            }

            ForEach(channels.indices, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    if index == selected {
                        Label(channels[index].displayName, systemImage: "checkmark")
                    } else {
                        Text(channels[index].displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.caption)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.86), in: Capsule())
            .overlay(Capsule().stroke(.black.opacity(0.25), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
