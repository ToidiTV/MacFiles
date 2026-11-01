import AppKit
import UniformTypeIdentifiers
import FilesShared
import FilesStorage

struct VirtualFileReference {
    enum Origin { case archive(URL, String, ArchiveMember), remote(RemoteProvider, RemoteConnection, String, RemoteItem), local(URL) }
    let item: ListedItem
    let origin: Origin
    let localIdentity: FileIdentity?
    init(item: ListedItem, origin: Origin) {
        self.item = item; self.origin = origin
        if case .local(let url) = origin { localIdentity = FileIdentity(url) } else { localIdentity = nil }
    }
    func materialize(in folder: URL) async throws -> URL {
        switch origin {
        case .local(let url):
            let target = folder.appendingPathComponent(item.name)
            let task = Task.detached { try CancellableCopy.copy(url, to: target) }
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }; return target
        case .archive(let url, let password, let entry):
            let report = try await ArchiveService().extract(url, to: folder, selected: [entry.path], password: password)
            guard let root = report.completed.first else { throw ArchiveFailure("No archive entry was extracted.") }
            return root.appendingPathComponent(entry.path)
        case .remote(let provider, _, let path, let entry):
            guard let current = try await provider.list(path).first(where: { $0.name == entry.name }) else { throw StorageError.changedItem(entry.name) }
            return try await provider.download(current, from: path, to: folder)
        }
    }
    func remove() async throws -> OperationReport {
        switch origin {
        case .local(let url):
            guard localIdentity == FileIdentity(url) else { throw StorageError.changedItem(item.name) }
            let undo = await MacStorageService.shared.undo([.trash(url, identity: FileIdentity(url))])
            var report = undo; report.undo = undo.inverse; report.inverse = []; return report
        case .archive(let url, let password, let entry): return try await ArchiveService().edit(url, change: .remove([entry.path]), password: password)
        case .remote(let provider, _, let path, let entry):
            let result = try await provider.trash(entry, in: path)
            let id = await RemoteUndoRegistry.shared.register(provider)
            var report = OperationReport(); report.undo = [.remote(id, result.undo)]; report.completed = [item.url]; return report
        }
    }
}

@MainActor extension ShellPageViewModel {
    func virtualURL(_ path: String) -> URL {
        var parts = URLComponents(); parts.scheme = archiveURL == nil ? "macfiles-remote" : "macfiles-archive"; parts.host = id.uuidString; parts.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")); return parts.url!
    }
    var virtualItems: [ListedItem] {
        if archiveURL != nil {
            let values = archiveSession.search.isEmpty ? ArchiveMember.children(of: archiveSession.prefix, in: archiveSession.entries) : archiveSession.entries.filter { $0.path.localizedStandardContains(archiveSession.search) }
            return values.map { ListedItem(virtualURL: virtualURL($0.path), name: ($0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).lastPathComponent, directory: $0.directory, size: $0.size, modified: $0.modified == .distantPast ? nil : $0.modified, symbolicLink: $0.link) }
        }
        return networkSession.items.map { ListedItem(virtualURL: virtualURL((try? RemoteProvider.child(networkSession.path, $0.name)) ?? $0.name), name: $0.name, directory: $0.directory, size: $0.size, modified: $0.modified, symbolicLink: $0.linkTarget != nil) }
    }
    func reference(_ item: ListedItem) -> VirtualFileReference? {
        if item.url.isFileURL { return .init(item: item, origin: .local(item.url)) }
        if let url = archiveURL {
            let path = String(item.url.path.dropFirst())
            let entry = archiveSession.entries.first { $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path }
                ?? ArchiveMember(path: path + (item.isDirectory ? "/" : ""), size: item.size, directory: item.isDirectory, link: item.isSymbolicLink, encrypted: false, modified: item.modified ?? .distantPast)
            return .init(item: item, origin: .archive(url, archiveSession.password, entry))
        }
        guard let provider = networkSession.provider else { return nil }
        return .init(item: item, origin: .remote(provider, networkSession.connection, item.url.deletingLastPathComponent().path, .init(name: item.name, directory: item.isDirectory, size: item.size)))
    }
    func children(_ item: ListedItem) async throws -> [ListedItem] {
        if item.url.isFileURL { let hidden = SettingsService.shared.showHidden || SettingsService.shared.showDotfiles; return try await Task.detached { try MacDirectoryService.list(item.url, hidden: hidden).items }.value }
        if archiveURL != nil {
            let prefix = String(item.url.path.dropFirst()) + "/"
            return ArchiveMember.children(of: prefix, in: archiveSession.entries).map { ListedItem(virtualURL: virtualURL($0.path), name: ($0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).lastPathComponent, directory: $0.directory, size: $0.size, modified: $0.modified, symbolicLink: $0.link) }
        }
        guard let provider = networkSession.provider else { throw CommandFailure("Connect to the server first.") }
        return try await provider.list(item.url.path).map { ListedItem(virtualURL: virtualURL(try RemoteProvider.child(item.url.path, $0.name)), name: $0.name, directory: $0.directory, size: $0.size, modified: $0.modified, symbolicLink: $0.linkTarget != nil) }
    }
    func synchronizeVirtualSelection() {
        if archiveURL != nil {
            archiveSession.selected = Set(selectedItems.map { item in let path = String(item.url.path.dropFirst()); return path + (item.isDirectory ? "/" : "") })
        } else { networkSession.selected = Set(selectedItems.map(\.name)) }
    }
}

