import AppKit
import SwiftUI
import FilesShared
import FilesStorage

@MainActor final class InlineRenameRequest {
    static let prepare = Notification.Name("MacFiles.prepareInlineRename")
    static let notification = Notification.Name("MacFiles.inlineRename")
    let paneID: UUID
    let item: ListedItem
    let commit: (String) -> Void
    var handled = false
    init(paneID: UUID, item: ListedItem, commit: @escaping (String) -> Void) { self.paneID = paneID; self.item = item; self.commit = commit }
    static func begin(pane: ShellPageViewModel, item: ListedItem, commit: @escaping (String) -> Void) {
        let request = InlineRenameRequest(paneID: pane.id, item: item, commit: commit)
        NotificationCenter.default.post(name: prepare, object: request)
        NotificationCenter.default.post(name: notification, object: request)
        if !request.handled { DispatchQueue.main.async { NotificationCenter.default.post(name: notification, object: request) } }
    }
    static func initialSelection(name: String, directory: Bool) -> NSRange {
        let stem = directory || (name as NSString).pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        return NSRange(location: 0, length: (stem as NSString).length)
    }
}
@MainActor final class RenameableTextField: NSTextField, NSTextFieldDelegate {
    var paneID: UUID?
    var itemURL: URL?
    private var observer: NSObjectProtocol?
    private var request: InlineRenameRequest?
    private var display = ""
    private var oldLines = 1
    var isRenaming: Bool { request != nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false; isSelectable = false; isBezeled = false; drawsBackground = false; delegate = self
        observer = NotificationCenter.default.addObserver(forName: InlineRenameRequest.notification, object: nil, queue: .main) { [weak self] note in
            guard let self, let request = note.object as? InlineRenameRequest, !request.handled, request.paneID == self.paneID, request.item.url == self.itemURL, self.window != nil else { return }
            request.handled = true; self.begin(request)
        }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func configure(display: String, item: ListedItem, paneID: UUID) {
        if itemURL != item.url { finish(commit: false) }
        itemURL = item.url; self.paneID = paneID; self.display = display
        if !isRenaming { stringValue = display }
    }
    private func begin(_ request: InlineRenameRequest) {
        finish(commit: false); self.request = request; oldLines = maximumNumberOfLines
        stringValue = request.item.name; isEditable = true; isSelectable = true; isBezeled = true; drawsBackground = true; maximumNumberOfLines = 1
        backgroundColor = .textBackgroundColor; textColor = .textColor
        window?.makeFirstResponder(self)
        if let editor = currentEditor() { editor.selectedRange = InlineRenameRequest.initialSelection(name: request.item.name, directory: request.item.isDirectory) }
    }
    private func finish(commit: Bool) {
        guard let request else { return }
        let value = stringValue
        if commit {
            do { try MacStorageService.validateName(value) }
            catch { toolTip = error.localizedDescription; NSSound.beep(); return }
        }
        self.request = nil; window?.makeFirstResponder(nil)
        isEditable = false; isSelectable = false; isBezeled = false; drawsBackground = false; maximumNumberOfLines = oldLines; stringValue = display; toolTip = nil
        if commit && value != request.item.name { request.commit(value) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { finish(commit: true); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finish(commit: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { finish(commit: false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finish(commit: false) }; super.viewWillMove(toWindow: newWindow) }
}
struct InlineFileName: NSViewRepresentable {
    let item: ListedItem
    let pane: ShellPageViewModel
    func makeNSView(context: Context) -> RenameableTextField { let field = RenameableTextField(frame: .zero); field.font = ExplorerFont.native(size: 12); field.lineBreakMode = .byTruncatingMiddle; return field }
    func updateNSView(_ field: RenameableTextField, context: Context) { field.configure(display: item.displayName, item: item, paneID: pane.id) }
}
