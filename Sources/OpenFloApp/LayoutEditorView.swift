import AppKit
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

private let layoutDefaultCanvasSize = CGSize(width: 960, height: 680)
private let layoutScrollableCanvasSize = CGSize(width: 1_860, height: 1_320)
private let layoutPrintPageSize = CGSize(width: 620, height: 520)
private let layoutZoomLevels = [0.25, 0.33, 0.5, 0.66, 0.75, 1.0, 1.25, 1.5, 2.0, 2.4]

struct LayoutEditorView: View {
    @ObservedObject var workspace: WorkspaceModel

    @State private var selectedTool: LayoutCanvasTool = .cursor
    @State private var selectedItemID: UUID?
    @State private var showProperties = true
    @State private var status = "Drag populations from the workspace to build a layout."

    var body: some View {
        VStack(spacing: 0) {
            layoutMenuBar
            layoutRibbon
            toolStrip
            HStack(spacing: 0) {
                canvasArea
                if showProperties {
                    Divider()
                    propertiesPanel
                        .frame(width: 286)
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            LayoutDeleteKeyMonitor {
                guard selectedItemID != nil else { return false }
                deleteSelectedItem()
                return true
            }
        )
    }

    private var layoutMenuBar: some View {
        HStack(spacing: 26) {
            Text("Layout Editor")
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .overlay(Rectangle().stroke(Color.accentColor.opacity(0.45), lineWidth: 1))

            Menu("File") {
                Button("Export Image...") { exportImage() }
                Button("Create Batch Report") { createBatchReport() }
            }
            Menu("Edit") {
                Button(layoutBinding(\.showGrid, fallback: false).wrappedValue ? "Hide Grid" : "Show Grid") {
                    layoutBinding(\.showGrid, fallback: false).wrappedValue.toggle()
                }
                Button(layoutBinding(\.showPageBreaks, fallback: true).wrappedValue ? "Hide Pagebreaks" : "Show Pagebreaks") {
                    layoutBinding(\.showPageBreaks, fallback: true).wrappedValue.toggle()
                }
                Divider()
                Button("Delete Selected") { deleteSelectedItem() }
                    .disabled(selectedItemID == nil)
            }
            Menu("Object") {
                Button("Text") { addTextBox() }
                Button("Rectangle") { addShape(.rectangle) }
                Button("Oval") { addShape(.oval) }
                Button("Line") { addShape(.line) }
                Button("Statistics Table") { addTablePlaceholder() }
            }
            Menu("Arrange") {
                Button("Bring Forward") { moveSelectedItem(zOffset: 1) }
                    .disabled(selectedItemID == nil)
                Button("Send Backward") { moveSelectedItem(zOffset: -1) }
                    .disabled(selectedItemID == nil)
            }

            Spacer()

            Button {
                showProperties.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Properties")

            Button {
                workspace.addLayout()
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help("New layout")
        }
        .font(.title3)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.regularMaterial)
    }

    private var layoutRibbon: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(spacing: 12) {
                    Button { workspace.addLayout() } label: {
                        Image(systemName: "plus").font(.title)
                    }
                    .help("Add layout")

                    Button { workspace.duplicateSelectedLayout() } label: {
                        Image(systemName: "square.on.square").font(.title2)
                    }
                    .help("Duplicate layout")

                    Button { workspace.deleteSelectedLayout() } label: {
                        Image(systemName: "minus").font(.title2.weight(.bold))
                    }
                    .help("Delete layout")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.teal)
                .frame(width: 42)

                VStack(spacing: 6) {
                    List(selection: $workspace.selectedLayoutID) {
                        ForEach(workspace.layouts) { layout in
                            HStack(spacing: 8) {
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 1)
                                    .frame(width: 12, height: 28)
                                Circle()
                                    .fill(Color.teal)
                                    .frame(width: 18, height: 18)
                                Text(layout.name)
                                    .font(.headline)
                            }
                            .tag(layout.id)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 82)
                    .overlay(Rectangle().stroke(.gray, lineWidth: 1))

                    TextField("Layout name", text: selectedLayoutNameBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(6)
            .frame(width: 430, height: 150)
            .overlay(alignment: .bottom) {
                Text("Layouts")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Group")
                    Menu("All Samples") {}
                        .frame(width: 210)
                }
                HStack {
                    Text("Iterate by")
                    Picker("", selection: layoutBinding(\.iterationMode, fallback: .off)) {
                        ForEach(LayoutIterationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                HStack {
                    Text("Value")
                    Picker("", selection: iterationSampleBinding) {
                        Text("Off").tag(UUID?.none)
                        ForEach(workspace.samples) { sample in
                            Text(sample.name).tag(Optional(sample.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                    .disabled(layoutBinding(\.iterationMode, fallback: .off).wrappedValue == .off)
                }
                Spacer()
                Text("Iteration")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(width: 390, height: 150)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Output")
                    Picker("", selection: layoutBinding(\.batchDestination, fallback: .layout)) {
                        ForEach(LayoutBatchDestination.allCases) { destination in
                            Text(destination.rawValue).tag(destination)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 126)
                }
                HStack {
                    Picker("", selection: layoutBinding(\.batchAxis, fallback: .columns)) {
                        ForEach(LayoutBatchAxis.allCases) { axis in
                            Text(axis.rawValue).tag(axis)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Stepper("\(layoutBinding(\.batchCount, fallback: 3).wrappedValue)", value: layoutBinding(\.batchCount, fallback: 3), in: 1...8)
                        .frame(width: 86)
                }
                Toggle("Across", isOn: layoutBinding(\.batchAcross, fallback: true))
                Button {
                    createBatchReport()
                } label: {
                    Label("Create Batch Report", systemImage: "gearshape.fill")
                }
                Spacer()
                Text("Batch")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(width: 270, height: 150)

            Spacer()
        }
        .frame(height: 150)
        .background(.regularMaterial)
        .overlay(Rectangle().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }

    private var toolStrip: some View {
        HStack(spacing: 4) {
            ForEach(LayoutCanvasTool.allCases) { tool in
                Button {
                    selectedTool = tool
                    if tool.insertsImmediately {
                        insert(tool)
                        selectedTool = .cursor
                    }
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.title3)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .help(tool.rawValue)
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 8)

            Button { zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 30, height: 30)
            }
            Button { zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 30, height: 30)
            }
            Button {
                layoutBinding(\.showGrid, fallback: false).wrappedValue.toggle()
            } label: {
                Image(systemName: "square.grid.3x3")
                    .frame(width: 30, height: 30)
            }
            Button {
                layoutBinding(\.showPageBreaks, fallback: true).wrappedValue.toggle()
            } label: {
                Image(systemName: "rectangle.split.3x1")
                    .frame(width: 30, height: 30)
            }

            Spacer()

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                showProperties.toggle()
            } label: {
                Image(systemName: showProperties ? "chevron.right.2" : "chevron.left.2")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .help("Properties")
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var canvasArea: some View {
        let layout = selectedLayout
        return GeometryReader { geometry in
            let zoom = layout?.zoom ?? 1
            let scrollable = hasPlot(in: layout)
            let canvasSize = canvasSize(for: layout, viewport: geometry.size, scrollable: scrollable, zoom: zoom)

            ZStack(alignment: .bottomLeading) {
                if scrollable {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        layoutPage(layout: layout, canvasSize: canvasSize, zoom: zoom)
                            .scaleEffect(zoom, anchor: .topLeading)
                            .frame(
                                width: canvasSize.width * zoom,
                                height: canvasSize.height * zoom,
                                alignment: .topLeading
                            )
                            .padding(18)
                    }
                } else {
                    layoutPage(layout: layout, canvasSize: canvasSize, zoom: 1)
                        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }

                zoomControls
                    .padding(6)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                handleGateDrop(providers)
            }
        }
    }

    private func layoutPage(layout: WorkspaceLayout?, canvasSize: CGSize, zoom: Double) -> some View {
        LayoutPageView(
            workspace: workspace,
            layout: layout,
            selectedItemID: selectedItemID,
            iterationSampleID: effectiveIterationSampleID,
            isInteractive: true,
            canvasSize: canvasSize,
            zoom: zoom,
            onSelect: { selectedItemID = $0 },
            onUpdate: { item in workspace.updateLayoutItem(item) },
            onDelete: { id in workspace.deleteLayoutItem(id: id) },
            onOverlayDrop: { payload, item in addOverlay(payload, to: item) }
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }

            Menu {
                ForEach(layoutZoomLevels, id: \.self) { level in
                    Button("\(Int((level * 100).rounded()))%") {
                        setZoom(level)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(Int(((selectedLayout?.zoom ?? 1) * 100).rounded()))%")
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 82, height: 28)
            }

            Button {
                zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.bordered)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var propertiesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Properties", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button {
                    showProperties = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)

            if let itemBinding = selectedItemBinding {
                itemProperties(item: itemBinding)
            } else {
                layoutProperties
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var layoutProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout")
                .font(.title3.weight(.semibold))
            TextField("Name", text: selectedLayoutNameBinding)
                .textFieldStyle(.roundedBorder)
            Toggle("Show background grid", isOn: layoutBinding(\.showGrid, fallback: false))
            Toggle("Show pagebreaks", isOn: layoutBinding(\.showPageBreaks, fallback: true))
            HStack {
                Text("Zoom")
                Slider(value: layoutBinding(\.zoom, fallback: 1), in: 0.5...2.4)
                Text("\(Int((selectedLayout?.zoom ?? 1) * 100))%")
                    .frame(width: 44, alignment: .trailing)
            }
            Button {
                exportImage()
            } label: {
                Label("Export Image...", systemImage: "square.and.arrow.up")
            }
            Button {
                createBatchReport()
            } label: {
                Label("Create Batch Report", systemImage: "gearshape")
            }
        }
    }

    @ViewBuilder
    private func itemProperties(item: Binding<WorkspaceLayoutItem>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.wrappedValue.kind.displayName)
                .font(.title3.weight(.semibold))

            frameEditor(item: item)

            switch item.wrappedValue.kind {
            case .plot:
                plotProperties(item: item)
            case .text:
                textProperties(item: item)
            case .shape:
                shapeProperties(item: item)
            case .table:
                Text("The statistics table placeholder is included in exports and batch layouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                deleteSelectedItem()
            } label: {
                Label("Delete Item", systemImage: "trash")
            }
        }
    }

    private func frameEditor(item: Binding<WorkspaceLayoutItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("X")
                    numericField(value: frameBinding(item, \.x))
                    Text("Y")
                    numericField(value: frameBinding(item, \.y))
                }
                GridRow {
                    Text("W")
                    numericField(value: frameBinding(item, \.width))
                    Text("H")
                    numericField(value: frameBinding(item, \.height))
                }
            }
        }
    }

    private func plotProperties(item: Binding<WorkspaceLayoutItem>) -> some View {
        let descriptor = plotDescriptorBinding(item)
        let channelOptions = workspace.layoutChannelOptions(
            for: descriptor.wrappedValue.sourceSelection,
            including: [descriptor.wrappedValue.xChannelName, descriptor.wrappedValue.yChannelName]
        )
        let channels = channelOptions.names
        return VStack(alignment: .leading, spacing: 10) {
            Text("Graph Definition")
                .font(.headline)

            if !descriptor.wrappedValue.overlays.isEmpty {
                HStack {
                    Label("\(descriptor.wrappedValue.overlays.count + 1) overlaid populations", systemImage: "circle.grid.cross")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Clear") {
                        descriptor.wrappedValue.overlays.removeAll()
                    }
                    .controlSize(.small)
                }
            }

            Picker("Type", selection: Binding<PlotMode>(
                get: { descriptor.wrappedValue.plotMode },
                set: { descriptor.wrappedValue.plotMode = $0 }
            )) {
                ForEach(PlotMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            axisControl("X Axis", selection: Binding<String>(
                get: { descriptor.wrappedValue.xChannelName ?? channels.first ?? "" },
                set: { descriptor.wrappedValue.xChannelName = $0 }
            ), options: channelOptions)

            axisControl("Y Axis", selection: Binding<String>(
                get: { descriptor.wrappedValue.yChannelName ?? channels.dropFirst().first ?? channels.first ?? "" },
                set: { descriptor.wrappedValue.yChannelName = $0 }
            ), options: channelOptions)
            .disabled(descriptor.wrappedValue.plotMode.isOneDimensional)
            .opacity(descriptor.wrappedValue.plotMode.isOneDimensional ? 0.45 : 1)

            Toggle("Show background grid", isOn: Binding<Bool>(
                get: { descriptor.wrappedValue.showGrid },
                set: { descriptor.wrappedValue.showGrid = $0 }
            ))
            Toggle("Show ancestry thumbnails", isOn: Binding<Bool>(
                get: { descriptor.wrappedValue.showAncestry },
                set: { descriptor.wrappedValue.showAncestry = $0 }
            ))

            HStack {
                Text("Axis font")
                Stepper("\(Int(descriptor.wrappedValue.axisFontSize)) pt", value: Binding<Double>(
                    get: { descriptor.wrappedValue.axisFontSize },
                    set: { descriptor.wrappedValue.axisFontSize = $0 }
                ), in: 8...24)
            }
            Picker("Axis color", selection: Binding<String>(
                get: { descriptor.wrappedValue.axisColorName },
                set: { descriptor.wrappedValue.axisColorName = $0 }
            )) {
                ForEach(layoutColorNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }

    @ViewBuilder
    private func axisControl(
        _ title: String,
        selection: Binding<String>,
        options: WorkspaceChannelOptions
    ) -> some View {
        if options.isLimited {
            TextField(title, text: selection)
                .textFieldStyle(.roundedBorder)
        } else {
            Picker(title, selection: selection) {
                ForEach(options.names, id: \.self) { channel in
                    Text(channel).tag(channel)
                }
            }
        }
    }

    private func textProperties(item: Binding<WorkspaceLayoutItem>) -> some View {
        TextEditor(text: Binding<String>(
            get: {
                if case .text(let text) = item.wrappedValue.kind { return text }
                return ""
            },
            set: { item.wrappedValue.kind = .text($0) }
        ))
        .frame(height: 120)
        .overlay(Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 1))
    }

    private func shapeProperties(item: Binding<WorkspaceLayoutItem>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Shape", selection: Binding<LayoutShapeKind>(
                get: {
                    if case .shape(let shape) = item.wrappedValue.kind { return shape }
                    return .rectangle
                },
                set: { item.wrappedValue.kind = .shape($0) }
            )) {
                ForEach(LayoutShapeKind.allCases) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            Picker("Stroke", selection: item.strokeColorName) {
                ForEach(layoutColorNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            Picker("Fill", selection: item.fillColorName) {
                ForEach(["None"] + layoutColorNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            HStack {
                Text("Line")
                Slider(value: item.lineWidth, in: 0.5...8)
            }
        }
    }

    private func numericField(value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
    }

    private var selectedLayout: WorkspaceLayout? {
        guard let selectedLayoutID = workspace.selectedLayoutID,
              let layout = workspace.layouts.first(where: { $0.id == selectedLayoutID }) else {
            return workspace.layouts.first
        }
        return layout
    }

    private var selectedLayoutIndex: Int? {
        if let selectedLayoutID = workspace.selectedLayoutID,
           let index = workspace.layouts.firstIndex(where: { $0.id == selectedLayoutID }) {
            return index
        }
        return workspace.layouts.indices.first
    }

    private var selectedItemBinding: Binding<WorkspaceLayoutItem>? {
        guard let layoutIndex = selectedLayoutIndex,
              let selectedItemID,
              let itemIndex = workspace.layouts[layoutIndex].items.firstIndex(where: { $0.id == selectedItemID }) else {
            return nil
        }
        return Binding(
            get: { workspace.layouts[layoutIndex].items[itemIndex] },
            set: { workspace.layouts[layoutIndex].items[itemIndex] = $0 }
        )
    }

    private var effectiveIterationSampleID: UUID? {
        guard selectedLayout?.iterationMode == .sample else { return nil }
        return selectedLayout?.iterationSampleID ?? workspace.samples.first?.id
    }

    private func hasPlot(in layout: WorkspaceLayout?) -> Bool {
        layout?.items.contains { item in
            if case .plot = item.kind {
                return true
            }
            return false
        } ?? false
    }

    private func canvasSize(for layout: WorkspaceLayout?, viewport: CGSize, scrollable: Bool, zoom: Double) -> CGSize {
        guard scrollable else {
            return CGSize(
                width: max(layoutDefaultCanvasSize.width, viewport.width),
                height: max(layoutDefaultCanvasSize.height, viewport.height)
            )
        }

        let resolvedZoom = max(zoom, 0.1)
        let viewportAdjustedWidth = (viewport.width + 640) / resolvedZoom
        let viewportAdjustedHeight = (viewport.height + 460) / resolvedZoom
        let itemBounds = layout?.items.reduce(CGRect.null) { bounds, item in
            bounds.union(
                CGRect(
                    x: item.frame.x,
                    y: item.frame.y,
                    width: item.frame.width,
                    height: item.frame.height
                )
            )
        } ?? .null
        let itemWidth = itemBounds.isNull ? 0 : itemBounds.maxX + 220
        let itemHeight = itemBounds.isNull ? 0 : itemBounds.maxY + 220

        return CGSize(
            width: max(layoutScrollableCanvasSize.width, viewportAdjustedWidth, itemWidth),
            height: max(layoutScrollableCanvasSize.height, viewportAdjustedHeight, itemHeight)
        )
    }

    private var selectedLayoutNameBinding: Binding<String> {
        Binding(
            get: { selectedLayout?.name ?? "Layout" },
            set: { workspace.renameSelectedLayout(to: $0) }
        )
    }

    private var iterationSampleBinding: Binding<UUID?> {
        Binding(
            get: { selectedLayout?.iterationSampleID ?? workspace.samples.first?.id },
            set: { value in
                guard let index = selectedLayoutIndex else { return }
                workspace.layouts[index].iterationSampleID = value
            }
        )
    }

    private func layoutBinding<Value>(_ keyPath: WritableKeyPath<WorkspaceLayout, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { selectedLayout?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard let index = selectedLayoutIndex else { return }
                workspace.layouts[index][keyPath: keyPath] = value
            }
        )
    }

    private func frameBinding(_ item: Binding<WorkspaceLayoutItem>, _ keyPath: WritableKeyPath<LayoutFrame, Double>) -> Binding<Double> {
        Binding(
            get: { item.wrappedValue.frame[keyPath: keyPath] },
            set: { item.wrappedValue.frame[keyPath: keyPath] = $0 }
        )
    }

    private func plotDescriptorBinding(_ item: Binding<WorkspaceLayoutItem>) -> Binding<WorkspacePlotDescriptor> {
        Binding(
            get: {
                if case .plot(let descriptor) = item.wrappedValue.kind {
                    return descriptor
                }
                return WorkspacePlotDescriptor(sourceSelection: WorkspaceSelection.allSamples, gatePath: [], name: "Plot")
            },
            set: { item.wrappedValue.kind = .plot($0) }
        )
    }

    private func insert(_ tool: LayoutCanvasTool) {
        switch tool {
        case .cursor:
            break
        case .text:
            addTextBox()
        case .rectangle:
            addShape(.rectangle)
        case .oval:
            addShape(.oval)
        case .line:
            addShape(.line)
        case .table:
            addTablePlaceholder()
        }
    }

    private func addTextBox() {
        let item = WorkspaceLayoutItem(frame: .defaultText, kind: .text("Annotation Box:\nSample Name\nPopulation Name\nEvent Count"))
        workspace.addLayoutItem(item)
        selectedItemID = item.id
    }

    private func addShape(_ shape: LayoutShapeKind) {
        let item = WorkspaceLayoutItem(frame: .defaultShape, kind: .shape(shape), fillColorName: shape == .line ? "None" : "Light Teal")
        workspace.addLayoutItem(item)
        selectedItemID = item.id
    }

    private func addTablePlaceholder() {
        let item = WorkspaceLayoutItem(frame: LayoutFrame(x: 460, y: 350, width: 330, height: 150), kind: .table)
        workspace.addLayoutItem(item)
        selectedItemID = item.id
    }

    private func handleGateDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                guard let payload = gatePayload(from: item) else { return }
                Task { @MainActor in
                    let descriptors = workspace.plotDescriptors(fromDragPayload: payload)
                    for (index, descriptor) in descriptors.enumerated() {
                        let frame = LayoutFrame.defaultPlot.offsetBy(dx: Double(index) * 28, dy: Double(index) * 28)
                        let item = WorkspaceLayoutItem(frame: frame, kind: .plot(descriptor))
                        workspace.addLayoutItem(item)
                        selectedItemID = item.id
                    }
                    status = descriptors.isEmpty
                        ? "Drop a gate or population row from the workspace."
                        : "Added \(descriptors.count) graph plot\(descriptors.count == 1 ? "" : "s")."
                }
            }
        }
        return true
    }

    private func deleteSelectedItem() {
        guard let selectedItemID else { return }
        workspace.deleteLayoutItem(id: selectedItemID)
        self.selectedItemID = nil
    }

    private func moveSelectedItem(zOffset: Int) {
        guard let layoutIndex = selectedLayoutIndex,
              let selectedItemID,
              let current = workspace.layouts[layoutIndex].items.firstIndex(where: { $0.id == selectedItemID }) else { return }
        let target = min(max(current + zOffset, 0), workspace.layouts[layoutIndex].items.count - 1)
        guard target != current else { return }
        let item = workspace.layouts[layoutIndex].items.remove(at: current)
        workspace.layouts[layoutIndex].items.insert(item, at: target)
    }

    private func setZoom(_ value: Double) {
        guard let index = selectedLayoutIndex else { return }
        workspace.layouts[index].zoom = min(max(value, layoutZoomLevels.first ?? 0.25), layoutZoomLevels.last ?? 2.4)
    }

    private func zoomIn() {
        setZoom(nextZoomLevel(direction: 1))
    }

    private func zoomOut() {
        setZoom(nextZoomLevel(direction: -1))
    }

    private func nextZoomLevel(direction: Int) -> Double {
        let current = selectedLayout?.zoom ?? 1
        if direction > 0 {
            return layoutZoomLevels.first { $0 > current + 0.001 } ?? (layoutZoomLevels.last ?? current)
        }
        return layoutZoomLevels.reversed().first { $0 < current - 0.001 } ?? (layoutZoomLevels.first ?? current)
    }

    private func createBatchReport() {
        guard let layout = selectedLayout else { return }
        if layout.batchDestination == .webPage {
            exportWebPage(layout)
        } else {
            workspace.createBatchLayout(from: layout.id)
        }
    }

    private func exportImage() {
        guard let layout = selectedLayout else { return }
        let panel = NSSavePanel()
        panel.title = "Export Layout Image"
        panel.nameFieldStringValue = "\(layout.name).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeLayoutPNG(layout, to: url, iterationSampleID: effectiveIterationSampleID)
            status = "Exported \(url.lastPathComponent)."
        } catch {
            status = "Could not export image: \(error.localizedDescription)"
        }
    }

    private func exportWebPage(_ layout: WorkspaceLayout) {
        let panel = NSSavePanel()
        panel.title = "Save Batch Web Page"
        panel.nameFieldStringValue = "\(layout.name).html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let htmlURL = panel.url else { return }

        do {
            let folder = htmlURL.deletingLastPathComponent().appendingPathComponent("OpenFlo Web Files", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var imageTags: [String] = []
            for (index, sample) in workspace.samples.enumerated() {
                let filename = "layout-\(index + 1).png"
                let imageURL = folder.appendingPathComponent(filename)
                try writeLayoutPNG(layout, to: imageURL, iterationSampleID: sample.id)
                imageTags.append("<h2>\(escapeHTML(sample.name))</h2><img src=\"OpenFlo Web Files/\(filename)\" alt=\"\(escapeHTML(sample.name))\">")
            }
            let html = """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <title>\(escapeHTML(layout.name))</title>
            <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; }
            img { max-width: 100%; border: 1px solid #c7c7c7; margin-bottom: 28px; }
            h2 { font-size: 16px; margin: 18px 0 8px; }
            </style>
            </head>
            <body>
            \(imageTags.joined(separator: "\n"))
            </body>
            </html>
            """
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            status = "Saved batch web page \(htmlURL.lastPathComponent)."
        } catch {
            status = "Could not create web batch: \(error.localizedDescription)"
        }
    }

    private func writeLayoutPNG(_ layout: WorkspaceLayout, to url: URL, iterationSampleID: UUID?) throws {
        let size = NSSize(width: 960, height: 680)
        let view = NSHostingView(
            rootView: LayoutPageView(
                workspace: workspace,
                layout: layout,
                selectedItemID: nil,
                iterationSampleID: iterationSampleID,
                isInteractive: false,
                canvasSize: size,
                zoom: 1,
                onSelect: { _ in },
                onUpdate: { _ in },
                onDelete: { _ in },
                onOverlayDrop: { _, _ in }
            )
            .frame(width: size.width, height: size.height)
        )
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }

    private func addOverlay(_ payload: String, to item: WorkspaceLayoutItem) {
        guard case .plot(var descriptor) = item.kind else { return }
        let overlays = workspace.plotOverlayDescriptors(
            fromDragPayload: payload,
            startingAt: descriptor.overlays.count + 1
        )
        guard !overlays.isEmpty else {
            status = "Drop a gate or population row onto a plot to create an overlay."
            return
        }

        let existingSelections = Set(descriptor.overlays.map(\.sourceSelection) + [descriptor.sourceSelection])
        let newOverlays = overlays.filter { !existingSelections.contains($0.sourceSelection) }
        guard !newOverlays.isEmpty else {
            status = "That population is already in this overlay."
            return
        }

        var updated = item
        descriptor.plotMode = .dot
        descriptor.overlays.append(contentsOf: newOverlays)
        updated.kind = .plot(descriptor)
        workspace.updateLayoutItem(updated)
        selectedItemID = item.id
        status = "Added \(newOverlays.count) population\(newOverlays.count == 1 ? "" : "s") to the overlay."
    }
}

private struct LayoutPageView: View {
    @ObservedObject var workspace: WorkspaceModel
    let layout: WorkspaceLayout?
    let selectedItemID: UUID?
    let iterationSampleID: UUID?
    let isInteractive: Bool
    let canvasSize: CGSize
    let zoom: Double
    let onSelect: (UUID?) -> Void
    let onUpdate: (WorkspaceLayoutItem) -> Void
    let onDelete: (UUID) -> Void
    let onOverlayDrop: (String, WorkspaceLayoutItem) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(nil)
                }

            if layout?.showGrid == true {
                LayoutGridView()
            }

            if layout?.showPageBreaks == true {
                LayoutPageBreakView(pageSize: layoutPrintPageSize)
            }

            if isInteractive {
                LayoutCanvasInteractionMonitor(
                    items: layout?.items ?? [],
                    selectedItemID: selectedItemID,
                    onSelect: onSelect,
                    onUpdate: onUpdate
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(false)
            }

            if let layout {
                ForEach(layout.items) { item in
                    LayoutCanvasItemView(
                        workspace: workspace,
                        item: item,
                        selected: selectedItemID == item.id,
                        iterationSampleID: iterationSampleID,
                        isInteractive: isInteractive,
                        zoom: zoom,
                        onSelect: { onSelect(item.id) },
                        onUpdate: onUpdate,
                        onDelete: { onDelete(item.id) },
                        onOverlayDrop: { payload in onOverlayDrop(payload, item) }
                    )
                }
            } else {
                Text("No layout")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .position(x: canvasSize.width / 2, y: canvasSize.height / 2)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(Color.white)
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.4))
        .contentShape(Rectangle())
    }
}

private struct LayoutCanvasItemView: View {
    @ObservedObject var workspace: WorkspaceModel
    let item: WorkspaceLayoutItem
    let selected: Bool
    let iterationSampleID: UUID?
    let isInteractive: Bool
    let zoom: Double
    let onSelect: () -> Void
    let onUpdate: (WorkspaceLayoutItem) -> Void
    let onDelete: () -> Void
    let onOverlayDrop: (String) -> Void

    @State private var dragStartFrame: LayoutFrame?
    @State private var resizeStartFrame: LayoutFrame?
    @State private var activeResizeHandle: LayoutResizeHandle?
    @State private var isDropTargeted = false

    var body: some View {
        itemBody
            .frame(width: item.frame.width, height: item.frame.height)
            .contentShape(Rectangle())
            .overlay {
                if selected {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if selected, isInteractive {
                    resizeHandles
                }
            }
            .overlay {
                if isDropTargeted, acceptsOverlayDrop {
                    Rectangle()
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                        .background(Color.red.opacity(0.08))
                        .allowsHitTesting(false)
                }
            }
            .position(x: item.frame.x + item.frame.width / 2, y: item.frame.y + item.frame.height / 2)
            .onDrop(of: [UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
                handleOverlayDrop(providers)
            }
            .contextMenu {
                Button("Delete") { onDelete() }
            }
    }

    private var resizeHandles: some View {
        GeometryReader { geometry in
            ForEach(LayoutResizeHandle.allCases) { handle in
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                }
                    .frame(width: handle.hitSize(in: geometry.size).width, height: handle.hitSize(in: geometry.size).height)
                    .position(handle.position(in: geometry.size))
                    .contentShape(Rectangle())
                    .help(handle.helpText)
            }
        }
        .allowsHitTesting(false)
    }

    private var acceptsOverlayDrop: Bool {
        if case .plot = item.kind {
            return isInteractive
        }
        return false
    }

    @ViewBuilder
    private var itemBody: some View {
        switch item.kind {
        case .plot(let descriptor):
            LayoutPlotItemView(
                workspace: workspace,
                descriptor: descriptor,
                iterationSampleID: iterationSampleID
            )
        case .text(let text):
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(Color.white.opacity(0.92))
                .overlay(Rectangle().stroke(Color.black.opacity(0.35), lineWidth: 1))
        case .shape(let shape):
            LayoutShapeView(shape: shape, item: item)
        case .table:
            LayoutTablePlaceholderView(workspace: workspace)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard activeResizeHandle == nil else { return }
                if selected, resizeHandle(at: value.startLocation, in: itemSize) != nil {
                    return
                }
                if dragStartFrame == nil {
                    dragStartFrame = item.frame
                    onSelect()
                }
                guard let dragStartFrame else { return }
                let translation = unscaled(value.translation)
                var moved = item
                moved.frame = dragStartFrame.offsetBy(dx: translation.width, dy: translation.height)
                onUpdate(moved)
            }
            .onEnded { _ in
                dragStartFrame = nil
            }
    }

    private func resizeGesture(_ handle: LayoutResizeHandle) -> some Gesture {
        DragGesture()
            .onChanged { value in
                activeResizeHandle = handle
                if resizeStartFrame == nil {
                    resizeStartFrame = item.frame
                    onSelect()
                }
                guard let resizeStartFrame else { return }
                let translation = unscaled(value.translation)
                var resized = item
                resized.frame = handle.resizedFrame(
                    from: resizeStartFrame,
                    translation: translation,
                    minimumSize: CGSize(width: 90, height: 70)
                )
                onUpdate(resized)
            }
            .onEnded { _ in
                resizeStartFrame = nil
                activeResizeHandle = nil
            }
    }

    private func unscaled(_ translation: CGSize) -> CGSize {
        let factor = max(CGFloat(zoom), 0.01)
        return CGSize(width: translation.width / factor, height: translation.height / factor)
    }

    private func resizeHandle(at location: CGPoint, in size: CGSize) -> LayoutResizeHandle? {
        LayoutResizeHandle.allCases.first { handle in
            handle.hitRect(in: size).contains(location)
        }
    }

    private var itemSize: CGSize {
        CGSize(width: CGFloat(item.frame.width), height: CGFloat(item.frame.height))
    }

    private func handleOverlayDrop(_ providers: [NSItemProvider]) -> Bool {
        guard acceptsOverlayDrop else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                guard let payload = gatePayload(from: item) else { return }
                Task { @MainActor in
                    onOverlayDrop(payload)
                }
            }
        }
        return true
    }
}

private enum LayoutResizeHandle: CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: String { "\(self)" }

    var helpText: String {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            return "Resize"
        case .top, .bottom:
            return "Resize height"
        case .left, .right:
            return "Resize width"
        }
    }

    func position(in size: CGSize) -> CGPoint {
        let inset: CGFloat = 8
        switch self {
        case .topLeft:
            return CGPoint(x: inset, y: inset)
        case .top:
            return CGPoint(x: size.width / 2, y: inset)
        case .topRight:
            return CGPoint(x: size.width - inset, y: inset)
        case .right:
            return CGPoint(x: size.width - inset, y: size.height / 2)
        case .bottomRight:
            return CGPoint(x: size.width - inset, y: size.height - inset)
        case .bottom:
            return CGPoint(x: size.width / 2, y: size.height - inset)
        case .bottomLeft:
            return CGPoint(x: inset, y: size.height - inset)
        case .left:
            return CGPoint(x: inset, y: size.height / 2)
        }
    }

    func hitSize(in size: CGSize) -> CGSize {
        switch self {
        case .top, .bottom:
            return CGSize(width: max(44, size.width - 44), height: 24)
        case .left, .right:
            return CGSize(width: 24, height: max(44, size.height - 44))
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            return CGSize(width: 28, height: 28)
        }
    }

    func hitRect(in size: CGSize) -> CGRect {
        let center = position(in: size)
        let hitSize = hitSize(in: size)
        return CGRect(
            x: center.x - hitSize.width / 2,
            y: center.y - hitSize.height / 2,
            width: hitSize.width,
            height: hitSize.height
        )
    }

    func resizedFrame(from frame: LayoutFrame, translation: CGSize, minimumSize: CGSize) -> LayoutFrame {
        var x = frame.x
        var y = frame.y
        var width = frame.width
        var height = frame.height
        let dx = Double(translation.width)
        let dy = Double(translation.height)
        let minWidth = Double(minimumSize.width)
        let minHeight = Double(minimumSize.height)

        switch self {
        case .topLeft, .left, .bottomLeft:
            let proposedWidth = frame.width - dx
            if proposedWidth >= minWidth {
                x = frame.x + dx
                width = proposedWidth
            } else {
                x = frame.x + frame.width - minWidth
                width = minWidth
            }
        case .topRight, .right, .bottomRight:
            width = max(minWidth, frame.width + dx)
        case .top, .bottom:
            break
        }

        switch self {
        case .topLeft, .top, .topRight:
            let proposedHeight = frame.height - dy
            if proposedHeight >= minHeight {
                y = frame.y + dy
                height = proposedHeight
            } else {
                y = frame.y + frame.height - minHeight
                height = minHeight
            }
        case .bottomLeft, .bottom, .bottomRight:
            height = max(minHeight, frame.height + dy)
        case .left, .right:
            break
        }

        return LayoutFrame(x: max(0, x), y: max(0, y), width: width, height: height)
    }
}

private struct LayoutPlotItemView: View {
    @ObservedObject var workspace: WorkspaceModel
    let descriptor: WorkspacePlotDescriptor
    let iterationSampleID: UUID?

    @State private var snapshot: LayoutPlotSnapshot?
    @State private var activeRenderID: String?
    @State private var isRendering = false

    var body: some View {
        let renderID = workspace.layoutPlotSnapshotRenderID(for: descriptor, iterationSampleID: iterationSampleID)
        VStack(spacing: 0) {
            ZStack {
                if let image = snapshot?.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .padding(22)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.12))
                    Text(isRendering ? "Rendering plot..." : "Missing population")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if descriptor.showGrid {
                    PlotGridOverlay()
                        .padding(22)
                }

                if descriptor.showAncestry, let snapshot {
                    ancestryView(snapshot.ancestry)
                        .frame(width: 92)
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let snapshot, !snapshot.legend.isEmpty {
                    legendView(snapshot.legend)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot?.sampleName ?? descriptor.name)
                    .font(.caption.weight(.semibold))
                Text("\(snapshot?.populationName ?? descriptor.name) • \((snapshot?.eventCount ?? 0).formatted()) events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(snapshot?.xAxisTitle ?? "X Axis")
                    Spacer()
                    Text(snapshot?.yAxisTitle ?? "Y Axis")
                }
                .font(.system(size: descriptor.axisFontSize * 0.72))
                .foregroundStyle(color(named: descriptor.axisColorName))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .background(Color.white)
        .overlay(Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 1))
        .onAppear {
            refreshSnapshot(renderID: renderID)
        }
        .onChange(of: renderID) {
            refreshSnapshot(renderID: renderID)
        }
    }

    private func refreshSnapshot(renderID: String) {
        if let cached = workspace.cachedLayoutPlotSnapshot(for: descriptor, iterationSampleID: iterationSampleID) {
            snapshot = cached
            activeRenderID = renderID
            isRendering = false
            return
        }

        guard descriptor.overlays.isEmpty,
              let payload = workspace.layoutPlotRenderPayload(for: descriptor, iterationSampleID: iterationSampleID) else {
            snapshot = workspace.layoutPlotSnapshot(for: descriptor, iterationSampleID: iterationSampleID)
            activeRenderID = renderID
            isRendering = false
            return
        }

        guard activeRenderID != renderID || !isRendering else { return }
        activeRenderID = renderID

        if payload.sampleKind == .singleCell {
            let rendered = WorkspaceModel.renderLayoutPlotSnapshot(from: payload)
            workspace.storeLayoutPlotSnapshot(rendered, for: descriptor, iterationSampleID: iterationSampleID)
            snapshot = rendered
            isRendering = false
            return
        }

        snapshot = nil
        isRendering = true

        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = WorkspaceModel.renderLayoutPlotSnapshot(from: payload)
            DispatchQueue.main.async {
                guard activeRenderID == renderID else { return }
                workspace.storeLayoutPlotSnapshot(rendered, for: descriptor, iterationSampleID: iterationSampleID)
                snapshot = rendered
                isRendering = false
            }
        }
    }

    private func ancestryView(_ ancestry: [String]) -> some View {
        VStack(spacing: 4) {
            ForEach(ancestry.indices, id: \.self) { index in
                Text(ancestry[index])
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(3)
                    .background(Color.white.opacity(0.9))
                    .overlay(Rectangle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
    }

    private func legendView(_ entries: [LayoutPlotLegendEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(color(named: entry.colorName))
                        .frame(width: 9, height: 9)
                    Text(entry.name)
                        .lineLimit(1)
                    Text(entry.eventCount.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 8, weight: .semibold))
            }
        }
        .padding(5)
        .frame(maxWidth: 190, alignment: .leading)
        .background(Color.white.opacity(0.88))
        .overlay(Rectangle().stroke(Color.black.opacity(0.25), lineWidth: 1))
    }
}

private struct LayoutShapeView: View {
    let shape: LayoutShapeKind
    let item: WorkspaceLayoutItem

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: item.lineWidth, dy: item.lineWidth)
            let stroke = color(named: item.strokeColorName)
            let fill = fillColor(named: item.fillColorName)
            let path: Path
            switch shape {
            case .rectangle:
                path = Path(rect)
            case .oval:
                path = Path(ellipseIn: rect)
            case .line:
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                line.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path = line
            case .diamond:
                var diamond = Path()
                diamond.move(to: CGPoint(x: rect.midX, y: rect.minY))
                diamond.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                diamond.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                diamond.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                diamond.closeSubpath()
                path = diamond
            case .triangle:
                var triangle = Path()
                triangle.move(to: CGPoint(x: rect.midX, y: rect.minY))
                triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                triangle.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                triangle.closeSubpath()
                path = triangle
            }
            if let fill {
                context.fill(path, with: .color(fill))
            }
            context.stroke(path, with: .color(stroke), lineWidth: item.lineWidth)
        }
    }
}

private struct LayoutTablePlaceholderView: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sample")
                Spacer()
                Text("# Events")
            }
            .font(.caption.weight(.semibold))
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))

            ForEach(workspace.samples.prefix(5)) { sample in
                HStack {
                    Text(sample.name)
                        .lineLimit(1)
                    Spacer()
                    Text(sample.table.rowCount.formatted())
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
                }
            }
            Spacer()
        }
        .background(Color.white)
        .overlay(Rectangle().stroke(Color.black.opacity(0.45), lineWidth: 1))
    }
}

