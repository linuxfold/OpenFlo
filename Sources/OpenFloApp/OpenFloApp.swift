import AppKit
import SwiftUI

@main
struct OpenFloApp: App {
    @NSApplicationDelegateAdaptor(OpenFloApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class OpenFloApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let iconURL = Bundle.main.url(forResource: "OpenFloOpen", withExtension: "png")
            ?? Bundle.module.url(forResource: "OpenFloOpen", withExtension: "png")
        guard let iconURL, let image = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
