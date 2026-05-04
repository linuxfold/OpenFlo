import Foundation
import OpenFloCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

func expectClose(_ actual: Double?, _ expected: Double, tolerance: Double = 0.0001, _ message: String) {
    guard let actual, abs(actual - expected) <= tolerance else {
        fatalError("\(message). Expected \(expected), got \(String(describing: actual))")
    }
}

func testMaskBooleanOperations() {
    var left = EventMask(count: 130)
    var right = EventMask(count: 130)
    left[1] = true
    left[64] = true
    right[64] = true
    right[129] = true

    expect(left.selectedCount == 2, "left mask should have two selected events")
    expect(left.intersection(right).selectedCount == 1, "intersection should have one selected event")
    expect(left.union(right).selectedCount == 3, "union should have three selected events")
    expect(left.subtracting(right).selectedCount == 1, "subtraction should have one selected event")
}

func testRectangleGate() {
    let x: [Float] = [0, 1, 2, 3, 4]
    let y: [Float] = [0, 1, 2, 3, 4]
    let gate = PolygonGate.rectangle(xRange: 1.5...3.5, yRange: 1.5...3.5)
    let mask = gate.evaluate(xValues: x, yValues: y)
    expect(mask[0] == false, "event 0 should be outside gate")
    expect(mask[1] == false, "event 1 should be outside gate")
    expect(mask[2] == true, "event 2 should be inside gate")
    expect(mask[3] == true, "event 3 should be inside gate")
    expect(mask[4] == false, "event 4 should be outside gate")
}

func testHistogramBuildsExpectedBins() {
    let histogram = Histogram2D.build(
        xValues: [0, 0, 1, 1],
        yValues: [0, 0, 1, 1],
        width: 2,
        height: 2,
        xRange: 0...1,
        yRange: 0...1
    )

    expect(histogram[0, 0] == 2, "lower-left bin should contain two events")
    expect(histogram[1, 1] == 2, "upper-right bin should contain two events")
    expect(histogram.maxBin == 2, "max bin should be two")
}

func testFocusedRangeIgnoresExtremeOutliers() {
    let values = (0..<1_000).map { Float($0) } + [1_000_000]
    let focused = EventTable.focusedRange(values: values)
    let full = EventTable.range(values: values)

    expect(focused.lowerBound > 50, "focused range should trim the low tail")
    expect(focused.upperBound < 950, "focused range should trim the high tail")
    expect(full.upperBound > 900_000, "full range should include the extreme event")
}

func testRangesTolerateInvalidMasks() {
    let values: [Float] = [10, 20, 30]
    let shortMask = EventMask(count: 2, fill: true)
    let emptySelection = EventMask(count: values.count)
    let nonFiniteValues: [Float] = [.nan, .infinity, -.infinity]

    expect(EventTable.range(values: values, mask: shortMask) == 0...1, "range should fall back for mismatched masks")
    expect(EventTable.range(values: values, mask: emptySelection) == 0...1, "range should fall back when no events are selected")
    expect(EventTable.range(values: nonFiniteValues) == 0...1, "range should fall back when no finite values are available")
    expect(EventTable.focusedRange(values: values, mask: shortMask) == 0...1, "focused range should fall back for mismatched masks")
}