private struct LayoutGridView: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0.0, through: size.width, by: 24) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 24) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.gray.opacity(0.18)), lineWidth: 1)
        }
    }
}

private struct LayoutPageBreakView: View {
    let pageSize: CGSize

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let columnCount = max(1, Int(ceil(size.width / max(pageSize.width, 1))))
            let rowCount = max(1, Int(ceil(size.height / max(pageSize.height, 1))))

            for column in 1..<columnCount {
                let x = CGFloat(column) * pageSize.width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for row in 1..<rowCount {
                let y = CGFloat(row) * pageSize.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(.black.opacity(0.42)), style: StrokeStyle(lineWidth: 1.2, dash: [9, 9]))

            for row in 0..<rowCount {
                for column in 0..<columnCount {
                    let pageNumber = row * columnCount + column + 1
                    let x = min(CGFloat(column) * pageSize.width + pageSize.width / 2, size.width - 34)
                    let y = min(CGFloat(row + 1) * pageSize.height - 20, size.height - 20)
                    let text = context.resolve(
                        Text("- \(pageNumber) -")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.blue)
                    )
                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PlotGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for index in 1..<4 {
                let x = size.width * CGFloat(index) / 4
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * CGFloat(index) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.black.opacity(0.22)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct LayoutCanvasInteractionMonitor: NSViewRepresentable {
    let items: [WorkspaceLayoutItem]
    let selectedItemID: UUID?
    var onSelect: (UUID?) -> Void
    var onUpdate: (WorkspaceLayoutItem) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.items = items
        view.selectedItemID = selectedItemID
        view.onSelect = onSelect
        view.onUpdate = onUpdate
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.items = items
        nsView.selectedItemID = selectedItemID
        nsView.onSelect = onSelect
        nsView.onUpdate = onUpdate
    }

    final class MonitorView: NSView {
        struct Operation {
            enum Kind {
                case move
                case resize(LayoutResizeHandle)
            }

            let itemID: UUID
            let startPoint: CGPoint
            let startFrame: LayoutFrame
            let kind: Kind
            var didDrag = false
        }

        var items: [WorkspaceLayoutItem] = []
        var selectedItemID: UUID?
        var onSelect: ((UUID?) -> Void)?
        var onUpdate: ((WorkspaceLayoutItem) -> Void)?
        private var monitor: Any?
        private var operation: Operation?
        private var pendingEmptyClick = false

        override var isFlipped: Bool { true }

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
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else {
                    if event.type == .leftMouseUp {
                        self.finishInteraction(at: point)
                    }
                    return event
                }

                switch event.type {
                case .leftMouseDown:
                    self.beginInteraction(at: point)
                case .leftMouseDragged:
                    self.updateInteraction(at: point)
                case .leftMouseUp:
                    self.finishInteraction(at: point)
                default:
                    break
                }
                return event
            }
        }

        private func beginInteraction(at point: CGPoint) {
            guard let hit = hitItem(at: point) else {
                pendingEmptyClick = true
                operation = nil
                return
            }

            pendingEmptyClick = false
            onSelect?(hit.item.id)

            if hit.item.id == selectedItemID,
               let handle = resizeHandle(at: point, in: hit.item) {
                operation = Operation(itemID: hit.item.id, startPoint: point, startFrame: hit.item.frame, kind: .resize(handle))
                return
            }
            operation = Operation(itemID: hit.item.id, startPoint: point, startFrame: hit.item.frame, kind: .move)
        }

        private func updateInteraction(at point: CGPoint) {
            guard var operation,
                  var item = items.first(where: { $0.id == operation.itemID }) else { return }
            operation.didDrag = true
            self.operation = operation
            let translation = CGSize(width: point.x - operation.startPoint.x, height: point.y - operation.startPoint.y)

            switch operation.kind {
            case .move:
                item.frame = operation.startFrame.offsetBy(dx: translation.width, dy: translation.height)
            case .resize(let handle):
                item.frame = handle.resizedFrame(
                    from: operation.startFrame,
                    translation: translation,
                    minimumSize: CGSize(width: 90, height: 70)
                )
            }
            onUpdate?(item)
        }

        private func finishInteraction(at point: CGPoint) {
            defer {
                self.pendingEmptyClick = false
                self.operation = nil
            }
            if pendingEmptyClick, hitItem(at: point) == nil {
                onSelect?(nil)
            }
        }

        private func hitItem(at point: CGPoint) -> (item: WorkspaceLayoutItem, rect: CGRect)? {
            for item in items.reversed() {
                let rect = CGRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
                if rect.insetBy(dx: -8, dy: -8).contains(point) {
                    return (item, rect)
                }
            }
            return nil
        }

        private func resizeHandle(at point: CGPoint, in item: WorkspaceLayoutItem) -> LayoutResizeHandle? {
            let localPoint = CGPoint(x: point.x - item.frame.x, y: point.y - item.frame.y)
            let itemSize = CGSize(width: item.frame.width, height: item.frame.height)
            return LayoutResizeHandle.allCases.first { handle in
                handle.hitRect(in: itemSize).contains(localPoint)
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

private struct LayoutDeleteKeyMonitor: NSViewRepresentable {
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
                guard !isEditingText(in: window) else { return event }
                return self.onDelete?() == true ? nil : event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func isEditingText(in window: NSWindow) -> Bool {
            if window.firstResponder is NSTextView {
                return true
            }
            if window.firstResponder is NSTextField {
                return true
            }
            return false
        }
    }
}

private enum LayoutCanvasTool: String, CaseIterable, Identifiable {
    case cursor = "Cursor"
    case text = "Text"
    case rectangle = "Rectangle"
    case oval = "Oval"
    case line = "Line"
    case table = "Stats Table"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .text: return "textformat"
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .line: return "line.diagonal"
        case .table: return "tablecells"
        }
    }

    var insertsImmediately: Bool {
        self != .cursor
    }
}
