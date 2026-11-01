import XCTest
import FilesShared
import FilesStorage
@testable import FilesApp

final class AuditParityTests: XCTestCase {
    @MainActor func testFilesFirstPathSortAndPreferenceRestoration() throws {
        let settings = SettingsService.shared
        let foldersFirst = settings.foldersFirst; let filesFirst = settings.filesFirst
        defer { settings.foldersFirst = foldersFirst; settings.filesFirst = filesFirst }
        let pane = ShellPageViewModel(); defer { pane.shutdown() }
        let folder = ListedItem(virtualURL: URL(string: "macfiles-archive://test/a-folder")!, name: "a-folder", directory: true, size: 0)
        let first = ListedItem(virtualURL: URL(string: "macfiles-archive://test/a/z.txt")!, name: "z.txt", directory: false, size: 2)
        let second = ListedItem(virtualURL: URL(string: "macfiles-archive://test/z/a.txt")!, name: "a.txt", directory: false, size: 1)
        settings.foldersFirst = false; settings.filesFirst = true; pane.sort = .path
        XCTAssertEqual(pane.orderedItems([folder, second, first]).map(\.name), ["z.txt", "a.txt", "a-folder"])
        pane.ascending = false
        XCTAssertEqual(pane.orderedItems([folder, second, first]).map(\.name), ["a.txt", "z.txt", "a-folder"])
        settings.filesFirst = false; settings.foldersFirst = true
        XCTAssertEqual(pane.orderedItems([first, folder, second]).first?.name, "a-folder")
        for sort in [SortField.created, .tags, .cloud] {
            pane.sort = sort
            XCTAssertEqual(Set(pane.orderedItems([first, folder, second]).map(\.name)), ["z.txt", "a.txt", "a-folder"])
        }
    }
    func testQuotedPathsRoundTripThroughPOSIXShellWithoutExpansion() async throws {
        for path in ["/tmp/a'b", "/tmp/$(printf expanded)", "/tmp/a\nb", "/tmp/日本語 file"] {
            let quoted = ClipboardPaths.format([path], quoted: true)
            let output = try await ProcessService.run("/bin/sh", ["-c", "printf '%s' " + quoted])
            XCTAssertEqual(output.output, path)
        }
    }
    @MainActor func testExplicitFolderWindowDoesNotRestoreUnrelatedTabs() throws {
        let defaults = UserDefaults.standard
        let saved = ["sessionTabs", "sessionTabsV2"].map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }
        defaults.set(["/tmp/unrelated", "/tmp/another"], forKey: "sessionTabs")
        let target = FileManager.default.temporaryDirectory
        let model = MainPageViewModel(initialLocation: target)
        defer { for tab in model.tabs { tab.primary.shutdown(); tab.secondary?.shutdown() } }
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.activePane.location?.standardizedFileURL, target.standardizedFileURL)
    }
    func testGroupingDirectionDatesAndLegacyPresentation() throws {
        let january = Date(timeIntervalSince1970: 1705320000)
        let february = Date(timeIntervalSince1970: 1707998400)
        let a = ListedItem(virtualURL: URL(string: "test://a")!, name: "a", directory: false, size: 1, modified: january)
        let b = ListedItem(virtualURL: URL(string: "test://b")!, name: "b", directory: false, size: 1, modified: february)
        let groups = ItemGrouping.groups([a,b], by: .modified, ascending: false, dateUnit: .month)
        XCTAssertEqual(groups.map(\.title), ["2024-02", "2024-01"])
        XCTAssertEqual(ItemGrouping.groups([a,b], by: .modified, dateUnit: .year).count, 1)
        let legacy = Data(#"{"layout":"Details","sort":"Name","ascending":true}"#.utf8)
        let value = try JSONDecoder().decode(FolderPresentation.self, from: legacy)
        XCTAssertNil(value.groupAscending)
        let saved = FolderPresentation(layout: .details, sort: .name, ascending: true, group: .modified, groupAscending: false, groupDateUnit: .month)
        let restored = try JSONDecoder().decode(FolderPresentation.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.groupAscending, false); XCTAssertEqual(restored.groupDateUnit, .month)
    }
    func testGitSyncPullsAndDoesNotPushAfterDivergence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String], _ directory: URL) async throws -> String {
            try await ProcessService.run("/usr/bin/git", ["-C", directory.path] + args,
                environment: ["GIT_CONFIG_NOSYSTEM":"1", "GIT_CONFIG_GLOBAL":"/dev/null", "GIT_AUTHOR_NAME":"Fixture", "GIT_AUTHOR_EMAIL":"fixture@example.invalid", "GIT_COMMITTER_NAME":"Fixture", "GIT_COMMITTER_EMAIL":"fixture@example.invalid"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let remote = root.appendingPathComponent("remote.git"), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        _ = try await git(["init", "--bare", remote.path], root)
        _ = try await git(["clone", remote.path, a.path], root)
        _ = try await git(["commit", "--allow-empty", "-m", "initial"], a)
        _ = try await git(["push", "-u", "origin", "HEAD"], a)
        _ = try await git(["clone", remote.path, b.path], root)
        _ = try await git(["commit", "--allow-empty", "-m", "remote advancement"], b)
        _ = try await git(["push"], b)
        _ = try await GitService().operation("Sync", at: a)
        let synced = try await git(["rev-parse", "HEAD"], a)
        let expected = try await git(["rev-parse", "HEAD"], b)
        XCTAssertEqual(synced, expected)
        _ = try await git(["commit", "--allow-empty", "-m", "local divergence"], a)
        _ = try await git(["commit", "--allow-empty", "-m", "remote divergence"], b)
        _ = try await git(["push"], b)
        let before = try await git(["rev-parse", "HEAD"], remote)
        do { _ = try await GitService().operation("Sync", at: a); XCTFail("Divergent histories must not be pushed") } catch {}
        let after = try await git(["rev-parse", "HEAD"], remote)
        XCTAssertEqual(before, after)
    }

}
