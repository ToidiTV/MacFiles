import AppKit
import FilesShared

extension MainPageViewModel {
    func toggleFocusedSelection() {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return }
        let pane = activePane
        guard let url = pane.focusedItemURL else { return }
        pane.focusedItemURL = url
        if pane.selection.contains(url) { pane.selection.remove(url) } else { pane.selection.insert(url) }
        if pane.isVirtual { pane.synchronizeVirtualSelection() }
    }
    func cycleLayout(_ delta: Int) {
        changeLayoutSize(delta, cycle: true)
    }
    func changeLayoutSize(_ delta: Int, cycle: Bool = false) {
        var sizes = SettingsService.shared.layoutSizes
        activePane.layout = LayoutSizing.step(activePane.effectiveLayout, sizes: &sizes, forward: delta > 0, cycle: cycle)
        SettingsService.shared.layoutSizes = sizes
        iconRevision += 1
    }
    func setCompactOverlay(_ enabled: Bool) {
        guard let window = NSApp.keyWindow, compactOverlay != enabled else { return }
        if enabled { normalWindowFrame = window.frame; normalWindowLevel = window.level }
        compactOverlay = enabled
        DispatchQueue.main.async {
            window.contentMinSize = enabled ? NSSize(width: 400, height: 350) : NSSize(width: 860, height: 560)
            window.level = enabled ? .floating : self.normalWindowLevel
            if enabled { window.setContentSize(NSSize(width: 400, height: 350)) }
            else if let frame = self.normalWindowFrame { window.setFrame(frame, display: true) }
        }
    }
    func chooseAppBackground() {
        if activePane.selectedItems.count == 1, let item = activePane.selectedItems.first, item.url.isFileURL, NSImage(contentsOf: item.url) != nil { SettingsService.shared.backgroundImagePath = item.url.path; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SettingsService.shared.backgroundImagePath = url.path
    }
}
