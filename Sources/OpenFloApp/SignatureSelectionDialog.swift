import AppKit
import OpenFloCore
import SwiftUI
import UniformTypeIdentifiers

struct SignatureSelectionSource {
    let name: String
    let signatures: [SeqtometrySignature]
    let isSelectedByDefault: Bool
}

struct SignatureSelectionResult {
    let signatures: [SeqtometrySignature]
    let sourceName: String?
    let addedSignatures: [SeqtometrySignature]
}

@MainActor
enum SignatureSelectionDialog {
    static func present(
        matrixURLs: [URL],
        sources: [SignatureSelectionSource]
    ) -> SignatureSelectionResult? {
        let state = SignatureSelectionState(sources: sources)
        let view = SignatureSelectionDialogView(state: state, matrixURLs: matrixURLs)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Score Single-Cell Matrix"
        alert.informativeText = matrixURLs.count == 1
            ? "Choose signatures for \(matrixURLs[0].lastPathComponent)."
            : "Choose signatures for \(matrixURLs.count) single-cell matrices."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Import Without Scoring")
        alert.addButton(withTitle: "Cancel")

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 440)
        alert.accessoryView = hostingView

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return SignatureSelectionResult(
                signatures: state.selectedSignatures,
                sourceName: state.selectedSourceSummary,
                addedSignatures: state.addedSignatures
            )
        case .alertSecondButtonReturn:
            return SignatureSelectionResult(signatures: [], sourceName: nil, addedSignatures: state.addedSignatures)
        default:
            return nil
        }
    }
}

@MainActor
private final class SignatureSelectionState: ObservableObject {
    @Published var rows: [SignatureSelectionRow]
    @Published var status: String

    init(sources: [SignatureSelectionSource]) {
        var seen: Set<String> = []
        var initialRows: [SignatureSelectionRow] = []
        for source in sources {
            for signature in source.signatures {
                let key = Self.normalizedName(signature.name)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                initialRows.append(
                    SignatureSelectionRow(
                        sourceName: source.name,
                        signature: signature,
                        isSelected: source.isSelectedByDefault,
                        isUserAdded: false
                    )
                )
            }
        }
        rows = initialRows
        status = "\(initialRows.count) available signature\(initialRows.count == 1 ? "" : "s")."
    }

    var selectedSignatures: [SeqtometrySignature] {
        deduplicated(rows.filter(\.isSelected).map(\.signature))
    }

    var addedSignatures: [SeqtometrySignature] {
        deduplicated(rows.filter(\.isUserAdded).map(\.signature))
    }

    var selectedSourceSummary: String? {
        let selectedRows = rows.filter(\.isSelected)
        guard !selectedRows.isEmpty else { return nil }
        let sources = Array(Set(selectedRows.map(\.sourceName))).sorted()
        if sources.count == 1 {
            return sources[0]
        }
        return "\(sources.count) signature sources"
    }

    func selectAll() {
        for index in rows.indices {
            rows[index].isSelected = true
        }
    }

    func clearSelection() {
        for index in rows.indices {
            rows[index].isSelected = false
        }
    }

    func addSignatureFile() {
        let panel = NSOpenPanel()
        panel.title = "Add Signature File"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["tsv", "csv", "txt", "gmt"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }

        var addedCount = 0
        var failed: [String] = []
        for url in panel.urls {
            do {
                let signatures = try SeqtometrySignatureParser.load(url: url)
                append(signatures, sourceName: url.lastPathComponent, isUserAdded: true)
                addedCount += signatures.count
            } catch {
                failed.append(url.lastPathComponent)
            }
        }

        if failed.isEmpty {
            status = "Added \(addedCount) signature\(addedCount == 1 ? "" : "s") from file."
        } else {
            status = "Added \(addedCount); could not read \(failed.joined(separator: ", "))."
        }
    }

    func addCustomSignatures() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Custom Signatures"
        alert.informativeText = "Paste rows such as: name<TAB>gene1,gene2,gene3."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let signatures = try SeqtometrySignatureParser.parse(text: textView.string, filename: "custom.tsv")
            append(signatures, sourceName: "Custom signatures", isUserAdded: true)
            status = "Added \(signatures.count) custom signature\(signatures.count == 1 ? "" : "s")."
        } catch {
            status = "Could not parse custom signatures: \(error.localizedDescription)"
        }
    }

    private func append(_ signatures: [SeqtometrySignature], sourceName: String, isUserAdded: Bool) {
        var existingNames = Set(rows.map { Self.normalizedName($0.signature.name) })
        let newRows = signatures.compactMap { signature -> SignatureSelectionRow? in
            let key = Self.normalizedName(signature.name)
            guard !existingNames.contains(key) else { return nil }
            existingNames.insert(key)
            return SignatureSelectionRow(
                sourceName: sourceName,
                signature: signature,
                isSelected: true,
                isUserAdded: isUserAdded
            )
        }
        rows.append(contentsOf: newRows)
    }

    private func deduplicated(_ signatures: [SeqtometrySignature]) -> [SeqtometrySignature] {
        var seen: Set<String> = []
        var output: [SeqtometrySignature] = []
        for signature in signatures {
            let key = Self.normalizedName(signature.name)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(signature)
        }
        return output
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private struct SignatureSelectionRow: Identifiable {
    let id = UUID()
    let sourceName: String
    let signature: SeqtometrySignature
    var isSelected: Bool
    let isUserAdded: Bool
}

private struct SignatureSelectionDialogView: View {
    @ObservedObject var state: SignatureSelectionState
    let matrixURLs: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Select All") {
                    state.selectAll()
                }
                Button("Clear") {
                    state.clearSelection()
                }
                Spacer()
                Button {
                    state.addSignatureFile()
                } label: {
                    Label("Add File...", systemImage: "folder.badge.plus")
                }
                Button {
                    state.addCustomSignatures()
                } label: {
                    Label("Custom...", systemImage: "square.and.pencil")
                }
            }

            GroupBox {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach($state.rows) { $row in
                            Toggle(isOn: $row.isSelected) {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.signature.name)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(row.sourceName) • \(row.signature.genes.count) genes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 300)
            }

            HStack {
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(state.selectedSignatures.count) selected")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
        }
        .padding(4)
        .frame(width: 620, height: 440)
    }
}
