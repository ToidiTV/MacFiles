import XCTest
import AppKit
import FilesShared
@testable import FilesApp

final class InlineRenameTests: XCTestCase {
    @MainActor func testInitialRenameSelectionPreservesExtensionAndUnicode() {
        for (name, directory, expected) in [("Report.txt", false, "Report"), ("archive.tar.gz", false, "archive.tar"), ("Folder.name", true, "Folder.name"), ("Readme", false, "Readme"), ("🗂️ résumé.txt", false, "🗂️ résumé")] {
            let range = InlineRenameRequest.initialSelection(name: name, directory: directory)
            XCTAssertEqual((name as NSString).substring(with: range), expected)
        }
    }
    @MainActor func testInlineRenameCommitCancelAndInvalidName() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try ListedItem(url: url), pane = ShellPageViewModel(location: url.deletingLastPathComponent())
        let field = RenameableTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(field)
        field.configure(display: item.displayName, item: item, paneID: pane.id)
        var names: [String] = []
        InlineRenameRequest.begin(pane: pane, item: item) { names.append($0) }
        XCTAssertTrue(field.isRenaming)
        field.stringValue = "cancelled.txt"
        XCTAssertTrue(field.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertTrue(names.isEmpty); XCTAssertFalse(field.isRenaming)
        InlineRenameRequest.begin(pane: pane, item: item) { names.append($0) }
        field.stringValue = "../invalid"
        _ = field.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(field.isRenaming); XCTAssertTrue(names.isEmpty)
        field.stringValue = "valid.txt"
        _ = field.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(names, ["valid.txt"]); XCTAssertFalse(field.isRenaming)
    }
}