func testStatisticEngineExactStatistics() {
    let table = EventTable(
        channels: [Channel(name: "FL1-A")],
        columns: [[1, 2, 3, 4, 5, .nan, .infinity]]
    )
    var population = EventMask(count: table.rowCount)
    for index in 0..<table.rowCount {
        population[index] = true
    }
    var parent = EventMask(count: table.rowCount)
    for index in 0..<6 {
        parent[index] = true
    }
    let grandparent = EventMask(count: table.rowCount, fill: true)
    var denominator = EventMask(count: table.rowCount)
    for index in 0..<4 {
        denominator[index] = true
    }

    func evaluate(_ kind: StatisticKind, percentile: Double? = nil) -> Double? {
        StatisticEngine.evaluate(
            request: StatisticRequest(kind: kind, channelName: "FL1-A", percentile: percentile),
            table: table,
            population: population,
            parent: parent,
            grandparent: grandparent,
            denominator: denominator,
            totalCount: table.rowCount,
            channelResolver: { $0 == "FL1-A" ? 0 : nil }
        ).number
    }

    expectClose(evaluate(.count), 7, "count should include non-finite channel values")
    expectClose(evaluate(.frequencyOfParent), Double(7) / Double(6) * 100, "frequency of parent should use parent mask")
    expectClose(evaluate(.frequencyOfGrandparent), 100, "frequency of grandparent should use grandparent mask")
    expectClose(evaluate(.frequencyOfPopulation), Double(7) / Double(4) * 100, "frequency of population should use denominator mask")
    expectClose(evaluate(.frequencyOfTotal), 100, "frequency of total should use table row count")
    expectClose(evaluate(.mean), 3, "mean should ignore non-finite channel values")
    expectClose(evaluate(.median), 3, "median should interpolate the central value")
    expectClose(evaluate(.percentile, percentile: 25), 2, "percentile should use exact interpolation")
    expectClose(evaluate(.standardDeviation), sqrt(2), "SD should use population standard deviation")
    expectClose(evaluate(.cv), 100 * sqrt(2) / 3, "CV should be percent SD over mean")
    expectClose(evaluate(.robustSD), 1.3652, "robust SD should use P84.13 and P15.87")
    expectClose(evaluate(.robustCV), 45.5066667, tolerance: 0.0002, "robust CV should use documented FlowJo formula")
    expectClose(evaluate(.mad), 1, "MAD should be median absolute deviation")
    expectClose(evaluate(.madPercent), 100 / 3, "MADP should normalize MAD by median")
    expectClose(evaluate(.geometricMean), 2.605171, tolerance: 0.0002, "geometric mean should use positive finite values")
}

func testStatisticEngineModeAndGraphSpace() {
    let table = EventTable(channels: [Channel(name: "FL1-A")], columns: [[1, 2, 2, 3, 4]])
    let population = EventMask(count: table.rowCount, fill: true)
    let mode = StatisticEngine.evaluate(
        request: StatisticRequest(kind: .mode, channelName: "FL1-A"),
        table: table,
        population: population,
        parent: nil,
        grandparent: nil,
        totalCount: table.rowCount,
        channelResolver: { $0 == "FL1-A" ? 0 : nil }
    ).number
    expectClose(mode, 2, "mode should return the most frequent selected value")

    let graphMedian = StatisticEngine.evaluateChannelStatistic(
        request: StatisticRequest(
            kind: .median,
            channelName: "FL1-A",
            space: .exactGraph(StatisticTransformSettings(transform: .arcsinh, cofactor: 2))
        ),
        values: table.column(0),
        mask: population
    ).number
    expectClose(graphMedian, asinh(Double(2) / Double(2)), "exact graph statistics should use transformed values")
}

func testTransformInverseRoundTrip() {
    let values: [Float] = [-500, -10, 0, 10, 500]
    for transform in TransformKind.allCases {
        for value in values {
            let graph = transform.apply(value, cofactor: 150, extraNegativeDecades: 1, widthBasis: 1.2, positiveDecades: 4.5)
            guard let inverse = transform.inverse(graph, cofactor: 150, extraNegativeDecades: 1, widthBasis: 1.2, positiveDecades: 4.5) else {
                fatalError("inverse should exist for \(transform.rawValue)")
            }
            let tolerance: Float = transform == .logarithmic && value < 1 ? 1.1 : 0.01
            expect(abs(inverse - (transform == .logarithmic ? max(value, 1) : value)) <= tolerance, "inverse should round-trip \(transform.rawValue)")
        }
    }
}

func testFCSTextParserHandlesEscapedDelimiter() throws {
    let text = "/$PAR/2/$P1N/FSC-A/$P2N/CD//3/$TOT/1/"
    let keywords = try FCSParser.parseTextSegment(Data(text.utf8))
    expect(keywords["$PAR"] == "2", "FCS parser should read parameter count")
    expect(keywords["$P2N"] == "CD/3", "FCS parser should unescape doubled delimiters")
}

