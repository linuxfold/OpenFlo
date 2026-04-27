import Foundation
import OpenFloCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
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

func singleFloatFCS(
    value: Float,
    byteOrder: String,
    parameterName: String = "FSC-A",
    parameterStain: String? = nil,
    eventCountText: String = "1",
    bitWidthText: String = "32",
    includeKeywordOffsets: Bool = false
) -> Data {
    let stainText = parameterStain.map { "/$P1S/\($0)" } ?? ""
    let textStart = 58
    var text = ""
    var dataStart = 0
    var dataEnd = 0

    for _ in 0..<4 {
        text = "/$TOT/\(eventCountText)/$PAR/1/$DATATYPE/F/$BYTEORD/\(byteOrder)/$P1N/\(parameterName)/$P1B/\(bitWidthText)/$P1R/262144\(stainText)"
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
try testFCSTextParserHandlesEscapedDelimiter()
try testFCSFloatByteOrders()
try testFCSMarkerFluorochromeLabels()
print("OpenFloCore smoke tests passed")
