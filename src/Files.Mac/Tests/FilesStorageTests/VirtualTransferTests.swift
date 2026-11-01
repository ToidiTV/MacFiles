import XCTest
import AppKit
import FilesShared
@testable import FilesStorage
@testable import FilesApp

final class VirtualTransferTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-virtual-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func fixture() async throws -> (URL, ArchiveMember) {
        let source = root.appendingPathComponent("hello.txt"); try Data("virtual fixture".utf8).write(to: source)
        let archive = root.appendingPathComponent("sample.zip"); _ = try await ArchiveService().compress([source], to: archive, format: .zip)
        let members = try await ArchiveService().list(archive)
        return (archive, try XCTUnwrap(members.first))
    }
    @MainActor func testVirtualCutPreservesChangedSource() async throws {
        let source = root.appendingPathComponent("source.txt"); try Data("before".utf8).write(to: source)
        let reference = VirtualFileReference(item: try ListedItem(url: source), origin: .local(source))
        let receipt = TransferCutReceipt(references: [reference], fingerprints: [try TransferFingerprint.digest(source)])
        try Data("changed".utf8).write(to: source)
        let result = await receipt.consume(); XCTAssertFalse(result.errors.isEmpty); XCTAssertEqual(try String(contentsOf: source), "changed")
    }
    @MainActor func testArchiveCutAndUndoRestoreSourceAndDestination() async throws {
        let (archive, member) = try await fixture(); let pane = ShellPageViewModel(); pane.openVirtual(.archive(archive, "")); pane.archiveSession.entries = [member]
        let item = try XCTUnwrap(pane.visibleItems.first); let reference = try XCTUnwrap(pane.reference(item))
        let cache = root.appendingPathComponent("cache"); try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let staged = try await reference.materialize(in: cache)
        let receipt = TransferCutReceipt(references: [reference], fingerprints: [try TransferFingerprint.digest(staged)])
        let destination = root.appendingPathComponent("destination"); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let copy = await MacStorageService.shared.perform(.copy, sources: [staged], destination: destination)
        let removal = await receipt.consume(); XCTAssertTrue(removal.errors.isEmpty)
        let entries = try await ArchiveService().list(archive); XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent(item.name)), "virtual fixture")
        let undo = await MacStorageService.shared.undo([.compound(copy.undo + removal.undo)])
        XCTAssertTrue(undo.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(item.name).path))
        let restored = try await ArchiveService().list(archive); XCTAssertEqual(restored.map(\.path), [member.path]); cleanup(undo.inverse); pane.shutdown()
    }
    @MainActor func testFilePromiseUsesReceiverDestinationAndSurvivesPaneClose() async throws {
        let (archive, member) = try await fixture(); let pane = ShellPageViewModel(); pane.openVirtual(.archive(archive, "")); pane.archiveSession.entries = [member]
        let promise = try XCTUnwrap(FileDrag.writer(try XCTUnwrap(pane.visibleItems.first), pane: pane) as? NSFilePromiseProvider)
        pane.shutdown()
        let target = root.appendingPathComponent("receiver-renamed.txt")
        let complete = expectation(description: "File promise completed")
        promise.delegate?.filePromiseProvider(promise, writePromiseTo: target) { error in XCTAssertNil(error); complete.fulfill() }
        await fulfillment(of: [complete], timeout: 10)
        XCTAssertEqual(try String(contentsOf: target), "virtual fixture")
        let collision = expectation(description: "Collision kept")
        promise.delegate?.filePromiseProvider(promise, writePromiseTo: target) { error in XCTAssertNotNil(error); collision.fulfill() }
        await fulfillment(of: [collision], timeout: 10)
        XCTAssertEqual(try String(contentsOf: target), "virtual fixture")
    }
    func testCompoundUndoStopsBeforeDeletingDestinationWhenRemoteRecoveryFails() async throws {
        let file = root.appendingPathComponent("only-local-copy.txt"); try Data("retained".utf8).write(to: file)
        let steps: [UndoStep] = [.compound([.trash(file, identity: FileIdentity(file)), .remote(UUID(), [])])]
        let decoded = try JSONDecoder().decode([UndoStep].self, from: JSONEncoder().encode(steps))
        let result = await MacStorageService.shared.undo(decoded)
        XCTAssertFalse(result.errors.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)); XCTAssertFalse(result.undo.isEmpty)
    }
    @MainActor func testVirtualItemsUseAllSharedLayoutsAndSelection() async throws {
        let (archive, member) = try await fixture(); let pane = ShellPageViewModel(); pane.openVirtual(.archive(archive, "")); pane.archiveSession.entries = [member]
        for layout in LayoutMode.allCases {
            pane.layout = layout; pane.selection = Set(pane.visibleItems.map(\.url)); pane.synchronizeVirtualSelection()
            XCTAssertEqual(pane.selectedItems.map(\.name), ["hello.txt"]); XCTAssertEqual(pane.archiveSession.selected, ["hello.txt"])
            XCTAssertFalse(try XCTUnwrap(pane.selectedItems.first).url.isFileURL)
        }
        let directory = ArchiveMember(path: "nested/", size: 0, directory: true, link: false, encrypted: false, modified: .distantPast)
        pane.archiveSession.entries += [directory, ArchiveMember(path: "nested/child.txt", size: 1, directory: false, link: false, encrypted: false, modified: .distantPast)]
        let folder = try XCTUnwrap(pane.visibleItems.first { $0.isDirectory }); let children = try await pane.children(folder)
        XCTAssertEqual(children.map(\.name), ["child.txt"]); pane.shutdown()
    }
    func testArchivePermissionsRebuildAndUndo() async throws {
        let (archive, member) = try await fixture()
        let old = try Data(contentsOf: archive)
        let result = try await ArchiveService().edit(archive, change: .permissions([member.path], 0o751))
        let entries = try await ArchiveService().list(archive); XCTAssertEqual(entries.first?.posixPermissions, 0o751)
        let undo = await MacStorageService.shared.undo(result.undo); XCTAssertEqual(try Data(contentsOf: archive), old); cleanup(undo.inverse)
    }
    private func cleanup(_ steps: [UndoStep]) {
        for step in steps {
            if case .compound(let children) = step { cleanup(children) }
            if case .move(let from, _, _) = step, from.path.contains("/.Trash/") { try? FileManager.default.removeItem(at: from) }
        }
    }
}

