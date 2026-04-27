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

@MainActor
final class OpenFloWindowManager: NSObject, NSWindowDelegate {
    static let shared = OpenFloWindowManager()

    private var workspaceWindowControllers: [NSWindowController] = []

    func openWorkspaceWindow() {
        let hostingController = NSHostingController(
            rootView: ContentView()
                .frame(minWidth: 760, minHeight: 520)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "*unsaved* OpenFlo"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.delegate = self

        let controller = NSWindowController(window: window)
        workspaceWindowControllers.append(controller)
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        workspaceWindowControllers.removeAll { $0.window === window }
    }
}
