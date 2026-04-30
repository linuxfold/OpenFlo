import AppKit
import OpenFloCore
import SwiftUI

struct CompensationMatrixEditorView: View {
    @ObservedObject var workspace: WorkspaceModel
    @State private var selectedMatrixID: UUID?
    @State private var previewSampleID: UUID?
    @State private var overlayUncompensated = true
    @State private var draftMatrix: CompensationMatrix?

    init(workspace: WorkspaceModel, initialMatrixID: UUID?, initialSampleID: UUID?) {
        self.workspace = workspace
        _selectedMatrixID = State(initialValue: initialMatrixID)
        _previewSampleID = State(initialValue: initialSampleID)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                matrixList
                    .frame(width: 230)
                Divider()
                VStack(spacing: 0) {
                    matrixGrid
                    Divider()
                    previewPane
                        .frame(height: 270)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear(perform: repairSelection)
        .onChange(of: workspace.compensationMatrices) {
            repairSelection()
        }
    }

    private var selectedMatrix: CompensationMatrix? {
        workspace.compensationMatrix(id: selectedMatrixID)
    }

    private var displayedMatrix: CompensationMatrix? {
        draftMatrix ?? selectedMatrix
    }

    private var isEditingDraft: Bool {
        draftMatrix != nil
    }

    private var selectedSample: WorkspaceSample? {
        previewSampleID.flatMap { id in workspace.samples.first { $0.id == id } }
    }

    private var compatiblePreviewSamples: [WorkspaceSample] {
        guard let matrix = displayedMatrix else { return workspace.samples }
        return workspace.samples.filter { sample in
            let names = Set(sample.rawTable.channels.map(\.name))
            return matrix.parameters.allSatisfy { names.contains($0) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Name:")
                .font(.callout.weight(.semibold))
            TextField("Matrix name", text: matrixNameBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
                .disabled(!isEditingDraft)

            Button("Edit") {
                beginEditingSelectedMatrix()
            }
            .disabled(selectedMatrixID == nil || isEditingDraft)

            Button("Reset") {
                resetDraft()
            }
            .disabled(!isEditingDraft || draftMatrix?.originalMatrixID == nil)

            Button {
            } label: {
                Text("M")
                    .font(.callout.monospaced().weight(.bold))
                    .frame(width: 24)
            }
            .help("Drag saved matrix to a sample or All Samples")
            .disabled(isEditingDraft || selectedMatrixID == nil)
            .onDrag {
                guard !isEditingDraft, let matrixID = selectedMatrixID else { return NSItemProvider() }
                return gateItemProvider(workspace.compensationDragPayload(matrixID: matrixID))
            }

            Button("Save Matrix") {
                saveDraftMatrix()
            }
            .disabled(!isEditingDraft)

            Button("Apply to All") {
                if let matrixID = selectedMatrixID {
                    workspace.assignCompensationToAllCompatible(matrixID)
                }
            }
            .disabled(isEditingDraft || selectedMatrixID == nil)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.regularMaterial)
    }

    private var matrixNameBinding: Binding<String> {
        Binding(
            get: { displayedMatrix?.name ?? "" },
            set: { name in
                guard isEditingDraft else { return }
                draftMatrix?.name = name
                draftMatrix?.modifiedAt = Date()
            }
        )
    }

    private var matrixList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Matrices")
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(workspace.compensationMatrices) { matrix in
                        matrixListButton(matrix: matrix, isDraft: false)
                    }
                    if let draftMatrix {
                        matrixListButton(matrix: draftMatrix, isDraft: true)
                    }
                }
                .padding(8)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    if let id = workspace.createIdentityMatrixForSelectedSample() {
                        draftMatrix = nil
                        selectedMatrixID = id
                        repairPreviewSample()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New identity matrix")

                Button {
                    beginEditingSelectedMatrix()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Edit a copy")
                .disabled(selectedMatrixID == nil || isEditingDraft)

                Spacer()
            }
            .buttonStyle(.bordered)
            .padding(10)
        }
    }

    private func matrixListButton(matrix: CompensationMatrix, isDraft: Bool) -> some View {
        Button {
            guard !isDraft else { return }
            draftMatrix = nil
            selectedMatrixID = matrix.id
            repairPreviewSample()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isDraft ? "square.and.pencil" : matrix.locked ? "lock.square" : "square.grid.3x3.fill")
                    .foregroundStyle(isDraft ? .teal : matrix.locked ? .gray : colorFromHex(matrix.colorHex) ?? .teal)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDraft ? "\(matrix.name) (unsaved)" : matrix.name)
                        .lineLimit(1)
                    Text(isDraft ? "Unsaved edit copy" : sourceLabel(for: matrix))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        ((isDraft && isEditingDraft) || (!isDraft && !isEditingDraft && selectedMatrixID == matrix.id))
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var matrixGrid: some View {
        if let matrix = displayedMatrix {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        Text("Source \\ Target")
                            .font(.caption.weight(.semibold))
                            .frame(width: 150, height: 34, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                        ForEach(matrix.parameters, id: \.self) { parameter in
                            Text(parameter)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(width: 112, height: 34)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                        }
                    }

                    ForEach(matrix.parameters.indices, id: \.self) { source in
                        GridRow {
                            Text(matrix.parameters[source])
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(width: 150, height: 34, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                                .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1))

                            ForEach(matrix.parameters.indices, id: \.self) { target in
                                MatrixValueCell(
                                    value: matrix.percent[source][target],
                                    isLocked: !isEditingDraft || source == target,
                                    onChange: { value in
                                        updateDraftValue(source: source, target: target, value: value)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(14)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x3")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Button("Create Matrix") {
                    if let id = workspace.createIdentityMatrixForSelectedSample() {
                        selectedMatrixID = id
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Preview Sample", selection: previewSampleBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(compatiblePreviewSamples) { sample in
                        Text(sample.name).tag(Optional(sample.id))
                    }
                }
                .frame(width: 320)

                Picker("Preview Population", selection: .constant("all")) {
                    Text("All Events").tag("all")
                }
                .frame(width: 220)
                .disabled(true)

                Picker("View", selection: .constant("nxn")) {
                    Text("NxN").tag("nxn")
                }
                .frame(width: 120)
                .disabled(true)

                Toggle("Overlay Uncompensated", isOn: $overlayUncompensated)
                    .toggleStyle(.checkbox)

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(nsColor: .controlBackgroundColor))

            CompensationPreviewImage(
                matrix: displayedMatrix,
                sample: selectedSample,
                overlayUncompensated: overlayUncompensated
            )
            .padding(12)
        }
    }

    private var previewSampleBinding: Binding<UUID?> {
        Binding(
            get: { previewSampleID },
            set: { previewSampleID = $0 }
        )
    }

    private func repairSelection() {
        if selectedMatrixID == nil || workspace.compensationMatrix(id: selectedMatrixID) == nil {
            selectedMatrixID = workspace.compensationMatrices.first?.id
        }
        repairPreviewSample()
    }

    private func repairPreviewSample() {
        let compatibleIDs = Set(compatiblePreviewSamples.map(\.id))
        if let previewSampleID, compatibleIDs.contains(previewSampleID) {
            return
        }
        previewSampleID = compatiblePreviewSamples.first?.id ?? workspace.samples.first?.id
    }

    private func beginEditingSelectedMatrix() {
        guard let matrixID = selectedMatrixID,
              let copy = workspace.editableDraftCopy(of: matrixID) else { return }
        draftMatrix = copy
        repairPreviewSample()
    }

    private func updateDraftValue(source: Int, target: Int, value: Double) {
        guard isEditingDraft,
              value.isFinite,
              source != target,
              draftMatrix?.percent.indices.contains(source) == true,
              draftMatrix?.percent[source].indices.contains(target) == true else { return }
        draftMatrix?.percent[source][target] = value
        draftMatrix?.modifiedAt = Date()
    }

    private func resetDraft() {
        guard let originalID = draftMatrix?.originalMatrixID,
              let original = workspace.compensationMatrix(id: originalID) else { return }
        draftMatrix?.percent = original.percent
        draftMatrix?.modifiedAt = Date()
    }

    private func saveDraftMatrix() {
        guard let draftMatrix else { return }
        do {
            let savedID = try workspace.saveEditedMatrixCopy(draftMatrix)
            self.draftMatrix = nil
            selectedMatrixID = savedID
            repairPreviewSample()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not save matrix"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func sourceLabel(for matrix: CompensationMatrix) -> String {
        switch matrix.source {
        case .acquisition(let keyword):
            return "Acquisition \(keyword)"
        case .acquisitionCopy:
            return "Edited acquisition copy"
        case .manualIdentity:
            return "Manual"
        case .manualImported:
            return "Imported"
        case .singleStainControls:
            return "Controls"
        }
    }
}

private struct MatrixValueCell: View {
    let value: Double
    let isLocked: Bool
    let onChange: (Double) -> Void

    @State private var text: String

    init(value: Double, isLocked: Bool, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.isLocked = isLocked
        self.onChange = onChange
        _text = State(initialValue: Self.format(value))
    }

    var body: some View {
        HStack(spacing: 4) {
            if isLocked {
                Text(Self.format(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                TextField("", text: $text)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: text) { _, newValue in
                        if let parsed = Double(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            onChange(parsed)
                        }
                    }
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 112, height: 34)
        .background(cellColor)
        .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1))
        .focusable(!isLocked)
        .onChange(of: value) { _, newValue in
            let formatted = Self.format(newValue)
            if text != formatted {
                text = formatted
            }
        }
        .onMoveCommand { direction in
            guard !isLocked else { return }
            let delta: Double
            switch direction {
            case .up:
                delta = stepSize()
            case .down:
                delta = -stepSize()
            default:
                return
            }
            let nextValue = value + delta
            text = Self.format(nextValue)
            onChange(nextValue)
        }
    }

    private var cellColor: Color {
        if isLocked && value == 100 {
            return Color(nsColor: .textBackgroundColor)
        }
        if value < 0 {
            return Color.blue.opacity(min(0.30, 0.08 + abs(value) / 100.0))
        }
        if value == 0 {
            return Color(nsColor: .textBackgroundColor)
        }
        if value < 5 {
            return Color.yellow.opacity(0.18)
        }
        if value < 20 {
            return Color.orange.opacity(0.22)
        }
        return Color.orange.opacity(0.36)
    }

    private func stepSize() -> Double {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.control) {
            return 10
        }
        if flags.contains(.shift) {
            return 1
        }
        if flags.contains(.option) {
            return 0.01
        }
        return 0.1
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}

private struct CompensationPreviewImage: View {
    let matrix: CompensationMatrix?
    let sample: WorkspaceSample?
    let overlayUncompensated: Bool

    @State private var image: NSImage?
    @State private var isRendering = false

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 1))
            } else {
                Image(systemName: isRendering ? "hourglass" : "chart.dots.scatter")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: previewKey) {
            await renderPreview()
        }
    }