extension VirtualTransferTests {
    func testRemoteListingPreservesArrowNamesAndLinkMetadata() throws {
        let entries = RemoteProvider.parseUnixList("-rwxr-x--- 1 501 20 12 Oct 31 19:00 before -> after.txt\nlrwxrwxrwx 1 502 21 10 Oct 31 19:00 shortcut -> target.txt\n")
        XCTAssertEqual(entries.map(\.name), ["before -> after.txt", "shortcut"])
        XCTAssertNil(entries[0].linkTarget); XCTAssertEqual(entries[0].permissions, "750")
        XCTAssertEqual(entries[1].linkTarget, "target.txt"); XCTAssertEqual(entries[1].owner, "502"); XCTAssertEqual(entries[1].group, "21")
    }
    @MainActor func testCutPayloadMutationIsRejected() async throws {
        let source = root.appendingPathComponent("source.txt"); try Data("original".utf8).write(to: source)
        let item = try ListedItem(url: source)
        let receipt = TransferCutReceipt(references: [.init(item: item, origin: .local(source))], fingerprints: [try TransferFingerprint.digest(source)])
        let staged = root.appendingPathComponent("staged.txt"); try Data("different".utf8).write(to: staged)
        do { try await receipt.validatePayload([staged]); XCTFail("Changed payload accepted") } catch {}
        XCTAssertEqual(try String(contentsOf: source), "original")
    }
    func testArchivePasteConflictsKeepBothAndSkip() async throws {
        let (archive, _) = try await fixture(); let source = root.appendingPathComponent("hello.txt")
        let skipped = try await ArchiveService().edit(archive, change: .add([source], prefix: "", conflict: .skip))
        XCTAssertTrue(skipped.completed.isEmpty)
        let added = try await ArchiveService().edit(archive, change: .add([source], prefix: ""))
        XCTAssertEqual(added.completed, [source])
        let entries = try await ArchiveService().list(archive); XCTAssertEqual(Set(entries.map(\.path)), ["hello.txt", "hello (2).txt"])
        let undo = await MacStorageService.shared.undo(added.undo); cleanup(undo.inverse)
        let first = await MacStorageService.shared.undo(skipped.undo); cleanup(first.inverse)
    }
    @MainActor func testRemoteCutAndCompoundUndoRestoreSource() async throws {
        let server = root.appendingPathComponent("server"), cache = root.appendingPathComponent("cache"), destination = root.appendingPathComponent("destination")
        for folder in [server, cache, destination] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data("remote source".utf8).write(to: server.appendingPathComponent("remote.txt"))
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "ftp_server", withExtension: "py", subdirectory: "Fixtures"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-u", fixture.path, server.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); defer { if process.isRunning { process.terminate() } }
        var line = Data(); while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty { if byte[0] == 10 { break }; line.append(byte) }
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self)))
        let connection = RemoteConnection(name: "Fixture", kind: .ftp, host: "127.0.0.1", port: port, username: "test")
        let provider = RemoteProvider(connection: connection, password: "test")
        let listed = try await provider.list("/"); let remote = try XCTUnwrap(listed.first)
        let item = ListedItem(virtualURL: URL(string: "macfiles-remote://fixture/remote.txt")!, name: remote.name, directory: false, size: remote.size)
        let reference = VirtualFileReference(item: item, origin: .remote(provider, connection, "/", remote))
        let staged = try await reference.materialize(in: cache)
        let receipt = TransferCutReceipt(references: [reference], fingerprints: [try TransferFingerprint.digest(staged)])
        let copy = await MacStorageService.shared.perform(.copy, sources: [staged], destination: destination)
        let removal = await receipt.consume(); XCTAssertTrue(removal.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: server.appendingPathComponent("remote.txt").path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("remote.txt")), "remote source")
        let undo = await MacStorageService.shared.undo([.compound(copy.undo + removal.undo)])
        XCTAssertTrue(undo.errors.isEmpty); XCTAssertEqual(try String(contentsOf: server.appendingPathComponent("remote.txt")), "remote source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("remote.txt").path)); cleanup(undo.inverse)
    }
}

