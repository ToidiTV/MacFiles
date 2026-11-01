import XCTest
import FilesShared
@testable import FilesStorage

final class StorageTests: XCTestCase {
    var root: URL!
    var storage: MacStorageService!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storage = MacStorageService()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func file(_ name: String, text: String = "original") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testCopyConflictKeepsBothContents() async throws {
        let source = try file("notes.txt")
        let destination = try folder("destination")
        try Data("existing".utf8).write(to: destination.appendingPathComponent("notes.txt"))
        let report = await storage.perform(.copy, sources: [source], destination: destination)
        XCTAssertTrue(report.errors.isEmpty); XCTAssertEqual(report.renamedCount, 1)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("notes.txt"), encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("notes (2).txt"), encoding: .utf8), "original")
    }
    func testRecursiveCopyIncludingSymlinkDestinationIsRejected() async throws {
        let parent = try folder("parent")
        let child = try folder("parent/child")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        for destination in [parent, child, link] {
            let result = await storage.perform(.copy, sources: [parent], destination: destination)
            XCTAssertEqual(result.completed.count, 0); XCTAssertEqual(result.errors.count, 1)
        }
    }
    func testCopyRootIntoDescendantIsRejectedBeforeTraversing() async throws {
        let result = await storage.perform(.copy, sources: [URL(fileURLWithPath: "/")], destination: root)
        XCTAssertEqual(result.completed.count, 0); XCTAssertEqual(result.errors.count, 1)
    }
    func testMoveAndUndoRestoreOriginalContents() async throws {
        let source = try file("move.txt")
        let destination = try folder("destination")
        let moved = await storage.perform(.move, sources: [source], destination: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let undo = await storage.undo(moved.undo)
        XCTAssertTrue(undo.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }
    func testUndoDoesNotReplaceNewOriginalAndRetainsFailedStep() async throws {
        let source = try file("move.txt")
        let destination = try folder("destination")
        let moved = await storage.perform(.move, sources: [source], destination: destination)
        try Data("new original".utf8).write(to: source)
        let undo = await storage.undo(moved.undo)
        XCTAssertEqual(undo.errors.count, 1); XCTAssertEqual(undo.undo.count, 1)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new original")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("move.txt"), encoding: .utf8), "original")
    }
    func testNestedSelectionMovesOnlyOnce() async throws {
        let parent = try folder("parent")
        let child = try file("parent/child.txt")
        let destination = try folder("destination")
        let result = await storage.perform(.move, sources: [parent, child, parent], destination: destination)
        XCTAssertEqual(result.completed.count, 1); XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("parent/child.txt").path))
    }
    func testBatchReportsPartialFailureAndPreservesUndo() async throws {
        let source = try file("valid.txt")
        let destination = try folder("destination")
        let result = await storage.perform(.copy, sources: [source, root.appendingPathComponent("missing")], destination: destination)
        XCTAssertEqual(result.completed.count, 1); XCTAssertEqual(result.errors.count, 1); XCTAssertEqual(result.undo.count, 1)
    }
    func testRenameCannotOverwriteExistingOrDanglingLink() async throws {
        let source = try file("original.txt")
        _ = try file("existing.txt", text: "existing")
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("absent"))
        for name in ["existing.txt", "link.txt"] {
            do { _ = try await storage.rename(source, to: name); XCTFail("Overwrote a destination") }
            catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        }
    }
    func testInvalidNamesCannotEscapeDestination() async throws {
        for name in ["", "  ", ".", "..", "../escaped", "a/b", "a:b", "a\0b"] {
            do { _ = try await storage.create(in: root, name: name, directory: true); XCTFail("Accepted \(name)") }
            catch {}
        }
    }
    func testSearchSkipsHiddenAndPackageContents() throws {
        _ = try folder("subfolder"); _ = try folder("Sample.app")
        _ = try file("subfolder/needle.txt"); _ = try file(".needle-hidden"); _ = try file("Sample.app/needle-private")
        let hiddenOff = try MacDirectoryService.search(root, query: "needle", hidden: false)
        XCTAssertEqual(hiddenOff.items.map(\.name), ["needle.txt"])
        let hiddenOn = try MacDirectoryService.search(root, query: "needle", hidden: true)
        XCTAssertEqual(Set(hiddenOn.items.map(\.name)), ["needle.txt", ".needle-hidden"])
    }
    func testMoveWithinSameFolderIsNoOp() async throws {
        let source = try file("keep.txt")
        let result = await storage.perform(.move, sources: [source], destination: root)
        XCTAssertTrue(result.completed.isEmpty); XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testCaseOnlyRenameWorksWithoutLosingContents() async throws {
        let source = try file("camel.txt")
        let result = try await storage.rename(source, to: "Camel.txt")
        XCTAssertEqual(result.completed.first?.lastPathComponent, "Camel.txt")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Camel.txt"), encoding: .utf8), "original")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names, ["Camel.txt"])
        let undo = await storage.undo(result.undo)
        XCTAssertTrue(undo.errors.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["camel.txt"])
    }
    func testUndoDoesNotTrashAReplacementAtTheSamePath() async throws {
        let source = try file("copy.txt")
        let destination = try folder("destination")
        let result = await storage.perform(.copy, sources: [source], destination: destination)
        let copy = destination.appendingPathComponent("copy.txt")
        // Keep the old inode alive so the replacement cannot reuse it.
        try FileManager.default.moveItem(at: copy, to: destination.appendingPathComponent("old-copy.txt"))
        try Data("replacement".utf8).write(to: copy)
        let undo = await storage.undo(result.undo)
        XCTAssertEqual(undo.errors.count, 1); XCTAssertEqual(undo.undo.count, 1)
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "replacement")
    }
    func testNavigationBranchesAndPreservesHome() {
        var history = NavigationHistory()
        let one = root.appendingPathComponent("one"), two = root.appendingPathComponent("two")
        history.visit(one); history.visit(two); history.back()
        XCTAssertEqual(history.current, one); XCTAssertTrue(history.canGoForward)
        history.visit(root); XCTAssertFalse(history.canGoForward)
        history.back(); history.back(); XCTAssertNil(history.current)
        XCTAssertFalse(history.canGoBack)
    }
}
