import Foundation

enum DelimitedTextError: Error, LocalizedError, Sendable {
    case unterminatedQuote

    var errorDescription: String? {
        switch self {
        case .unterminatedQuote:
            return "Delimited text has an unterminated quoted field."
        }
    }
}

enum DelimitedText {
    static func detectDelimiter(in text: String, preferred: Character? = nil) -> Character {
        if let preferred {
            return preferred
        }

        let sampleLines = text
            .split(whereSeparator: \.isNewline)
            .prefix(20)
            .map(String.init)
        let candidates: [Character] = ["\t", ",", ";"]
        let scores = candidates.map { delimiter in
            sampleLines.reduce(0) { count, line in
                count + line.filter { $0 == delimiter }.count
            }
        }
        guard let bestIndex = scores.indices.max(by: { scores[$0] < scores[$1] }),
              scores[bestIndex] > 0 else {
            return "\t"
        }
        return candidates[bestIndex]
    }

    static func parseRows(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if isQuoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            isQuoted = false
                            consume(next, delimiter: delimiter, rows: &rows, row: &row, field: &field, isQuoted: &isQuoted)
                        }
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                consume(character, delimiter: delimiter, rows: &rows, row: &row, field: &field, isQuoted: &isQuoted)
            }
        }

        guard !isQuoted else { throw DelimitedTextError.unterminatedQuote }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            append(row: row, to: &rows)
        }
        return rows
    }

    private static func consume(
        _ character: Character,
        delimiter: Character,
        rows: inout [[String]],
        row: inout [String],
        field: inout String,
        isQuoted: inout Bool
    ) {
        if character == "\"" && field.isEmpty {
            isQuoted = true
        } else if character == delimiter {
            row.append(field)
            field.removeAll(keepingCapacity: true)
        } else if character == "\n" {
            row.append(field)
            append(row: row, to: &rows)
            row.removeAll(keepingCapacity: true)
            field.removeAll(keepingCapacity: true)
        } else if character != "\r" {
            field.append(character)
        }
    }

    private static func append(row: [String], to rows: inout [[String]]) {
        guard row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return
        }
        rows.append(row)
    }
}