func testFCSFloatByteOrders() throws {
    let little = try FCSParser.parse(data: singleFloatFCS(value: 42.25, byteOrder: "1,2,3,4"))
    let big = try FCSParser.parse(data: singleFloatFCS(value: 42.25, byteOrder: "4,3,2,1"))

    expect(abs(little.table.value(event: 0, channel: 0) - 42.25) < 0.001, "1,2,3,4 should parse as little-endian")
    expect(abs(big.table.value(event: 0, channel: 0) - 42.25) < 0.001, "4,3,2,1 should parse as big-endian")
}

func testFCSParserTrimsPaddedNumericKeywords() throws {
    let file = try FCSParser.parse(
        data: singleFloatFCS(
            value: 17.5,
            byteOrder: "4,3,2,1",
            eventCountText: "1       ",
            bitWidthText: " 32 ",
            includeKeywordOffsets: true
        )
    )

    expect(file.table.rowCount == 1, "padded $TOT should parse as the event count")
    expect(file.table.channels[0].bitWidth == 32, "padded $P1B should parse as the bit width")
    expect(abs(file.table.value(event: 0, channel: 0) - 17.5) < 0.001, "padded data offsets should still locate the event data")
}

func testFCSMarkerFluorochromeLabels() throws {
    let file = try FCSParser.parse(
        data: singleFloatFCS(
            value: 42.25,
            byteOrder: "1,2,3,4",
            parameterName: "Alexa Fluor 647-A",
            parameterStain: "CD86"
        )
    )
    let channel = file.table.channels[0]

    expect(channel.name == "Alexa Fluor 647-A", "channel name should preserve the detector label")
    expect(channel.markerName == "CD86", "channel marker should come from $P1S")
    expect(channel.fluorochromeName == "AF647", "Alexa Fluor 647 should be abbreviated to AF647")
    expect(channel.displayName == "CD86 (AF647)", "display name should combine marker and fluorochrome")
}

func testSpilloverParserNormalizesFractionsToPercent() throws {
    let channels = ["FITC-A", "PE-A"].map { Channel(name: $0) }
    let matrix = FCSParser.parseSpilloverKeyword(
        "2,FITC-A,PE-A,1,0.10,0,1",
        keyword: "$SPILL",
        channels: channels
    )

    expect(matrix?.parameters == ["FITC-A", "PE-A"], "$SPILL parser should preserve parameter order")
    expect(matrix?.percent[0][0] == 100, "fractional diagonal should normalize to 100 percent")
    expect(abs((matrix?.percent[0][1] ?? 0) - 10) < 0.0001, "fractional spillover should normalize to percent")
}

func testSpilloverParserKeepsPercentUnits() throws {
    let channels = ["FITC-A", "PE-A"].map { Channel(name: $0) }
    let matrix = FCSParser.parseSpilloverKeyword(
        "2,FITC-A,PE-A,100,16.3,0,100",
        keyword: "$SPILLOVER",
        channels: channels
    )

    expect(matrix?.percent[0][0] == 100, "percent diagonal should remain 100")
    expect(abs((matrix?.percent[0][1] ?? 0) - 16.3) < 0.0001, "percent spillover should remain unchanged")
}

func testFCSParserReadsSpillWithoutDollarPrefix() throws {
    let file = try FCSParser.parse(
        data: singleFloatFCS(
            value: 42.25,
            byteOrder: "1,2,3,4",
            parameterName: "FITC-A",
            extraText: "/SPILL/1,FITC-A,1"
        )
    )

    expect(file.acquisitionCompensation?.parameters == ["FITC-A"], "FCS parser should read SPILL without a dollar prefix")
    expect(file.acquisitionCompensation?.percent == [[100]], "SPILL fraction values should normalize to percent")
}

func testSpilloverParserPreservesUnmatchedParameters() throws {
    let matrix = FCSParser.parseSpilloverKeyword(
        "2,FITC-A,PE-A,1,0.1,0,1",
        keyword: "SPILL",
        channels: [Channel(name: "FITC-A")]
    )

    expect(matrix?.parameters == ["FITC-A", "PE-A"], "parser should preserve acquisition matrix names even before matching sample channels")
}

