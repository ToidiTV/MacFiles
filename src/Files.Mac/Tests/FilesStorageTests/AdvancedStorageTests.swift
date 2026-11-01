import XCTest
import Foundation
import CArchive
import FilesShared
@testable import FilesStorage

final class AdvancedStorageTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-advanced-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ name: String, _ content: String = "hello") throws -> URL {
        let url = root.appendingPathComponent(name); try Data(content.utf8).write(to: url); return url
    }
    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testAllArchiveFormatsRoundTripUnicodeAndHiddenFiles() async throws {
        let source = try folder("Documents")
        _ = try file("Documents/hello ü.txt", "Hello 🌍")
        _ = try file("Documents/.hidden", "secret")
        let out = try folder("output")
        let archive = ArchiveService()
        for format in ArchiveFormat.allCases {
            let target = root.appendingPathComponent("test." + format.extensionName)
            _ = try await archive.compress([source], to: target, format: format)
            let listing = try await archive.list(target)
            XCTAssertTrue(listing.contains { $0.path == "Documents/hello ü.txt" }, "\(format): \(listing.map(\.path))")
            let result = try await archive.extract(target, to: out)
            let extracted = try XCTUnwrap(result.completed.first)
            XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("Documents/hello ü.txt"), encoding: .utf8), "Hello 🌍")
            XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("Documents/.hidden"), encoding: .utf8), "secret")
        }
    }
    func testEncryptedZipRequiresCorrectPassword() async throws {
        let source = try file("private.txt")
        let target = root.appendingPathComponent("private.zip")
        let out = try folder("out")
        let archive = ArchiveService()
        _ = try await archive.compress([source], to: target, format: .zip, password: "test-password")
        do { _ = try await archive.extract(target, to: out, password: "wrong"); XCTFail("Wrong password succeeded") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [])
        let report = try await archive.extract(target, to: out, password: "test-password")
        XCTAssertEqual(try String(contentsOf: report.completed[0].appendingPathComponent("private.txt"), encoding: .utf8), "hello")
    }
    func testArchiveSelectedExtractionAndExistingDestinationPreserved() async throws {
        let one = try file("one.txt"), two = try file("two.txt")
        let target = root.appendingPathComponent("test.zip"), out = try folder("out")
        _ = try folder("out/test"); _ = try file("out/test/keep.txt", "keep")
        let archive = ArchiveService()
        _ = try await archive.compress([one, two], to: target, format: .zip)
        let result = try await archive.extract(target, to: out, selected: ["two.txt"])
        XCTAssertEqual(result.completed[0].lastPathComponent, "test (2)")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: result.completed[0].path), ["two.txt"])
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("test/keep.txt"), encoding: .utf8), "keep")
    }
    func testArchiveTraversalAndEscapingLinksAreRejected() async throws {
        for path in ["../escape", "/tmp/escape", "a/../../escape", "C:/escape", "a\\..\\escape"] {
            XCTAssertThrowsError(try ArchiveService.validatedPath(path))
        }
        let target = root.appendingPathComponent("unsafe.tar")
        let writer = try XCTUnwrap(archive_write_new()); defer { archive_write_free(writer) }
        archive_write_set_format_pax_restricted(writer); archive_write_open_filename(writer, target.path)
        let entry = try XCTUnwrap(archive_entry_new()); defer { archive_entry_free(entry) }
        archive_entry_set_pathname(entry, "../escape.txt"); archive_entry_set_filetype(entry, UInt32(S_IFREG)); archive_entry_set_size(entry, 0)
        XCTAssertEqual(archive_write_header(writer, entry), ARCHIVE_OK); archive_write_close(writer)
        let out = try folder("out")
        do { _ = try await ArchiveService().extract(target, to: out); XCTFail("Traversal extracted") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [])
        let source = try folder("source")
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("escape").path, withDestinationPath: "../../outside")
        let links = root.appendingPathComponent("links.tar")
        _ = try await ArchiveService().compress([source], to: links, format: .tar)
        do { _ = try await ArchiveService().extract(links, to: out); XCTFail("Escaping symlink extracted") } catch {}
    }
    func testBulkRenameSwapAndUndoRedoPreserveContents() async throws {
        let a = try file("a.txt", "A"), b = try file("b.txt", "B")
        let storage = MacStorageService()
        let report = try await storage.bulkRename([RenameProposal(source: a, name: "b.txt"), RenameProposal(source: b, name: "a.txt")])
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "B")
        let undo = await storage.undo(report.undo)
        XCTAssertTrue(undo.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "A")
        let redo = await storage.undo(undo.inverse)
        XCTAssertTrue(redo.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "A")
    }
    func testBulkRenamePreflightIsAllOrNothing() async throws {
        let a = try file("a.txt", "A"), b = try file("b.txt", "B")
        _ = try file("taken.txt", "existing")
        do { _ = try await MacStorageService().bulkRename([RenameProposal(source: a, name: "new.txt"), RenameProposal(source: b, name: "taken.txt")]); XCTFail("Collision accepted") } catch {}
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "A")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
    }
    func testHashKnownVectorAndPermissions() throws {
        let url = try file("hash.txt", "abc")
        let hashes = try MetadataService.hashes(url)
        XCTAssertEqual(hashes.md5, "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(hashes.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try MetadataService.setPermissions("640", for: [url])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertThrowsError(try MetadataService.setPermissions("999", for: [url]))
    }
    func testGitStatusStageCommitBranchDiffAndUnstage() async throws {
        let git = GitService()
        _ = try await git.operation("Initialize", at: root)
        _ = try await ProcessService.run("/usr/bin/git", ["-C", root.path, "config", "user.name", "MacFiles Test"])
        _ = try await ProcessService.run("/usr/bin/git", ["-C", root.path, "config", "user.email", "test@example.invalid"])
        _ = try file("space ü.txt", "first\n")
        let initial = try await git.inspect(root)
        XCTAssertEqual(initial.changes.map(\.path), ["space ü.txt"])
        try await git.stage(["space ü.txt"], at: root)
        try await git.commit("Initial fixture", at: root)
        let main = try await git.inspect(root)
        XCTAssertTrue(main.changes.isEmpty)
        try await git.switchBranch("feature/test", at: root, create: true)
        _ = try file("space ü.txt", "second\n")
        let diff = try await git.diff("space ü.txt", at: root)
        XCTAssertTrue(diff.contains("+second"))
        try await git.stage(["space ü.txt"], at: root)
        try await git.unstage(["space ü.txt"], at: root)
        let changed = try await git.inspect(root)
        XCTAssertEqual(changed.changes.first?.worktree, "M")
        try await git.switchBranch(main.branch, at: root, create: false)
    }
    func testRemoteListingParsesSpacesAndRejectsCommandInjection() throws {
        let list = RemoteProvider.parseMLSD("type=dir;modify=20261031190000; Folder with spaces\r\ntype=file;size=42; a ü.txt\r\ntype=cdir; .\r\n")
        XCTAssertEqual(list.map(\.name), ["Folder with spaces", "a ü.txt"])
        XCTAssertEqual(list.last?.size, 42)
        let unix = RemoteProvider.parseUnixList("-rw-r--r-- 1 501 20 19 Oct 31 19:00 hello world.txt\n")
        XCTAssertEqual(unix.first?.name, "hello world.txt")
        XCTAssertThrowsError(try RemoteProvider.child("/", "x\nDELE /file"))
        XCTAssertThrowsError(try RemoteProvider.child("/", "../outside"))
    }
    func testFTPProviderRoundTripAgainstLoopbackServer() async throws {
        let serverRoot = try folder("server"), local = try folder("local")
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "ftp_server", withExtension: "py", subdirectory: "Fixtures"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-u", fixture.path, serverRoot.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); defer { process.terminate(); process.waitUntilExit() }
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty { if byte[0] == 10 { break }; line.append(byte) }
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self)))
        let provider = RemoteProvider(connection: RemoteConnection(name: "Test", kind: .ftp, host: "127.0.0.1", port: port, username: "test"), password: "test")
        let source = try file("upload ü.txt", "remote round trip")
        try await provider.mkdir("Remote folder", in: "/")
        try await provider.upload(source, to: "/Remote folder")
        let listing = try await provider.list("/Remote folder")
        XCTAssertEqual(listing.map(\.name), ["upload ü.txt"])
        let downloaded = try await provider.download(listing[0], from: "/Remote folder", to: local)
        XCTAssertEqual(try String(contentsOf: downloaded, encoding: .utf8), "remote round trip")
        try await provider.rename(listing[0], to: "renamed.txt", in: "/Remote folder")
        let renamed = try await provider.list("/Remote folder")
        XCTAssertEqual(renamed.first?.name, "renamed.txt")
        try await provider.delete(renamed[0], in: "/Remote folder")
        let empty = try await provider.list("/Remote folder")
        XCTAssertTrue(empty.isEmpty)
        let initial = try await provider.uploadWithConflicts(source, to: "/Remote folder", conflict: .keepBoth)
        XCTAssertEqual(initial.undo.count, 1)
        try Data("replacement".utf8).write(to: source)
        let replacement = try await provider.uploadWithConflicts(source, to: "/Remote folder", conflict: .replace, verifyContents: true)
        XCTAssertEqual(replacement.undo.count, 2)
        let inverse = try await provider.undoRemote(replacement.undo)
        let restored = try String(contentsOf: serverRoot.appendingPathComponent("Remote folder/upload ü.txt")); XCTAssertEqual(restored, "remote round trip")
        _ = try await provider.undoRemote(inverse)
        XCTAssertEqual(try String(contentsOf: serverRoot.appendingPathComponent("Remote folder/upload ü.txt")), "replacement")
        let remoteItems = try await provider.list("/Remote folder")
        let fileItem = try XCTUnwrap(remoteItems.first { $0.name == source.lastPathComponent })
        let recovery = try await provider.trash(fileItem, in: "/Remote folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: serverRoot.appendingPathComponent("Remote folder/upload ü.txt").path))
        _ = try await provider.undoRemote(recovery.undo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: serverRoot.appendingPathComponent("Remote folder/upload ü.txt").path))

    }

    func testExtendedAttributesRoundTripBinaryAndRemoval() throws {
        let url = try file("attributes.txt")
        let value = Data([0, 1, 255, 8, 42])
        try ExtendedAttributes.write("com.macfiles.test", data: value, to: url)
        XCTAssertEqual(try ExtendedAttributes.list(url).first { $0.name == "com.macfiles.test" }?.data, value)
        try ExtendedAttributes.remove("com.macfiles.test", from: url)
        XCTAssertFalse(try ExtendedAttributes.list(url).contains { $0.name == "com.macfiles.test" })
        XCTAssertThrowsError(try ExtendedAttributes.write("bad\0name", data: value, to: url))
    }
    func testAdvancedSearchCombinesFiltersAndCountsSkippedContent() throws {
        _ = try folder("nested")
        _ = try file("nested/Match ü.txt", "needle in a document")
        _ = try file("nested/Match.swift", "other text")
        _ = try file("nested/.Match.txt", "needle hidden")
        _ = try file("nested/unrelated.txt", "needle")
        _ = try file("nested/Match.bin", "binary")
        try Data([0, 255, 0]).write(to: root.appendingPathComponent("nested/Match.bin"))
        var options = SearchOptions(); options.name = "^Match"; options.regularExpression = true; options.text = "needle"; options.fileExtension = "txt"
        let result = try SearchService.search([root, root], options: options)
        XCTAssertEqual(result.items.map(\.name), ["Match ü.txt"])
        options.minimumBytes = 1000
        XCTAssertTrue(try SearchService.search([root], options: options).items.isEmpty)
        options.minimumBytes = nil; options.fileExtension = ""; options.name = "Match"; options.hidden = true
        XCTAssertEqual(try SearchService.search([root], options: options).items.count, 2)
        XCTAssertEqual(try SearchService.search([root], options: options).skipped, 1)
        options.name = "["
        XCTAssertThrowsError(try SearchService.search([root], options: options))
    }
    func testArchiveVirtualFoldersAndFolderExtraction() async throws {
        let child = try folder("parent/child")
        _ = try file("parent/child/file.txt")
        let target = root.appendingPathComponent("nested.zip")
        let archive = ArchiveService()
        _ = try await archive.compress([child.deletingLastPathComponent()], to: target, format: .zip)
        let entries = try await archive.list(target)
        XCTAssertEqual(ArchiveMember.children(of: "", in: entries).map(\.path), ["parent/"])
        XCTAssertEqual(ArchiveMember.children(of: "parent/", in: entries).map(\.path), ["parent/child/"])
        let output = try folder("out")
        let report = try await archive.extract(target, to: output, selected: ["parent/child/"])
        XCTAssertEqual(try String(contentsOf: report.completed[0].appendingPathComponent("parent/child/file.txt")), "hello")
    }
    func testLibraryListingAndSessionRestoresSplitPaneMetadata() throws {
        let a = try folder("a"), b = try folder("b")
        _ = try file("a/one.txt"); _ = try file("b/two.txt")
        let result = try MacDirectoryService.listLocations([a, b, a], query: nil, hidden: false)
        XCTAssertEqual(Set(result.items.map(\.name)), ["one.txt", "two.txt"])
        let library = FolderLibrary(name: "Documents", folders: [a, b])
        let pane = PaneSnapshot(location: a, layout: .columns, sort: .modified, ascending: false, library: library)
        let tab = TabSnapshot(primary: pane, secondary: PaneSnapshot(location: b, layout: .gallery, sort: .size, ascending: true))
        let restored = try JSONDecoder().decode(TabSnapshot.self, from: JSONEncoder().encode(tab))
        XCTAssertEqual(restored.primary.library?.folders, [a, b]); XCTAssertEqual(restored.primary.layout, .columns)
        XCTAssertEqual(restored.secondary?.location, b); XCTAssertEqual(restored.secondary?.sort, .size)
        XCTAssertFalse(restored.primary.ascending)
        let old = Data("{\"layout\":\"Details\",\"sort\":\"Name\",\"ascending\":true}".utf8)
        XCTAssertNil(try JSONDecoder().decode(PaneSnapshot.self, from: old).library)
    }
    func testAliasCreationPreservesDestinationAndResolvesTarget() async throws {
        let target = try file("target.txt", "alias target")
        let storage = MacStorageService()
        let report = try await storage.createAlias(target, in: root, name: "target alias")
        let alias = try XCTUnwrap(report.completed.first)
        XCTAssertEqual(try URL(resolvingAliasFileAt: alias).resolvingSymlinksInPath(), target.resolvingSymlinksInPath())
        do { _ = try await storage.createAlias(target, in: root, name: "target alias"); XCTFail("Alias overwrote existing file") } catch {}
        XCTAssertEqual(try String(contentsOf: target), "alias target")
    }

    func testReplacingCopyAndMoveUndoRedoPreservesBothVersions() async throws {
        let storage = MacStorageService()
        for operation in [FileOperation.copy, .move] {
            let sourceFolder = try folder("source-" + operation.rawValue), destination = try folder("destination-" + operation.rawValue)
            let source = sourceFolder.appendingPathComponent("item.txt"), target = destination.appendingPathComponent("item.txt")
            try Data("new".utf8).write(to: source); try Data("old".utf8).write(to: target)
            let result = await storage.perform(operation, sources: [source], destination: destination, conflict: .replace)
            XCTAssertTrue(result.errors.isEmpty); XCTAssertEqual(try String(contentsOf: target), "new")
            let undo = await storage.undo(result.undo)
            XCTAssertTrue(undo.errors.isEmpty); XCTAssertEqual(try String(contentsOf: target), "old"); XCTAssertEqual(try String(contentsOf: source), "new")
            let redo = await storage.undo(undo.inverse)
            XCTAssertTrue(redo.errors.isEmpty); XCTAssertEqual(try String(contentsOf: target), "new")
            let restored = await storage.undo(redo.inverse)
            XCTAssertTrue(restored.errors.isEmpty)
            // Remove only the disposable fixture copies that Undo placed in Trash.
            for step in restored.inverse { if case .move(let from, _, _) = step, from.path.contains("/.Trash/") { try? FileManager.default.removeItem(at: from) } }
        }
    }
    func testSkipConflictAndFailedCopyLeavesNoPartialDestination() async throws {
        let source = try file("item.txt", "new"), destination = try folder("destination")
        let target = destination.appendingPathComponent("item.txt"); try Data("old".utf8).write(to: target)
        let storage = MacStorageService()
        let skipped = await storage.perform(.copy, sources: [source], destination: destination, conflict: .skip)
        XCTAssertTrue(skipped.completed.isEmpty); XCTAssertEqual(try String(contentsOf: target), "old")
        let missing = root.appendingPathComponent("missing.txt")
        let failed = await storage.perform(.copy, sources: [missing], destination: destination, conflict: .replace)
        XCTAssertFalse(failed.errors.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["item.txt"])
    }

    func testFlattenSkipsConflictsAndLinksAndCanUndoHierarchy() async throws {
        let source = try folder("source/a/b")
        let rootFolder = root.appendingPathComponent("source")
        _ = try file("source/a/b/nested.txt", "nested"); _ = try file("source/a/b/conflict.txt", "child"); _ = try file("source/conflict.txt", "root")
        let outside = try folder("outside"); _ = try file("outside/untouched.txt")
        try FileManager.default.createSymbolicLink(at: rootFolder.appendingPathComponent("linked"), withDestinationURL: outside)
        let storage = MacStorageService()
        let report = try await storage.flatten(rootFolder)
        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: rootFolder.appendingPathComponent("nested.txt")), "nested")
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("conflict.txt")), "child")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("untouched.txt").path))
        let undo = await storage.undo(report.undo)
        XCTAssertTrue(undo.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("nested.txt")), "nested")
    }
    func testTemplateAndGroupingPreserveFileContentsAndSelectionIdentities() async throws {
        let template = try file("sample.txt", "template contents")
        let report = try await MacStorageService().createFromTemplate(template, in: root, name: "created.txt")
        XCTAssertEqual(try String(contentsOf: report.completed[0]), "template contents")
        do { _ = try await MacStorageService().createFromTemplate(template, in: root, name: "created.txt"); XCTFail("Template overwrote destination") } catch {}
        let folder = try folder("folder")
        let items = try [template, folder, report.completed[0]].map { try ListedItem(url: $0) }
        let groups = ItemGrouping.groups(items, by: .kind)
        XCTAssertEqual(Set(groups.flatMap(\.items).map(\.url)), Set(items.map(\.url)))
        XCTAssertEqual(groups.first { $0.title == "Folders" }?.items.map(\.url), [folder.standardizedFileURL])
        XCTAssertEqual(ItemGrouping.groups(items, by: .none).count, 1)
    }

    func testSFTPServerListingAndUnsupportedFormats() async throws {
        let directory = try folder("remote folder")
        _ = try file("remote folder/sample ü.txt")
        let commands = "cd \"\(directory.path)\"\nls -ln\n"
        let output = try await ProcessService.run("/usr/bin/sftp", ["-D", "/usr/libexec/sftp-server", "-b", "-"], input: Data(commands.utf8))
        let listing = try RemoteProvider.checkedListing(output.output, mlsd: false, sftp: true)
        XCTAssertEqual(listing.map(\.name), ["sample ü.txt"])
        XCTAssertThrowsError(try RemoteProvider.checkedListing("10-31-26  12:00PM <DIR> Windows listing", mlsd: false))
        XCTAssertThrowsError(try RemoteProvider.checkedListing("type=file;size=1; okay.txt\ninvalid entry", mlsd: true))
        XCTAssertEqual(try RemoteProvider.checkedListing("sftp> ls -ln\ntotal 0\n", mlsd: false, sftp: true).count, 0)
    }

}
