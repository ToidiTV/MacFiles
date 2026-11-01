// Copyright (c) 2026 MacFiles contributors. Licensed under the MIT License.
import Foundation
import FilesShared

public enum StorageError: LocalizedError {
    case invalidName, recursiveDestination, alreadyExists(String), notDirectory, noUndo, changedItem(String)
    public var errorDescription: String? {
        switch self {
        case .invalidName: return NativeLocalization.text("Enter a name without a slash or colon. The name cannot be empty, ‘.’, or ‘..’.")
        case .recursiveDestination: return NativeLocalization.text("A folder cannot be copied or moved inside itself.")
        case .alreadyExists(let name): return NativeLocalization.text("‘\(name)’ already exists. Choose a different name.")
        case .notDirectory: return NativeLocalization.text("The destination is not an accessible folder.")
        case .noUndo: return NativeLocalization.text("This operation cannot be undone.")
        case .changedItem(let name): return NativeLocalization.text("‘\(name)’ was replaced since this operation. Undo left the replacement untouched.")
        }
    }
}

public enum ConflictPolicy: String, Sendable { case keepBoth, skip, replace }

public enum FileOperation: String, Sendable { case copy, move, trash }
public struct FileIdentity: Equatable, Codable, Sendable {
    let device: UInt64
    let inode: UInt64
    public init?(_ url: URL) {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = values[.systemNumber] as? NSNumber,
              let inode = values[.systemFileNumber] as? NSNumber else { return nil }
        self.device = device.uint64Value; self.inode = inode.uint64Value
    }
}
public indirect enum UndoStep: Codable, Sendable {
    case move(from: URL, to: URL, identity: FileIdentity? = nil)
    case trash(URL, identity: FileIdentity? = nil)
    case batchRename([RenameUndoItem])
    case remote(UUID, [RemoteUndoStep])
    case compound([UndoStep])
}
public struct OperationReport: Sendable {
    public var completed: [URL] = []
    public var undo: [UndoStep] = []
    public var inverse: [UndoStep] = []
    public var errors: [String] = []
    public var renamedCount = 0
    public init() {}
}

public struct DirectoryListing: Sendable {
    public let items: [ListedItem]
    public let skipped: Int
}

public enum MacDirectoryService {
    public static func listLocations(_ roots: [URL], query: String?, hidden: Bool) throws -> DirectoryListing {
        var items: [ListedItem] = []; var skipped = 0; var lastError: Error?
        var successful = 0
        for root in roots {
            try Task.checkCancellation()
            do {
                let result = try query.map { try search(root, query: $0, hidden: hidden) } ?? list(root, hidden: hidden)
                items += result.items; skipped += result.skipped; successful += 1
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error; skipped += 1 }
        }
        if successful == 0, let lastError { throw lastError }
        var seen = Set<URL>()
        return DirectoryListing(items: items.filter { seen.insert($0.url).inserted }, skipped: skipped)
    }
    public static func list(_ directory: URL, hidden: Bool) throws -> DirectoryListing {
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(ListedItem.keys), options: hidden ? [] : [.skipsHiddenFiles])
        var items: [ListedItem] = []; var skipped = 0
        for url in urls {
            try Task.checkCancellation()
            do { items.append(try ListedItem(url: url)) } catch { skipped += 1 }
        }
        return DirectoryListing(items: items, skipped: skipped)
    }

    public static func search(_ directory: URL, query: String, hidden: Bool) throws -> DirectoryListing {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !hidden { options.insert(.skipsHiddenFiles) }
        var skipped = 0
        guard let enumerator = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: Array(ListedItem.keys), options: options,
            errorHandler: { _, _ in skipped += 1; return true }) else { throw StorageError.notDirectory }
        var result: [ListedItem] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if url.lastPathComponent.localizedStandardContains(query) {
                do { result.append(try ListedItem(url: url)) } catch { skipped += 1 }
            }
        }
        return DirectoryListing(items: result, skipped: skipped)
    }
}

