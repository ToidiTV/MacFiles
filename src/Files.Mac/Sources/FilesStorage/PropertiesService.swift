import Foundation
import CoreServices
import Darwin
import FilesShared

public struct PropertyValue: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let value: String
    public init(_ name: String, _ value: String) { self.name = name; self.value = value }
}
public struct FileSecurity: Sendable {
    public let owner: String
    public let group: String
    public let uid: UInt32
    public let gid: UInt32
    public let mode: String
    public let acl: String
}
public enum PropertiesService {
    private static func posix(_ url: URL) -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
    public static func general(_ urls: [URL]) throws -> [PropertyValue] {
        var logical: Int64 = 0; var allocated: Int64 = 0; var folders = 0
        for url in urls {
            let item = try ListedItem(url: url); if item.isDirectory { folders += 1 }
            let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
            logical += item.size; allocated += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var output = [PropertyValue("Selected items", "\(urls.count)"), .init("Folders", "\(folders)"), .init("File size", ByteCountFormatter.string(fromByteCount: logical, countStyle: .file)), .init("Allocated size", ByteCountFormatter.string(fromByteCount: allocated, countStyle: .file))]
        guard urls.count == 1, let url = urls.first else { return output }
        let item = try ListedItem(url: url)
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey, .volumeSupportsCaseSensitiveNamesKey, .isReadableKey, .isWritableKey, .isExecutableKey, .isUserImmutableKey])
        output.append(.init("Name", item.name)); output.append(.init("Path", url.path)); output.append(.init("Kind", item.localizedKind))
        output.append(.init("Content type", values.contentType?.identifier ?? NativeLocalization.text("Unknown")))
        output.append(.init("Created", item.created?.formatted(.dateTime.locale(NativeLocalization.locale)) ?? NativeLocalization.text("Unknown"))); output.append(.init("Modified", item.modified?.formatted(.dateTime.locale(NativeLocalization.locale)) ?? NativeLocalization.text("Unknown")))
        output.append(.init("Volume", values.volumeName ?? NativeLocalization.text("Unknown")))
        output.append(.init("Readable", NativeLocalization.text(values.isReadable == true ? "Yes" : "No"))); output.append(.init("Writable", NativeLocalization.text(values.isWritable == true ? "Yes" : "No")))
        output.append(.init("Executable", NativeLocalization.text(values.isExecutable == true ? "Yes" : "No"))); output.append(.init("Hidden", NativeLocalization.text(item.isHidden ? "Yes" : "No"))); output.append(.init("Locked", NativeLocalization.text(values.isUserImmutable == true ? "Yes" : "No")))
        if let capacity = values.volumeTotalCapacity { output.append(.init("Volume capacity", ByteCountFormatter.string(fromByteCount: Int64(capacity), countStyle: .file))) }
        if let free = values.volumeAvailableCapacity { output.append(.init("Volume available", ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file))) }
        output.append(.init("Volume case sensitive", NativeLocalization.text(values.volumeSupportsCaseSensitiveNames == true ? "Yes" : "No")))
        output.append(.init("Volume read only", NativeLocalization.text(values.volumeIsReadOnly == true ? "Yes" : "No")))
        return output
    }
    public static func metadata(_ url: URL) -> [PropertyValue] {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString), let names = MDItemCopyAttributeNames(item), let attributes = MDItemCopyAttributes(item, names) as? [String: Any] else { return [] }
        return attributes.keys.filter { !$0.hasPrefix("_") && !$0.hasSuffix("_Ranking") }.sorted().compactMap { key in
            guard let value = attributes[key], !(value is NSNull) else { return nil }
            let text: String
            if let date = value as? Date { text = date.formatted(.dateTime.locale(NativeLocalization.locale)) }
            else if let values = value as? [Any] { text = values.map { String(describing: $0) }.joined(separator: ", ") }
            else { text = String(describing: value) }
            let label = key.replacingOccurrences(of: "kMDItemFS", with: "File ").replacingOccurrences(of: "kMDItem", with: "").replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            return .init(label, text)
        }
    }
    public static func security(_ url: URL) throws -> FileSecurity {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let uid = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value ?? 0
        let gid = (attrs[.groupOwnerAccountID] as? NSNumber)?.uint32Value ?? 0
        let mode = String(format: "%03o", ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777)
        let acl = acl_get_link_np(url.path, ACL_TYPE_EXTENDED)
        var text = "!#acl 1\n"
        if let acl {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var length = 0
            guard let raw = acl_to_text(acl, &length) else { throw posix(url) }
            defer { acl_free(raw) }; text = String(cString: raw)
        } else if errno != ENOENT { throw posix(url) }
        return FileSecurity(owner: attrs[.ownerAccountName] as? String ?? String(uid), group: attrs[.groupOwnerAccountName] as? String ?? String(gid), uid: uid, gid: gid, mode: mode, acl: text)
    }
    public static func validateACL(_ text: String) throws {
        guard !text.contains("\0"), let acl = acl_from_text(text) else { throw CommandFailure("Invalid macOS ACL text. Preserve the !#acl 1 header and use valid entries.") }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw CommandFailure("The ACL failed validation.") }
    }
    public static func setACL(_ text: String, at url: URL, expected: FileIdentity?) throws {
        try validateACL(text)
        guard expected == FileIdentity(url), expected != nil else { throw StorageError.changedItem(url.lastPathComponent) }
        guard let acl = acl_from_text(text) else { throw posix(url) }; defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_link_np(url.path, ACL_TYPE_EXTENDED, acl) == 0 else { throw posix(url) }
    }
    public static func setOwner(uid: UInt32, gid: UInt32, at url: URL, expected: FileIdentity?) throws {
        guard expected == FileIdentity(url), expected != nil else { throw StorageError.changedItem(url.lastPathComponent) }
        guard lchown(url.path, uid, gid) == 0 else { throw posix(url) }
    }
    public static func setFlags(hidden: Bool, locked: Bool, at url: URL) throws {
        guard (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CommandFailure("Edit the target's attributes instead of a symbolic link.") }
        let previous = try url.resourceValues(forKeys: [.isHiddenKey, .isUserImmutableKey])
        let wasLocked = previous.isUserImmutable == true
        do {
            try (url as NSURL).setResourceValue(false, forKey: .isUserImmutableKey)
            try (url as NSURL).setResourceValue(hidden, forKey: .isHiddenKey)
            try (url as NSURL).setResourceValue(locked, forKey: .isUserImmutableKey)
        } catch {
            try? (url as NSURL).setResourceValue(previous.isHidden == true, forKey: .isHiddenKey)
            try? (url as NSURL).setResourceValue(wasLocked, forKey: .isUserImmutableKey)
            throw error
        }
    }
    public static func applicationInfo(_ url: URL) async throws -> [PropertyValue] {
        let info = Bundle(url: url)?.infoDictionary ?? [:]
        var values: [PropertyValue] = []
        for key in ["CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion", "LSArchitecturePriority", "LSRequiresNativeExecution", "NSHighResolutionCapable"] {
            if let value = info[key] { values.append(.init(key, String(describing: value))) }
        }
        var executable = url
        if let name = info["CFBundleExecutable"] as? String, !name.contains("/"), name != ".." { executable = url.appendingPathComponent("Contents/MacOS/" + name) }
        let file = try await ProcessService.run("/usr/bin/file", ["-b", executable.path], check: false)
        values.append(.init("Executable format", file.output.trimmingCharacters(in: .whitespacesAndNewlines)))
        values.append(.init("This Mac", ProcessInfo.processInfo.operatingSystemVersionString))
        return values
    }
    public static func signature(_ url: URL) async throws -> String {
        let description = try await ProcessService.run("/usr/bin/codesign", ["--display", "--verbose=4", url.path], check: false)
        guard description.status == 0 else { return NativeLocalization.text("No readable macOS code signature.\n\n") + description.output }
        let verification = try await ProcessService.run("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", url.path], check: false)
        return NativeLocalization.text(verification.status == 0 ? "Signature integrity verified. This does not constitute a notarization or malware assessment." : "Signature integrity verification failed.") + "\n\n" + description.output + "\n" + verification.output
    }
}
