import Foundation

public struct EventMask: Equatable, Sendable {
    public let count: Int
    public private(set) var words: [UInt64]

    public init(count: Int, fill: Bool = false) {
        precondition(count >= 0, "Mask count cannot be negative")
        self.count = count
        let wordCount = (count + 63) / 64
        self.words = Array(repeating: fill ? UInt64.max : 0, count: wordCount)
        if fill {
            clearUnusedBits()
        }
    }

    public init(count: Int, words: [UInt64]) {
        precondition(count >= 0, "Mask count cannot be negative")
        precondition(words.count == (count + 63) / 64, "Word count does not match event count")
        self.count = count
        self.words = words
        clearUnusedBits()
    }

    public subscript(index: Int) -> Bool {
        get {
            precondition(index >= 0 && index < count, "Mask index out of bounds")
            return (words[index >> 6] & (UInt64(1) << UInt64(index & 63))) != 0
        }
        set {
            precondition(index >= 0 && index < count, "Mask index out of bounds")
            let wordIndex = index >> 6
            let bit = UInt64(1) << UInt64(index & 63)
            if newValue {
                words[wordIndex] |= bit
            } else {
                words[wordIndex] &= ~bit
            }
        }
    }

    public var selectedCount: Int {
        words.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    public func intersection(_ other: EventMask) -> EventMask {
        precondition(count == other.count, "Masks must have the same event count")
        let combined = zip(words, other.words).map { $0 & $1 }
        return EventMask(count: count, words: combined)
    }

    public func union(_ other: EventMask) -> EventMask {
        precondition(count == other.count, "Masks must have the same event count")
        let combined = zip(words, other.words).map { $0 | $1 }
        return EventMask(count: count, words: combined)
    }

    public func subtracting(_ other: EventMask) -> EventMask {
        precondition(count == other.count, "Masks must have the same event count")
        let combined = zip(words, other.words).map { $0 & ~$1 }
        return EventMask(count: count, words: combined)
    }

    private mutating func clearUnusedBits() {
        guard count > 0, let lastIndex = words.indices.last else { return }
        let usedBits = count & 63
        guard usedBits != 0 else { return }
        let mask = (UInt64(1) << UInt64(usedBits)) - 1
        words[lastIndex] &= mask
    }
}
