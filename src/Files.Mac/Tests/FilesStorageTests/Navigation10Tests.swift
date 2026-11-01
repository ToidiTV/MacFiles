import XCTest
import FilesShared
import FilesStorage
@testable import FilesApp

final class Navigation10Tests: XCTestCase {
    @MainActor func testArchiveAddressValidationHistoryAndSearch() throws {
        let pane = ShellPageViewModel(location: nil)
        pane.openVirtual(.archive(URL(fileURLWithPath: "/tmp/navigation-fixture.zip"), ""))
        pane.archiveSession.entries = [ArchiveMember(path: "Nested/Child.txt", size: 17, directory: false, link: false, encrypted: false, modified: .distantPast)]
        XCTAssertTrue(pane.navigateVirtualPath("/Nested"))
        XCTAssertEqual(pane.navigationPath, "/Nested")
        XCTAssertEqual(pane.visibleItems.map(\.name), ["Child.txt"])
        XCTAssertFalse(pane.navigateVirtualPath("/Missing"))
        XCTAssertEqual(pane.navigationPath, "/Nested")
        XCTAssertTrue(pane.navigateVirtualPath("/Nested/../../"))
        XCTAssertEqual(pane.navigationPath, "/")
        pane.archiveSession.step(-1)
        XCTAssertEqual(pane.navigationPath, "/Nested")
        pane.archiveSession.step(1)
        pane.query = "Child"
        XCTAssertEqual(pane.visibleItems.map(\.name), ["Child.txt"])
        pane.query = ""
        XCTAssertEqual(pane.visibleItems.map(\.name), ["Nested"])
        XCTAssertFalse(pane.navigateVirtualPath("relative"))
        XCTAssertFalse(pane.navigateVirtualPath("/bad\0name"))
    }
    @MainActor func testRemoteTypedNavigationAfterBackTruncatesForwardHistory() {
        let session = NetworkBrowserSession()
        session.recordNavigation("/")
        session.recordNavigation("/Folder")
        session.recordNavigation("/", historyIndex: 0)
        session.recordNavigation("/Folder")
        XCTAssertEqual(session.history, ["/", "/Folder"])
        XCTAssertEqual(session.historyIndex, 1)
        session.recordNavigation("/", historyIndex: 0)
        session.recordNavigation("/Other")
        XCTAssertEqual(session.history, ["/", "/Other"])
        XCTAssertEqual(session.historyIndex, 1)
    }
    @MainActor func testRemoteAddressDispatchNormalizesWithinRoot() {
        let pane = ShellPageViewModel(location: nil)
        pane.openVirtual(.network(UUID(), "/"))
        var actions: [String] = []
        pane.virtualAction = { actions.append($0) }
        XCTAssertTrue(pane.navigateVirtualPath("/one/../two words"))
        XCTAssertEqual(actions, ["navigate:/two words"])
        XCTAssertFalse(pane.navigateVirtualPath("ftp://other-host/"))
        XCTAssertEqual(actions.count, 1)
    }
}
