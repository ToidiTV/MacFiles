import Foundation
import FilesShared
import CArchive
import Darwin

public struct ArchiveMember: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let directory: Bool
    public let link: Bool
    public let encrypted: Bool
    public let modified: Date
    public var linkTarget: String? = nil
    public var hardLink = false
    public var posixPermissions: UInt16? = nil
    public init(path: String, size: Int64, directory: Bool, link: Bool, encrypted: Bool, modified: Date, linkTarget: String? = nil, hardLink: Bool = false, posixPermissions: UInt16? = nil) {
        self.path = path; self.size = size; self.directory = directory; self.link = link; self.encrypted = encrypted; self.modified = modified; self.linkTarget = linkTarget; self.hardLink = hardLink; self.posixPermissions = posixPermissions
    }
}

public extension ArchiveMember {
    static func children(of prefix: String, in entries: [ArchiveMember]) -> [ArchiveMember] {
        var children: [String: ArchiveMember] = [:]
        for entry in entries where entry.path.hasPrefix(prefix) {
            let suffix = String(entry.path.dropFirst(prefix.count))
            let parts = suffix.split(separator: "/")
            guard let first = parts.first else { continue }
            let directory = parts.count > 1 || entry.directory
            let path = prefix + first + (directory ? "/" : "")
            if parts.count == 1 { children[path] = entry }
            else if children[path] == nil { children[path] = ArchiveMember(path: path, size: 0, directory: true, link: false, encrypted: false, modified: entry.modified) }
        }
        return children.values.sorted { $0.directory != $1.directory ? $0.directory : $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

public enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip = "ZIP", sevenZip = "7z", tar = "TAR", gzip = "TAR.GZ", bzip = "TAR.BZ2"
    public var extensionName: String {
        switch self { case .zip: return "zip"; case .sevenZip: return "7z"; case .tar: return "tar"; case .gzip: return "tar.gz"; case .bzip: return "tar.bz2" }
    }
}

public struct ArchiveFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { NativeLocalization.text(message) }
    public init(_ message: String) { self.message = message }
}

public actor ArchiveService {
    private let fm = FileManager.default
    public init() {}
    public static func supports(_ url: URL) -> Bool {
        ["001", "zip", "7z", "tar", "gz", "tgz", "bz2", "xz", "txz", "rar", "cab", "iso", "cpio", "xar"].contains(url.pathExtension.lowercased())
    }
    private func failure(_ archive: OpaquePointer) -> ArchiveFailure {
        ArchiveFailure(archive_error_string(archive).map { String(cString: $0) } ?? "Archive operation failed.")
    }
    private func check(_ result: Int32, _ archive: OpaquePointer) throws {
        guard result >= ARCHIVE_OK else { throw failure(archive) }
    }
    private func reader(_ url: URL, password: String) throws -> OpaquePointer {
        guard let reader = archive_read_new() else { throw ArchiveFailure("Cannot allocate archive reader.") }
        archive_read_support_filter_all(reader); archive_read_support_format_all(reader)
        if !password.isEmpty { archive_read_add_passphrase(reader, password) }
        do { try check(archive_read_open_filename(reader, url.path, 65536), reader) }
        catch { archive_read_free(reader); throw error }
        return reader
    }
    public static func validatedPath(_ path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains("\\"), !path.contains("\0") else {
            throw ArchiveFailure("Archive contains an unsafe path: \(path)")
        }
        let components = path.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !components.contains(".."), !(components.first?.contains(":") ?? false) else {
            throw ArchiveFailure("Archive path escapes the destination: \(path)")
        }
        return components
    }
    public func list(_ url: URL, password: String = "") async throws -> [ArchiveMember] {
        if ["7z", "001", "rar"].contains(url.pathExtension.lowercased()) { return try await SevenZipService.list(url, password: password) }
        let reader = try reader(url, password: password); defer { archive_read_free(reader) }
        var result: [ArchiveMember] = []; var entry: OpaquePointer?
        while true {
            try Task.checkCancellation()
            let code = archive_read_next_header(reader, &entry)
            if code == ARCHIVE_EOF { break }
            try check(code, reader)
            guard let entry, let name = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { continue }
            let path = String(cString: name)
            result.append(ArchiveMember(path: path, size: archive_entry_size(entry),
                directory: archive_entry_filetype(entry) == UInt32(S_IFDIR),
                link: archive_entry_symlink(entry) != nil || archive_entry_hardlink(entry) != nil,
                encrypted: archive_entry_is_encrypted(entry) > 0, modified: Date(timeIntervalSince1970: Double(archive_entry_mtime(entry))), posixPermissions: UInt16(archive_entry_perm(entry) & 0o777)))
            try check(archive_read_data_skip(reader), reader)
        }
        return result
    }
    private func unique(_ url: URL) -> URL {
        var result = url; var number = 2
        while (try? fm.attributesOfItem(atPath: result.path)) != nil {
            result = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent) (\(number))")
            number += 1
        }
        return result
    }
    private func ensureParents(_ parts: [String], root: URL) throws -> URL {
        var parent = root
        for part in parts {
            parent.appendPathComponent(part)
            if let attributes = try? fm.attributesOfItem(atPath: parent.path) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw ArchiveFailure("Archive attempts to write through a link or file: \(part)") }
            } else { try fm.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        }
        return parent
    }
    public func extract(_ url: URL, to destination: URL, selected: Set<String> = [], password: String = "",
                        progress: @Sendable (String) -> Void = { _ in }) async throws -> OperationReport {
        if ["7z", "001", "rar"].contains(url.pathExtension.lowercased()) { return try await SevenZipService.extract(url, to: destination, selected: selected, password: password) }
        let reader = try reader(url, password: password); defer { archive_read_free(reader) }
        let staging = destination.appendingPathComponent(".MacFiles-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        var entry: OpaquePointer?; var deferredLinks: [(URL, URL)] = []
        var directoryAttributes: [(URL, [FileAttributeKey: Any])] = []
        var bytes: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try Task.checkCancellation()
            let code = archive_read_next_header(reader, &entry)
            if code == ARCHIVE_EOF { break }
            try check(code, reader)
            guard let entry, let raw = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { continue }
            let path = String(cString: raw)
            let parts = try Self.validatedPath(path)
            guard let name = parts.last else { archive_read_data_skip(reader); continue }
            if !selected.isEmpty && !selected.contains(where: { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) {
                archive_read_data_skip(reader); continue
            }
            progress(path)
            let parent = try ensureParents(Array(parts.dropLast()), root: staging)
            let target = parent.appendingPathComponent(name)
            let type = archive_entry_filetype(entry)
            let mode = archive_entry_perm(entry) & 0o777
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: mode), .modificationDate: Date(timeIntervalSince1970: Double(archive_entry_mtime(entry)))]
            if type == UInt32(S_IFDIR) {
                _ = try ensureParents(parts, root: staging)
                directoryAttributes.append((target, attributes)); continue
            }
            if let hardLink = archive_entry_hardlink(entry) {
                let linkParts = try Self.validatedPath(String(cString: hardLink))
                guard !linkParts.isEmpty else { throw ArchiveFailure("Invalid hard link.") }
                deferredLinks.append((target, staging.appendingPathComponent(linkParts.joined(separator: "/"))))
                continue
            }
            if let symlink = archive_entry_symlink(entry) {
                let link = String(cString: symlink)
                guard !link.hasPrefix("/"), !link.contains("\\") else { throw ArchiveFailure("Archive contains an unsafe symbolic link.") }
                let resolved = parent.appendingPathComponent(link).standardizedFileURL
                guard resolved.path.hasPrefix(staging.path + "/") else { throw ArchiveFailure("Archive symbolic link escapes the destination.") }
                try fm.createSymbolicLink(atPath: target.path, withDestinationPath: link)
                continue
            }
            guard type == UInt32(S_IFREG) || type == 0 else { throw ArchiveFailure("Special device entries cannot be extracted: \(path)") }
            let descriptor = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw ArchiveFailure("Cannot create archive entry: \(path)") }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                while true {
                    try Task.checkCancellation()
                    let count = archive_read_data(reader, &buffer, buffer.count)
                    if count == 0 { break }
                    guard count > 0 else { throw failure(reader) }
                    bytes += Int64(count)
                    // Recheck available disk space during streaming, including for unknown sizes.
                    if bytes >= 64 * 1024 * 1024 {
                        bytes = 0
                        let free = try destination.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
                        if free < 16 * 1024 * 1024 { throw ArchiveFailure("Not enough free space to finish extraction.") }
                    }
                    try handle.write(contentsOf: Data(buffer.prefix(count)))
                }
                try handle.close()
                try fm.setAttributes(attributes, ofItemAtPath: target.path)
            } catch { try? handle.close(); throw error }
        }
        for (target, source) in deferredLinks {
            let relative = String(source.path.dropFirst(staging.path.count + 1)).split(separator: "/").map(String.init)
            _ = try ensureParents(Array(relative.dropLast()), root: staging)
            guard (try fm.attributesOfItem(atPath: source.path)[.type]) as? FileAttributeType == .typeRegular,
                  link(source.path, target.path) == 0 else { throw ArchiveFailure("Cannot restore archive hard link.") }
        }
        for (directory, attributes) in directoryAttributes.reversed() { try fm.setAttributes(attributes, ofItemAtPath: directory.path) }
        let target = unique(destination.appendingPathComponent(url.deletingPathExtension().lastPathComponent))
        try fm.moveItem(at: staging, to: target)
        var report = OperationReport(); report.completed = [target]; report.undo = [.trash(target, identity: FileIdentity(target))]
        return report
    }

    private func archiveEntries(_ sources: [URL]) throws -> [(URL, String)] {
        var entries: [(URL, String)] = []
        var names = Set<String>()
        for source in sources {
            guard names.insert(source.lastPathComponent).inserted else { throw ArchiveFailure("Selected items have duplicate names. Archive them separately.") }
            entries.append((source, source.lastPathComponent))
            let attrs = try fm.attributesOfItem(atPath: source.path)
            if attrs[.type] as? FileAttributeType == .typeDirectory {
                var enumerationError: Error?
                let traversalRoot = source.resolvingSymlinksInPath()
                guard let enumerator = fm.enumerator(at: traversalRoot, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw StorageError.notDirectory }
                for case let child as URL in enumerator {
                    try Task.checkCancellation()
                    entries.append((child, source.lastPathComponent + "/" + child.pathComponents.suffix(enumerator.level).joined(separator: "/")))
                }
                if let enumerationError { throw enumerationError }
            }
        }
        return entries
    }

    public func compress(_ sources: [URL], to destination: URL, format: ArchiveFormat, password: String = "", volumeBytes: Int64? = nil, options: ArchiveCompressionOptions? = nil,
                         progress: @Sendable (String) -> Void = { _ in }) async throws -> OperationReport {
        if (format == .sevenZip && !password.isEmpty) || volumeBytes != nil || options != nil { return try await SevenZipService.compress(sources, to: destination, format: format, password: password, volumeBytes: volumeBytes, options: options) }
        guard (try? fm.attributesOfItem(atPath: destination.path)) == nil else { throw StorageError.alreadyExists(destination.lastPathComponent) }
        if !password.isEmpty && format != .zip { throw ArchiveFailure("Password protection is supported for ZIP archives.") }
        let entries = try archiveEntries(sources)
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".MacFiles-archive-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        guard let writer = archive_write_new() else { throw ArchiveFailure("Cannot allocate archive writer.") }
        defer { archive_write_free(writer) }
        switch format {
        case .zip: try check(archive_write_set_format_zip(writer), writer)
        case .sevenZip: try check(archive_write_set_format_7zip(writer), writer)
        case .tar, .gzip, .bzip:
            try check(archive_write_set_format_pax_restricted(writer), writer)
            if format == .gzip { try check(archive_write_add_filter_gzip(writer), writer) }
            if format == .bzip { try check(archive_write_add_filter_bzip2(writer), writer) }
        }
        if !password.isEmpty {
            try check(archive_write_set_passphrase(writer, password), writer)
            try check(archive_write_set_options(writer, "zip:encryption=aes256"), writer)
        }
        try check(archive_write_open_filename(writer, temp.path), writer)
        for (source, name) in entries {
            try Task.checkCancellation(); progress(name)
            guard let entry = archive_entry_new() else { throw ArchiveFailure("Cannot allocate archive entry.") }
            defer { archive_entry_free(entry) }
            var statInfo = stat()
            guard lstat(source.path, &statInfo) == 0 else { throw ArchiveFailure("Cannot read \(source.path)") }
            archive_entry_copy_stat(entry, &statInfo)
            archive_entry_set_pathname(entry, name)
            let type = statInfo.st_mode & S_IFMT
            if type == S_IFLNK { archive_entry_set_symlink(entry, try fm.destinationOfSymbolicLink(atPath: source.path)); archive_entry_set_size(entry, 0) }
            else if type == S_IFDIR { archive_entry_set_size(entry, 0) }
            else if type != S_IFREG { throw ArchiveFailure("Cannot archive special device: \(name)") }
            try check(archive_write_header(writer, entry), writer)
            if type == S_IFREG {
                let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
                while let data = try handle.read(upToCount: 65536), !data.isEmpty {
                    try Task.checkCancellation()
                    let written = data.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, data.count) }
                    guard written == data.count else { throw failure(writer) }
                }
            }
            try check(archive_write_finish_entry(writer), writer)
        }
        try check(archive_write_close(writer), writer)
        try fm.moveItem(at: temp, to: destination)
        var report = OperationReport(); report.completed = [destination]; report.undo = [.trash(destination, identity: FileIdentity(destination))]
        return report
    }
}
