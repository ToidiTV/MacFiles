import XCTest
import ImageIO
import CoreGraphics
import AVFoundation
import UniformTypeIdentifiers
import FilesShared
@testable import FilesStorage
@testable import FilesApp

final class RemainingParityTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-remaining-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func image() throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 30, height: 12, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 30, height: 12))
        let url = root.appendingPathComponent("picture.png")
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(output)); return url
    }
    func testShortcutDefaultsAndConflicts() throws {
        var config = try ShortcutConfiguration().validated()
        XCTAssertEqual(config.action(for: KeyChord("c", command: true)), "copy")
        config.overrides["copy"] = [KeyChord("r", command: true)]
        XCTAssertThrowsError(try config.validated())
        config.overrides["refresh"] = []; XCTAssertNoThrow(try config.validated())
        XCTAssertNil(config.action(for: KeyChord("c", command: true)))
        let restored = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
        config.overrides["copy"] = [KeyChord("q", command: true)]; XCTAssertThrowsError(try config.validated())
    }
    func testNewLayoutModesPreserveOldSessionsAndGrouping() throws {
        for mode in LayoutMode.allCases {
            let snapshot = PaneSnapshot(location: root, layout: mode, sort: .name, ascending: true, group: .kind)
            let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: JSONEncoder().encode(snapshot)); XCTAssertEqual(decoded.layout, mode)
            XCTAssertGreaterThan(mode.cellWidth, mode.iconSize); XCTAssertGreaterThan(mode.cellHeight, mode.iconSize)
        }
        let file = try image(); let folder = root.appendingPathComponent("folder"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let groups = ItemGrouping.groups(try [ListedItem(url: file), ListedItem(url: folder)], by: .kind)
        XCTAssertEqual(groups.count, 2); XCTAssertEqual(Set(groups.flatMap(\.items).map { $0.url.path }), Set([file.path, folder.path]))
    }
    func testImageRotationAndUndoPreserveOriginalBytesAndAttributes() async throws {
        let url = try image(); let original = try Data(contentsOf: url)
        try ExtendedAttributes.write("com.macfiles.fixture", data: Data("retained".utf8), to: url)
        let report = try await MediaService.edit(url, clockwise: true)
        XCTAssertTrue(report.errors.isEmpty)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil)); let rotated = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(rotated.width, 12); XCTAssertEqual(rotated.height, 30)
        XCTAssertEqual(try ExtendedAttributes.list(url).first { $0.name == "com.macfiles.fixture" }?.data, Data("retained".utf8))
        let undo = await MacStorageService.shared.undo(report.undo); XCTAssertTrue(undo.errors.isEmpty); XCTAssertEqual(try Data(contentsOf: url), original)
        cleanupUndo(undo.inverse)
    }
    func testEmbeddedImageMetadataRoundTrip() async throws {
        let url = try image(); var fields = MediaFields(); fields.artist = "Test Author"; fields.comment = "Description"; fields.copyright = "Fixture"
        let report = try await MediaService.edit(url, fields: fields); XCTAssertTrue(report.errors.isEmpty)
        let read = try await MediaService.fields(url); XCTAssertEqual(read.artist, fields.artist); XCTAssertEqual(read.comment, fields.comment)
        let undo = await MacStorageService.shared.undo(report.undo); cleanupUndo(undo.inverse)
    }
    @MainActor func testVirtualTabsPersistLocationWithoutPasswords() throws {
        let url = root.appendingPathComponent("test.zip")
        let pane = ShellPageViewModel(); pane.openVirtual(.archive(url, "inside/")); XCTAssertNil(pane.operationDirectory)
        let snapshot = pane.snapshot; let data = try JSONEncoder().encode(snapshot)
        let restored = ShellPageViewModel(); restored.restore(try JSONDecoder().decode(PaneSnapshot.self, from: data))
        XCTAssertEqual(restored.archiveURL, url); XCTAssertEqual(restored.archiveSession.prefix, "inside/")
        pane.navigate(root); XCTAssertFalse(pane.isVirtual); pane.shutdown(); restored.shutdown()
    }
    func testEncryptedSevenZipAndSplitVolumeRoundTrip() async throws {
        let source = root.appendingPathComponent("payload.bin")
        let bytes = Data((0..<16384).map { _ in UInt8.random(in: 0...255) }); try bytes.write(to: source)
        let archive = ArchiveService(); let output = root.appendingPathComponent("protected.7z")
        let report = try await archive.compress([source], to: output, format: .sevenZip, password: "fixture-only", volumeBytes: 1024)
        XCTAssertGreaterThan(report.completed.count, 1)
        let first = try XCTUnwrap(report.completed.first)
        let entries = try await archive.list(first, password: "fixture-only"); XCTAssertEqual(entries.map(\.path), ["payload.bin"])
        do { _ = try await archive.list(first, password: "wrong"); XCTFail("Wrong password succeeded") } catch {}
        let destination = root.appendingPathComponent("extracted"); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let extracted = try await archive.extract(first, to: destination, password: "fixture-only")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(extracted.completed.first).appendingPathComponent("payload.bin")), bytes)
    }
    func testArchiveEditAndUndoPreserveOriginal() async throws {
        let first = root.appendingPathComponent("first.txt"); try Data("first".utf8).write(to: first)
        let archive = ArchiveService(); let url = root.appendingPathComponent("edit.zip"); _ = try await archive.compress([first], to: url, format: .zip)
        let bytes = try Data(contentsOf: url)
        let report = try await archive.edit(url, change: .rename("first.txt", to: "renamed.txt"))
        XCTAssertTrue(report.errors.isEmpty)
        let entries = try await archive.list(url); XCTAssertEqual(entries.map(\.path), ["renamed.txt"])
        let undo = await MacStorageService.shared.undo(report.undo); XCTAssertEqual(try Data(contentsOf: url), bytes); cleanupUndo(undo.inverse)
        let remove = try await archive.edit(url, change: .remove(["first.txt"]))
        let empty = try await archive.list(url); XCTAssertTrue(empty.isEmpty)
        let restored = await MacStorageService.shared.undo(remove.undo); cleanupUndo(restored.inverse)
    }
    func testSevenZipListingRejectsUnsafeAndAmbiguousPaths() throws {
        XCTAssertThrowsError(try SevenZipService.parseListing("Path = ../escape\nSize = 1\n\n"))
        XCTAssertThrowsError(try SevenZipService.parseListing("Path = a\nPath = b\nSize = 1\n\n"))
        XCTAssertThrowsError(try SevenZipService.parseListing("Path = a\nSize = 1\n\nPath = a\nSize = 1\n\n"))
    }
    func testContentSearchAcrossChunksAndOfficeDocument() async throws {
        let text = root.appendingPathComponent("large.txt")
        try Data((String(repeating: "x", count: 65534) + "héllo across chunk" + String(repeating: "y", count: 65536)).utf8).write(to: text)
        XCTAssertEqual(try DocumentTextService.contains("héllo across chunk", in: text), true)
        let office = root.appendingPathComponent("word"); try FileManager.default.createDirectory(at: office, withIntermediateDirectories: true)
        try Data("<?xml version=\"1.0\"?><w:document xmlns:w=\"urn:fixture\"><w:p><w:r><w:t>Office needle</w:t></w:r></w:p></w:document>".utf8).write(to: office.appendingPathComponent("document.xml"))
        let docx = root.appendingPathComponent("document.docx"); _ = try await ArchiveService().compress([office], to: docx, format: .zip)
        XCTAssertEqual(try DocumentTextService.contains("Office needle", in: docx), true)
        XCTAssertEqual(try DocumentTextService.contains("absent", in: docx), false)
    }
    func testUndoStepJournalRoundTripPreservesIdentity() throws {
        let url = try image(); let step = UndoStep.move(from: url, to: root.appendingPathComponent("next.png"), identity: FileIdentity(url))
        let restored = try JSONDecoder().decode([UndoStep].self, from: JSONEncoder().encode([step]))
        guard case .move(let from, _, let identity) = restored[0] else { return XCTFail("Wrong operation") }
        XCTAssertEqual(from, url); XCTAssertEqual(identity, FileIdentity(url))
    }
    func testCancelledCopyDoesNotPublishDestination() async throws {
        let source = try image(); let destination = root.appendingPathComponent("cancelled.png")
        let worker = Task {
            try await Task.sleep(for: .seconds(1))
            try CancellableCopy.copy(source, to: destination)
        }
        worker.cancel(); do { try await worker.value; XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
    func testSFTPPasswordAuthenticationAndHostVerification() async throws {
        guard let python = ProcessInfo.processInfo.environment["MACFILES_SFTP_TEST_PYTHON"] else { throw XCTSkip("Set MACFILES_SFTP_TEST_PYTHON to a Python with paramiko for the isolated SSH integration test.") }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "sftp_server", withExtension: "py", subdirectory: "Fixtures"))
        let serverRoot = root.appendingPathComponent("server"); try FileManager.default.createDirectory(at: serverRoot, withIntermediateDirectories: true)
        let known = root.appendingPathComponent("known_hosts")
        let process = Process(); process.executableURL = URL(fileURLWithPath: python); process.arguments = [fixture.path, serverRoot.path, known.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); defer { if process.isRunning { process.terminate() } }
        var line = Data(); while let byte = try pipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty { if byte[0] == 10 { break }; line.append(byte) }
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self)))
        let config = root.appendingPathComponent("ssh_config"); try Data().write(to: config)
        let connection = RemoteConnection(name: "Fixture", kind: .sftp, host: "127.0.0.1", port: port, username: "fixture")
        let provider = RemoteProvider(connection: connection, password: "fixture-password", knownHosts: known, sshConfig: config)
        let source = root.appendingPathComponent("test.txt"); try Data("SFTP password fixture".utf8).write(to: source)
        try await provider.upload(source, to: "/")
        let listed = try await provider.list("/"); XCTAssertEqual(listed.map(\.name), ["test.txt"])
        let wrong = RemoteProvider(connection: connection, password: "wrong", knownHosts: known, sshConfig: config)
        do { _ = try await wrong.list("/"); XCTFail("Wrong password accepted") } catch {}
        let missing = root.appendingPathComponent("empty_hosts"); try Data().write(to: missing)
        let unknown = RemoteProvider(connection: connection, password: "fixture-password", knownHosts: missing, sshConfig: config)
        do { _ = try await unknown.list("/"); XCTFail("Untrusted host accepted") } catch {}
        let proposal = try await SSHHostService.inspect(host: "127.0.0.1", port: port)
        XCTAssertTrue(proposal.fingerprints.contains("SHA256:"))
        try SSHHostService.trust(proposal, at: missing)
        let trusted = try await unknown.list("/"); XCTAssertEqual(trusted.count, 1)
    }
    func testFTPSVerifiesCertificateAndTransfersOverTLS() async throws {
        let cert = root.appendingPathComponent("cert.pem"), key = root.appendingPathComponent("key.pem"), config = root.appendingPathComponent("openssl.cnf")
        try "[req]\ndistinguished_name=dn\n[dn]\n[v3]\nsubjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\n".write(to: config, atomically: true, encoding: .utf8)
        _ = try await ProcessService.run("/usr/bin/openssl", ["req", "-x509", "-nodes", "-newkey", "rsa:2048", "-subj", "/CN=127.0.0.1", "-days", "1", "-keyout", key.path, "-out", cert.path, "-config", config.path, "-extensions", "v3"])
        let serverRoot = root.appendingPathComponent("server"); try FileManager.default.createDirectory(at: serverRoot, withIntermediateDirectories: true)
        try Data("TLS fixture".utf8).write(to: serverRoot.appendingPathComponent("secure.txt"))
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "ftp_server", withExtension: "py", subdirectory: "Fixtures"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-u", fixture.path, serverRoot.path, cert.path, key.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); defer { if process.isRunning { process.terminate() } }
        var line = Data(); while let byte = try pipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty { if byte[0] == 10 { break }; line.append(byte) }
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self)))
        let connection = RemoteConnection(name: "TLS", kind: .ftps, host: "127.0.0.1", port: port, username: "test")
        let untrusted = RemoteProvider(connection: connection, password: "test")
        do { _ = try await untrusted.list("/"); XCTFail("Untrusted certificate accepted") } catch {}
        let provider = RemoteProvider(connection: connection, password: "test", certificateAuthority: cert)
        let items = try await provider.list("/"); XCTAssertEqual(items.map(\.name), ["secure.txt"])
        let download = root.appendingPathComponent("download"); try FileManager.default.createDirectory(at: download, withIntermediateDirectories: true)
        let file = try await provider.download(items[0], from: "/", to: download)
        XCTAssertEqual(try String(contentsOf: file), "TLS fixture")
    }
    func testAudioMetadataPassthroughRoundTrip() async throws {
        var wave = Data()
        func string(_ value: String) { wave.append(Data(value.utf8)) }
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wave.append(contentsOf: $0) } }
        let samples = 4410
        string("RIFF"); number(UInt32(36 + samples * 2)); string("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(44100)); number(UInt32(88200)); number(UInt16(2)); number(UInt16(16)); string("data"); number(UInt32(samples * 2)); wave.append(Data(repeating: 0, count: samples * 2))
        let source = root.appendingPathComponent("audio.wav"); try wave.write(to: source)
        let output = root.appendingPathComponent("audio.m4a")
        _ = try await ProcessService.run("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac", source.path, output.path])
        var fields = MediaFields(); fields.title = "Fixture title"; fields.artist = "Fixture artist"; fields.album = "Fixture album"
        fields.comment = "Fixture comment"; fields.copyright = "Fixture copyright"
        let original = try Data(contentsOf: output)
        let report = try await MediaService.edit(output, fields: fields); XCTAssertTrue(report.errors.isEmpty)
        let edited = try Data(contentsOf: output)
        XCTAssertEqual(zip(original, edited).filter { $0 != $1 }.count, 4, "Only the old movie atom type may change before the new header is appended")
        let read = try await MediaService.fields(output); XCTAssertEqual(read.title, fields.title); XCTAssertEqual(read.artist, fields.artist); XCTAssertEqual(read.album, fields.album); XCTAssertEqual(read.comment, fields.comment); XCTAssertEqual(read.copyright, fields.copyright)
        let movie = root.appendingPathComponent("audio.mov")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: output), presetName: AVAssetExportPresetPassthrough))
        exporter.outputURL = movie; exporter.outputFileType = .mov; await exporter.export()
        XCTAssertEqual(exporter.status, .completed)
        let movieEdit = try await MediaService.edit(movie, fields: fields); XCTAssertTrue(movieEdit.errors.isEmpty)
        let movieFields = try await MediaService.fields(movie); XCTAssertEqual(movieFields.title, fields.title)
        let movieUndo = await MacStorageService.shared.undo(movieEdit.undo); cleanupUndo(movieUndo.inverse)
        let undo = await MacStorageService.shared.undo(report.undo); cleanupUndo(undo.inverse)
    }
    func testSevenZipLinksAndEmptyEncryptedArchiveEdits() async throws {
        let folder = root.appendingPathComponent("payload"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("target".utf8).write(to: folder.appendingPathComponent("target.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: folder.appendingPathComponent("target.txt").path)
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("link").path, withDestinationPath: "target.txt")
        let archive = ArchiveService(); let url = root.appendingPathComponent("links.7z")
        _ = try await archive.compress([folder], to: url, format: .sevenZip, password: "test-password")
        let destination = root.appendingPathComponent("extracted"); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let extracted = try await archive.extract(url, to: destination, password: "test-password")
        let link = try XCTUnwrap(extracted.completed.first).appendingPathComponent("payload/link")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "target.txt")
        XCTAssertEqual(try String(contentsOf: link), "target")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: link.deletingLastPathComponent().appendingPathComponent("target.txt").path)[.posixPermissions] as? NSNumber)?.intValue, 0o751)
        try ExtendedAttributes.write("com.macfiles.archive-test", data: Data("metadata".utf8), to: url)
        let remove = try await archive.edit(url, change: .remove(["payload/"]), password: "test-password")
        XCTAssertTrue(remove.errors.isEmpty)
        let empty = try await archive.list(url, password: "test-password"); XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(try ExtendedAttributes.list(url).first { $0.name == "com.macfiles.archive-test" }?.data, Data("metadata".utf8))
        let create = try await archive.edit(url, change: .create("inside", prefix: "", directory: true), password: "test-password")
        let created = try await archive.list(url, password: "test-password"); XCTAssertEqual(created.map(\.path), ["inside/"])
        let undo = await MacStorageService.shared.undo(create.undo); cleanupUndo(undo.inverse)
        let undoRemove = await MacStorageService.shared.undo(remove.undo); cleanupUndo(undoRemove.inverse)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("link"))
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("link").path, withDestinationPath: "../../escape")
        let unsafe = root.appendingPathComponent("unsafe.7z")
        _ = try await archive.compress([folder], to: unsafe, format: .sevenZip, password: "test-password")
        do { _ = try await archive.extract(unsafe, to: destination, password: "test-password"); XCTFail("Escaping link accepted") } catch {}
    }
    func testSubprocessDoesNotReturnTruncatedOutput() async throws {
        do {
            _ = try await ProcessService.run("/usr/bin/python3", ["-c", "import sys; sys.stdout.write('x' * (17 * 1024 * 1024))"])
            XCTFail("Truncated output accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("16 MiB")) }
    }
    private func cleanupUndo(_ steps: [UndoStep]) {
        for step in steps { if case .move(let from, _, _) = step, from.path.contains("/.Trash/") { try? FileManager.default.removeItem(at: from) } }
    }
}
