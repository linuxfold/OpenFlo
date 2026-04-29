import Foundation

public struct SeqtometrySignature: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let genes: [String]

    public init(name: String, genes: [String]) {
        self.name = name
        self.genes = genes
    }
}

public enum SeqtometrySignatureError: Error, LocalizedError, Sendable {
    case noSignatures

    public var errorDescription: String? {
        switch self {
        case .noSignatures:
            return "No Seqtometry signatures were found."
        }
    }
}

public enum SeqtometrySignatureParser {
    public static func load(url: URL) throws -> [SeqtometrySignature] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text: text, filename: url.lastPathComponent)
    }

    public static func isLikelySignatureFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "gmt" {
            return true
        }
        guard ["csv", "tsv", "txt"].contains(ext),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4096)
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let delimiter = DelimitedText.detectDelimiter(in: firstLine, preferred: ext == "csv" ? "," : nil)
        guard let row = try? DelimitedText.parseRows(firstLine, delimiter: delimiter).first else { return false }
        let normalized = row.map { normalizeHeader($0) }
        return normalized.count >= 2
            && normalized[0] == "name"
            && ["value", "genes", "gene", "signature"].contains(normalized[1])
    }

    public static func parse(text: String, filename: String = "signatures") throws -> [SeqtometrySignature] {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let delimiter = DelimitedText.detectDelimiter(in: text, preferred: ext == "csv" ? "," : nil)
        let rows = try DelimitedText.parseRows(text, delimiter: delimiter)
        let signatures = parse(rows: rows, isGMT: ext == "gmt")
        guard !signatures.isEmpty else { throw SeqtometrySignatureError.noSignatures }
        return signatures
    }

    private static func parse(rows: [[String]], isGMT: Bool) -> [SeqtometrySignature] {
        guard !rows.isEmpty else { return [] }

        let header = rows[0].map { normalizeHeader($0) }
        let hasNameValueHeader = header.count >= 2
            && header[0] == "name"
            && ["value", "genes", "gene", "signature"].contains(header[1])
        let dataRows = hasNameValueHeader ? rows.dropFirst() : rows[...]

        return dataRows.compactMap { row in
            guard let rawName = row.first else { return nil }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            let geneFields: ArraySlice<String>
            if isGMT, row.count > 2 {
                geneFields = row.dropFirst(2)
            } else {
                geneFields = row.dropFirst()
            }
            let genes = splitGeneFields(geneFields)
            guard !genes.isEmpty else { return nil }
            return SeqtometrySignature(name: name, genes: genes)
        }
    }

    private static func splitGeneFields(_ fields: ArraySlice<String>) -> [String] {
        fields.flatMap { field in
            field
                .split { character in
                    character == "," || character == ";" || character.isWhitespace
                }
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
