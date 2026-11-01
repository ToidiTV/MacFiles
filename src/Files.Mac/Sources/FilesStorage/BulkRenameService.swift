import Foundation

public struct RenameUndoItem: Codable, Sendable {
    public let current: URL
    public let original: URL
    public let identity: FileIdentity?
}

extension MacStorageService {
    public func createUniqueAlias(_ source: URL, in folder: URL) throws -> OperationReport {
        let base = source.lastPathComponent + " alias"
        var index = 1
        while index < 10000 {
            let name = index == 1 ? base : "\(base) \(index)"
            do { return try createAlias(source, in: folder, name: name) }
            catch { if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSFileWriteFileExistsError { throw error } }
            index += 1
        }
        throw CommandFailure("Could not find an available filename.")
    }
    public func createAlias(_ source: URL, in folder: URL, name: String) throws -> OperationReport {
        try Self.validateName(name)
        let target = folder.appendingPathComponent(name)
        let temporary = folder.appendingPathComponent(".MacFiles-alias-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let data = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: target)
        var report = OperationReport(); report.completed = [target]; report.undo = [.trash(target, identity: FileIdentity(target))]
        return report
    }
    public func bulkRename(_ proposals: [RenameProposal]) throws -> OperationReport {
        let fm = FileManager.default
        let changed = proposals.filter { $0.name != $0.source.lastPathComponent }
        guard let parent = changed.first?.source.deletingLastPathComponent() else { return OperationReport() }
        guard changed.allSatisfy({ $0.source.deletingLastPathComponent() == parent }) else { throw CommandFailure("Bulk rename requires items from one folder.") }
        let sensitive = (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) ?? false
        func key(_ name: String) -> String { sensitive ? name : name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        let sources = Set(changed.map { key($0.source.lastPathComponent) })
        var targets = Set<String>()
        let existing = Set(try fm.contentsOfDirectory(atPath: parent.path).map(key))
        for proposal in changed {
            try Self.validateName(proposal.name)
            guard targets.insert(key(proposal.name)).inserted else { throw StorageError.alreadyExists(proposal.name) }
            if existing.contains(key(proposal.name)) && !sources.contains(key(proposal.name)) { throw StorageError.alreadyExists(proposal.name) }
            _ = try fm.attributesOfItem(atPath: proposal.source.path)
        }
        var staged: [(source: URL, temporary: URL, destination: URL)] = []
        var committed = Set<URL>()
        do {
            for proposal in changed {
                try Task.checkCancellation()
                let temporary = parent.appendingPathComponent(".MacFiles-rename-\(UUID().uuidString)")
                try fm.moveItem(at: proposal.source, to: temporary)
                staged.append((proposal.source, temporary, parent.appendingPathComponent(proposal.name)))
            }
            for item in staged {
                try Task.checkCancellation()
                try fm.moveItem(at: item.temporary, to: item.destination)
                committed.insert(item.destination)
            }
        } catch {
            var recovery: [String] = []
            for item in staged where committed.contains(item.destination) {
                do { try fm.moveItem(at: item.destination, to: item.temporary) }
                catch { recovery.append(item.destination.path) }
            }
            for item in staged where (try? fm.attributesOfItem(atPath: item.temporary.path)) != nil {
                do { try fm.moveItem(at: item.temporary, to: item.source) }
                catch { recovery.append(item.temporary.path) }
            }
            throw CommandFailure(error.localizedDescription + (recovery.isEmpty ? " No names were changed." : " Items preserved at: " + recovery.joined(separator: ", ")))
        }
        var report = OperationReport()
        report.completed = staged.map(\.destination)
        report.undo = [.batchRename(staged.map { RenameUndoItem(current: $0.destination, original: $0.source, identity: FileIdentity($0.destination)) })]
        return report
    }
}

extension MacStorageService {
    public func createFromTemplate(_ source: URL, in folder: URL, name: String) throws -> OperationReport {
        try Self.validateName(name)
        let fm = FileManager.default
        let target = folder.appendingPathComponent(name)
        guard (try? fm.attributesOfItem(atPath: target.path)) == nil else { throw StorageError.alreadyExists(name) }
        let stage = folder.appendingPathComponent(".MacFiles-template-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: source, to: stage)
        try fm.moveItem(at: stage, to: target)
        var report = OperationReport(); report.completed = [target]; report.undo = [.trash(target, identity: FileIdentity(target))]
        return report
    }
}

extension MacStorageService {
    public func retargetShortcut(_ url: URL, to target: URL) throws -> OperationReport {
        let fm = FileManager.default
        let values = try url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
        guard values.isAliasFile == true || values.isSymbolicLink == true else { throw CommandFailure("Select a macOS alias or symbolic link.") }
        guard url.standardizedFileURL != target.standardizedFileURL, url.standardizedFileURL != target.resolvingSymlinksInPath().standardizedFileURL else { throw CommandFailure("A shortcut cannot target itself.") }
        guard (try? fm.attributesOfItem(atPath: target.path)) != nil else { throw CommandFailure("The new shortcut target does not exist.") }
        let stage = url.deletingLastPathComponent().appendingPathComponent(".MacFiles-link-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        if values.isSymbolicLink == true { try fm.createSymbolicLink(at: stage, withDestinationURL: target) }
        else { let data = try target.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil); try URL.writeBookmarkData(data, to: stage) }
        var trashed: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &trashed)
        guard let backup = trashed as URL? else { throw CommandFailure("The old shortcut is in Trash, but macOS did not return its location.") }
        do { try fm.moveItem(at: stage, to: url) }
        catch { try? fm.moveItem(at: backup, to: url); throw error }
        var result = OperationReport(); result.completed = [url]
        result.undo = [.move(from: backup, to: url, identity: FileIdentity(backup)), .trash(url, identity: FileIdentity(url))]
        return result
    }
}