public actor MacStorageService {
    public static let shared = MacStorageService()
    private let fm = FileManager.default
    public init() {}

    public static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0")
        else { throw StorageError.invalidName }
    }

    private func exists(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    private func available(_ target: URL) -> URL {
        guard exists(target) else { return target }
        let folder = target.deletingLastPathComponent()
        let item = try? ListedItem(url: target)
        let ext = item?.isBrowsable == true ? "" : target.pathExtension
        let stem = ext.isEmpty ? target.lastPathComponent : target.deletingPathExtension().lastPathComponent
        var index = 2
        var candidate: URL
        repeat {
            candidate = folder.appendingPathComponent("\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"))
            index += 1
        } while exists(candidate)
        return candidate
    }

    public func create(in folder: URL, name: String, directory: Bool) throws -> OperationReport {
        try Self.validateName(name)
        let url = folder.appendingPathComponent(name)
        guard !exists(url) else { throw StorageError.alreadyExists(name) }
        if directory { try fm.createDirectory(at: url, withIntermediateDirectories: false) }
        else { try Data().write(to: url, options: .withoutOverwriting) }
        var result = OperationReport()
        result.completed = [url]; result.undo = [.trash(url, identity: FileIdentity(url))]
        return result
    }

    public func rename(_ url: URL, to name: String) throws -> OperationReport {
        try Self.validateName(name)
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard url != destination else { return OperationReport() }
        // Never replace another entry, including a dangling symbolic link.
        if exists(destination) {
            let names = try fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            guard !names.contains(name), url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame else {
                throw StorageError.alreadyExists(name)
            }
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".macfiles-rename-\(UUID().uuidString)")
            try fm.moveItem(at: url, to: temporary)
            do { try fm.moveItem(at: temporary, to: destination) }
            catch {
                let originalError = error
                do { try fm.moveItem(at: temporary, to: url) }
                catch {
                    throw NSError(domain: "MacFiles", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "Rename failed. Your item is preserved at \(temporary.path). \(originalError.localizedDescription)"])
                }
                throw originalError
            }
        } else { try fm.moveItem(at: url, to: destination) }
        var result = OperationReport()
        result.completed = [destination]; result.undo = [.move(from: destination, to: url, identity: FileIdentity(destination))]
        return result
    }

    public func perform(_ operation: FileOperation, sources: [URL], destination: URL?, conflict: ConflictPolicy = .keepBoth,
                        progress: @Sendable (Int, Int, String) -> Void = { _, _, _ in }) -> OperationReport {
        var result = OperationReport()
        let unique = Array(Set(sources.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        // A selected parent already includes its selected children.
        let roots = unique.filter { candidate in
            !unique.contains { other in other != candidate && candidate.path.hasPrefix(other.path + "/") }
        }
        for (index, source) in roots.enumerated() {
            if Task.isCancelled { result.errors.append("Stopped before the next item. Completed items were kept."); break }
            progress(index, roots.count, source.lastPathComponent)
            do {
                if operation == .trash {
                    var trashed: NSURL?
                    try fm.trashItem(at: source, resultingItemURL: &trashed)
                    result.completed.append(source)
                    if let trashed { result.undo.append(.move(from: trashed as URL, to: source, identity: FileIdentity(trashed as URL))) }
                } else {
                    guard let destination,
                          (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    else { throw StorageError.notDirectory }
                    let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL.path
                    let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL.path
                    if (try? ListedItem(url: source).isBrowsable) == true &&
                        (canonicalSource == "/" || canonicalDestination == canonicalSource || canonicalDestination.hasPrefix(canonicalSource + "/")) {
                        throw StorageError.recursiveDestination
                    }
                    let requested = destination.appendingPathComponent(source.lastPathComponent)
                    if operation == .move && requested.standardizedFileURL == source { continue }
                    let collision = exists(requested)
                    if collision && conflict == .skip { continue }
                    // A duplicate of itself always keeps both, even when the caller requested replacement.
                    let replaces = collision && conflict == .replace && requested.standardizedFileURL != source.standardizedFileURL
                    let target = replaces ? requested : available(requested)
                    if target != requested { result.renamedCount += 1 }
                    let staging = destination.appendingPathComponent(".MacFiles-copy-\(UUID().uuidString)")
                    defer { if exists(staging) { try? fm.removeItem(at: staging) } }
                    // Finish a copy in a private temporary location before moving an existing destination to Trash.
                    if operation == .copy { try CancellableCopy.copy(source, to: staging) }
                    var backup: URL?
                    if replaces {
                        var trashed: NSURL?
                        try fm.trashItem(at: target, resultingItemURL: &trashed)
                        backup = trashed as URL?
                        guard backup != nil else { throw CommandFailure("macOS moved the previous version to Trash but did not return its location. The new version was not installed.") }
                    }
                    do {
                        try fm.moveItem(at: operation == .copy ? staging : source, to: target)
                    } catch {
                        if let backup {
                            if !exists(target) { try? fm.moveItem(at: backup, to: target) }
                            if exists(backup) { result.undo.append(.move(from: backup, to: target, identity: FileIdentity(backup))) }
                        }
                        throw error
                    }
                    if let backup { result.undo.append(.move(from: backup, to: target, identity: FileIdentity(backup))) }
                    if operation == .copy { result.undo.append(.trash(target, identity: FileIdentity(target))) }
                    else { result.undo.append(.move(from: target, to: source, identity: FileIdentity(target))) }
                    result.completed.append(target)
                }
            } catch { result.errors.append("\(source.lastPathComponent): \(error.localizedDescription)") }
        }
        progress(roots.count, roots.count, "")
        return result
    }

    public func flatten(_ root: URL) throws -> OperationReport {
        let rootItem = try ListedItem(url: root)
        guard rootItem.isBrowsable, !rootItem.isSymbolicLink else { throw StorageError.notDirectory }
        var enumerationErrors: [String] = []
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: Array(ListedItem.keys), options: [.skipsPackageDescendants], errorHandler: { url, error in enumerationErrors.append("\(url.lastPathComponent): \(error.localizedDescription)"); return true }) else { throw StorageError.notDirectory }
        var files: [URL] = []; var folders: [URL] = []
        for case let url as URL in walker {
            try Task.checkCancellation()
            let item = try ListedItem(url: url)
            if item.isSymbolicLink { walker.skipDescendants(); continue }
            if item.isBrowsable { folders.append(url) }
            else if url.deletingLastPathComponent().resolvingSymlinksInPath() != root.resolvingSymlinksInPath() { files.append(url) }
        }
        var report = OperationReport()
        for file in files {
            // Transfer one by one so selecting a parent never suppresses a nested file.
            let result = perform(.move, sources: [file], destination: root, conflict: .skip)
            report.completed += result.completed; report.undo += result.undo; report.errors += result.errors
            if Task.isCancelled { return report }
        }
        for folder in folders.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            guard !Task.isCancelled else { return report }
            if (try? fm.contentsOfDirectory(atPath: folder.path).isEmpty) == true {
                let result = perform(.trash, sources: [folder], destination: nil)
                report.undo += result.undo; report.errors += result.errors
            }
        }
        report.errors += enumerationErrors
        return report
    }

    public func permanentlyDelete(_ urls: [URL]) -> OperationReport {
        var result = OperationReport()
        for url in urls {
            do { try Task.checkCancellation(); try fm.removeItem(at: url); result.completed.append(url) }
            catch { result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }
    public func undo(_ steps: [UndoStep]) async -> OperationReport {
        var report = OperationReport()
        for step in steps.reversed() {
            do {
                switch step {
                case .move(let source, let target, let identity):
                    if let identity, FileIdentity(source) != identity { throw StorageError.changedItem(source.lastPathComponent) }
                    if source.deletingLastPathComponent() == target.deletingLastPathComponent() {
                        _ = try rename(source, to: target.lastPathComponent)
                    } else {
                        guard !exists(target) else { throw StorageError.alreadyExists(target.lastPathComponent) }
                        try fm.moveItem(at: source, to: target)
                    }
                    report.completed.append(target)
                    report.inverse.append(.move(from: target, to: source, identity: FileIdentity(target)))
                case .trash(let url, let identity):
                    if let identity, FileIdentity(url) != identity { throw StorageError.changedItem(url.lastPathComponent) }
                    var trashed: NSURL?
                    try fm.trashItem(at: url, resultingItemURL: &trashed)
                    report.completed.append(url)
                    if let trashed { report.inverse.append(.move(from: trashed as URL, to: url, identity: FileIdentity(trashed as URL))) }
                case .compound(let steps):
                    var inverses: [UndoStep] = []
                    for index in steps.indices.reversed() {
                        let result = await undo([steps[index]])
                        report.completed += result.completed; inverses += result.inverse
                        if !result.errors.isEmpty {
                            report.errors += result.errors
                            report.undo.insert(.compound(Array(steps.prefix(index)) + result.undo), at: 0)
                            break
                        }
                    }
                    if !inverses.isEmpty { report.inverse.append(.compound(inverses)) }
                case .remote(let id, let steps):
                    let inverse = try await RemoteUndoRegistry.shared.undo(id, steps: steps)
                    report.inverse.append(.remote(id, inverse))
                case .batchRename(let entries):
                    for entry in entries {
                        if let identity = entry.identity, FileIdentity(entry.current) != identity { throw StorageError.changedItem(entry.current.lastPathComponent) }
                    }
                    let result = try bulkRename(entries.map { RenameProposal(source: $0.current, name: $0.original.lastPathComponent) })
                    report.completed += result.completed
                    report.inverse += result.undo
                }
            } catch {
                report.errors.append(error.localizedDescription)
                report.undo.insert(step, at: 0)
            }
        }
        return report
    }
}
