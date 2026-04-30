import Foundation

public struct CompensationMatrix: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var parameters: [String]
    public var percent: [[Double]]
    public var source: CompensationSource
    public var colorHex: String?
    public var locked: Bool
    public var originalMatrixID: UUID?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        parameters: [String],
        percent: [[Double]],
        source: CompensationSource,
        colorHex: String? = nil,
        locked: Bool = false,
        originalMatrixID: UUID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.percent = percent
        self.source = source
        self.colorHex = colorHex
        self.locked = locked
        self.originalMatrixID = originalMatrixID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public static func identity(
        name: String,
        parameters: [String],
        source: CompensationSource = .manualIdentity,
        colorHex: String? = nil
    ) -> CompensationMatrix {
        let count = parameters.count
        let percent = (0..<count).map { row in
            (0..<count).map { column in row == column ? 100.0 : 0.0 }
        }
        return CompensationMatrix(
            name: name,
            parameters: parameters,
            percent: percent,
            source: source,
            colorHex: colorHex,
            locked: false
        )
    }
}

public enum CompensationSource: Codable, Equatable, Sendable {
    case acquisition(keyword: String)
    case acquisitionCopy
    case manualIdentity
    case manualImported
    case singleStainControls
}