    private var previewKey: String {
        [
            matrix?.id.uuidString ?? "no-matrix",
            matrix.map { "\($0.modifiedAt.timeIntervalSinceReferenceDate)" } ?? "0",
            sample?.id.uuidString ?? "no-sample",
            overlayUncompensated ? "overlay" : "comp"
        ].joined(separator: ":")
    }

    @MainActor
    private func renderPreview() async {
        guard let matrix, let sample else {
            image = nil
            isRendering = false
            return
        }
        isRendering = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }

        let rawTable = sample.rawTable
        let matrixCopy = matrix
        let overlay = overlayUncompensated
        let result = await Task.detached(priority: .userInitiated) {
            renderCompensationPreview(matrix: matrixCopy, rawTable: rawTable, overlayUncompensated: overlay)
        }.value

        if !Task.isCancelled {
            image = result
            isRendering = false
        }
    }
}

private nonisolated func renderCompensationPreview(
    matrix: CompensationMatrix,
    rawTable: EventTable,
    overlayUncompensated: Bool
) -> NSImage? {
    guard matrix.parameters.count >= 2,
          let xIndex = rawTable.channels.firstIndex(where: { $0.name == matrix.parameters[0] }),
          let yIndex = rawTable.channels.firstIndex(where: { $0.name == matrix.parameters[1] }),
          let compensated = try? CompensationEngine.apply(matrix, to: rawTable) else {
        return nil
    }

    let xChannel = rawTable.channels[xIndex]
    let yChannel = rawTable.channels[yIndex]
    let xTransform = compensationPreviewDefaultTransform(for: xChannel)
    let yTransform = compensationPreviewDefaultTransform(for: yChannel)
    let rawX = xTransform.apply(to: rawTable.column(xIndex))
    let rawY = yTransform.apply(to: rawTable.column(yIndex))
    let compensatedX = xTransform.apply(to: compensated.column(xIndex))
    let compensatedY = yTransform.apply(to: compensated.column(yIndex))
    let xRange = min(EventTable.range(values: rawX).lowerBound, EventTable.range(values: compensatedX).lowerBound)...max(EventTable.range(values: rawX).upperBound, EventTable.range(values: compensatedX).upperBound)
    let yRange = min(EventTable.range(values: rawY).lowerBound, EventTable.range(values: compensatedY).lowerBound)...max(EventTable.range(values: rawY).upperBound, EventTable.range(values: compensatedY).upperBound)

    if overlayUncompensated {
        return OverlayDotPlotRenderer.image(
            series: [
                OverlayDotPlotSeries(xValues: rawX, yValues: rawY, mask: nil, colorName: "Gray"),
                OverlayDotPlotSeries(xValues: compensatedX, yValues: compensatedY, mask: nil, colorName: "Blue")
            ],
            width: 520,
            height: 520,
            xRange: xRange,
            yRange: yRange,
            maxDotsPerSeries: 55_000
        )
    }
    return DotPlotRenderer.image(
        xValues: compensatedX,
        yValues: compensatedY,
        mask: nil,
        width: 520,
        height: 520,
        xRange: xRange,
        yRange: yRange,
        maxDots: 110_000
    )
}

private nonisolated func compensationPreviewDefaultTransform(for channel: Channel) -> TransformKind {
    if let preferredTransform = channel.preferredTransform {
        return preferredTransform
    }
    let combinedName = "\(channel.name) \(channel.displayName)".uppercased()
    if combinedName.contains("FSC")
        || combinedName.contains("SSC")
        || channel.name.uppercased() == "TIME" {
        return .linear
    }
    return .logicle
}