@MainActor final class TransferCutReceipt {
    let references: [VirtualFileReference]
    let fingerprints: [Data]
    private var consumed = false
    var pending: Bool { !consumed }
    init(references: [VirtualFileReference], fingerprints: [Data]) { self.references = references; self.fingerprints = fingerprints }
    func validatePayload(_ urls: [URL]) async throws {
        guard urls.count == fingerprints.count else { throw CommandFailure("The transfer selection changed. Cut the items again.") }
        for (url, expected) in zip(urls, fingerprints) {
            guard try await Task.detached(operation: { try TransferFingerprint.digest(url) }).value == expected else { throw StorageError.changedItem(url.lastPathComponent) }
        }
    }
    func consume() async -> OperationReport {
        var result = OperationReport(); guard !consumed else { return result }
        consumed = true
        do {
            // Verify every source before removing any. A failed paste never reaches this point.
            for (reference, expected) in zip(references, fingerprints) {
                let folder = try ClipboardStaging.create(); defer { try? FileManager.default.removeItem(at: folder) }
                let copy = try await reference.materialize(in: folder)
                let actual = try await Task.detached { try TransferFingerprint.digest(copy) }.value
                guard actual == expected else { throw StorageError.changedItem(reference.item.name) }
            }
            for reference in references {
                let report = try await reference.remove(); result.completed += report.completed; result.undo += report.undo; result.errors += report.errors
                if !report.errors.isEmpty { break }
            }
        } catch { result.errors.append(error.localizedDescription) }
        return result
    }
}

@MainActor enum TransferClipboard {
    private static var changeCount = -1
    private static var receipt: TransferCutReceipt?
    static var currentCut: TransferCutReceipt? { changeCount == NSPasteboard.general.changeCount && receipt?.pending == true ? receipt : nil }
    static func prepare(_ references: [VirtualFileReference], cut: Bool) async throws -> OperationReport {
        let references = references.filter { reference in
            !references.contains { parent in parent.item.isDirectory && parent.item.url != reference.item.url && parent.item.url.scheme == reference.item.url.scheme && parent.item.url.host == reference.item.url.host && reference.item.url.path.hasPrefix(parent.item.url.path.hasSuffix("/") ? parent.item.url.path : parent.item.url.path + "/") }
        }
        var urls: [URL] = []; var fingerprints: [Data] = []
        for reference in references {
            let folder = try ClipboardStaging.create()
            let url = try await reference.materialize(in: folder); urls.append(url)
            if cut { fingerprints.append(try await Task.detached { try TransferFingerprint.digest(url) }.value) }
        }
        try Task.checkCancellation()
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        changeCount = NSPasteboard.general.changeCount; receipt = cut ? TransferCutReceipt(references: references, fingerprints: fingerprints) : nil
        var report = OperationReport(); report.completed = urls; return report
    }
}

private final class VirtualPromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    let reference: VirtualFileReference
    init(_ reference: VirtualFileReference) { self.reference = reference }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { reference.item.name }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            do {
                let folder = try ClipboardStaging.create(); defer { try? FileManager.default.removeItem(at: folder) }
                let source = try await reference.materialize(in: folder)
                let task = Task.detached { try CancellableCopy.copy(source, to: url) }
                try await task.value; completionHandler(nil)
            } catch { completionHandler(error) }
        }
    }
}

