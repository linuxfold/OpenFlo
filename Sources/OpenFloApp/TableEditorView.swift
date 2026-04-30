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
    @State private var templateName = "Table Template"
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
                    Menu {
                        if workspace.tableTemplates.isEmpty {
                            Text("No saved templates")
                        } else {
                            ForEach(workspace.tableTemplates) { template in
                                Button(template.name) {
                                    columns = template.columns
                                    selectedColumnIDs.removeAll()
                                    templateName = template.name
                                    status = "Loaded \(template.name)."
                                }
                            }
                        }
                    } label: {
                        Label("Load", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        workspace.saveTableTemplate(name: templateName, columns: columns)
                        status = "Saved \(templateName)."
                    } label: {
                        Label("Save", systemImage: "tray.and.arrow.up")
                    }
                    .disabled(columns.isEmpty)
                }

                TextField("Template name", text: $templateName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
            }

            Divider()
                .frame(height: 62)

            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Button {
                        addWorkspaceSelection()
                    } label: {
                        Label("Statistic", systemImage: "plus")
                    }

                    Button {
                        addKeywordColumn()
                    } label: {
                        Label("Keyword", systemImage: "tag")
                    }

                    Button {
                        addFormulaColumn()
                    } label: {
                        Label("Formula", systemImage: "function")
                    }

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
            Text("Type")
                .frame(width: 105, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Definition")
                .frame(width: 420, alignment: .leading)
            Text("Show")
                .frame(width: 52, alignment: .center)
            Text("Control")
                .frame(width: 66, alignment: .center)
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
                    Picker("", selection: $column.columnType) {
                        ForEach(ReportColumnType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 105)

                    TextField("Column Name", text: $column.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    columnDefinition(column: $column)
                        .frame(width: 420)

                    Toggle("", isOn: $column.showValues)
                        .toggleStyle(.checkbox)
                        .frame(width: 52)

                    Toggle("", isOn: $column.defineAsControl)
                        .toggleStyle(.checkbox)
                        .frame(width: 66)

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

    @ViewBuilder
    private func columnDefinition(column: Binding<WorkspaceTableColumn>) -> some View {
        switch column.wrappedValue.columnType {
        case .statistic:
            HStack(spacing: 6) {
                Picker("", selection: column.statistic) {
                    ForEach(WorkspaceStatisticKind.allCases) { statistic in
                        Text(statistic.rawValue).tag(statistic)
                    }
                }
                .labelsHidden()
                .frame(width: 152)

                if column.wrappedValue.statistic.requiresChannel {
                    parameterPicker(column: column)
                        .frame(width: 170)
                }

                if column.wrappedValue.statistic.requiresPercentile {
                    TextField(
                        "P",
                        value: Binding<Double>(
                            get: { column.wrappedValue.percentile ?? 50 },
                            set: { column.wrappedValue.percentile = $0 }
                        ),
                        format: .number
                    )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 54)
                        .help("Percentile")
                }

                if column.wrappedValue.statistic == .frequencyOfPopulation {
                    TextField(
                        "Denominator path",
                        text: Binding<String>(
                            get: { column.wrappedValue.denominatorGatePath.joined(separator: "/") },
                            set: { column.wrappedValue.denominatorGatePath = $0.split(separator: "/").map(String.init) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
        case .keyword:
            HStack(spacing: 6) {
                Picker("", selection: column.keyword.scope) {
                    ForEach(KeywordScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 116)

                TextField("Keyword", text: column.keyword.key)
                    .textFieldStyle(.roundedBorder)

                if column.wrappedValue.keyword.scope == .parameter {
                    parameterNamePicker(column: column)
                        .frame(width: 150)
                }
            }
        case .formula:
            TextField("Formula, e.g. <Cell column=\"Mean\"/> / <Cell column=\"Count\"/>", text: column.formula.expression)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func parameterNamePicker(column: Binding<WorkspaceTableColumn>) -> some View {
        let names = workspace.availableStatisticChannelNames(for: column.wrappedValue.sourceSelection)
        return Picker("", selection: Binding<String>(
            get: { column.wrappedValue.keyword.parameterName ?? names.first ?? "" },
            set: { column.wrappedValue.keyword.parameterName = $0.isEmpty ? nil : $0 }
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
                statistic: .frequencyOfParent,
                channelName: workspace.availableStatisticChannelNames(for: selection).first
            )
        )
        status = "Added \(path.last ?? "population")."
    }

    private func addKeywordColumn() {
        columns.append(
            WorkspaceTableColumn(
                columnType: .keyword,
                sourceSelection: workspace.selected,
                gatePath: [],
                name: "Keyword",
                keyword: KeywordColumnSpec(key: "$FIL")
            )
        )
        status = "Added a keyword column."
    }

    private func addFormulaColumn() {
        columns.append(
            WorkspaceTableColumn(
                columnType: .formula,
                sourceSelection: workspace.selected,
                gatePath: [],
                name: "Formula",
                formula: FormulaColumnSpec(expression: "")
            )
        )
        status = "Added a formula column."
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
    case text = "TSV"
    case csv = "CSV"
    case html = "HTML"
    case sql = "SQL"
    case excelXML = "Excel XML"

    var id: String { rawValue }

    var pathExtension: String {
        switch self {
        case .text: return "txt"
        case .csv: return "csv"
        case .html: return "html"
        case .sql: return "sql"
        case .excelXML: return "xml"
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
        case .sql:
            return [UTType(filenameExtension: "sql") ?? .plainText]
        case .excelXML:
            return [.xml]
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
        case .sql:
            return sql(output)
        case .excelXML:
            return excelXML(output)
        }
    }

    private func delimited(_ output: WorkspaceTableOutput, separator: String) -> String {
        let visible = visibleColumnIndices(output)
        let header = ["Sample"] + visible.map { output.columns[$0].name }
        let lines = output.rows.map { row in
            ([row.sampleName] + visible.map { index in
                row.values.indices.contains(index) ? row.values[index].displayString : ""
            })
            .map { escapeDelimited($0, separator: separator) }
            .joined(separator: separator)
        }
        return ([header.map { escapeDelimited($0, separator: separator) }.joined(separator: separator)] + lines)
            .joined(separator: "\n")
    }

    private func html(_ output: WorkspaceTableOutput) -> String {
        let ranges = heatMapRanges(for: output)
        let visible = visibleColumnIndices(output)
        let headerCells = visible.map { "<th>\(escapeHTML(output.columns[$0].name))</th>" }.joined()
        let bodyRows = output.rows.map { row in
            let valueCells = visible.map { index -> String in
                let value = row.values.indices.contains(index) ? row.values[index] : .missing
                let text = value.displayString
                let style = heatMapStyle(value: value.number, range: ranges[index], enabled: output.columns[index].heatMapped)
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

    private func sql(_ output: WorkspaceTableOutput) -> String {
        let visible = visibleColumnIndices(output)
        let columnNames = visible.map { sqlIdentifier(output.columns[$0].name) }
        let definitions = (["sample_name TEXT"] + columnNames.map { "\($0) TEXT" }).joined(separator: ", ")
        let inserts = output.rows.map { row in
            let values = [row.sampleName] + visible.map { index in
                row.values.indices.contains(index) ? row.values[index].displayString : ""
            }
            return "INSERT INTO openflo_table VALUES (\(values.map(sqlLiteral).joined(separator: ", ")));"
        }
        return (["CREATE TABLE openflo_table (\(definitions));"] + inserts).joined(separator: "\n")
    }

    private func excelXML(_ output: WorkspaceTableOutput) -> String {
        let visible = visibleColumnIndices(output)
        let headerCells = (["Sample"] + visible.map { output.columns[$0].name }).map(excelCell).joined()
        let rows = output.rows.map { row in
            let values = [row.sampleName] + visible.map { index in
                row.values.indices.contains(index) ? row.values[index].displayString : ""
            }
            return "<Row>\(values.map(excelCell).joined())</Row>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
          xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="OpenFlo Table">
        <Table>
        <Row>\(headerCells)</Row>
        \(rows)
        </Table>
        </Worksheet>
        </Workbook>
        """
    }
}

private struct TableOutputView: View {
    let output: WorkspaceTableOutput

    var body: some View {
        let ranges = heatMapRanges(for: output)
        let visible = visibleColumnIndices(output)
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    headerCell("Sample", alignment: .leading)
                    ForEach(visible, id: \.self) { index in
                        headerCell(output.columns[index].name)
                    }
                }

                ForEach(output.rows) { row in
                    GridRow {
                        bodyCell(row.sampleName, alignment: .leading)
                        ForEach(visible, id: \.self) { index in
                            let value = row.values.indices.contains(index) ? row.values[index] : .missing
                            bodyCell(
                                value.displayString,
                                fill: heatMapColor(value: value.number, range: ranges[index], enabled: output.columns[index].heatMapped)
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
            row.values.indices.contains(index) ? row.values[index].number : nil
        }
        guard let minimum = values.min(), let maximum = values.max(), minimum < maximum else { return nil }
        return minimum...maximum
    }
}

private func visibleColumnIndices(_ output: WorkspaceTableOutput) -> [Int] {
    output.columns.indices.filter { output.columns[$0].showValues }
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
    formatReportNumber(value)
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

private func sqlIdentifier(_ value: String) -> String {
    let cleaned = value
        .lowercased()
        .map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
    let identifier = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return identifier.isEmpty ? "column" : identifier
}

private func sqlLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

private func excelCell(_ value: String) -> String {
    "<Cell><Data ss:Type=\"String\">\(escapeHTML(value))</Data></Cell>"
}
