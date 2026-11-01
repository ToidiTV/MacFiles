import AppKit

@MainActor final class HoverSelection {
    private var area: NSTrackingArea?
    private var pending: DispatchWorkItem?
    func cancel() { pending?.cancel(); pending = nil }
    func schedule(_ action: @escaping () -> Void) {
        cancel()
        guard SettingsService.shared.preferences.selectOnHover, NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
        let work = DispatchWorkItem(block: action); pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func track(_ view: NSView) {
        if let area { view.removeTrackingArea(area) }
        let updated = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: view, userInfo: nil)
        area = updated; view.addTrackingArea(updated)
    }
}
