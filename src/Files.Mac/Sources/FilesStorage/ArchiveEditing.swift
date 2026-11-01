import Foundation
import FilesShared

public enum ArchiveEdit: Sendable { case add([URL], prefix: String, conflict: ConflictPolicy = .keepBoth, verifyContents: Bool = false), remove(Set<String>), rename(String, to: String), create(String, prefix: String, directory: Bool), permissions(Set<String>, UInt16) }
public extension ArchiveService {
    static func editableFormat(_ url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .gzip }
        if name.hasSuffix(".tar.bz2") { return .bzip }
        switch url.pathExtension.lowercased() { case "zip": return .zip; case "7z": return .sevenZip; case "tar": return .tar; default: return nil }
    }
    func edit(_ url: URL, change: ArchiveEdit, password: String = "") async throws -> OperationReport {
        guard let format = Self.editableFormat(url) else { throw ArchiveFailure("This archive format is read-only. Extract it and create a ZIP or 7z archive to edit its contents.") }
        let original = try ListedItem(url: url); let identity = FileIdentity(url)
        guard !original.isSymbolicLink else { throw ArchiveFailure("Edit the archive target instead of a symbolic link.") }
        let existing = try await list(url, password: password)
        guard !existing.contains(where: { $0.encrypted }) || !password.isEmpty else { throw ArchiveFailure("Enter the archive password before editing.") }
        let fm = FileManager.default; let work = fm.temporaryDirectory.appendingPathComponent("MacFiles-archive-edit-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); defer { try? fm.removeItem(at: work) }
        let extraction = try await extract(url, to: work, password: password)
        guard let root = extraction.completed.first else { throw ArchiveFailure("Could not prepare archive contents.") }
        func resolve(_ path: String, leafLink: Bool = false) throws -> URL {
            let parts = try Self.validatedPath(path); var result = root
            for (index, part) in parts.enumerated() {
                result.appendPathComponent(part)
                if !(leafLink && index == parts.count - 1) && (try? result.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw ArchiveFailure("Archive editing cannot traverse symbolic links.") }
            }
            return result
        }
        var added: [URL]?
        var verifyAdded = false
        var addedPaths: [(URL, String)] = []
        switch change {
        case .add(let sources, let prefix, let conflict, let verify):
            added = []; verifyAdded = verify
            let folder = try resolve(prefix)
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw StorageError.notDirectory }
            for source in sources {
                try Task.checkCancellation()
                var target = folder.appendingPathComponent(source.lastPathComponent)
                if (try? fm.attributesOfItem(atPath: target.path)) != nil {
                    if conflict == .skip { continue }
                    if conflict == .replace { try fm.removeItem(at: target) }
                    else {
                        let ext = source.pathExtension; let stem = source.deletingPathExtension().lastPathComponent; var index = 2
                        repeat { target = folder.appendingPathComponent("\(stem) (\(index))" + (ext.isEmpty ? "" : "." + ext)); index += 1 } while (try? fm.attributesOfItem(atPath: target.path)) != nil
                    }
                }
                try CancellableCopy.copy(source, to: target); added?.append(source); addedPaths.append((source, String(target.path.dropFirst(root.path.count + 1))))
            }
        case .create(let name, let prefix, let directory):
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw StorageError.invalidName }
            let target = try resolve(prefix).appendingPathComponent(name)
            guard (try? fm.attributesOfItem(atPath: target.path)) == nil else { throw StorageError.alreadyExists(name) }
            if directory { try fm.createDirectory(at: target, withIntermediateDirectories: false) }
            else { try Data().write(to: target, options: .withoutOverwriting) }
        case .permissions(let paths, let mode):
            guard mode <= 0o777 else { throw StorageError.invalidName }
            for path in paths { let target = try resolve(path); try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path) }
        case .remove(let paths):
            guard !paths.isEmpty else { throw ArchiveFailure("Select archive entries to remove.") }
            let roots = paths.filter { path in !paths.contains { other in path != other && path.hasPrefix(other.hasSuffix("/") ? other : other + "/") } }
            for path in roots { let target = try resolve(path, leafLink: true); guard target.path != root.path else { throw ArchiveFailure("Cannot remove the archive root.") }; try fm.removeItem(at: target) }
        case .rename(let path, let name):
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw StorageError.invalidName }
            let source = try resolve(path, leafLink: true); let target = source.deletingLastPathComponent().appendingPathComponent(name)
            guard source.path != root.path else { throw ArchiveFailure("Cannot rename the archive root.") }
            guard (try? fm.attributesOfItem(atPath: target.path)) == nil else { throw StorageError.alreadyExists(name) }
            try fm.moveItem(at: source, to: target)
        }
        let outputFolder = work.appendingPathComponent("output"); try fm.createDirectory(at: outputFolder, withIntermediateDirectories: false)
        let output = outputFolder.appendingPathComponent(url.lastPathComponent)
        let sources = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        _ = try await compress(sources, to: output, format: format, password: password)
        if verifyAdded && !addedPaths.isEmpty {
            let verification = work.appendingPathComponent("verification"); try fm.createDirectory(at: verification, withIntermediateDirectories: false)
            let extracted = try await extract(output, to: verification, selected: Set(addedPaths.map { $0.1 }), password: password)
            guard let verifiedRoot = extracted.completed.first else { throw ArchiveFailure("No archive entry was extracted.") }
            for (source, path) in addedPaths {
                guard try TransferFingerprint.digest(source) == TransferFingerprint.digest(verifiedRoot.appendingPathComponent(path)) else { throw CommandFailure("The uploaded data did not match its source. The source was retained.") }
            }
        }
        try Task.checkCancellation()
        let staged = work.appendingPathComponent(url.lastPathComponent)
        try fm.copyItem(at: url, to: staged)
        let input = try FileHandle(forReadingFrom: output); defer { try? input.close() }
        let handle = try FileHandle(forWritingTo: staged); defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty { try Task.checkCancellation(); try handle.write(contentsOf: chunk) }
        try handle.synchronize()
        var report = try await MacStorageService.shared.replacePrepared(staged, original: url, identity: identity, modified: original.modified, size: original.size)
        if let added { report.completed = added }
        return report
    }
}
