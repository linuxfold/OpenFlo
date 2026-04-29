import AppKit
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct TableEditorView: View {
    @ObservedObject var workspace: WorkspaceModel

    @State private var columns: [WorkspaceTableColumn] = []
    @State private var selectedColumnIDs: Set<UUID> = []
    @State private var displayTarget: TableDisplayTarget = .display
    @State private var fileFormat: TableFileFormat = .text
    @State private var destinationURL: URL?
    @State private var status = "Drag populations or gates from the workspace."

    var body: some View {
        VStack(spacing: 0) {
            ribbon
            columnHeader
            columnList
            outputBand
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handleGateDrop(providers)
        }
    }

    private var ribbon: some View {
        HStack(spacing: 14) {
            Label("Table Editor", systemImage: "tablecells")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.teal)
                .frame(width: 150, alignment: .leading)

            Divider()
                .frame(height: 62)

            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Button {
                        addWorkspaceSelection()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(workspace.selected?.gateID == nil)

                    Button {
                        duplicateSelectedRows()
                    } label: {
                        Label("Duplicate", systemImage: "square.on.square")
                    }
                    .disabled(selectedColumnIDs.isEmpty)

                    Button(role: .destructive) {
                        deleteSelectedRows()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedColumnIDs.isEmpty)
                }

                Text("Rows")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 62)

            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Button {
                        setHeatMap(true)
                    } label: {
                        Label("Heat Map", systemImage: "flame")
                    }
                    .disabled(selectedColumnIDs.isEmpty)

                    Button {
                        setHeatMap(false)
                    } label: {
                        Label("No Heat", systemImage: "flame.slash")
                    }
                    .disabled(selectedColumnIDs.isEmpty)
                }

                Text("Visualize")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 62)

            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Picker("Display", selection: $displayTarget) {
                        ForEach(TableDisplayTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)

                    Picker("Type", selection: $fileFormat) {
                        ForEach(TableFileFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .disabled(displayTarget == .display)

                    Button {
                        chooseDestination()
                    } label: {
                        Label("Destination", systemImage: "folder")
                    }
                    .disabled(displayTarget == .display)
                }

                Text("Output")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                createTable()
            } label: {
                Label("Create Table", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(columns.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 94)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.18)).frame(height: 1)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Statistic")
                .frame(width: 160, alignment: .leading)
            Text("Parameter")
                .frame(width: 230, alignment: .leading)
            Text("Heat")
                .frame(width: 58, alignment: .center)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var columnList: some View {
        List(selection: $selectedColumnIDs) {
            ForEach($columns) { $column in
                HStack(spacing: 8) {
                    TextField("Column Name", text: $column.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Picker("", selection: $column.statistic) {
                        ForEach(WorkspaceStatisticKind.allCases) { statistic in
                            Text(statistic.rawValue).tag(statistic)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)

                    parameterPicker(column: $column)
                        .frame(width: 230)
                        .disabled(!column.statistic.requiresChannel)
                        .opacity(column.statistic.requiresChannel ? 1 : 0.45)

                    Toggle("", isOn: $column.heatMapped)
                        .toggleStyle(.checkbox)
                        .frame(width: 58)
                }
                .padding(.vertical, 4)
                .tag(column.id)
            }
        }
        .overlay {
            if columns.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "arrow.down.doc")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Drag workspace gates or populations here")
                        .font(.headline)
                    Text("Each row becomes a statistic column in the generated table.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var outputBand: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.teal)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(destinationURL?.lastPathComponent ?? "No destination")
                .font(.caption)
                .foregroundStyle(displayTarget == .file ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func parameterPicker(column: Binding<WorkspaceTableColumn>) -> some View {
        let names = workspace.availableStatisticChannelNames(for: column.wrappedValue.sourceSelection)
        return Picker("", selection: Binding<String>(
            get: { column.wrappedValue.channelName ?? names.first ?? "" },
            set: { column.wrappedValue.channelName = $0.isEmpty ? nil : $0 }
        )) {
            ForEach(names, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .labelsHidden()
    }

    private func addWorkspaceSelection() {
        guard let selection = workspace.selected else { return }
        let path = workspace.gatePathNames(for: selection)
        guard !path.isEmpty else { return }
        columns.append(
            WorkspaceTableColumn(
                sourceSelection: selection,
                gatePath: path,
                name: path.last ?? workspace.displayName(for: selection),
                statistic: .count,
                channelName: workspace.availableStatisticChannelNames(for: selection).first
            )
        )
        status = "Added \(path.last ?? "population")."
    }

    private func duplicateSelectedRows() {
        let selected = columns.filter { selectedColumnIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        columns.append(contentsOf: selected.map { column in
            var duplicate = column
            duplicate.id = UUID()
            duplicate.name = "\(column.name) Copy"
            return duplicate
        })
        status = "Duplicated \(selected.count) row\(selected.count == 1 ? "" : "s")."
    }

    private func deleteSelectedRows() {
        let count = selectedColumnIDs.count
        columns.removeAll { selectedColumnIDs.contains($0.id) }
        selectedColumnIDs.removeAll()
        status = "Deleted \(count) row\(count == 1 ? "" : "s")."
    }

    private func setHeatMap(_ enabled: Bool) {
        for index in columns.indices where selectedColumnIDs.contains(columns[index].id) {
            columns[index].heatMapped = enabled
        }
        status = enabled ? "Enabled heat mapping." : "Disabled heat mapping."
    }

    private func handleGateDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                guard let payload = gatePayload(from: item) else { return }
                Task { @MainActor in
                    let newColumns = workspace.tableColumns(fromDragPayload: payload)
                    columns.append(contentsOf: newColumns)
                    status = newColumns.isEmpty
                        ? "Drop a gate or population row from the workspace."
                        : "Added \(newColumns.count) table row\(newColumns.count == 1 ? "" : "s")."
                }
            }
        }
        return true
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Save Table"
        panel.nameFieldStringValue = "OpenFlo Table.\(fileFormat.pathExtension)"
        panel.allowedContentTypes = fileFormat.contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationURL = url
        status = "Destination set to \(url.lastPathComponent)."
    }

    private func createTable() {
        let output = workspace.tableOutput(for: columns)
        if displayTarget == .display {
            openOutputWindow(output)
            status = "Displayed table for \(output.rows.count) sample\(output.rows.count == 1 ? "" : "s")."
            return
        }

        guard let destinationURL else {
            chooseDestination()
            guard let destinationURL else { return }
            save(output, to: destinationURL)
            return
        }
        save(output, to: destinationURL)
    }

    private func save(_ output: WorkspaceTableOutput, to url: URL) {
        do {
            let text = fileFormat.render(output)
            try text.write(to: url, atomically: true, encoding: .utf8)
            status = "Saved \(url.lastPathComponent)."
        } catch {
            status = "Could not save table: \(error.localizedDescription)"
        }
    }

    private func openOutputWindow(_ output: WorkspaceTableOutput) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenFlo Table Output"
        window.center()
        window.contentView = NSHostingView(rootView: TableOutputView(output: output))
        let controller = NSWindowController(window: window)
        TableOutputWindowStore.controllers.append(controller)
        controller.showWindow(nil)
    }
}

private enum TableDisplayTarget: String, CaseIterable, Identifiable {
    case display = "Display"
    case file = "To File"

    var id: String { rawValue }
}

private enum TableFileFormat: String, CaseIterable, Identifiable {
    case text = "Text"
    case csv = "CSV"
    case html = "HTML"

    var id: String { rawValue }

    var pathExtension: String {
        switch self {
        case .text: return "txt"
        case .csv: return "csv"
        case .html: return "html"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .text:
            return [.plainText]
        case .csv:
            return [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        case .html:
            return [.html]
        }
    }

    func render(_ output: WorkspaceTableOutput) -> String {
        switch self {
        case .text:
            return delimited(output, separator: "\t")
        case .csv:
            return delimited(output, separator: ",")
        case .html:
            return html(output)
        }
    }

    private func delimited(_ output: WorkspaceTableOutput, separator: String) -> String {
        let header = ["Sample"] + output.columns.map(\.name)
        let lines = output.rows.map { row in
            ([row.sampleName] + row.values.map { value in
                value.map { formatStatistic($0) } ?? ""
            })
            .map { escapeDelimited($0, separator: separator) }
            .joined(separator: separator)
        }
        return ([header.map { escapeDelimited($0, separator: separator) }.joined(separator: separator)] + lines)
            .joined(separator: "\n")
    }

    private func html(_ output: WorkspaceTableOutput) -> String {
        let ranges = heatMapRanges(for: output)
        let headerCells = output.columns.map { "<th>\(escapeHTML($0.name))</th>" }.joined()
        let bodyRows = output.rows.map { row in
            let valueCells = row.values.enumerated().map { index, value -> String in
                let text = value.map { formatStatistic($0) } ?? ""
                let style = heatMapStyle(value: value, range: ranges[index], enabled: output.columns[index].heatMapped)
                return "<td\(style)>\(escapeHTML(text))</td>"
            }.joined()
            return "<tr><th>\(escapeHTML(row.sampleName))</th>\(valueCells)</tr>"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>OpenFlo Table</title>
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #b7b7b7; padding: 6px 10px; text-align: right; }
        th:first-child, td:first-child { text-align: left; }
        thead th { background: #e9eef0; }
        </style>
        </head>
        <body>
        <table>
        <thead><tr><th>Sample</th>\(headerCells)</tr></thead>
        <tbody>
        \(bodyRows)
        </tbody>
        </table>
        </body>
        </html>
        """
    }
}

private struct TableOutputView: View {
    let output: WorkspaceTableOutput

    var body: some View {
        let ranges = heatMapRanges(for: output)
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    headerCell("Sample", alignment: .leading)
                    ForEach(output.columns) { column in
                        headerCell(column.name)
                    }
                }

                ForEach(output.rows) { row in
                    GridRow {
                        bodyCell(row.sampleName, alignment: .leading)
                        ForEach(output.columns.indices, id: \.self) { index in
                            let value = row.values[index]
                            bodyCell(
                                value.map { formatStatistic($0) } ?? "",
                                fill: heatMapColor(value: value, range: ranges[index], enabled: output.columns[index].heatMapped)
                            )
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func headerCell(_ text: String, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .frame(width: 150, height: 32, alignment: alignment)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 1))
    }

    private func bodyCell(_ text: String, alignment: Alignment = .trailing, fill: Color = Color(nsColor: .textBackgroundColor)) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .frame(width: 150, height: 30, alignment: alignment)
            .padding(.horizontal, 8)
            .background(fill)
            .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 1))
    }
}

@MainActor
private enum TableOutputWindowStore {
    static var controllers: [NSWindowController] = []
}

private func heatMapRanges(for output: WorkspaceTableOutput) -> [ClosedRange<Double>?] {
    output.columns.indices.map { index in
        let values = output.rows.compactMap { row in
            row.values.indices.contains(index) ? row.values[index] : nil
        }
        guard let minimum = values.min(), let maximum = values.max(), minimum < maximum else { return nil }
        return minimum...maximum
    }
}

private func heatMapColor(value: Double?, range: ClosedRange<Double>?, enabled: Bool) -> Color {
    guard enabled, let value, let range else { return Color(nsColor: .textBackgroundColor) }
    let fraction = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    let red = 0.20 + fraction * 0.82
    let green = 0.44 + fraction * 0.42
    let blue = 0.94 - fraction * 0.72
    return Color(red: red, green: green, blue: blue).opacity(0.68)
}

private func heatMapStyle(value: Double?, range: ClosedRange<Double>?, enabled: Bool) -> String {
    guard enabled, let value, let range else { return "" }
    let fraction = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    let red = Int((0.20 + fraction * 0.82) * 255)
    let green = Int((0.44 + fraction * 0.42) * 255)
    let blue = Int((0.94 - fraction * 0.72) * 255)
    return " style=\"background: rgb(\(red), \(green), \(blue));\""
}

private func formatStatistic(_ value: Double) -> String {
    guard value.isFinite else { return "" }
    if abs(value.rounded() - value) < 0.0001 {
        return Int(value.rounded()).formatted()
    }
    if abs(value) >= 100 {
        return String(format: "%.1f", value)
    }
    return String(format: "%.3g", value)
}

private func escapeDelimited(_ value: String, separator: String) -> String {
    guard value.contains(separator) || value.contains("\"") || value.contains("\n") else { return value }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}
