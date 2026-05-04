import Foundation
import AppKit
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = WorkspaceModel()
    @State private var selectedRowIDs: Set<String> = []
    @State private var focusedRowID: String?
    @State private var selectionAnchorRowID: String?
    @State private var editingRowID: String?
    @State private var editName = ""

    var body: some View {
        VStack(spacing: 0) {
            ribbon
            if let progress = workspace.progress {
                WorkspaceProgressBanner(progress: progress)
            }
            workspacePane
        }
        .frame(minWidth: 940, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncSelectionFromWorkspace()
        }
        .onChange(of: workspace.selected) {
            syncSelectionFromWorkspace()
        }
        .onChange(of: selectedRowIDs) {
            syncWorkspaceFromSelection()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
        .onDeleteCommand {
            deleteSelected()
        }
        .background(
            DeleteKeyMonitor {
                guard editingRowID == nil, currentRow != nil else { return false }
                deleteSelected()
                return true
            }
        )
    }

    private var ribbon: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Label("OpenFlo", systemImage: "triangle.lefthalf.filled")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 84, alignment: .leading)
                    .padding(.top, 4)

                Divider()
                    .frame(height: 156)

                navigateRibbonGroup

                Divider()
                    .frame(height: 156)

                toolsRibbonGroup

                Divider()
                    .frame(height: 156)

                editRibbonGroup

                Spacer()

                Text(workspace.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
        }
        .background(.regularMaterial)
    }

    private var navigateRibbonGroup: some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    WorkspaceRibbonButton(title: "New", systemImage: "doc.badge.plus", width: 142) {
                        OpenFloWindowManager.shared.openWorkspaceWindow()
                    }

                    WorkspaceRibbonButton(title: "Open...", systemImage: "folder", width: 142) {
                        workspace.openWorkspacePanel()
                    }

                    WorkspaceRibbonButton(title: "Save...", systemImage: "square.and.arrow.down", width: 142) {
                        workspace.saveWorkspacePanel()
                    }
                }

                HStack(spacing: 0) {
                    WorkspaceRibbonMenuButton(title: "Add Samples...", systemImage: "testtube.2") {
                        Button("FCS Files...") {
                            workspace.openFCSPanel()
                        }
                        Button("Single Cell Matrix...") {
                            workspace.openSingleCellPanel()
                        }
                        Button("Seqtometry Signature...") {
                            workspace.openSignaturePanel()
                        }
                        Divider()
                        Button("PBMC3k Seqtometry Demo") {
                            workspace.downloadSeqtometryDemo()
                        }
                    }

                    WorkspaceRibbonButton(title: "Layout Editor", systemImage: "ruler") {
                        workspace.openLayoutEditor()
                    }
                }

                HStack(spacing: 0) {
                    WorkspaceRibbonButton(title: "Table Editor", systemImage: "tablecells", width: 142) {
                        workspace.openTableEditor()
                    }

                    WorkspaceRibbonButton(title: "Create Group...", systemImage: "curlybraces", width: 142) {
                        workspace.createGroup()
                    }
                }
            }

            Text("Navigate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 430)
    }

    private var toolsRibbonGroup: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                WorkspaceRibbonTallButton(
                    title: "Edit Compensation Matrix",
                    systemImage: "square.grid.3x3"
                ) {
                    openToolsCompensationEditor()
                }
                .disabled(!canEditCompensationMatrix)
            }

            Text("Tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 156)
    }

    private var editRibbonGroup: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                WorkspaceRibbonIconButton(title: "Rename", systemImage: "pencil") {
                    beginRename()
                }
                .disabled(currentRow == nil)

                WorkspaceRibbonIconButton(title: "Delete", systemImage: "trash") {
                    deleteSelected()
                }
                .disabled(currentRow == nil)
                .keyboardShortcut(.delete, modifiers: [])

                WorkspaceRibbonIconButton(title: "Apply Gate to All", systemImage: "square.stack.3d.up") {
                    workspace.applySelectedGateToAllSamples()
                }
            }

            Text("Edit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 140)
    }

    private var workspacePane: some View {
        VStack(spacing: 0) {
            groupHeader
            Divider()
            tableHeader

            List(selection: $selectedRowIDs) {
                ForEach(workspace.rows) { row in
                    WorkspaceRowView(
                        row: row,
                        isEditing: editingRowID == row.id,
                        editName: $editName,
                        onCommitRename: {
                            workspace.rename(row.selection, to: editName)
                            editingRowID = nil
                        },
                        onCompensationDoubleClick: {
                            workspace.openCompensationEditor(for: row.selection)
                        },
                        compensationDragProvider: {
                            compensationItemProvider(for: row)
                        }
                    )
                    .tag(row.id)
                    .contentShape(Rectangle())
                    .background(
                        RowClickMonitor { clickCount, modifiers in
                            handleRowMouseDown(row, clickCount: clickCount, modifiers: modifiers)
                        }
                    )
                    .contextMenu {
                        Button("Open") {
                            workspace.openPlotWindow(for: row.selection)
                        }
                        Button("Rename") {
                            beginRename(row: row)
                        }
                        Button(role: .destructive) {
                            delete(row: row)
                        } label: {
                            Text("Delete")
                        }
                        compensationContextMenuItems(for: row)
                    }
                    .onDrag {
                        if let payload = workspace.dragPayload(for: row, selectedRows: selectedRowsForDrag(startingAt: row)) {
                            return gateItemProvider(payload)
                        }
                        return NSItemProvider()
                    }
                    .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                        handleGateDrop(providers, target: row.selection)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if workspace.samples.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Drop .fcs or single-cell files here")
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
            .contentShape(Rectangle())
            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                handleGateDrop(providers, target: .allSamples)
            }

            ForEach(workspace.groupRows) { row in
                WorkspaceRowView(
                    row: row,
                    isEditing: editingRowID == row.id,
                    editName: $editName,
                    onCommitRename: {
                        workspace.rename(row.selection, to: editName)
                        editingRowID = nil
                    },
                    onCompensationDoubleClick: {
                        workspace.openCompensationEditor(for: row.selection)
                    },
                    compensationDragProvider: {
                        compensationItemProvider(for: row)
                    }
                )
                .contentShape(Rectangle())
                .background(
                    RowClickMonitor { clickCount, modifiers in
                        handleRowMouseDown(row, clickCount: clickCount, modifiers: modifiers)
                    }
                )
                .contextMenu {
                    Button("Rename") {
                        beginRename(row: row)
                    }
                    Button(role: .destructive) {
                        delete(row: row)
                    } label: {
                        Text("Delete")
                    }
                    compensationContextMenuItems(for: row)
                }
                .onDrag {
                    if let payload = workspace.dragPayload(for: row, selectedRows: selectedRowsForDrag(startingAt: row)) {
                        return gateItemProvider(payload)
                    }
                    return NSItemProvider()
                }
                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                    handleGateDrop(providers, target: row.selection)
                }
            }

            compensationGroupRow
        }
    }

    private var compensationGroupRow: some View {
        HStack {
            Image(systemName: "square.grid.3x3")
                .foregroundStyle(.gray)
                .frame(width: 18)
            Text("Compensation")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            Spacer()
            Text("\(workspace.compensationGroupSampleCount)")
                .frame(width: 64, alignment: .trailing)
            Text("Compensation")
                .frame(width: 110, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            workspace.openExistingCompensationForEditing(for: workspace.selected ?? .allSamples)
        }
        .contextMenu {
            Button("Edit Compensation Matrix") {
                workspace.openExistingCompensationForEditing(for: workspace.selected ?? .allSamples)
            }
            Button("Apply Selected Matrix to All Samples") {
                if let matrixID = workspace.compensationMatrices.first?.id {
                    workspace.assignCompensationToAllCompatible(matrixID)
                }
            }
            .disabled(workspace.compensationMatrices.isEmpty)
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handleGateDrop(providers, target: .allSamples)
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
        if let focusedRowID, selectedRowIDs.contains(focusedRowID), let row = workspace.rows.first(where: { $0.id == focusedRowID }) {
            return row
        }
        if let focusedRowID, selectedRowIDs.contains(focusedRowID), let row = workspace.groupRows.first(where: { $0.id == focusedRowID }) {
            return row
        }
        return allRows.first { selectedRowIDs.contains($0.id) }
    }

    private var canEditCompensationMatrix: Bool {
        workspace.canEditExistingCompensation(for: currentRow?.selection)
    }

    private var allRows: [WorkspaceRow] {
        workspace.groupRows + workspace.rows
    }

    private func beginRename() {
        guard let row = currentRow else { return }
        beginRename(row: row)
    }

    private func beginRename(row: WorkspaceRow) {
        selectOnly(row)
        editingRowID = row.id
        editName = row.name
    }

    private func deleteSelected() {
        let rows = selectedRowsForDeletion()
        guard !rows.isEmpty else { return }
        if rows.count == 1 {
            delete(row: rows[0])
            return
        }
        guard confirmDelete(rows: rows) else { return }
        for row in rows {
            workspace.delete(row.selection)
        }
        selectedRowIDs.removeAll()
        focusedRowID = nil
        selectionAnchorRowID = nil
        editingRowID = nil
    }

    private func delete(row: WorkspaceRow) {
        selectOnly(row)
        guard confirmDelete(row: row) else { return }
        workspace.delete(row.selection)
        editingRowID = nil
    }

    private func confirmDelete(row: WorkspaceRow) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = row.isGroupGate
            ? "Delete all-samples gate \"\(row.name)\"?"
            : row.isGate ? "Delete gate \"\(row.name)\"?" : "Delete sample \"\(row.name)\"?"
        alert.informativeText = row.isGroupGate
            ? "This will remove the gate template from All Samples."
            : row.isGate
                ? "This will remove the gate and any child gates from the workspace."
                : "This will remove the sample and any gates under it from the workspace."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmDelete(rows: [WorkspaceRow]) -> Bool {
        let sampleCount = rows.filter { !$0.isGate && !$0.isGroupGate }.count
        let gateCount = rows.filter(\.isGate).count
        let itemText = rows.count == 1 ? "item" : "items"
        let detailParts = [
            sampleCount > 0 ? "\(sampleCount) sample\(sampleCount == 1 ? "" : "s")" : nil,
            gateCount > 0 ? "\(gateCount) gate\(gateCount == 1 ? "" : "s")" : nil
        ].compactMap { $0 }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(rows.count) \(itemText)?"
        alert.informativeText = detailParts.isEmpty
            ? "This will remove the selected items from the workspace."
            : "This will remove \(detailParts.joined(separator: " and ")) from the workspace. Any child gates under selected items will also be removed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func selectedRowsForDeletion() -> [WorkspaceRow] {
        let rows = allRows.filter { selectedRowIDs.contains($0.id) }
        if !rows.isEmpty {
            return rows
        }
        return currentRow.map { [$0] } ?? []
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = droppedFileURL(from: item)
                if let url {
                    Task { @MainActor in
                        workspace.addDataURLs([url])
                    }
                }
            }
        }
        return true
    }

    private func syncSelectionFromWorkspace() {
        guard let selection = workspace.selected else {
            selectedRowIDs.removeAll()
            focusedRowID = nil
            selectionAnchorRowID = nil
            return
        }
        let rowID = workspace.rowID(sampleID: selection.sampleID, gateID: selection.gateID)
        guard !selectedRowIDs.contains(rowID) || focusedRowID != rowID else { return }
        selectedRowIDs = [rowID]
        focusedRowID = rowID
        selectionAnchorRowID = rowID
    }

    private func syncWorkspaceFromSelection() {
        guard !selectedRowIDs.isEmpty else {
            focusedRowID = nil
            workspace.selected = nil
            return
        }
        if let focusedRowID, selectedRowIDs.contains(focusedRowID), let row = allRows.first(where: { $0.id == focusedRowID }) {
            workspace.selected = row.selection
            return
        }
        guard let row = allRows.first(where: { selectedRowIDs.contains($0.id) }) else { return }
        focusedRowID = row.id
        selectionAnchorRowID = row.id
        workspace.selected = row.selection
    }

    private func selectRow(_ row: WorkspaceRow, modifiers: NSEvent.ModifierFlags? = nil) {
        let flags = modifiers?.intersection(.deviceIndependentFlagsMask)
            ?? NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask)
            ?? []
        if flags.contains(.command) {
            if selectedRowIDs.contains(row.id) {
                selectedRowIDs.remove(row.id)
                if focusedRowID == row.id {
                    focusedRowID = allRows.first { selectedRowIDs.contains($0.id) }?.id
                }
            } else {
                selectedRowIDs.insert(row.id)
                focusedRowID = row.id
            }
            selectionAnchorRowID = row.id
        } else if flags.contains(.shift), let anchor = selectionAnchorRowID {
            selectedRowIDs = rowIDsBetween(anchor, row.id)
            focusedRowID = row.id
        } else {
            selectedRowIDs = [row.id]
            focusedRowID = row.id
            selectionAnchorRowID = row.id
        }
        if let focusedRowID, let focusedRow = allRows.first(where: { $0.id == focusedRowID }) {
            workspace.selected = focusedRow.selection
        } else {
            workspace.selected = nil
        }
    }

    private func handleRowMouseDown(_ row: WorkspaceRow, clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        if clickCount >= 2 {
            selectOnly(row)
            workspace.openPlotWindow(for: row.selection)
            return
        }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if row.isGate,
           selectedRowIDs.count > 1,
           selectedRowIDs.contains(row.id),
           !flags.contains(.command),
           !flags.contains(.shift) {
            focusedRowID = row.id
            workspace.selected = row.selection
            return
        }
        selectRow(row, modifiers: modifiers)
    }

    private func selectOnly(_ row: WorkspaceRow) {
        selectedRowIDs = [row.id]
        focusedRowID = row.id
        selectionAnchorRowID = row.id
        workspace.selected = row.selection
    }

    private func rowIDsBetween(_ first: String, _ second: String) -> Set<String> {
        let rows = allRows
        guard let firstIndex = rows.firstIndex(where: { $0.id == first }),
              let secondIndex = rows.firstIndex(where: { $0.id == second }) else {
            return [second]
        }
        let range = min(firstIndex, secondIndex)...max(firstIndex, secondIndex)
        return Set(rows[range].map(\.id))
    }

    private func selectedRowsForDrag(startingAt row: WorkspaceRow) -> [WorkspaceRow] {
        let selectedRows = allRows.filter { selectedRowIDs.contains($0.id) && ($0.isGate || !$0.selection.isAllSamples) }
        if selectedRowIDs.contains(row.id), !selectedRows.isEmpty {
            return selectedRows
        }
        return row.isGate || !row.selection.isAllSamples ? [row] : []
    }

    private func openToolsCompensationEditor() {
        if let row = currentRow, !row.selection.isAllSamples {
            selectOnly(row)
            workspace.openExistingCompensationForEditing(for: row.selection)
        } else {
            workspace.openExistingCompensationForEditing(for: currentRow?.selection ?? workspace.selected ?? .allSamples)
        }
    }

    private func handleGateDrop(_ providers: [NSItemProvider], target: WorkspaceSelection) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let payload = gatePayload(from: item)
                if let payload {
                    Task { @MainActor in
                        workspace.copyGate(dragPayload: payload, to: target)
                    }
                }
            }
        }
        return true
    }

    private func compensationItemProvider(for row: WorkspaceRow) -> NSItemProvider {
        guard let matrixID = row.compensationBadge?.matrixID else { return NSItemProvider() }
        return gateItemProvider(workspace.compensationDragPayload(matrixID: matrixID))
    }

    @ViewBuilder
    private func compensationContextMenuItems(for row: WorkspaceRow) -> some View {
        if !row.isGate, !row.selection.isAllSamples {
            Divider()
            Button("View Matrix") {
                workspace.openCompensationEditor(for: row.selection)
            }
            .disabled(!workspace.hasCompensationMatrix(for: row.selection))

            Button("Edit Compensation Matrix") {
                workspace.editCompensationCopy(for: row.selection)
            }
            .disabled(!workspace.hasCompensationMatrix(for: row.selection))

            Button("Apply Acquisition Matrix") {
                workspace.applyAcquisitionCompensation(for: row.selection)
            }

            Button("Show Uncompensated") {
                do {
                    try workspace.assignCompensation(nil, to: row.selection.sampleID)
                } catch {
                    workspace.openCompensationEditor(for: row.selection)
                }
            }
        }
    }
}

