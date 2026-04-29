import Foundation

public struct PlotPoint: Codable, Equatable, Sendable {
    public let x: Float
    public let y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public enum GateKind: String, Codable, Equatable, Sendable {
    case polygon
    case rectangle
    case ellipse
    case xCutoff
    case quadrant
}

public struct PolygonGate: Codable, Equatable, Sendable {
    public let name: String
    public let vertices: [PlotPoint]
    public let kind: GateKind

    public init(name: String = "Polygon", vertices: [PlotPoint], kind: GateKind = .polygon) {
        precondition(vertices.count >= 3, "A polygon gate requires at least three vertices")
        self.name = name
        self.vertices = vertices
        self.kind = kind
    }

    public static func rectangle(name: String = "Rectangle", xRange: ClosedRange<Float>, yRange: ClosedRange<Float>) -> PolygonGate {
        PolygonGate(
            name: name,
            vertices: [
                PlotPoint(x: xRange.lowerBound, y: yRange.lowerBound),
                PlotPoint(x: xRange.upperBound, y: yRange.lowerBound),
                PlotPoint(x: xRange.upperBound, y: yRange.upperBound),
                PlotPoint(x: xRange.lowerBound, y: yRange.upperBound)
            ],
            kind: .rectangle
        )
    }

    public static func xCutoff(name: String = "X Cut", threshold: Float, xUpper: Float, yRange: ClosedRange<Float>) -> PolygonGate {
        PolygonGate(
            name: name,
            vertices: [
                PlotPoint(x: threshold, y: yRange.lowerBound),
                PlotPoint(x: xUpper, y: yRange.lowerBound),
                PlotPoint(x: xUpper, y: yRange.upperBound),
                PlotPoint(x: threshold, y: yRange.upperBound)
            ],
            kind: .xCutoff
        )
    }

    public static func quadrant(name: String = "Quadrant", origin: PlotPoint, xUpper: Float, yUpper: Float) -> PolygonGate {
        PolygonGate(
            name: name,
            vertices: [
                origin,
                PlotPoint(x: xUpper, y: origin.y),
                PlotPoint(x: xUpper, y: yUpper),
                PlotPoint(x: origin.x, y: yUpper)
            ],
            kind: .quadrant
        )
    }

    public static func ellipse(
        name: String = "Oval",
        xRange: ClosedRange<Float>,
        yRange: ClosedRange<Float>,
        segments: Int = 72
    ) -> PolygonGate {
        precondition(segments >= 12, "Ellipse gate requires at least 12 segments")
        let centerX = (xRange.lowerBound + xRange.upperBound) / 2
        let centerY = (yRange.lowerBound + yRange.upperBound) / 2
        let radiusX = (xRange.upperBound - xRange.lowerBound) / 2
        let radiusY = (yRange.upperBound - yRange.lowerBound) / 2
        let vertices = (0..<segments).map { index in
            let angle = 2 * Float.pi * Float(index) / Float(segments)
            return PlotPoint(
                x: centerX + cos(angle) * radiusX,
                y: centerY + sin(angle) * radiusY
            )
        }
        return PolygonGate(name: name, vertices: vertices, kind: .ellipse)
    }

    public func contains(x: Float, y: Float) -> Bool {
        if kind == .xCutoff {
            let xs = vertices.map(\.x)
            guard let lower = xs.min(), let upper = xs.max() else { return false }
            return x >= lower && x <= upper
        }

        var inside = false
        var previous = vertices[vertices.count - 1]

        for current in vertices {
            let crosses = (current.y > y) != (previous.y > y)
            if crosses {
                let xAtY = (previous.x - current.x) * (y - current.y) / (previous.y - current.y) + current.x
                if x < xAtY {
                    inside.toggle()
                }
            }
            previous = current
        }

        return inside
    }

    public func evaluate(xValues: [Float], yValues: [Float], base: EventMask? = nil) -> EventMask {
        precondition(xValues.count == yValues.count, "X and Y arrays must have the same count")
        if let base {
            precondition(base.count == xValues.count, "Base mask count must match values count")
        }

        let eventCount = xValues.count
        let wordCount = (eventCount + 63) / 64
        guard wordCount > 0 else { return EventMask(count: 0) }

        let availableWorkers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        let workers = max(1, min(4, availableWorkers, wordCount))
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        final class PartialStore: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [(offset: Int, words: [UInt64])] = []

            func append(offset: Int, words: [UInt64]) {
                lock.lock()
                storage.append((offset: offset, words: words))
                lock.unlock()
            }

            func values() -> [(offset: Int, words: [UInt64])] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
        }
        let partialStore = PartialStore()

        for worker in 0..<workers {
            let wordStart = worker * wordCount / workers
            let wordEnd = (worker + 1) * wordCount / workers
            group.enter()
            queue.async {
                var words = Array(repeating: UInt64(0), count: wordEnd - wordStart)
                for wordIndex in wordStart..<wordEnd {
                    var word: UInt64 = 0
                    let eventStart = wordIndex * 64
                    let eventEnd = min(eventStart + 64, eventCount)

                    for event in eventStart..<eventEnd {
                        if let base, !base[event] {
                            continue
                        }
                        if contains(x: xValues[event], y: yValues[event]) {
                            word |= UInt64(1) << UInt64(event & 63)
                        }
                    }

                    words[wordIndex - wordStart] = word
                }

                partialStore.append(offset: wordStart, words: words)
                group.leave()
            }
        }

        group.wait()

        var words = Array(repeating: UInt64(0), count: wordCount)
        for partial in partialStore.values() {
            for index in partial.words.indices {
                words[partial.offset + index] = partial.words[index]
            }
        }

        return EventMask(count: eventCount, words: words)
    }
}
