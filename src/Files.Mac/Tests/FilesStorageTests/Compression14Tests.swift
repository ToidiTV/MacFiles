import XCTest
@testable import FilesStorage

final class Compression14Tests: XCTestCase {
    func testAdvancedCompressionRoundTripsAndPreservesExistingDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Fixture.txt")
        let bytes = Data(String(repeating: "Compression fixture 🗂️\n", count: 3000).utf8)
        try bytes.write(to: source)
        for format in [ArchiveFormat.zip, .sevenZip] {
            let output = root.appendingPathComponent("Archive." + format.extensionName)
            let options = ArchiveCompressionOptions(level: 9, dictionaryKiB: 1024, wordSize: 64, threads: 2)
            _ = try await ArchiveService().compress([source], to: output, format: format, options: options)
            let original = try Data(contentsOf: output)
            let stored = root.appendingPathComponent("Stored." + format.extensionName)
            _ = try await ArchiveService().compress([source], to: stored, format: format, options: .init(level: 0))
            XCTAssertLessThan(original.count, try Data(contentsOf: stored).count, "Compression level must affect the produced archive")
            let destination = root.appendingPathComponent(format.rawValue)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let report = try await ArchiveService().extract(output, to: destination)
            XCTAssertTrue(report.errors.isEmpty)
            // Extraction wraps the payload in a recovery-aware destination folder.
            let enumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil)!
            let extracted = try XCTUnwrap(enumerator.compactMap { $0 as? URL }.first { $0.lastPathComponent == source.lastPathComponent })
            XCTAssertEqual(try Data(contentsOf: extracted), bytes)
            do { _ = try await ArchiveService().compress([source], to: output, format: format, options: options); XCTFail("Existing archive overwritten") } catch {}
            XCTAssertEqual(try Data(contentsOf: output), original)
        }
    }
    func testCompressionOptionValidation() throws {
        XCTAssertThrowsError(try ArchiveCompressionOptions(level: -1).arguments(for: .zip))
        XCTAssertThrowsError(try ArchiveCompressionOptions(threads: 0).arguments(for: .sevenZip))
        XCTAssertThrowsError(try ArchiveCompressionOptions(dictionaryKiB: Int.max).arguments(for: .sevenZip))
        XCTAssertThrowsError(try ArchiveCompressionOptions(wordSize: 274).arguments(for: .sevenZip))
        XCTAssertThrowsError(try ArchiveCompressionOptions().arguments(for: .tar))
    }
}
