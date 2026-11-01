import Foundation
import CryptoKit

public struct FileHashes: Sendable {
    public let md5: String
    public let sha1: String
    public let sha256: String
    public let sha512: String
}

public enum MetadataService {
    public static func hashes(_ url: URL) throws -> FileHashes {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var md5 = Insecure.MD5(); var sha1 = Insecure.SHA1(); var sha256 = SHA256(); var sha512 = SHA512()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation(); md5.update(data: data); sha1.update(data: data); sha256.update(data: data); sha512.update(data: data)
        }
        func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
        return FileHashes(md5: hex(md5.finalize()), sha1: hex(sha1.finalize()), sha256: hex(sha256.finalize()), sha512: hex(sha512.finalize()))
    }
    public static func setTags(_ tags: [String], for urls: [URL]) throws {
        for url in urls {
            try Task.checkCancellation()
            try NativeTags.apply(tags, catalog: NativeTags.managed(url), to: [url])
        }
    }
    public static func directorySize(_ url: URL) throws -> (Int64, Int) {
        let fm = FileManager.default
        var bytes: Int64 = 0; var count = 0
        var failure: Error?
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [], errorHandler: { _, error in failure = error; return true }) else { throw StorageError.notDirectory }
        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let values = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]); count += 1
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        if let failure { throw failure }
        return (bytes, count)
    }
    public static func setPermissions(_ mode: String, for urls: [URL]) throws {
        guard mode.count == 3, let number = Int(mode, radix: 8), number <= 0o777 else { throw CommandFailure("Enter three octal digits, for example 644 or 755.") }
        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw CommandFailure("Edit permissions on the link's target instead.") }
            try FileManager.default.setAttributes([.posixPermissions: number], ofItemAtPath: url.path)
        }
    }
}

public struct RenameProposal: Identifiable, Sendable {
    public var id: URL { source }
    public let source: URL
    public let name: String
    public init(source: URL, name: String) { self.source = source; self.name = name }
}
