import Foundation
import OpenFloCore

guard CommandLine.arguments.count == 2 else {
    print("Usage: OpenFloInspect /path/to/file.fcs")
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let file = try FCSParser.load(url: url)
let table = file.table
let keywords = file.metadata.keywords

print("\(url.lastPathComponent)")
print("Version: \(file.metadata.version)")
print("Events: \(table.rowCount)")
print("Channels: \(table.channelCount)")
print("Datatype: \(keywords["$DATATYPE"] ?? "?")")
print("Byte order: \(keywords["$BYTEORD"] ?? "?")")

for index in table.channels.indices {
    let channel = table.channels[index]
    let full = table.range(for: index)
    let focus = table.focusedRange(for: index)
    let label: String
    if let marker = channel.markerName, let fluorochrome = channel.fluorochromeName {
        label = "\(marker) (\(fluorochrome)) - \(channel.name)"
    } else if channel.displayName == channel.name {
        label = channel.name
    } else {
        label = "\(channel.name) (\(channel.displayName))"
    }
    print("\(index + 1). \(label): full \(format(full)), focus75 \(format(focus))")
}

private func format(_ range: ClosedRange<Float>) -> String {
    "\(format(range.lowerBound))...\(format(range.upperBound))"
}

private func format(_ value: Float) -> String {
    if abs(value) >= 10_000 || abs(value) < 0.01 {
        return String(format: "%.3g", Double(value))
    }
    if abs(value) >= 100 {
        return String(format: "%.0f", Double(value))
    }
    return String(format: "%.2f", Double(value))
}
