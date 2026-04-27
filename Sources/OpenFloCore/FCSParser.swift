import Foundation

public enum FCSParserError: Error, LocalizedError, Sendable {
    case fileTooSmall
    case invalidHeader
    case invalidTextSegment
    case unsupportedDataType(String)
    case unsupportedByteOrder(String)
    case unsupportedIntegerWidth(Int)
    case missingKeyword(String)
    case malformedData

    public var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "The file is too small to be an FCS file."
        case .invalidHeader:
            return "The FCS header is invalid."
        case .invalidTextSegment:
            return "The FCS text segment is invalid."
        case .unsupportedDataType(let type):
            return "Unsupported FCS data type: \(type)."
        case .unsupportedByteOrder(let byteOrder):
            return "Unsupported FCS byte order: \(byteOrder)."
        case .unsupportedIntegerWidth(let width):
            return "Unsupported FCS integer width: \(width)."
        case .missingKeyword(let keyword):
            return "The FCS file is missing required keyword \(keyword)."
        case .malformedData:
            return "The FCS data segment is malformed."
        }
    }
}

public struct FCSMetadata: Equatable, Sendable {
    public let version: String
    public let keywords: [String: String]
}

public struct FCSFile: Sendable {
    public let metadata: FCSMetadata
    public let table: EventTable
}

public enum FCSParser {
    public static func load(url: URL) throws -> FCSFile {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> FCSFile {
        guard data.count >= 58 else { throw FCSParserError.fileTooSmall }

        let version = try ascii(data, 0..<6).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("FCS") else { throw FCSParserError.invalidHeader }

        let textStart = try headerInteger(data, 10..<18)
        let textEnd = try headerInteger(data, 18..<26)
        let dataStartHeader = try headerInteger(data, 26..<34)
        let dataEndHeader = try headerInteger(data, 34..<42)
        guard textStart >= 0, textEnd >= textStart, textEnd < data.count else {
            throw FCSParserError.invalidHeader
        }

        let textData = data[textStart...textEnd]
        var keywords = try parseTextSegment(Data(textData))
        keywords = Dictionary(uniqueKeysWithValues: keywords.map { ($0.key.uppercased(), $0.value) })

        let parameterCount = try requiredInt("$PAR", keywords)
        let eventCount = try requiredInt("$TOT", keywords)
        let dataType = try required("$DATATYPE", keywords).uppercased()
        let byteOrder = keywords["$BYTEORD"] ?? "1,2,3,4"
        let littleEndian = try isLittleEndian(byteOrder)
        let dataStart = optionalInt(keywords["$BEGINDATA"]).flatMap { $0 > 0 ? $0 : nil } ?? dataStartHeader
        let dataEnd = optionalInt(keywords["$ENDDATA"]).flatMap { $0 > 0 ? $0 : nil } ?? dataEndHeader
        guard dataStart >= 0, dataEnd >= dataStart, dataEnd < data.count else {
            throw FCSParserError.invalidHeader
        }

        let channels = (1...parameterCount).map { index in
            let name = keywords["$P\(index)N"] ?? "P\(index)"
            let marker = normalizedOptional(keywords["$P\(index)S"])
            let fluorochrome = fluorochromeName(from: name, markerName: marker)
            let bitWidth = optionalInt(keywords["$P\(index)B"])
            return Channel(name: name, bitWidth: bitWidth, markerName: marker, fluorochromeName: fluorochrome)
        }

        let segment = data[dataStart...dataEnd]
        let columns: [[Float]]
        switch dataType {
        case "F":
            columns = try parseFloats(segment: segment, eventCount: eventCount, parameterCount: parameterCount, littleEndian: littleEndian)
        case "D":
            columns = try parseDoubles(segment: segment, eventCount: eventCount, parameterCount: parameterCount, littleEndian: littleEndian)
        case "I":
            let widths = try (1...parameterCount).map { index -> Int in
                guard let width = optionalInt(keywords["$P\(index)B"]) else {
                    throw FCSParserError.missingKeyword("$P\(index)B")
                }
                return width
            }
            columns = try parseIntegers(segment: segment, eventCount: eventCount, widths: widths, littleEndian: littleEndian)
        default:
            throw FCSParserError.unsupportedDataType(dataType)
        }

        let table = EventTable(channels: channels, columns: columns)
        return FCSFile(metadata: FCSMetadata(version: version, keywords: keywords), table: table)
    }

    public static func parseTextSegment(_ data: Data) throws -> [String: String] {
        guard let delimiter = data.first else { throw FCSParserError.invalidTextSegment }
        var tokens: [String] = []
        var current = Data()
        var index = data.index(after: data.startIndex)

        while index < data.endIndex {
            let byte = data[index]
            if byte == delimiter {
                let next = data.index(after: index)
                if next < data.endIndex, data[next] == delimiter {
                    current.append(delimiter)
                    index = data.index(after: next)
                } else {
                    tokens.append(String(decoding: current, as: UTF8.self))
                    current.removeAll(keepingCapacity: true)
                    index = next
                }
            } else {
                current.append(byte)
                index = data.index(after: index)
            }
        }

        if !current.isEmpty {
            tokens.append(String(decoding: current, as: UTF8.self))
        }

        var result: [String: String] = [:]
        var tokenIndex = 0
        while tokenIndex + 1 < tokens.count {
            let key = tokens[tokenIndex].uppercased()
            let value = tokens[tokenIndex + 1]
            if !key.isEmpty {
                result[key] = value
            }
            tokenIndex += 2
        }
        return result
    }

    private static func parseFloats(segment: Data.SubSequence, eventCount: Int, parameterCount: Int, littleEndian: Bool) throws -> [[Float]] {
        let expected = eventCount * parameterCount * MemoryLayout<UInt32>.size
        guard segment.count >= expected else { throw FCSParserError.malformedData }
        var columns = Array(repeating: Array(repeating: Float(0), count: eventCount), count: parameterCount)
        var offset = segment.startIndex

        for event in 0..<eventCount {
            for parameter in 0..<parameterCount {
                let bits = readUInt32(segment, at: offset, littleEndian: littleEndian)
                columns[parameter][event] = Float(bitPattern: bits)
                offset += 4
            }
        }
        return columns
    }

    private static func parseDoubles(segment: Data.SubSequence, eventCount: Int, parameterCount: Int, littleEndian: Bool) throws -> [[Float]] {
        let expected = eventCount * parameterCount * MemoryLayout<UInt64>.size
        guard segment.count >= expected else { throw FCSParserError.malformedData }
        var columns = Array(repeating: Array(repeating: Float(0), count: eventCount), count: parameterCount)
        var offset = segment.startIndex

        for event in 0..<eventCount {
            for parameter in 0..<parameterCount {
                let bits = readUInt64(segment, at: offset, littleEndian: littleEndian)
                columns[parameter][event] = Float(Double(bitPattern: bits))
                offset += 8
            }
        }
        return columns
    }

    private static func parseIntegers(segment: Data.SubSequence, eventCount: Int, widths: [Int], littleEndian: Bool) throws -> [[Float]] {
        var columns = Array(repeating: Array(repeating: Float(0), count: eventCount), count: widths.count)
        var offset = segment.startIndex

        for event in 0..<eventCount {
            for parameter in widths.indices {
                switch widths[parameter] {
                case 8:
                    guard offset < segment.endIndex else { throw FCSParserError.malformedData }
                    columns[parameter][event] = Float(segment[offset])
                    offset += 1
                case 16:
                    guard offset + 1 < segment.endIndex else { throw FCSParserError.malformedData }
                    columns[parameter][event] = Float(readUInt16(segment, at: offset, littleEndian: littleEndian))
                    offset += 2
                case 32:
                    guard offset + 3 < segment.endIndex else { throw FCSParserError.malformedData }
                    columns[parameter][event] = Float(readUInt32(segment, at: offset, littleEndian: littleEndian))
                    offset += 4
                default:
                    throw FCSParserError.unsupportedIntegerWidth(widths[parameter])
                }
            }
        }
        return columns
    }

    private static func required(_ key: String, _ keywords: [String: String]) throws -> String {
        guard let value = keywords[key] else { throw FCSParserError.missingKeyword(key) }
        return value
    }

    private static func isLittleEndian(_ byteOrder: String) throws -> Bool {
        let normalized = byteOrder.replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "1,2,3,4", "1,2":
            return true
        case "4,3,2,1", "2,1":
            return false
        default:
            throw FCSParserError.unsupportedByteOrder(byteOrder)
        }
    }

