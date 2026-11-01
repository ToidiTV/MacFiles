import Foundation
import Darwin

public struct ExtendedAttribute: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let data: Data
}
public enum ExtendedAttributes {
    private static func failure(_ url: URL) -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
    public static func list(_ url: URL) throws -> [ExtendedAttribute] {
        let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { throw failure(url) }
        guard size > 0 else { return [] }
        var names = [CChar](repeating: 0, count: size)
        let count = listxattr(url.path, &names, names.count, XATTR_NOFOLLOW)
        guard count >= 0 else { throw failure(url) }
        let raw = names.prefix(count).map { UInt8(bitPattern: $0) }
        return try raw.split(separator: 0).map { bytes in
            let name = String(decoding: bytes, as: UTF8.self)
            let length = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard length >= 0 else { throw failure(url) }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
            guard read >= 0 else { throw failure(url) }
            data.count = read
            return ExtendedAttribute(name: name, data: data)
        }.sorted { $0.name < $1.name }
    }
    public static func write(_ name: String, data: Data, to url: URL) throws {
        guard !name.isEmpty, !name.contains("\0"), name.utf8.count <= 127 else { throw CommandFailure("Enter an attribute name of 1–127 UTF-8 bytes.") }
        let result = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw failure(url) }
    }
    public static func remove(_ name: String, from url: URL) throws {
        guard removexattr(url.path, name, XATTR_NOFOLLOW) == 0 else { throw failure(url) }
    }
}
