import XCTest
import FilesStorage
@testable import FilesApp

final class Navigation13Tests: XCTestCase {
    @MainActor func testArchiveHistoryWorksWithoutMountedBrowserAndClearsSearch() {
        let pane = ShellPageViewModel(location: nil)
        pane.openVirtual(.archive(URL(fileURLWithPath: "/tmp/navigation.zip"), ""))
        pane.archiveSession.entries = [ArchiveMember(path: "One/Two/File.txt", size: 10, directory: false, link: false, encrypted: false, modified: .distantPast)]
        XCTAssertTrue(pane.navigateVirtualPath("/One"))
        XCTAssertTrue(pane.navigateVirtualPath("/One/Two"))
        pane.query = "not-a-file"
        pane.selection = [pane.virtualURL("One/Two/File.txt")]
        pane.back()
        XCTAssertEqual(pane.navigationPath, "/One")
        XCTAssertEqual(pane.query, "")
        XCTAssertTrue(pane.selection.isEmpty)
        pane.forward()
        XCTAssertEqual(pane.navigationPath, "/One/Two")
        pane.query = "stale"
        pane.up()
        XCTAssertEqual(pane.navigationPath, "/One")
        XCTAssertEqual(pane.query, "")
        XCTAssertEqual(pane.visibleItems.map(\.name), ["Two"])
    }
    @MainActor func testDisconnectedRemoteAddressDoesNotPretendToNavigate() {
        let pane = ShellPageViewModel(location: nil)
        pane.openVirtual(.network(UUID(), "/"))
        XCTAssertFalse(pane.navigateVirtualPath("/missing"))
        XCTAssertEqual(pane.navigationPath, "/")
    }
}