    private static func requiredInt(_ key: String, _ keywords: [String: String]) throws -> Int {
        guard let value = optionalInt(try required(key, keywords)) else {
            throw FCSParserError.missingKeyword(key)
        }
        return value
    }

    private static func optionalInt(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fluorochromeName(from channelName: String, markerName: String?) -> String? {
        guard markerName != nil else { return nil }
        let detector = detectorName(from: channelName)
        let upper = detector.uppercased()
        guard !upper.isEmpty, !upper.hasPrefix("FSC"), !upper.hasPrefix("SSC"), upper != "TIME" else {
            return nil
        }
        return canonicalFluorochromeName(detector)
    }

    private static func detectorName(from channelName: String) -> String {
        let trimmed = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        for suffix in ["-A", "-H", "-W"] where upper.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func canonicalFluorochromeName(_ name: String) -> String {
        let collapsed = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let upper = collapsed.uppercased()
        if upper.hasPrefix("ALEXA FLUOR ") {
            let number = collapsed.dropFirst("Alexa Fluor ".count).filter { $0.isNumber }
            if !number.isEmpty {
                return "AF\(number)"
            }
        }
        if upper.hasPrefix("ALEXAFLUOR ") {
            let number = collapsed.dropFirst("AlexaFluor ".count).filter { $0.isNumber }
            if !number.isEmpty {
                return "AF\(number)"
            }
        }
        return collapsed
    }

    private static func headerInteger(_ data: Data, _ range: Range<Int>) throws -> Int {
        let text = try ascii(data, range).trimmingCharacters(in: .whitespaces)
        return Int(text) ?? 0
    }

    private static func ascii(_ data: Data, _ range: Range<Int>) throws -> String {
        guard range.lowerBound >= 0, range.upperBound <= data.count else {
            throw FCSParserError.invalidHeader
        }
        return String(decoding: data[range], as: UTF8.self)
    }

    private static func readUInt16(_ data: Data.SubSequence, at offset: Data.Index, littleEndian: Bool) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1)
    }

    private static func readUInt32(_ data: Data.SubSequence, at offset: Data.Index, littleEndian: Bool) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        if littleEndian {
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private static func readUInt64(_ data: Data.SubSequence, at offset: Data.Index, littleEndian: Bool) -> UInt64 {
        var value = UInt64(0)
        if littleEndian {
            for shift in 0..<8 {
                value |= UInt64(data[offset + shift]) << UInt64(shift * 8)
            }
        } else {
            for shift in 0..<8 {
                value = (value << 8) | UInt64(data[offset + shift])
            }
        }
        return value
    }
}
