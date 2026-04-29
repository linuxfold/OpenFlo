import AppKit
import SwiftUI

let layoutColorNames = ["Black", "Teal", "Blue", "Red", "Purple", "Orange", "Gray", "Light Teal"]
let layoutOverlayColorNames = ["Blue", "Red", "Teal", "Purple", "Orange", "Gray", "Black"]

func layoutOverlayColorName(at index: Int) -> String {
    layoutOverlayColorNames[index % layoutOverlayColorNames.count]
}

func color(named name: String) -> Color {
    switch name {
    case "Teal": return .teal
    case "Blue": return .blue
    case "Red": return .red
    case "Purple": return .purple
    case "Orange": return .orange
    case "Gray": return .gray
    case "Light Teal": return Color.teal.opacity(0.28)
    default: return .black
    }
}

func nsColor(named name: String) -> NSColor {
    switch name {
    case "Teal": return NSColor.systemTeal
    case "Blue": return NSColor.systemBlue
    case "Red": return NSColor.systemRed
    case "Purple": return NSColor.systemPurple
    case "Orange": return NSColor.systemOrange
    case "Gray": return NSColor.systemGray
    case "Light Teal": return NSColor.systemTeal.withAlphaComponent(0.28)
    default: return NSColor.black
    }
}

func rgbaColor(named name: String, alpha: UInt8 = 230) -> (UInt8, UInt8, UInt8, UInt8) {
    let color = nsColor(named: name).usingColorSpace(.deviceRGB) ?? .black
    return (
        UInt8(min(max(color.redComponent * 255, 0), 255)),
        UInt8(min(max(color.greenComponent * 255, 0), 255)),
        UInt8(min(max(color.blueComponent * 255, 0), 255)),
        alpha
    )
}

func fillColor(named name: String) -> Color? {
    name == "None" ? nil : color(named: name)
}
