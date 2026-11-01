import XCTest
import Foundation
import FilesShared
import FilesStorage
@testable import FilesApp

final class AppStateTests: XCTestCase {
    private var savedSession: [(String, Any?)] = []
    override func setUp() {
        super.setUp()
        savedSession = ["sessionTabs", "sessionTabsV2"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
    }
    override func tearDown() {
        for (key, value) in savedSession { UserDefaults.standard.set(value, forKey: key) }
        super.tearDown()
    }
    @MainActor func testOperationQueueExecutesInOrderAndCancelsQueuedJob() async throws {
        let model = MainPageViewModel(initialLocation: FileManager.default.temporaryDirectory)
        defer { for tab in model.tabs { tab.primary.shutdown(); tab.secondary?.shutdown() } }
        var events: [String] = []
        var gate: CheckedContinuation<Void, Never>?
        model.run("first") {
            events.append("first started")
            await withCheckedContinuation { gate = $0 }
            events.append("first finished")
            return OperationReport()
        }
        for _ in 0..<100 where gate == nil { await Task.yield() }
        XCTAssertNotNil(gate)
        model.run("second") { events.append("second"); return OperationReport() }
        model.run("cancel me") { events.append("should not run"); return OperationReport() }
        XCTAssertEqual(model.queuedCount, 2)
        model.cancelQueued(try XCTUnwrap(model.operationRecords.last?.id))
        XCTAssertEqual(model.queuedCount, 1)
        gate?.resume()
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(events, ["first started", "first finished", "second"])
        XCTAssertEqual(model.operationRecords.map(\.state), ["Completed", "Completed", "Cancelled"])
    }
    @MainActor func testRunningCancellationDoesNotCancelNextQueuedOperation() async throws {
        let model = MainPageViewModel(initialLocation: FileManager.default.temporaryDirectory)
        defer { for tab in model.tabs { tab.primary.shutdown(); tab.secondary?.shutdown() } }
        var started = false; var nextRan = false
        model.run("cancel running") { started = true; try await Task.sleep(for: .seconds(10)); return OperationReport() }
        for _ in 0..<100 where !started { await Task.yield() }
        model.run("next") { try Task.checkCancellation(); nextRan = true; return OperationReport() }
        model.cancelOperation()
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(nextRan)
        XCTAssertEqual(model.operationRecords.map(\.state), ["Cancelled", "Completed"])
    }
    @MainActor func testVirtualCommandsUseTheirPaneHandler() {
        let model = MainPageViewModel(initialLocation: FileManager.default.temporaryDirectory); let url = URL(fileURLWithPath: "/tmp/command-fixture.zip")
        model.openVirtualTab(.archive(url, "")); var commands: [String] = []
        model.activePane.virtualAction = { commands.append($0) }
        XCTAssertTrue(model.canExecute(.new))
        model.executeShortcut("new"); model.executeShortcut("newFile"); model.clearSelection()
        XCTAssertEqual(commands, ["new", "newFile", "clear"])
        model.activePane.shutdown()
    }
    func testSavedSearchPreservesRootsAndAllFilters() throws {
        var options = SearchOptions(); options.name = "report.*"; options.regularExpression = true; options.fileExtension = "txt,pdf"; options.tag = "Work"; options.text = "sample"; options.minimumBytes = 1; options.maximumBytes = 100; options.modifiedAfter = Date(timeIntervalSince1970: 1000); options.hidden = true; options.kind = "Files"
        let saved = SavedSearch(name: "Reports", roots: [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")], options: options)
        let restored = try JSONDecoder().decode(SavedSearch.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.id, saved.id); XCTAssertEqual(restored.roots, saved.roots)
        XCTAssertEqual(restored.options.tag, "Work"); XCTAssertEqual(restored.options.minimumBytes, 1)
        XCTAssertEqual(restored.options.modifiedAfter, options.modifiedAfter); XCTAssertTrue(restored.options.regularExpression)
        XCTAssertTrue(restored.options.hidden); XCTAssertEqual(restored.options.text, "sample")
    }
}