@MainActor enum FileDrag {
    static func writer(_ item: ListedItem, pane: ShellPageViewModel) -> NSPasteboardWriting? {
        if item.url.isFileURL { return item.url as NSURL }
        guard let reference = pane.reference(item) else { return nil }
        let writer = VirtualPromiseWriter(reference)
        let type = item.isDirectory ? UTType.folder : UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
        let promise = NSFilePromiseProvider(fileType: type.identifier, delegate: writer); promise.userInfo = writer; return promise
    }
    static var types: [NSPasteboard.PasteboardType] { [NSPasteboard.PasteboardType.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType(rawValue: $0) } }
    static func operation(_ board: NSPasteboard, mask: NSDragOperation, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) -> NSDragOperation {
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if modifiers.contains(.command), !modifiers.contains(.option), mask.contains(.move), !urls.isEmpty, !urls.contains(where: ClipboardStaging.contains) { return .move }
        return mask.contains(.copy) ? .copy : []
    }
    static func accept(_ sender: NSDraggingInfo, model: MainPageViewModel, pane: ShellPageViewModel, destination: URL?) -> Bool {
        let operation = operation(sender.draggingPasteboard, mask: sender.draggingSourceOperationMask)
        guard !operation.isEmpty, !model.busy, !pane.isVirtual || pane.virtualPaste != nil else { return false }
        return receive(sender.draggingPasteboard, model: model, pane: pane, destination: destination, operation: operation)
    }
    static func receive(_ board: NSPasteboard, model: MainPageViewModel, pane: ShellPageViewModel, destination: URL?, operation: NSDragOperation = .copy) -> Bool {
        guard !model.busy, !pane.isVirtual || pane.virtualPaste != nil else { return false }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { model.receiveFiles(urls, pane: pane, destination: destination, moveSources: operation == .move); return true }
        guard let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !promises.isEmpty else { return false }
        let virtual = pane.isVirtual; let archive = pane.archiveURL; let provider = pane.networkSession.provider
        let target = destination ?? pane.operationDirectory ?? pane.columnDirectory ?? (virtual ? pane.virtualURL(archive == nil ? pane.networkSession.path : pane.archiveSession.prefix) : nil)
        do {
            let folder = try ClipboardStaging.create()
            for promise in promises { promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
                Task { @MainActor in
                    if let error { model.alert("Transfer failed", error.localizedDescription) }
                    else if pane.isVirtual != virtual || (virtual && (pane.archiveURL != archive || pane.networkSession.provider !== provider)) { model.alert("Transfer failed", "The destination connection changed. Drop the files again.") }
                    else { model.receiveFiles([url], pane: pane, destination: target) }
                }
            } }; return true
        } catch { model.alert("Transfer failed", error.localizedDescription); return false }
    }
}

@MainActor extension MainPageViewModel {
    func receiveFiles(_ urls: [URL], pane: ShellPageViewModel, destination: URL?, cut: TransferCutReceipt? = nil, moveSources: Bool = false) {
        let paste = pane.virtualPaste; let folder = destination ?? pane.operationDirectory
        let conflict = ConflictPolicy.keepBoth
        let virtual = pane.isVirtual; let archive = pane.archiveURL; let provider = pane.networkSession.provider; let connection = pane.networkSession.connection
        let target = destination ?? pane.operationDirectory ?? pane.columnDirectory ?? (virtual ? pane.virtualURL(archive == nil ? pane.networkSession.path : pane.archiveSession.prefix) : nil)
        run(cut == nil && !moveSources ? "Copying files" : "Moving files") {
            if virtual && (!pane.isVirtual || pane.archiveURL != archive || pane.networkSession.provider !== provider) { throw CommandFailure("The destination connection changed. Paste the files again.") }
            var cut = cut
            if moveSources && cut == nil {
                let references = try urls.map { VirtualFileReference(item: try ListedItem(url: $0), origin: .local($0)) }
                var fingerprints: [Data] = []
                for url in urls { fingerprints.append(try await Task.detached { try TransferFingerprint.digest(url) }.value) }
                cut = TransferCutReceipt(references: references, fingerprints: fingerprints)
            }
            if let cut {
                for reference in cut.references {
                    let sameOrigin: Bool
                    switch reference.origin {
                    case .local: sameOrigin = !virtual
                    case .archive(let sourceArchive, _, _): sameOrigin = sourceArchive == archive
                    case .remote(_, let sourceConnection, _, _): sameOrigin = archive == nil && virtual && sourceConnection.kind == connection.kind && sourceConnection.host == connection.host && sourceConnection.port == connection.port && sourceConnection.username == connection.username
                    }
                    if sameOrigin, let target, reference.item.isDirectory {
                        let source = reference.item.url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")); let path = target.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if path == source || path.hasPrefix(source + "/") { throw StorageError.recursiveDestination }
                    }
                }
            }
            var report: OperationReport
            if let cut { try await cut.validatePayload(urls) }
            if virtual { guard let paste else { throw CommandFailure("This location is not ready for transfers.") }; report = try await paste(urls, target, cut != nil) }
            else { guard let folder else { throw StorageError.notDirectory }; report = await self.storage.perform(.copy, sources: urls, destination: folder, conflict: conflict) }
            if let cut, report.errors.isEmpty, report.completed.count == urls.count {
                do { try await cut.validatePayload(virtual ? urls : report.completed) }
                catch { report.errors.append(error.localizedDescription); return report }
                let removal = await cut.consume(); report.undo += removal.undo; report.errors += removal.errors
                if !report.undo.isEmpty { report.undo = [.compound(report.undo)] }
            }
            self.refreshAll(); return report
        }
    }
}