func testCompensationIdentityLeavesValuesUnchanged() throws {
    let table = EventTable(
        channels: [Channel(name: "FITC-A"), Channel(name: "PE-A")],
        columns: [[10, 20, 30], [2, 4, 6]]
    )
    let matrix = CompensationMatrix.identity(name: "Identity", parameters: ["FITC-A", "PE-A"])
    let compensated = try CompensationEngine.apply(matrix, to: table)

    expect(compensated.column(0) == table.column(0), "identity compensation should keep first channel unchanged")
    expect(compensated.column(1) == table.column(1), "identity compensation should keep second channel unchanged")
}

func testCompensationTwoChannelSpill() throws {
    let table = EventTable(
        channels: [Channel(name: "FITC-A"), Channel(name: "PE-A")],
        columns: [[1000], [100]]
    )
    let matrix = CompensationMatrix(
        name: "FITC into PE",
        parameters: ["FITC-A", "PE-A"],
        percent: [
            [100, 10],
            [0, 100]
        ],
        source: .manualIdentity
    )
    let compensated = try CompensationEngine.apply(matrix, to: table)

    expect(abs(compensated.value(event: 0, channel: 0) - 1000) < 0.001, "FITC should stay at 1000")
    expect(abs(compensated.value(event: 0, channel: 1)) < 0.001, "PE should compensate FITC spillover to zero")
}

func testCompensationLeavesUnlistedChannelsUnchanged() throws {
    let table = EventTable(
        channels: [Channel(name: "FSC-A"), Channel(name: "FITC-A"), Channel(name: "PE-A"), Channel(name: "Time")],
        columns: [[1, 2], [1000, 500], [100, 50], [9, 10]]
    )
    let matrix = CompensationMatrix(
        name: "FITC into PE",
        parameters: ["FITC-A", "PE-A"],
        percent: [
            [100, 10],
            [0, 100]
        ],
        source: .manualIdentity
    )
    let compensated = try CompensationEngine.apply(matrix, to: table)

    expect(compensated.column(0) == [1, 2], "FSC should not be modified by compensation")
    expect(compensated.column(3) == [9, 10], "Time should not be modified by compensation")
}

func testCompensationMissingChannelThrows() throws {
    let table = EventTable(channels: [Channel(name: "FITC-A")], columns: [[1]])
    let matrix = CompensationMatrix.identity(name: "Missing", parameters: ["FITC-A", "PE-A"])

    do {
        _ = try CompensationEngine.apply(matrix, to: table)
        fatalError("missing compensation channel should throw")
    } catch CompensationError.missingChannel("PE-A") {
    } catch {
        fatalError("missing compensation channel should produce a specific error")
    }
}

func testSingleCellDelimitedParserGenesByCells() throws {
    let rows = [
        ["gene", "Cell1", "Cell2"],
        ["CD3D", "1", "2"],
        ["MS4A1", "3", "4"]
    ]
    let file = try SingleCellDataParser.parseDelimited(rows: rows)

    expect(file.orientation == .genesByCells, "gene-labeled matrix should parse as genes x cells")
    expect(file.table.rowCount == 2, "single-cell rows should become cells")
    expect(file.table.channelCount == 2, "single-cell columns should become genes")
    expect(file.table.channels[0].kind == .singleCellFeature, "genes should be marked as single-cell features")
    expect(file.table.value(event: 1, channel: 0) == 2, "gene x cell values should parse")
}

func testMatrixMarketSparseParserMaterializesExpectedValues() throws {
    let directory = try matrixMarketFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let matrixFile = try SingleCellDataParser.loadMatrixMarketMatrix(url: directory, normalizeCounts: false)
    expect(matrixFile.matrix.geneCount == 2, "sparse Matrix Market parser should read gene count")
    expect(matrixFile.matrix.cellCount == 3, "sparse Matrix Market parser should read cell count")
    expect(matrixFile.matrix.nonZeroCount == 4, "sparse Matrix Market parser should keep only non-zero entries")

    let table = matrixFile.materializedTable()
    expect(table.column(0) == [1, 2, 0], "materialized first gene column should match Matrix Market entries")
    expect(table.column(1) == [3, 0, 4], "materialized second gene column should match Matrix Market entries")
}

