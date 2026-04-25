import AppKit
import SwiftUI

struct PlotInteractionOverlay: NSViewRepresentable {
    var onMouseDown: (CGPoint, Int) -> Void
    var onMouseDragged: (CGPoint) -> Void
    var onMouseUp: (CGPoint) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseDragged = onMouseDragged
        nsView.onMouseUp = onMouseUp
    }

    final class InteractionView: NSView {
        var onMouseDown: ((CGPoint, Int) -> Void)?
        var onMouseDragged: ((CGPoint) -> Void)?
        var onMouseUp: ((CGPoint) -> Void)?

        override var isFlipped: Bool { true }

        override func mouseDown(with event: NSEvent) {
            onMouseDown?(convert(event.locationInWindow, from: nil), event.clickCount)
        }

        override func mouseDragged(with event: NSEvent) {
            onMouseDragged?(convert(event.locationInWindow, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            onMouseUp?(convert(event.locationInWindow, from: nil))
        }
    }
}
