import XCTest
import Foundation
import FilesShared
@testable import FilesStorage

final class ParityTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-parity-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ name: String) throws -> URL { let url = root.appendingPathComponent(name); try Data("test".utf8).write(to: url); return url }
    func testToolbarContextsRoundTripAndNormalization() throws {
        var toolbar = ToolbarConfiguration.standard
        XCTAssertTrue(toolbar.entries(for: .always).contains { $0.action == .properties })
        toolbar.contexts[ToolbarContext.always.rawValue]?.removeAll { $0.action == .properties }
        let properties = ToolbarEntry(.properties, showLabel: true)
        toolbar.contexts[ToolbarContext.file.rawValue] = [properties, ToolbarEntry(.copy)]
        let restored = try JSONDecoder().decode(ToolbarConfiguration.self, from: JSONEncoder().encode(toolbar)).validated()
        XCTAssertEqual(restored, toolbar)
        let resolved = restored.resolved(context: .file, cloud: true)
        XCTAssertEqual(resolved.filter { $0.action == .copy }.count, 1)
        XCTAssertTrue(resolved.contains { $0.action == .properties && $0.showLabel })
        XCTAssertTrue(resolved.contains { $0.action == .download })
        XCTAssertFalse(restored.resolved(context: .browsing, cloud: false).contains { $0.action == .properties })
        var hidden = properties; hidden.showIcon = false; hidden.showLabel = false
        let fixed = try ToolbarConfiguration(contexts: [ToolbarContext.file.rawValue: [hidden, hidden]]).validated()
        let entries = fixed.entries(for: .file)
        XCTAssertNotEqual(entries[0].id, entries[1].id); XCTAssertTrue(entries[0].showIcon)
        XCTAssertThrowsError(try ToolbarConfiguration(contexts: ["unknown": []]).validated())
    }
    func testCloudClassificationDoesNotInventProviderSyncCompletion() {
        func cloud(_ provider: String? = "Provider", iCloud: Bool = false, dataless: Bool = false, status: URLUbiquitousItemDownloadingStatus? = nil, uploading: Bool = false, downloading: Bool = false, uploaded: Bool? = nil, conflict: Bool = false, error: String? = nil) -> CloudState {
            CloudState.classify(isICloud: iCloud, provider: provider, dataless: dataless, status: status, uploading: uploading, downloading: downloading, uploaded: uploaded, conflict: conflict, error: error)
        }
        XCTAssertEqual(cloud(nil).availability, .local)
        XCTAssertEqual(cloud().availability, .providerLocal)
        XCTAssertFalse(cloud(dataless: true).canPreview)
        XCTAssertEqual(cloud(iCloud: true, status: .current, uploaded: true).availability, .uploaded)
        XCTAssertEqual(cloud(iCloud: true, uploaded: false).availability, .pending)
        XCTAssertEqual(cloud(uploading: true).availability, .uploading)
        XCTAssertEqual(cloud(downloading: true).availability, .downloading)
        XCTAssertEqual(cloud(conflict: true).availability, .conflict)
        XCTAssertEqual(cloud(error: "failure").detail, "failure")
        let home = URL(fileURLWithPath: "/Test")
        XCTAssertEqual(CloudState.providerName(home.appendingPathComponent("Library/CloudStorage/Example-Team/file.txt"), home: home), "Example-Team")
        XCTAssertNil(CloudState.providerName(home.appendingPathComponent("Library/CloudStorageFake/file.txt"), home: home))
    }
    func testLocalFileCannotBeEvictedOrTreatedAsCloudDownload() throws {
        let url = try file("local.txt")
        XCTAssertFalse(try ListedItem(url: url).cloud.isCloud)
        XCTAssertThrowsError(try CloudService.evictICloud(url))
        XCTAssertFalse(try CloudService.download([url]).errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: url), "test")
    }
    func testSecurityRoundTripAndIdentityGuard() throws {
        let url = try file("security.txt")
        let original = try PropertiesService.security(url)
        XCTAssertEqual(original.uid, getuid())
        try PropertiesService.validateACL(original.acl)
        try PropertiesService.setACL(original.acl, at: url, expected: FileIdentity(url))
        XCTAssertEqual(try PropertiesService.security(url).acl, original.acl)
        XCTAssertThrowsError(try PropertiesService.setACL("not an ACL", at: url, expected: FileIdentity(url)))
        let identity = FileIdentity(url)
        try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("old.txt"))
        _ = try file("security.txt")
        XCTAssertThrowsError(try PropertiesService.setACL(original.acl, at: url, expected: identity))
        XCTAssertThrowsError(try PropertiesService.setOwner(uid: getuid(), gid: getgid(), at: url, expected: identity))
    }
    func testPropertiesFlagsAndGeneralInformation() throws {
        let url = try file("attributes.txt")
        try PropertiesService.setFlags(hidden: true, locked: false, at: url)
        XCTAssertTrue(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden == true)
        try PropertiesService.setFlags(hidden: false, locked: false, at: url)
        let general = try PropertiesService.general([url])
        XCTAssertEqual(general.first { $0.name == "File size" }?.value, "4 bytes")
        XCTAssertEqual(general.first { $0.name == "Path" }?.value, url.path)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        XCTAssertThrowsError(try PropertiesService.setFlags(hidden: true, locked: false, at: link))
    }
    func testRetargetAliasAndSymbolicLinkWithUndo() async throws {
        let first = try file("first.txt"), second = try file("second.txt")
        let storage = MacStorageService()
        let alias = try await storage.createAlias(first, in: root, name: "alias").completed[0]
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        for url in [alias, link] {
            let report = try await storage.retargetShortcut(url, to: second)
            let target = url == alias ? try URL(resolvingAliasFileAt: url) : url.resolvingSymlinksInPath()
            XCTAssertEqual(target.resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
            let undo = await storage.undo(report.undo)
            XCTAssertTrue(undo.errors.isEmpty)
            let restored = url == alias ? try URL(resolvingAliasFileAt: url) : url.resolvingSymlinksInPath()
            XCTAssertEqual(restored.resolvingSymlinksInPath(), first.resolvingSymlinksInPath())
            for step in undo.inverse { if case .move(let from, _, _) = step, from.path.contains("/.Trash/") { try? FileManager.default.removeItem(at: from) } }
        }
    }
    func testSignatureInspectionHandlesUnsignedFilesWithoutExecution() async throws {
        let url = try file("unsigned.txt")
        let report = try await PropertiesService.signature(url)
        XCTAssertTrue(report.contains("No readable macOS code signature"))
        let compatibility = try await PropertiesService.applicationInfo(url)
        XCTAssertTrue(compatibility.contains { $0.name == "Executable format" && $0.value.contains("text") })
    }
    func testCustomIconFlagRefreshesListingIdentity() throws {
        let url = try file("icon.txt")
        let original = try ListedItem(url: url)
        XCTAssertFalse(original.hasCustomIcon)
        var info = Data(repeating: 0, count: 32); info[8] = 0x04
        try ExtendedAttributes.write("com.apple.FinderInfo", data: info, to: url)
        let changed = try ListedItem(url: url)
        XCTAssertTrue(changed.hasCustomIcon); XCTAssertNotEqual(original, changed)
        try ExtendedAttributes.remove("com.apple.FinderInfo", from: url)
        XCTAssertFalse(try ListedItem(url: url).hasCustomIcon)
    }

}