func testSeqtometrySignatureParser() throws {
    let text = """
    name\tvalue
    T cell\tCD3D,TRAC,CD3G
    B cell\tMS4A1 CD79A
    """
    let signatures = try SeqtometrySignatureParser.parse(text: text, filename: "signatures.tsv")

    expect(signatures.count == 2, "signature parser should read name/value rows")
    expect(signatures[0].genes == ["CD3D", "TRAC", "CD3G"], "comma-separated signature genes should parse")
    expect(signatures[1].genes == ["MS4A1", "CD79A"], "whitespace-separated signature genes should parse")
}

func testSparseSeqtometryScoreMatchesDenseMatrix() throws {
    let directory = try matrixMarketFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let matrixURL = directory.appendingPathComponent("matrix.mtx")
    let matrixFile = try SingleCellDataParser.loadMatrixMarketMatrix(url: directory, normalizeCounts: false)
    let denseFile = try SingleCellDataParser.parseMatrixMarket(url: matrixURL, normalizeCounts: false)
    let signatures = [
        SeqtometrySignature(name: "CD3D score", genes: ["CD3D"]),
        SeqtometrySignature(name: "MS4A1 score", genes: ["MS4A1"])
    ]

    let denseScores = try SeqtometryScorer.scoreColumns(table: denseFile.table, signatures: signatures)
    let sparseScores = try SeqtometryScorer.scoreColumns(matrixFile: matrixFile, signatures: signatures)

    expect(denseScores.count == sparseScores.count, "sparse scorer should emit the same number of score columns")
    for scoreIndex in denseScores.indices {
        expect(denseScores[scoreIndex].values.count == sparseScores[scoreIndex].values.count, "sparse score length should match dense score length")
        for cellIndex in denseScores[scoreIndex].values.indices {
            expect(
                abs(denseScores[scoreIndex].values[cellIndex] - sparseScores[scoreIndex].values[cellIndex]) < 0.0001,
                "sparse score should match dense score for signature \(scoreIndex), cell \(cellIndex)"
            )
        }
    }
}

func testSeqtometryScoreMatchesReferenceExample() throws {
    let channels = ["a", "b", "c", "d", "e"].map {
        Channel(name: $0, kind: .singleCellFeature, preferredTransform: .linear)
    }
    let table = EventTable(
        channels: channels,
        columns: [
            [1, 8, 3],
            [2, 7, 4],
            [0, 9, 2],
            [4, 0, 0],
            [5, 2, 1]
        ]
    )
    let signatures = [SeqtometrySignature(name: "Sig", genes: ["a", "c"])]
    let scored = try SeqtometryScorer.tableByAppendingScores(to: table, signatures: signatures)
    guard let scoreIndex = scored.channels.firstIndex(where: { $0.name == "Sig" }) else {
        fatalError("signature score channel should be appended")
    }

    let scores = scored.column(scoreIndex)
    expect(scores.count == 3, "signature score should have one value per cell")
    expect(abs(scores[0] - 0) < 0.0001, "first reference score should match")
    expect(abs(scores[1] - 1) < 0.0001, "second reference score should match")
    expect(abs(scores[2] - 0.5) < 0.0001, "third reference score should match")
    expect(scored.channels[scoreIndex].kind == .seqtometrySignature, "score channels should be marked as signatures")
}

func matrixMarketFixtureDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenFloMatrixMarket-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let matrix = """
    %%MatrixMarket matrix coordinate real general
    %
    2 3 4
    1 1 1
    2 1 3
    1 2 2
    2 3 4
    """
    let features = """
    ENSG0001\tCD3D
    ENSG0002\tMS4A1
    """
    let barcodes = """
    Cell1
    Cell2
    Cell3
    """

    try matrix.write(to: directory.appendingPathComponent("matrix.mtx"), atomically: true, encoding: .utf8)
    try features.write(to: directory.appendingPathComponent("features.tsv"), atomically: true, encoding: .utf8)
    try barcodes.write(to: directory.appendingPathComponent("barcodes.tsv"), atomically: true, encoding: .utf8)
    return directory
}

