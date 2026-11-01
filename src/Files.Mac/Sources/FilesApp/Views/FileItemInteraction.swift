import AppKit
import SwiftUI
import FilesShared

struct FileItemInteraction<Content: View>: NSViewRepresentable {
    let item: ListedItem
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject var model: MainPageViewModel
    let select: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction
    @ViewBuilder let content: () -> Content
    private func rendered() -> AnyView { AnyView(content().environment(\.locale, locale).environment(\.layoutDirection, direction)) }
    func makeNSView(context: Context) -> FileInteractionHost<Content> { FileInteractionHost(root: rendered()) }
    func updateNSView(_ view: FileInteractionHost<Content>, context: Context) {
        view.host.rootView = rendered(); view.hostLeading?.constant = SettingsService.shared.preferences.selectionCheckboxes ? 24 : 0; view.checkbox.isHidden = !SettingsService.shared.preferences.selectionCheckboxes; view.checkbox.state = pane.selection.contains(item.url) ? .on : .off; view.checkbox.setAccessibilityLabel(L10n.text("Select") + " " + item.displayName); view.item = item; view.pane = pane; view.model = model; view.select = select
        view.setAccessibilityElement(true); view.setAccessibilityLabel(item.name); view.setAccessibilityRole(.button)
    }
}

final class FileInteractionHost<Content: View>: NSView, NSDraggingSource {
    let host: NSHostingView<AnyView>
    var hostLeading: NSLayoutConstraint?
    let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    @objc private func toggleCheckbox() {
        guard let item, let pane else { return }; model?.activePaneID = pane.id; pane.focusedItemURL = item.url
        if checkbox.state == .on { pane.selection.insert(item.url) } else { pane.selection.remove(item.url) }
    }
    var item: ListedItem?
    var pane: ShellPageViewModel?
    var model: MainPageViewModel?
    var select: (() -> Void)?
    private var dragged = false
    private let hover = HoverSelection()
    override func updateTrackingAreas() { super.updateTrackingAreas(); hover.track(self) }
    override func mouseMoved(with event: NSEvent) {
        hover.schedule { [weak self] in guard let self, let item = self.item, let pane = self.pane else { return }; self.model?.activePaneID = pane.id; pane.focusedItemURL = item.url; pane.selection = [item.url] }
    }
    override func mouseExited(with event: NSEvent) { hover.cancel() }
    override func mouseUp(with event: NSEvent) {
        guard !dragged, event.clickCount == 1, let item, let pane, let model,
              event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              SettingsService.shared.preferences.opensOnSingleClick(directory: item.isBrowsable),
              !(item.isBrowsable && pane.effectiveLayout == .columns) else { return }
        model.open(item, pane: pane)
    }
    private var menuCoordinator: FileTableView.Coordinator?
    init(root: AnyView) {
        host = NSHostingView(rootView: root); super.init(frame: .zero)
        registerForDraggedTypes(FileDrag.types)
        checkbox.target = self; checkbox.action = #selector(toggleCheckbox); checkbox.translatesAutoresizingMaskIntoConstraints = false
        host.translatesAutoresizingMaskIntoConstraints = false; addSubview(host)
        hostLeading = host.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([hostLeading!, host.trailingAnchor.constraint(equalTo: trailingAnchor), host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)])
        addSubview(checkbox)
        NSLayoutConstraint.activate([checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1), checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 1)])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { let hit = super.hitTest(point); return hit is NSButton ? hit : hit == nil ? nil : self }
    override func mouseDown(with event: NSEvent) {
        hover.cancel(); dragged = false; guard let item, let pane, let model else { return }
        model.activePaneID = pane.id; pane.focusedItemURL = item.url
        if event.clickCount == 2 && !(pane.effectiveLayout == .columns && item.isBrowsable) { model.open(item, pane: pane) } else { select?() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let item, let pane else { return }; dragged = true
        let sources = pane.selection.contains(item.url) ? pane.selectedItems : [item]
        let items = sources.enumerated().compactMap { index, file -> NSDraggingItem? in
            guard let writer = FileDrag.writer(file, pane: pane) else { return nil }
            let drag = NSDraggingItem(pasteboardWriter: writer)
            let icon = NSImage(systemSymbolName: file.isDirectory ? "folder" : "doc", accessibilityDescription: file.name)
            drag.setDraggingFrame(NSRect(x: 8 + index * 4, y: 2 + index * 4, width: 32, height: 32), contents: icon); return drag
        }
        if !items.isEmpty { beginDraggingSession(with: items, event: event, source: self) }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { pane?.isVirtual == false ? [.copy, .move] : .copy }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item, let pane, let model else { return nil }
        model.activePaneID = pane.id
        if !pane.selection.contains(item.url) { select?() }
        let coordinator = FileTableView.Coordinator(FileTableView(pane: pane, model: model, items: [item])); coordinator.displayed = [item]; menuCoordinator = coordinator
        return coordinator.menu(0)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let pane, let model, !model.busy, !pane.isVirtual || pane.virtualPaste != nil else { return [] }; return FileDrag.operation(sender.draggingPasteboard, mask: sender.draggingSourceOperationMask)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pane, let model else { return false }
        return FileDrag.accept(sender, model: model, pane: pane, destination: item?.isDirectory == true ? item?.url : pane.columnDirectory)
    }
    override func accessibilityPerformPress() -> Bool { select?(); return true }
}
