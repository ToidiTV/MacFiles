import AppKit
import FilesShared

private final class FilesPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
@MainActor private final class FilesPromptController: NSObject, NSTextFieldDelegate {
    let field: NSTextField
    let confirm: NSButton
    var accepted = false
    init(value: String, action: String) {
        field = NSTextField(string: value)
        confirm = NSButton(title: L10n.text(action), target: nil, action: nil)
        super.init()
        field.delegate = self
        confirm.target = self; confirm.action = #selector(accept)
        confirm.isEnabled = !value.isEmpty
    }
    @objc func accept() { guard !field.stringValue.isEmpty else { return }; accepted = true; NSApp.stopModal() }
    @objc func cancel() { NSApp.stopModal() }
    func controlTextDidChange(_ notification: Notification) { confirm.isEnabled = !field.stringValue.isEmpty }
}
@MainActor enum FilesPrompt {
    static func name(_ title: String, value: String, action: String) -> String? {
        let controller = FilesPromptController(value: value, action: action)
        let parent = NSApp.keyWindow
        let panel = FilesPromptPanel(contentRect: NSRect(x: 0, y: 0, width: 488, height: 220), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hasShadow = true; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.title = L10n.text(title); panel.appearance = parent?.effectiveAppearance
        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.wantsLayer = true; content.layer?.cornerRadius = 8; content.layer?.masksToBounds = true
        let dark = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        content.layer?.backgroundColor = (dark ? NSColor(white: 0.125, alpha: 1) : NSColor(white: 0.953, alpha: 1)).cgColor
        content.layer?.borderWidth = 1; content.layer?.borderColor = NSColor.separatorColor.cgColor
        let heading = NSTextField(labelWithString: L10n.text(title)); heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 156, width: 440, height: 44); heading.maximumNumberOfLines = 2; content.addSubview(heading)
        let card = NSView(frame: NSRect(x: 24, y: 92, width: 440, height: 52)); card.wantsLayer = true; card.layer?.cornerRadius = 4
        card.layer?.backgroundColor = (dark ? NSColor(white: 0.153, alpha: 1) : .white).cgColor
        card.layer?.borderColor = NSColor.separatorColor.cgColor; card.layer?.borderWidth = 1
        controller.field.frame = NSRect(x: 12, y: 11, width: 416, height: 30); controller.field.font = .systemFont(ofSize: 14)
        controller.field.bezelStyle = .roundedBezel
        card.addSubview(controller.field); content.addSubview(card)
        let separator = NSBox(frame: NSRect(x: 0, y: 62, width: 488, height: 1)); separator.boxType = .separator; content.addSubview(separator)
        let cancel = NSButton(title: L10n.text("Cancel"), target: controller, action: #selector(FilesPromptController.cancel))
        cancel.bezelStyle = .rounded; cancel.frame = NSRect(x: 368, y: 16, width: 96, height: 32); cancel.keyEquivalent = "\u{1b}"
        controller.confirm.bezelStyle = .rounded; controller.confirm.frame = NSRect(x: 260, y: 16, width: 96, height: 32); controller.confirm.keyEquivalent = "\r"
        content.addSubview(controller.confirm); content.addSubview(cancel)
        content.userInterfaceLayoutDirection = NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight
        panel.contentView = content; panel.initialFirstResponder = controller.field; panel.defaultButtonCell = controller.confirm.cell as? NSButtonCell
        if let parent { panel.setFrameOrigin(NSPoint(x: parent.frame.midX - 244, y: parent.frame.midY - 110)); parent.addChildWindow(panel, ordered: .above) } else { panel.center() }
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(controller.field); controller.field.selectText(nil)
        NSApp.runModal(for: panel)
        let result = controller.accepted ? controller.field.stringValue : nil
        parent?.removeChildWindow(panel); panel.orderOut(nil); parent?.makeKey()
        return result
    }
}
