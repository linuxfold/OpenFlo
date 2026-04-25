import Foundation
import AppKit
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = WorkspaceModel()
    @State private var selectedRowID: String?
    @State private var editingRowID: String?
    @State private var editName = ""

    var body: some View {
        VStack(spacing: 0) {
            ribbon
            workspacePane
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedRowID = workspace.selected.map { workspace.rowID(sampleID: $0.sampleID, gateID: $0.gateID) }
        }
        .onChange(of: selectedRowID) {
            guard let selectedRowID, let row = workspace.rows.first(where: { $0.id == selectedRowID }) else { return }
            workspace.selected = row.selection
        }
        .onChange(of: workspace.selected) {
            selectedRowID = workspace.selected.map { workspace.rowID(sampleID: $0.sampleID, gateID: $0.gateID) }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
    }

    private var ribbon: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Label("OpenFlo", systemImage: "triangle.lefthalf.filled")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.teal)

                Divider()
                    .frame(height: 34)

                Button {
                    workspace.openFCSPanel()
                } label: {
                    Label("Add Samples", systemImage: "plus.rectangle.on.folder")
                }

                Menu {
                    Button("750,000 events") { workspace.addSynthetic(events: 750_000) }
                    Button("2,000,000 events") { workspace.addSynthetic(events: 2_000_000) }
                    Button("5,000,000 events") { workspace.addSynthetic(events: 5_000_000) }
                } label: {
                    Label("Synthetic", systemImage: "waveform.path.ecg")
                }

                Button {
                    beginRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .disabled(currentRow == nil)

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(currentRow == nil)

                Button {
                    workspace.applySelectedGateToAllSamples()
                } label: {
                    Label("Apply Gate to All", systemImage: "square.stack.3d.up")
                }

                Spacer()

                Text(workspace.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
        }
        .background(.regularMaterial)
    }

    private var workspacePane: some View {
        VStack(spacing: 0) {
            groupHeader
            Divider()
            tableHeader

            List(selection: $selectedRowID) {
                ForEach(workspace.rows) { row in
                    WorkspaceRowView(
                        row: row,
                        isEditing: editingRowID == row.id,
                        editName: $editName,
                        onCommitRename: {
                            workspace.rename(row.selection, to: editName)
                            editingRowID = nil
                        }
                    )
                    .tag(row.id)
                    .onTapGesture(count: 2) {
                        workspace.openPlotWindow(for: row.selection)
                    }
                    .contextMenu {
                        Button("Open") {
                            workspace.openPlotWindow(for: row.selection)
                        }
                        Button("Rename") {
                            beginRename(row: row)
                        }
                        Button(role: .destructive) {
                            workspace.delete(row.selection)
                        } label: {
                            Text("Delete")
                        }
                    }
                    .onDrag {
                        if let payload = workspace.dragPayload(for: row) {
                            return NSItemProvider(object: payload as NSString)
                        }
                        return NSItemProvider(object: "" as NSString)
                    }
                    .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                        handleGateDrop(providers, target: row.selection)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if workspace.rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Drop .fcs files here")
                            .font(.headline)
                        Text("or use Add Samples")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                handleFileDrop(providers)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var groupHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Group")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .frame(width: 64, alignment: .trailing)
                Text("Role")
                    .frame(width: 110, alignment: .trailing)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor))

            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.teal)
                Text("All Samples")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(workspace.samples.count)")
                    .frame(width: 64, alignment: .trailing)
                Text("Experiment")
                    .frame(width: 110, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Statistic")
                .frame(width: 100, alignment: .trailing)
            Text("#Cells")
                .frame(width: 96, alignment: .trailing)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var currentRow: WorkspaceRow? {
        guard let selectedRowID else { return nil }
        return workspace.rows.first { $0.id == selectedRowID }
    }

    private func beginRename() {
        guard let row = currentRow else { return }
        beginRename(row: row)
    }

    private func beginRename(row: WorkspaceRow) {
        selectedRowID = row.id
        editingRowID = row.id
        editName = row.name
    }

    private func deleteSelected() {
        guard let row = currentRow else { return }
        workspace.delete(row.selection)
        editingRowID = nil
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = droppedFileURL(from: item)
                if let url {
                    Task { @MainActor in
                        workspace.addFCSURLs([url])
                    }
                }
            }
        }
        return true
    }

    private func handleGateDrop(_ providers: [NSItemProvider], target: WorkspaceSelection) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let payload = (item as? String) ?? (item as? NSString).map(String.init)
                if let payload {
                    Task { @MainActor in
                        workspace.copyGate(dragPayload: payload, to: target)
                    }
                }
            }
        }
        return true
    }
}

private nonisolated func droppedFileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    if let string = item as? String {
        return URL(string: string)
    }
    if let string = item as? NSString {
        return URL(string: string as String)
    }
    return nil
}

private struct WorkspaceRowView: View {
    let row: WorkspaceRow
    let isEditing: Bool
    @Binding var editName: String
    let onCommitRename: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: CGFloat(row.depth) * 18)
                Image(systemName: row.isGate ? "skew" : "doc")
                    .foregroundStyle(row.isGate ? .orange : .blue)
                if isEditing {
                    TextField("Name", text: $editName)
                        .textFieldStyle(.plain)
                        .onSubmit(onCommitRename)
                } else {
                    Text(row.name)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.isGate ? "Count" : "Events")
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text(row.count.map { $0.formatted() } ?? "...")
                .frame(width: 96, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 2)
    }
}
