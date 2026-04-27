import AppKit
import OpenFloCore
import SwiftUI

@MainActor
struct AxisTransformEditorView: View {
    @ObservedObject var model: AppModel
    let axis: PlotAxis

    @State private var settings: AxisDisplaySettings
    @State private var minimum: Double
    @State private var maximum: Double
    @State private var selectedChannels: Set<Int>

    init(model: AppModel, axis: PlotAxis) {
        self.model = model
        self.axis = axis
        let initialSettings = model.axisSettings(for: axis)
        let initialRange = model.axisRange(for: axis)
        _settings = State(initialValue: initialSettings)
        _minimum = State(initialValue: Double(initialSettings.minimum ?? initialRange.lowerBound))
        _maximum = State(initialValue: Double(initialSettings.maximum ?? initialRange.upperBound))
        _selectedChannels = State(initialValue: [model.channelIndex(for: axis)])
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                previewPane
                    .padding(.top, 20)

                HStack {
                    axisBoundButtons(bound: .minimum)
                    Spacer()
                    axisBoundButtons(bound: .maximum)
                }
                .padding(.horizontal, 140)

                scaleSection
                transformsSection

                HStack {
                    Button {
                        NSApp.keyWindow?.close()
                    } label: {
                        Image(systemName: "questionmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Help")

                    Button("Save") {
                        applySettings()
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Cancel") {
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Apply") {
                        applySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .frame(minWidth: 820)

            Divider()

            parameterList
                .frame(width: 290)
        }
        .frame(minWidth: 1120, minHeight: 700)
        .onChange(of: settings.transform) {
            resetRangeToAutomatic()
        }
    }

    private var previewChannelIndex: Int {
        selectedChannels.sorted().first ?? model.channelIndex(for: axis)
    }

    private var previewRange: ClosedRange<Float> {
        let lower = Float(min(minimum, maximum))
        let upper = Float(max(minimum, maximum))
        guard lower.isFinite, upper.isFinite, upper > lower else {
            return model.automaticRange(forChannel: previewChannelIndex, settings: settings)
        }
        return lower...upper
    }

    private var previewPane: some View {
        let range = previewRange
        let histogram = model.previewHistogram(channelIndex: previewChannelIndex, settings: settings, range: range)
        let maxBin = max(histogram.max() ?? 1, 1)

        return ZStack(alignment: .bottom) {
            Canvas { context, size in
                let plotRect = CGRect(x: 56, y: 16, width: size.width - 82, height: size.height - 64)
                context.stroke(Path(plotRect), with: .color(.black), lineWidth: 1.2)

                var path = Path()
                path.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                for (index, count) in histogram.enumerated() {
                    let x = plotRect.minX + CGFloat(index) / CGFloat(max(1, histogram.count - 1)) * plotRect.width
                    let y = plotRect.maxY - CGFloat(count) / CGFloat(maxBin) * plotRect.height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
                path.closeSubpath()
                context.fill(path, with: .color(.gray.opacity(0.68)))
                context.stroke(path, with: .color(.black), lineWidth: 3)

                let xLabel = context.resolve(Text(model.channels[previewChannelIndex].displayName).font(.headline))
                context.draw(xLabel, at: CGPoint(x: plotRect.midX, y: plotRect.maxY + 42), anchor: .center)

                let minLabel = context.resolve(Text(formatTick(range.lowerBound)).font(.caption).foregroundStyle(.black))
                let maxLabel = context.resolve(Text(formatTick(range.upperBound)).font(.caption).foregroundStyle(.black))
                context.draw(minLabel, at: CGPoint(x: plotRect.minX, y: plotRect.maxY + 18), anchor: .top)
                context.draw(maxLabel, at: CGPoint(x: plotRect.maxX, y: plotRect.maxY + 18), anchor: .top)
            }
        }
        .frame(height: 430)
    }

    private var scaleSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: "Scale", systemImage: "arrow.up.left.and.arrow.down.right")
            HStack(spacing: 14) {
                Text("Scale")
                Picker("", selection: $settings.transform) {
                    ForEach(TransformKind.flowScaleOptions) { transform in
                        Text(transform.displayName).tag(transform)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Text("Min")
                TextField("Min", value: $minimum, format: .number.precision(.fractionLength(0...3)))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)

                Text("Max")
                TextField("Max", value: $maximum, format: .number.precision(.fractionLength(0...3)))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)

                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(Rectangle().stroke(.gray.opacity(0.55), lineWidth: 1))
        }
        .padding(.horizontal, 16)
    }

    private var transformsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: "Transforms", systemImage: "textformat")
            HStack(spacing: 10) {
                transformSlider(
                    title: "Extra Neg. Decades",
                    value: sliderBinding(\.extraNegativeDecades),
                    range: 0...2,
                    ticks: ["0", "1", "2"]
                )
                transformSlider(
                    title: "Width Basis",
                    value: sliderBinding(\.widthBasis),
                    range: 0...3,
                    ticks: ["0", "1", "2", "3"]
                )
                transformSlider(
                    title: "Positive Decades",
                    value: sliderBinding(\.positiveDecades),
                    range: 1...7,
                    ticks: ["1", "4", "7"]
                )
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(Rectangle().stroke(.gray.opacity(0.55), lineWidth: 1))
            .disabled(!settings.transform.usesTransformSliders)
            .opacity(settings.transform.usesTransformSliders ? 1 : 0.45)
        }
        .padding(.horizontal, 16)
    }

    private var parameterList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apply to Parameters...")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.top, 12)

            List(selection: $selectedChannels) {
                ForEach(model.channels.indices, id: \.self) { index in
                    Text(model.channels[index].displayName)
                        .tag(index)
                }
            }

            HStack {
                Button("All") {
                    selectedChannels = Set(model.channels.indices)
                }
                Button("Current") {
                    selectedChannels = [model.channelIndex(for: axis)]
                }
            }
            .padding([.horizontal, .bottom], 10)
        }
    }

    private func axisBoundButtons(bound: AxisRangeBound) -> some View {
        HStack(spacing: 5) {
            Button {
                adjust(bound: bound, direction: -1)
            } label: {
                Image(systemName: "minus")
            }
            Button {
                adjust(bound: bound, direction: 1)
            } label: {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .frame(width: 22)
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color(nsColor: .controlColor))
        .overlay(Rectangle().stroke(.gray.opacity(0.7), lineWidth: 1))
    }

    private func transformSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, ticks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: value, in: range)
            HStack {
                ForEach(ticks, id: \.self) { tick in
                    Text(tick)
                    if tick != ticks.last {
                        Spacer()
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.primary)

            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().stroke(.gray.opacity(0.45), lineWidth: 1))
    }

    private func sliderBinding(_ keyPath: WritableKeyPath<AxisDisplaySettings, Float>) -> Binding<Double> {
        Binding(
            get: { Double(settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = Float($0) }
        )
    }

    private func adjust(bound: AxisRangeBound, direction: Double) {
        let span = max(abs(maximum - minimum), 1)
        let step = span * 0.05 * direction
        switch bound {
        case .minimum:
            minimum = min(minimum + step, maximum - abs(step))
        case .maximum:
            maximum = max(maximum + step, minimum + abs(step))
        }
    }

    private func applySettings() {
        var applied = settings
        let lower = Float(min(minimum, maximum))
        let upper = Float(max(minimum, maximum))
        if lower.isFinite, upper.isFinite, upper > lower {
            applied.minimum = lower
            applied.maximum = upper
        }
        model.applyAxisSettings(applied, toChannelIndices: selectedChannels)
    }

    private func resetRangeToAutomatic() {
        let range = model.automaticRange(forChannel: previewChannelIndex, settings: settings)
        minimum = Double(range.lowerBound)
        maximum = Double(range.upperBound)
    }

    private func formatTick(_ value: Float) -> String {
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
}