private struct WorkspaceProgressBanner: View {
    let progress: WorkspaceProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.teal)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(progress.title)
                    .font(.callout.weight(.semibold))
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let fraction = progress.fraction {
                    ProgressView(value: fraction, total: 1)
                        .progressViewStyle(.linear)
                        .tint(.teal)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.teal)
                }
            }

            if let fraction = progress.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 72)
        .background(Color.teal.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.teal.opacity(0.22))
                .frame(height: 1)
        }
    }
}

private struct RowClickMonitor: NSViewRepresentable {
    var onMouseDown: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onMouseDown = onMouseDown
    }

    final class MonitorView: NSView {
        var onMouseDown: ((Int, NSEvent.ModifierFlags) -> Void)?
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
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    self.onMouseDown?(event.clickCount, event.modifierFlags)
                }
                return event
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

private struct DeleteKeyMonitor: NSViewRepresentable {
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

nonisolated func gateItemProvider(_ payload: String) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
        completion(Data(payload.utf8), nil)
        return nil
    }
    return provider
}

nonisolated func gatePayload(from item: NSSecureCoding?) -> String? {
    if let string = item as? String {
        return string
    }
    if let string = item as? NSString {
        return string as String
    }
    if let data = item as? Data {
        return String(data: data, encoding: .utf8)
    }
    return nil
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
    let onCompensationDoubleClick: () -> Void
    let compensationDragProvider: () -> NSItemProvider

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: CGFloat(row.depth) * 18)
                if let badge = row.compensationBadge {
                    CompensationBadgeView(badge: badge)
                        .onTapGesture(count: 2, perform: onCompensationDoubleClick)
                        .onDrag(compensationDragProvider)
                } else {
                    Color.clear
                        .frame(width: 16, height: 16)
                }
                Image(systemName: row.isGate ? "skew" : row.role == "Cells" ? "tablecells" : "doc")
                    .foregroundStyle(row.isGate ? .orange : .blue)
                if isEditing {
                    TextField("Name", text: $editName)
                        .textFieldStyle(.plain)
                        .onSubmit(onCommitRename)
                } else {
                    Text(row.name)
                        .lineLimit(1)
                        .fontWeight(row.isSynced ? .semibold : .regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.isGroupGate ? "Template" : row.isGate ? "Count" : row.role)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text(row.isGroupGate ? "" : row.count.map { $0.formatted() } ?? "...")
                .frame(width: 96, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct CompensationBadgeView: View {
    let badge: WorkspaceCompensationBadge

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 16, height: 16)
            .help(badge.tooltip)
            .accessibilityLabel(badge.tooltip)
    }

    private var symbolName: String {
        switch badge.style {
        case .assignedAcquisition, .assignedUser:
            return "square.grid.3x3.fill"
        case .available:
            return "square.grid.3x3"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var foreground: Color {
        switch badge.style {
        case .assignedAcquisition:
            return .gray
        case .assignedUser:
            return colorFromHex(badge.colorHex) ?? .teal
        case .available:
            return .secondary
        case .error:
            return .orange
        }
    }
}

func colorFromHex(_ hex: String?) -> Color? {
    guard let hex else { return nil }
    let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
    let red = Double((value >> 16) & 0xff) / 255.0
    let green = Double((value >> 8) & 0xff) / 255.0
    let blue = Double(value & 0xff) / 255.0
    return Color(red: red, green: green, blue: blue)
}

private struct WorkspaceRibbonButton: View {
    let title: String
    let systemImage: String
    var width: CGFloat = 214
    var height: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WorkspaceRibbonButtonLabel(
                title: title,
                systemImage: systemImage,
                width: width,
                height: height
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceRibbonMenuButton<Content: View>: View {
    let title: String
    let systemImage: String
    var width: CGFloat = 214
    var height: CGFloat = 42
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            WorkspaceRibbonButtonLabel(
                title: title,
                systemImage: systemImage,
                showsMenuIndicator: true,
                width: width,
                height: height
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceRibbonIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isEnabled ? Color.teal : Color.secondary)
                .frame(width: 40, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovering && isEnabled ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct WorkspaceRibbonTallButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.teal : Color.secondary)
                    .frame(height: 42)

                Text(title)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 144, height: 126)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering && isEnabled ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct WorkspaceRibbonButtonLabel: View {
    let title: String
    let systemImage: String
    var showsMenuIndicator = false
    let width: CGFloat
    let height: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(isEnabled ? Color.teal : Color.secondary)
                .frame(width: 24)

            Text(title)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)

            Spacer(minLength: 4)

            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering && isEnabled ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