extension VirtualTransferTests {
    func testRemoteUndoEndpointSurvivesRestartWithoutPersistingCredentials() async throws {
        let suite = "MacFiles-remote-undo-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let connection = RemoteConnection(name: "Fixture", kind: .ftp, host: "localhost", port: 21, username: "fixture")
        let provider = RemoteProvider(connection: connection, password: "secret-never-in-journal")
        let registry = RemoteUndoRegistry(defaults: defaults); let id = await registry.register(provider)
        let data = try XCTUnwrap(defaults.data(forKey: "remoteUndoEndpointsV1"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret-never-in-journal"))
        let restarted = RemoteUndoRegistry(defaults: defaults)
        let reconnected = RemoteConnection(name: "New session", kind: .ftp, host: "localhost", port: 21, username: "fixture")
        let restoredID = await restarted.register(RemoteProvider(connection: reconnected, password: "new-password"))
        XCTAssertEqual(restoredID, id)
        let otherAccount = RemoteConnection(name: "Other", kind: .ftp, host: "localhost", port: 21, username: "other")
        let otherID = await restarted.register(RemoteProvider(connection: otherAccount)); XCTAssertNotEqual(otherID, id)
    }
}

extension VirtualTransferTests {
    @MainActor func testCutDoesNotDeleteAReplacementWithIdenticalBytes() async throws {
        let source = root.appendingPathComponent("source.txt"); try Data("same bytes".utf8).write(to: source)
        let reference = VirtualFileReference(item: try ListedItem(url: source), origin: .local(source))
        let receipt = TransferCutReceipt(references: [reference], fingerprints: [try TransferFingerprint.digest(source)])
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("old-source.txt"))
        try Data("same bytes".utf8).write(to: source)
        let report = await receipt.consume()
        XCTAssertFalse(report.errors.isEmpty); XCTAssertEqual(try String(contentsOf: source), "same bytes"); XCTAssertFalse(receipt.pending)
    }
    @MainActor func testDirectoryFilePromisePreservesNestedContents() async throws {
        let source = root.appendingPathComponent("Folder"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("nested promise".utf8).write(to: source.appendingPathComponent("ü.txt"))
        let archive = root.appendingPathComponent("folder.zip"); _ = try await ArchiveService().compress([source], to: archive, format: .zip)
        let pane = ShellPageViewModel(); pane.openVirtual(.archive(archive, "")); pane.archiveSession.entries = try await ArchiveService().list(archive)
        let folder = try XCTUnwrap(pane.visibleItems.first { $0.isDirectory })
        let promise = try XCTUnwrap(FileDrag.writer(folder, pane: pane) as? NSFilePromiseProvider); pane.shutdown()
        let destination = root.appendingPathComponent("Delivered folder")
        let complete = expectation(description: "Folder promise completed")
        promise.delegate?.filePromiseProvider(promise, writePromiseTo: destination) { error in XCTAssertNil(error); complete.fulfill() }
        await fulfillment(of: [complete], timeout: 10)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("ü.txt")), "nested promise")
    }
}

