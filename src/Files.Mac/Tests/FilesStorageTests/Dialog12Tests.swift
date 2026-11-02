import XCTest
import SwiftUI
import AppKit
import FilesStorage
@testable import FilesApp

final class Dialog12Tests: XCTestCase {
    @MainActor func testUpLeavesArchiveRootAndClearsVirtualState() {
        let pane = ShellPageViewModel(location: nil)
        let archive = URL(fileURLWithPath: "/tmp/MacFiles-UI12/Sample.zip")
        pane.openVirtual(.archive(archive, ""))
        pane.up()
        XCTAssertFalse(pane.isVirtual)
        XCTAssertEqual(pane.location, archive.deletingLastPathComponent())
    }
    @MainActor func testDialogRendering() async throws {
        guard let output = ProcessInfo.processInfo.environment["MACFILES_RENDER_DIR"] else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-UI12")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Example.txt")
        try Data("Dialog rendering fixture\n".utf8).write(to: file)
        let model = MainPageViewModel(initialLocation: folder)
        let cases: [(String, ToolKind, CGFloat, CGFloat)] = [
            ("properties", .properties, 1100, 760), ("properties-small", .properties, 860, 560),
            ("network", .network, 1100, 760), ("network-small", .network, 860, 560),
            ("extract", .extract, 1100, 760), ("extract-small", .extract, 860, 560), ("compress", .compress, 1100, 760), ("compress-small", .compress, 860, 560), ("rename", .rename, 1100, 760),
            ("toolbar", .toolbar, 1100, 760)]
        for (name, kind, width, height) in cases {
            model.tool = ToolRequest(kind: kind, urls: [file], directory: folder)
            let view = NSHostingView(rootView: ShellView(model: model).environment(\.colorScheme, .dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(350))
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
            XCTAssertGreaterThan(data.count, 1000)
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        model.tool = nil
    }
}
