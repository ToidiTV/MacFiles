import SwiftUI
import AppKit

struct TabWheelRegion: NSViewRepresentable {
    let scroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> TabWheelView { let view = TabWheelView(); view.scroll = scroll; return view }
    func updateNSView(_ view: TabWheelView, context: Context) { view.scroll = scroll }
}
final class TabWheelView: NSView {
    var scroll: ((CGFloat) -> Void)?
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)), abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            guard event.momentumPhase.isEmpty else { return nil }
            if event.phase == .began { self.accumulated = 0 }
            self.accumulated += event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas || abs(self.accumulated) >= 30 {
                self.scroll?(self.accumulated); self.accumulated = 0
            }
            return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