extension VirtualTransferTests {
    @MainActor func testMoveIntoArchiveVerifiesDestinationAndUndoesBothSides() async throws {
        let (archive, _) = try await fixture(); let oldArchive = try Data(contentsOf: archive)
        let source = root.appendingPathComponent("move-me.txt"); try Data("verified archive transfer".utf8).write(to: source)
        let reference = VirtualFileReference(item: try ListedItem(url: source), origin: .local(source))
        let receipt = TransferCutReceipt(references: [reference], fingerprints: [try TransferFingerprint.digest(source)])
        let added = try await ArchiveService().edit(archive, change: .add([source], prefix: "", verifyContents: true))
        let removal = await receipt.consume(); XCTAssertTrue(removal.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let entries = try await ArchiveService().list(archive); XCTAssertTrue(entries.contains { $0.path == "move-me.txt" })
        let undo = await MacStorageService.shared.undo([.compound(added.undo + removal.undo)])
        XCTAssertTrue(undo.errors.isEmpty); XCTAssertEqual(try String(contentsOf: source), "verified archive transfer")
        XCTAssertEqual(try Data(contentsOf: archive), oldArchive); cleanup(undo.inverse)
    }
}

extension VirtualTransferTests {
    @MainActor func testSplitArchivePanePreservesVirtualLocationAndPresentation() async throws {
        let (archive, _) = try await fixture()
        let savedSession = ["sessionTabs", "sessionTabsV2"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in savedSession { UserDefaults.standard.set(value, forKey: key) } }
        let model = MainPageViewModel()
        defer { for tab in model.tabs { tab.primary.shutdown(); tab.secondary?.shutdown() } }
        model.openVirtualTab(.archive(archive, "nested/"))
        model.activePane.layout = .columns; model.activePane.sort = .size; model.activePane.group = .kind
        model.toggleSplit()
        let secondary = try XCTUnwrap(model.currentTab.secondary)
        XCTAssertEqual(secondary.snapshot.virtualLocation, .archive(archive, "nested/"))
        XCTAssertEqual(secondary.layout, .columns)
        XCTAssertEqual(secondary.sort, .size)
        XCTAssertEqual(secondary.group, .kind)
        model.toggleSplit(); XCTAssertNil(model.currentTab.secondary)
    }
}
