import XCTest
import AppKit
import FilesShared
import FilesStorage
@testable import FilesApp

final class AuditGapCompletionTests: XCTestCase {
    func testLayoutSizeCycleMatchesSourceOrderAndBoundaries() {
        var sizes: [String: Int] = [LayoutMode.details.rawValue: 0]
        var mode = LayoutMode.details
        for expected in 1...4 {
            mode = LayoutSizing.step(mode, sizes: &sizes, forward: true)
            XCTAssertEqual(mode, .details); XCTAssertEqual(LayoutSizing.level(mode, sizes: sizes), expected)
        }
        mode = LayoutSizing.step(mode, sizes: &sizes, forward: true)
        XCTAssertEqual(mode, .list); XCTAssertEqual(LayoutSizing.level(mode, sizes: sizes), 0)
        mode = LayoutSizing.step(mode, sizes: &sizes, forward: false)
        XCTAssertEqual(mode, .details); XCTAssertEqual(LayoutSizing.level(mode, sizes: sizes), 4)
        mode = LayoutSizing.step(.extraLargeIcons, sizes: &sizes, forward: true)
        XCTAssertEqual(mode, .columns); XCTAssertEqual(LayoutSizing.level(mode, sizes: sizes), 0)
        mode = LayoutSizing.step(mode, sizes: &sizes, forward: false)
        XCTAssertEqual(mode, .extraLargeIcons)
        XCTAssertEqual(LayoutSizing.step(.gallery, sizes: &sizes, forward: true), .gallery)
    }
    func testPreferencesDecodeOlderDocumentsAndRejectInvalidLimits() throws {
        var value = try JSONDecoder().decode(ExplorerPreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(value.showThumbnails); XCTAssertEqual(value.thumbnailCacheMB, 128); XCTAssertTrue(value.isValid)
        value.thumbnailCacheMB = -1; XCTAssertFalse(value.isValid)
        value.thumbnailCacheMB = 128; value.startupPages = ["relative/path"]; XCTAssertFalse(value.isValid)
    }
    @MainActor func testGlobalPresentationAndBackgroundTabTargeting() throws {
        let settings = SettingsService.shared
        let previous = settings.preferences; let oldLayout = settings.defaultLayout; let saved = settings.presentations
        defer { settings.preferences = previous; settings.defaultLayout = oldLayout; settings.presentations = saved }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        settings.preferences.syncFolderPreferences = true
        settings.rememberPresentation(FolderPresentation(layout: .list, sort: .size, ascending: false, group: .kind, groupAscending: false, groupDateUnit: .month), at: root)
        let unrelated = URL(fileURLWithPath: "/tmp/another-folder")
        XCTAssertEqual(settings.presentation(for: unrelated)?.sort, .size)
        XCTAssertEqual(settings.presentation(for: unrelated)?.group, .kind)
        settings.preferences.switchToNewTab = false
        let model = MainPageViewModel(initialLocation: root)
        defer { model.tabs.forEach { $0.primary.shutdown(); $0.secondary?.shutdown() } }
        let first = model.selectedTab
        model.newTab(root); XCTAssertEqual(model.selectedTab, first)
        model.newTab(root, activate: true); XCTAssertEqual(model.selectedTab, model.tabs.last?.id)
    }
    func testNamedTagRenameColorAndRemovalPreserveUnrelatedTags() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tags.txt"); try Data("keep".utf8).write(to: file)
        let old = NamedTag(name: "Project", color: 6)
        try NativeTags.apply(["Project", "Keep"], catalog: [old], to: [file])
        XCTAssertEqual(Set(try NativeTags.read(file)), ["Project\n6", "Keep"])
        let renamed = NamedTag(id: old.id, name: "Finished", color: 2)
        try NativeTags.replace(old, with: renamed, at: file)
        XCTAssertEqual(Set(try NativeTags.read(file)), ["Finished\n2", "Keep"])
        try NativeTags.replace(renamed, with: nil, at: file)
        XCTAssertEqual(try NativeTags.read(file), ["Keep"])
        XCTAssertEqual(try String(contentsOf: file), "keep")
        XCTAssertFalse(NamedTag.valid([old, NamedTag(name: "project")]))
        XCTAssertFalse(NamedTag(name: "Injected\n6").isValid)
        XCTAssertEqual(try JSONDecoder().decode([NamedTag].self, from: JSONEncoder().encode([old])), [old])
    }
    @MainActor func testFolderSizePreferenceAndUpSelection() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("child", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("data"))
        let settings = SettingsService.shared; let previous = settings.preferences
        defer { settings.preferences = previous }
        settings.preferences.calculateFolderSizes = true; settings.preferences.selectPreviousFolder = true
        let model = MainPageViewModel(initialLocation: folder); let pane = model.activePane
        defer { model.tabs.forEach { $0.primary.shutdown(); $0.secondary?.shutdown() } }
        pane.up()
        for _ in 0..<100 {
            if pane.items.first(where: { $0.url == folder })?.directorySizeCalculated == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(pane.selection, [folder])
        XCTAssertEqual(pane.items.first(where: { $0.url == folder })?.size, 4096)
        XCTAssertEqual(pane.items.first(where: { $0.url == folder })?.directorySizeCalculated, true)
        XCTAssertNotEqual(FileDisplayFormat.size(1_000_000, units: "Decimal"), FileDisplayFormat.size(1_000_000, units: "Binary"))
        XCTAssertTrue(FileDisplayFormat.size(123, units: "Bytes").contains("123"))
        XCTAssertEqual(FileDisplayFormat.date(Date(timeIntervalSince1970: 0), style: "Universal").count, 19)
    }
    @MainActor func testDragPasteboardCopiesToExplicitFolderAndNegotiatesMove() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt"), destination = root.appendingPathComponent("target", isDirectory: true)
        try Data("drag payload".utf8).write(to: source); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.writeObjects([source as NSURL])
        XCTAssertEqual(FileDrag.operation(board, mask: [.copy, .move], modifiers: []), .copy)
        XCTAssertEqual(FileDrag.operation(board, mask: [.copy, .move], modifiers: [.command]), .move)
        XCTAssertEqual(FileDrag.operation(board, mask: [.copy], modifiers: [.command]), .copy)
        XCTAssertEqual(FileDrag.operation(board, mask: [.copy, .move], modifiers: [.command, .option]), .copy)
        XCTAssertTrue(FileDrag.operation(board, mask: [], modifiers: []).isEmpty)
        let model = MainPageViewModel(initialLocation: root)
        defer { model.tabs.forEach { $0.primary.shutdown(); $0.secondary?.shutdown() } }
        XCTAssertTrue(FileDrag.receive(board, model: model, pane: model.activePane, destination: destination))
        for _ in 0..<200 { if !model.busy { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("source.txt")), Data("drag payload".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testGitHubCredentialValidationRejectsProtocolInjectionBeforeKeychainWrite() {
        XCTAssertThrowsError(try GitHubCredentials.save(username: "name\npassword=injected", token: "placeholder"))
        XCTAssertThrowsError(try GitHubCredentials.save(username: "example", token: "placeholder\nhost=elsewhere"))
        XCTAssertThrowsError(try GitHubCredentials.save(username: "", token: "placeholder"))
        XCTAssertThrowsError(try GitHubCredentials.save(username: "example", token: ""))
    }
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    func testExtractionPlacementAndCollisionPreserveExistingFiles() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let a = source.appendingPathComponent("a.txt"), b = source.appendingPathComponent("b.txt")
        try Data("archive A".utf8).write(to: a); try Data("archive B".utf8).write(to: b)
        let archive = root.appendingPathComponent("two.zip")
        _ = try await ArchiveService().compress([a,b], to: archive, format: .zip)
        try Data("existing".utf8).write(to: target.appendingPathComponent("a.txt"))
        let here = try await ArchiveWorkflows().extract(archive, in: target, placement: .here)
        XCTAssertEqual(here.completed.count, 2); XCTAssertTrue(here.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("a.txt")), "existing")
        XCTAssertEqual(here.undo.count, 2)
        let smart = try await ArchiveWorkflows().extract(archive, in: target, placement: .smart)
        XCTAssertEqual(smart.completed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: smart.completed[0].appendingPathComponent("b.txt").path))
        let child = try await ArchiveWorkflows().extract(archive, in: target, placement: .childFolder)
        XCTAssertNotEqual(child.completed.first, smart.completed.first)
    }
    func testSmartExtractionSingleRootAndQuickCompressionNaming() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("content".utf8).write(to: folder.appendingPathComponent("one.txt"))
        let first = try await ArchiveWorkflows().compress([folder], in: root, format: .zip)
        let second = try await ArchiveWorkflows().compress([folder], in: root, format: .zip)
        XCTAssertNotEqual(first.completed.first, second.completed.first)
        let result = try await ArchiveWorkflows().extract(first.completed[0], in: target, placement: .smart)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("Folder/one.txt").path))
        XCTAssertEqual(result.completed.count, 1)
    }
    func testPasteAliasesUsesUniqueNamesAndPreservesTarget() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a'b.txt"); try Data("original".utf8).write(to: file)
        let first = try await MacStorageService.shared.createUniqueAlias(file, in: root)
        let second = try await MacStorageService.shared.createUniqueAlias(file, in: root)
        XCTAssertNotEqual(first.completed.first, second.completed.first)
        var stale = false
        let resolved = try URL(resolvingAliasFileAt: second.completed[0], options: [.withoutUI, .withoutMounting])
        XCTAssertEqual(resolved.standardizedFileURL, file.standardizedFileURL)
        let data = try file.bookmarkData(options: .suitableForBookmarkFile)
        _ = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
        XCTAssertEqual(try String(contentsOf: file), "original")
    }
    @MainActor func testSeparateDotfilesAndTrashGrouping() throws {
        let settings = SettingsService.shared
        let saved = (settings.showHidden, settings.showDotfiles)
        defer { settings.showHidden = saved.0; settings.showDotfiles = saved.1 }
        let pane = ShellPageViewModel(); defer { pane.shutdown() }
        let dot = ListedItem(virtualURL: URL(string: "test:///.env")!, name: ".env", directory: false, size: 1)
        let plain = ListedItem(virtualURL: URL(string: "test:///plain")!, name: "plain", directory: false, size: 1)
        settings.showHidden = true; settings.showDotfiles = false
        XCTAssertEqual(pane.orderedItems([dot,plain]).map(\.name), ["plain"])
        settings.showHidden = false; settings.showDotfiles = true
        XCTAssertEqual(pane.orderedItems([dot,plain]).count, 2)
        XCTAssertEqual(pane.orderedItems([dot,plain], includeHidden: true).count, 2)
        var trashed = plain; trashed.originalLocation = URL(fileURLWithPath: "/original/plain"); trashed.deleted = Date(timeIntervalSince1970: 1705320000)
        XCTAssertEqual(ItemGrouping.groups([trashed], by: .originalFolder).first?.title, "/original")
        XCTAssertEqual(ItemGrouping.groups([trashed], by: .deleted, dateUnit: .year).first?.title, "2024")
    }
    @MainActor func testSettingsDocumentRejectsInvalidBeforeChangingPreferences() throws {
        let settings = SettingsService.shared; let old = settings.showHidden
        var document = SettingsDocument(settings)
        document.showHidden = !old; document.backgroundImageOpacity = 4
        XCTAssertThrowsError(try document.apply(settings)); XCTAssertEqual(settings.showHidden, old)
        document = SettingsDocument(settings)
        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SettingsDocument.self, from: encoded)
        try decoded.validate()
        XCTAssertEqual(decoded.visibleColumns, settings.visibleColumns)
    }
    func testAdaptiveLayoutUsesStrictSixtyPercentThreshold() {
        func item(_ name: String) -> ListedItem { ListedItem(virtualURL: URL(string: "test:///" + name)!, name: name, directory: false, size: 1) }
        let media = [item("a.jpg"),item("b.mp4"),item("c.mp3")]
        XCTAssertEqual(AdaptiveLayout.resolve(media), .icons)
        XCTAssertEqual(AdaptiveLayout.resolve(media + [item("a.txt"),item("b.txt")]), .details)
        XCTAssertEqual(AdaptiveLayout.resolve([]), .details)
    }

    func testPermanentDeletionDoesNotFollowSymlinkTarget() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.txt"), link = root.appendingPathComponent("link")
        try Data("keep target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let result = await MacStorageService.shared.permanentlyDelete([link])
        XCTAssertEqual(result.completed, [link]); XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: target), "keep target")
    }
    func testEveryAddedCommandHasAUniqueConfigurableShortcutIdentity() throws {
        let configuration = try ShortcutConfiguration().validated()
        XCTAssertEqual(configuration.action(for: KeyChord("space", option: true)), "toggleSelect")
        XCTAssertEqual(Set(ShortcutConfiguration.parityCommands.map(\.id)).count, ShortcutConfiguration.parityCommands.count)
    }

}
