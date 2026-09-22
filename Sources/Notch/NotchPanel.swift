import AppKit

/// Borderless, non-activating panel that floats over everything, including the
/// menu bar and full-screen apps. Non-activating matters: glancing at your
/// usage must never take focus off what you were actually doing.
final class NotchPanel: NSPanel {
    /// Supplies the right-click menu. Handled here rather than on the content
    /// view because `NSWindow.sendEvent` sees every event first — the hosting
    /// view's hit test resolves to a SwiftUI-owned subview, which has no menu
    /// of its own and may consume the click before it reaches us.
    var contextMenuProvider: (() -> NSMenu?)?
    /// A left click on the visible chrome. Handled here for the same reason the
    /// menu is: the hit test lands on a SwiftUI subview that may consume it.
    var onClick: ((CGPoint) -> Void)?
    /// ⌥-drag on the chrome, reported as the raw pointer delta since the last
    /// event — not a cumulative offset, so the caller decides what "along the
    /// edge" means for the current one. Plain dragging uses a movement threshold;
    /// Option dragging starts immediately.
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    /// The ⌥-drag ended. Where to persist the offset the drags above moved to.
    var onDragEnd: (() -> Void)?
    var canStartPlainDrag: ((CGPoint) -> Bool)?
    private var pendingClick: CGPoint?
    private var plainDragDelta = CGPoint.zero
    private var isPlainDragging = false

    override func sendEvent(_ event: NSEvent) {
        // Route the gesture before SwiftUI's hosting subviews consume it.
        if event.type == .leftMouseDown,
           canStartPlainDrag?(event.locationInWindow) == true,
           contentView?.hitTest(event.locationInWindow) != nil {
            mouseDown(with: event)
            return
        }
        if pendingClick != nil {
            if event.type == .leftMouseDragged { mouseDragged(with: event); return }
            if event.type == .leftMouseUp { mouseUp(with: event); return }
        }
        guard event.type == .rightMouseDown,
              let menu = contextMenuProvider?(),
              let view = contentView,
              // Only over the visible chrome; elsewhere the panel is a hole.
              view.hitTest(event.locationInWindow) != nil
        else { return super.sendEvent(event) }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    override func mouseDown(with event: NSEvent) {
        guard let view = contentView, view.hitTest(event.locationInWindow) != nil else {
            return super.mouseDown(with: event)
        }
        guard onDrag != nil else {
            onClick?(event.locationInWindow)
            return
        }
        if event.modifierFlags.contains(.option) {
            onDragStart?()
            trackOptionDrag()
        } else if canStartPlainDrag?(event.locationInWindow) == false {
            onClick?(event.locationInWindow)
        } else {
            pendingClick = event.locationInWindow
            plainDragDelta = .zero
            isPlainDragging = false
        }
    }

    /// A small movement tolerance keeps an ordinary click from moving the bar.
    static func startsPlainDrag(dx: CGFloat, dy: CGFloat) -> Bool {
        hypot(dx, dy) >= 5
    }

    override func mouseDragged(with event: NSEvent) {
        guard pendingClick != nil else { return super.mouseDragged(with: event) }
        if isPlainDragging {
            onDrag?(event.deltaX, event.deltaY)
        } else {
            plainDragDelta.x += event.deltaX
            plainDragDelta.y += event.deltaY
            if Self.startsPlainDrag(dx: plainDragDelta.x, dy: plainDragDelta.y) {
                isPlainDragging = true
                onDragStart?()
                onDrag?(plainDragDelta.x, plainDragDelta.y)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let click = pendingClick else { return super.mouseUp(with: event) }
        pendingClick = nil
        if isPlainDragging { onDragEnd?() } else { onClick?(click) }
        isPlainDragging = false
    }

    /// Blocks on this window's own event stream until the button lifts, the
    /// standard AppKit pattern for a custom drag started from `mouseDown`.
    /// Never falls through to `onClick` on release: an ⌥-drag is a distinct
    /// gesture from the start, not a click that grew into one, so there is
    /// nothing to reinterpret once the button comes up.
    private func trackOptionDrag() {
        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch event.type {
            case .leftMouseDragged:
                onDrag?(event.deltaX, event.deltaY)
            case .leftMouseUp:
                onDragEnd?()
                return
            default:
                return
            }
        }
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
