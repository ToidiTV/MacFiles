import XCTest
import AppKit
import FilesShared
import FilesStorage
@testable import FilesApp

final class Completion9Tests: XCTestCase {
    @MainActor func testOpeningFolderAliasAndSymbolicLinkNavigatesWithoutRecursion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = try await MacStorageService.shared.createAlias(folder, in: root, name: "alias").completed[0]
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let settings = SettingsService.shared
        let previous = settings.preferences.foldersInNewTab
        defer { settings.preferences.foldersInNewTab = previous }
        settings.preferences.foldersInNewTab = false
        let model = MainPageViewModel()
        for url in [folder, alias, link] {
            model.open(try ListedItem(url: url))
            XCTAssertEqual(model.activePane.location?.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
        }
    }
    func testNaturalFiltersApplyKindsNamesSizeAndDateBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["budget.pdf", "budget.txt", "other.pdf"] {
            let url = root.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1767225600)], ofItemAtPath: url.path)
        }
        let json = #"{"names":["budget"],"extensions":["pdf"],"kinds":["document"],"minimumBytes":4,"maximumBytes":20,"modifiedAfter":"2025-12-31","modifiedBefore":"2026-01-02"}"#
        let options = try NaturalSearchFilters.parse(json, base: SearchOptions())
        XCTAssertEqual(try SearchService.search([root], options: options).items.map(\.name), ["budget.pdf"])
        var excluded = options; excluded.modifiedBefore = Date(timeIntervalSince1970: 1767139200)
        XCTAssertTrue(try SearchService.search([root], options: excluded).items.isEmpty)
    }
    func testNaturalFiltersRejectInvalidAndEmptyOutputAndPreserveExplicitFilters() throws {
        for json in ["{}", #"{"extensions":["../pdf"]}"#, #"{"kinds":["delete"]}"#, #"{"minimumBytes":-1}"#, #"{"minimumBytes":10,"maximumBytes":2}"#, #"{"modifiedAfter":"2026-02-30"}"#, #"{"createdAfter":"2026-02-01","createdBefore":"2026-01-01"}"#] {
            XCTAssertThrowsError(try NaturalSearchFilters.parse(json, base: SearchOptions()), json)
        }
        var base = SearchOptions(); base.hidden = true; base.text = "literal text"; base.tag = "Keep"
        let decoded = try NaturalSearchFilters.parse(#"{"names":["$(touch /tmp/never)"]}"#, base: base)
        XCTAssertTrue(decoded.hidden); XCTAssertEqual(decoded.tag, "Keep"); XCTAssertEqual(decoded.text, "literal text")
        XCTAssertEqual(decoded.nameTerms, ["$(touch /tmp/never)"])
        let legacy = try JSONEncoder().encode(SearchOptions())
        XCTAssertNil(try JSONDecoder().decode(SearchOptions.self, from: legacy).modifiedBefore)
    }
    @MainActor func testBackgroundPresetsAndExternalOpenRouting() throws {
        XCTAssertEqual(BackgroundPresets.values.count, 20)
        XCTAssertTrue(BackgroundPresets.values.allSatisfy { $0.hex.isEmpty || Palette.color($0.hex) != nil })
        let previous = SettingsService.shared.preferences
        defer { SettingsService.shared.preferences = previous }
        SettingsService.shared.preferences.openExternalInNewWindow = true
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let delegate = AppDelegate(); let model = MainPageViewModel(initialLocation: root)
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        delegate.register(window, model: model)
        defer { model.tabs.forEach { $0.primary.shutdown(); $0.secondary?.shutdown() } }
        var opened: [URL] = []; delegate.openFolderWindow = { opened.append($0) }
        delegate.application(NSApplication.shared, open: [root])
        XCTAssertEqual(opened.map(\.path), [root.path]); XCTAssertEqual(model.tabs.count, 1)
        SettingsService.shared.preferences.openExternalInNewWindow = false
        delegate.application(NSApplication.shared, open: [root])
        XCTAssertEqual(opened.count, 1); XCTAssertEqual(model.tabs.count, 2)
    }
    func testManagedTagIdentityColorSurviveRenameAndClear() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("original bytes".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let old = NamedTag(name: "Project", color: 2, customHex: "12ABEF")
        try NativeTags.apply([old.name, "Unmanaged"], catalog: [old], to: [file])
        XCTAssertEqual(try NativeTags.managed(file), [old])
        let replacement = NamedTag(id: old.id, name: "Finished", color: 4, customHex: "AABBCC")
        try NativeTags.replace(old, with: replacement, at: file)
        XCTAssertEqual(try NativeTags.managed(file), [replacement])
        XCTAssertEqual(Set(try NativeTags.read(file)), ["Finished\n4", "Unmanaged"])
        try MetadataService.setTags([], for: [file])
        XCTAssertTrue(try NativeTags.managed(file).isEmpty)
        XCTAssertTrue(try NativeTags.read(file).isEmpty)
        XCTAssertEqual(try String(contentsOf: file), "original bytes")
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Old","color":2}"#
        XCTAssertNil(try JSONDecoder().decode(NamedTag.self, from: Data(legacy.utf8)).customHex)
        XCTAssertFalse(NamedTag(name: "Invalid", customHex: "nothex").isValid)
    }

}