func singleFloatFCS(
    value: Float,
    byteOrder: String,
    parameterName: String = "FSC-A",
    parameterStain: String? = nil,
    eventCountText: String = "1",
    bitWidthText: String = "32",
    includeKeywordOffsets: Bool = false,
    extraText: String = ""
) -> Data {
    let stainText = parameterStain.map { "/$P1S/\($0)" } ?? ""
    let textStart = 58
    var text = ""
    var dataStart = 0
    var dataEnd = 0

    for _ in 0..<4 {
        text = "/$TOT/\(eventCountText)/$PAR/1/$DATATYPE/F/$BYTEORD/\(byteOrder)/$P1N/\(parameterName)/$P1B/\(bitWidthText)/$P1R/262144\(stainText)\(extraText)"
        if includeKeywordOffsets {
            text += "/$BEGINDATA/ \(dataStart) /$ENDDATA/\(dataEnd)      "
        }
        text += "/"

        let nextDataStart = textStart + text.utf8.count
        let nextDataEnd = nextDataStart + 3
        if nextDataStart == dataStart, nextDataEnd == dataEnd {
            break
        }
        dataStart = nextDataStart
        dataEnd = nextDataEnd
    }

    let textEnd = textStart + text.utf8.count - 1
    if !includeKeywordOffsets {
        dataStart = textEnd + 1
        dataEnd = dataStart + 3
    }

    var data = Data("FCS3.1    ".utf8)
    data.append(fcsHeaderField(textStart))
    data.append(fcsHeaderField(textEnd))
    data.append(fcsHeaderField(dataStart))
    data.append(fcsHeaderField(dataEnd))
    data.append(fcsHeaderField(0))
    data.append(fcsHeaderField(0))
    data.append(Data(text.utf8))

    let bits = value.bitPattern
    if byteOrder == "1,2,3,4" {
        data.append(UInt8((bits >> 0) & 0xff))
        data.append(UInt8((bits >> 8) & 0xff))
        data.append(UInt8((bits >> 16) & 0xff))
        data.append(UInt8((bits >> 24) & 0xff))
    } else {
        data.append(UInt8((bits >> 24) & 0xff))
        data.append(UInt8((bits >> 16) & 0xff))
        data.append(UInt8((bits >> 8) & 0xff))
        data.append(UInt8((bits >> 0) & 0xff))
    }

    return data
}

func fcsHeaderField(_ value: Int) -> Data {
    Data(String(format: "%8d", value).utf8)
}

testMaskBooleanOperations()
testRectangleGate()
testHistogramBuildsExpectedBins()
testFocusedRangeIgnoresExtremeOutliers()
testRangesTolerateInvalidMasks()
testStatisticEngineExactStatistics()
testStatisticEngineModeAndGraphSpace()
testTransformInverseRoundTrip()
try testFCSTextParserHandlesEscapedDelimiter()
try testFCSFloatByteOrders()
try testFCSMarkerFluorochromeLabels()
try testSpilloverParserNormalizesFractionsToPercent()
try testSpilloverParserKeepsPercentUnits()
try testFCSParserReadsSpillWithoutDollarPrefix()
try testSpilloverParserPreservesUnmatchedParameters()
try testCompensationIdentityLeavesValuesUnchanged()
try testCompensationTwoChannelSpill()
try testCompensationLeavesUnlistedChannelsUnchanged()
try testCompensationMissingChannelThrows()
try testSingleCellDelimitedParserGenesByCells()
try testMatrixMarketSparseParserMaterializesExpectedValues()
try testSeqtometrySignatureParser()
try testSparseSeqtometryScoreMatchesDenseMatrix()
try testSeqtometryScoreMatchesReferenceExample()
print("OpenFloCore smoke tests passed")
