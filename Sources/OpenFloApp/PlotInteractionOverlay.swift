import AppKit
import SwiftUI

struct PlotInteractionOverlay: NSViewRepresentable {
    var onMouseDown: (CGPoint, Int) -> Void
    var onMouseDragged: (CGPoint) -> Void
    var onMouseUp: (CGPoint) -> Void
    var onMouseMoved: (CGPoint) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        view.onMouseMoved = onMouseMoved
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseDragged = onMouseDragged
        nsView.onMouseUp = onMouseUp
        nsView.onMouseMoved = onMouseMoved
    }

    final class InteractionView: NSView {
        var onMouseDown: ((CGPoint, Int) -> Void)?
        var onMouseDragged: ((CGPoint) -> Void)?
        var onMouseUp: ((CGPoint) -> Void)?
        var onMouseMoved: ((CGPoint) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseMoved]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onMouseDown?(convert(event.locationInWindow, from: nil), event.clickCount)
        }

        override func mouseDragged(with event: NSEvent) {
            onMouseDragged?(convert(event.locationInWindow, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            onMouseUp?(convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            onMouseMoved?(convert(event.locationInWindow, from: nil))
        }
    }
}
