import AppKit
import Combine
import FilesShared
import FilesStorage

@MainActor final class OperationActivity {
    static let shared = OperationActivity()
    var count = 0
}

@MainActor final class MainPageViewModel: ObservableObject {
    @Published var compactOverlay = false
    var normalWindowFrame: NSRect?
    var normalWindowLevel: NSWindow.Level = .normal
    @Published var iconRevision = 0
    @Published private(set) var currentOperation: UUID?
    @Published var operationRecords: [OperationRecord] = []
    private var pendingOperations: [PendingOperation] = []
    @Published private(set) var queuedCount = 0
    @Published var tabs: [ExplorerTab] = []
    @Published var selectedTab = UUID()
    @Published var activePaneID = UUID()
    @Published var showInfo = false
    @Published var showSettings = false
    @Published var tool: ToolRequest?
    @Published var focusAddress = 0
    @Published var focusSearch = 0
    @Published var operationTitle: String?
    @Published var operationProgress = 0.0
    @Published var statusMessage = ""
    @Published var volumes: [URL] = []
    private(set) var undoStack: [[UndoStep]] { get { UndoJournal.shared.undo } set { UndoJournal.shared.undo = newValue } }
    private(set) var redoStack: [[UndoStep]] { get { UndoJournal.shared.redo } set { UndoJournal.shared.redo = newValue } }
    let storage = MacStorageService.shared
    private var subscriptions: [AnyCancellable] = []
    private var volumeSubscriptions: [NSObjectProtocol] = []
    private var closedTabs: [TabSnapshot] = []
    private var cutChangeCount: Int?
    private var operationTask: Task<Void, Never>?
    private var operationID = UUID()
    var currentTab: ExplorerTab { tabs.first { $0.id == selectedTab } ?? tabs[0] }
    var activePane: ShellPageViewModel {
        let tab = currentTab
        return tab.secondary?.id == activePaneID ? tab.secondary! : tab.primary
    }
    var busy: Bool { operationTitle != nil }
    var redoAvailable: Bool { !redoStack.isEmpty }
    var canPaste: Bool { NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) }

    init(initialLocation: URL? = nil) {
        ClipboardStaging.cleanExpired()
        let paths = initialLocation.map { [$0.path] } ?? (SettingsService.shared.restoreTabs ? UserDefaults.standard.stringArray(forKey: "sessionTabs") ?? [""] : (SettingsService.shared.preferences.startupPages.isEmpty ? [""] : SettingsService.shared.preferences.startupPages))
        tabs = (paths.isEmpty ? [""] : Array(paths.prefix(20))).map { ExplorerTab(location: $0.isEmpty ? nil : URL(fileURLWithPath: $0)) }
        if initialLocation == nil, SettingsService.shared.restoreTabs, let data = UserDefaults.standard.data(forKey: "sessionTabsV2"), let saved = try? JSONDecoder().decode([TabSnapshot].self, from: data), !saved.isEmpty {
            tabs = saved.prefix(20).map { snapshot in
                var tab = ExplorerTab(location: snapshot.primary.location); tab.primary.restore(snapshot.primary)
                if let secondary = snapshot.secondary { tab.secondary = ShellPageViewModel(location: secondary.location); tab.secondary?.restore(secondary) }
                tab.verticalSplit = snapshot.verticalSplit ?? false
                return tab
            }
        }
        selectedTab = tabs[0].id; activePaneID = tabs[0].primary.id
        bindPanes(); refreshVolumes()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            volumeSubscriptions.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVolumes() }
            })
        }
    }
    func refreshVolumes() {
        volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey], options: [.skipHiddenVolumes]) ?? []
        if !volumes.contains(where: { $0.path == "/" }) { volumes.insert(URL(fileURLWithPath: "/"), at: 0) }
    }
    func bindPanes() {
        subscriptions.removeAll()
        subscriptions.append(UndoJournal.shared.objectWillChange.sink { [weak self] in self?.objectWillChange.send() })
        for pane in tabs.flatMap({ [$0.primary, $0.secondary].compactMap { $0 } }) {
            subscriptions.append(pane.objectWillChange.sink { [weak self] in self?.objectWillChange.send() })
            subscriptions.append(pane.objectWillChange.debounce(for: .milliseconds(400), scheduler: RunLoop.main).sink { [weak self] in self?.saveSession() })
            subscriptions.append(pane.archiveSession.objectWillChange.debounce(for: .milliseconds(400), scheduler: RunLoop.main).sink { [weak self] in self?.saveSession() })
            subscriptions.append(pane.networkSession.objectWillChange.debounce(for: .milliseconds(400), scheduler: RunLoop.main).sink { [weak self] in self?.saveSession(); self?.objectWillChange.send() })
            pane.onNavigate = { [weak self] url in
                if let url { SettingsService.shared.remember(url) }
                self?.saveSession()
            }
        }
        saveSession()
    }
    func saveSession() {
        UserDefaults.standard.set(tabs.map { $0.primary.location?.path ?? "" }, forKey: "sessionTabs")
        UserDefaults.standard.set(try? JSONEncoder().encode(tabs.map { TabSnapshot(primary: $0.primary.snapshot, secondary: $0.secondary?.snapshot, verticalSplit: $0.verticalSplit) }), forKey: "sessionTabsV2")
    }
    func handleVirtual(_ action: String) -> Bool {
        guard activePane.isVirtual else { return false }
        activePane.virtualAction?(action); return true
    }
    func openVirtualTab(_ location: VirtualLocation) {
        newTab(activate: true); activePane.openVirtual(location); saveSession()
    }
    func newTab(_ url: URL? = nil, activate: Bool? = nil) {
        var tab = ExplorerTab(location: url)
        let preferences = SettingsService.shared.preferences
        if preferences.newTabsDualPane { tab.secondary = ShellPageViewModel(location: url); tab.verticalSplit = preferences.newTabsVerticalSplit }
        tabs.append(tab)
        if (activate ?? preferences.switchToNewTab) || tabs.count == 1 { selectedTab = tab.id; activePaneID = tab.primary.id }
        bindPanes()
    }
    func selectTab(_ id: UUID) { selectedTab = id; activePaneID = currentTab.primary.id }
    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closedTabs.append(TabSnapshot(primary: tabs[index].primary.snapshot, secondary: tabs[index].secondary?.snapshot, verticalSplit: tabs[index].verticalSplit))
        tabs[index].primary.shutdown(); tabs[index].secondary?.shutdown()
        tabs.remove(at: index)
        if tabs.isEmpty { newTab() }
        else if selectedTab == id { selectTab(tabs[min(index, tabs.count - 1)].id) }
        bindPanes()
    }
    func reopenTab() { guard !closedTabs.isEmpty else { return }; newTab(snapshot: closedTabs.removeLast()) }
    func newTab(snapshot: TabSnapshot) {
        var tab = ExplorerTab(location: snapshot.primary.location); tab.primary.restore(snapshot.primary)
        if let secondary = snapshot.secondary { tab.secondary = ShellPageViewModel(location: secondary.location); tab.secondary?.restore(secondary) }
        tab.verticalSplit = snapshot.verticalSplit ?? false
        tabs.append(tab); selectedTab = tab.id; activePaneID = tab.primary.id; bindPanes()
    }
    func moveTab(_ id: UUID, before target: UUID) {
        guard id != target, let source = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: tabs.firstIndex(where: { $0.id == target }) ?? tabs.count); saveSession()
    }
    func arrangePanes(vertical: Bool) {
        if currentTab.secondary == nil { toggleSplit() }
        guard let index = tabs.firstIndex(where: { $0.id == selectedTab }) else { return }
        tabs[index].verticalSplit = vertical; saveSession()
    }
    func focusOtherPane() { guard let secondary = currentTab.secondary else { return }; activePaneID = activePaneID == secondary.id ? currentTab.primary.id : secondary.id }
    func invertSelection() {
        if handleVirtual("invert") { return }; activePane.selection = Set(activePane.visibleItems.map(\.url)).subtracting(activePane.selection) }
    func nextTab(_ delta: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTab }) else { return }
        selectTab(tabs[(index + delta + tabs.count) % tabs.count].id)
    }
    func toggleSplit() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTab }) else { return }
        if tabs[index].secondary != nil { tabs[index].secondary?.shutdown(); tabs[index].secondary = nil }
        else {
            let snapshot = activePane.snapshot
            let secondary = ShellPageViewModel(location: snapshot.location)
            secondary.restore(snapshot)
            tabs[index].secondary = secondary
        }
        activePaneID = tabs[index].primary.id; bindPanes()
    }
    func openOtherPane(_ url: URL) {
        if currentTab.secondary == nil { toggleSplit() }
        let target = activePane.id == currentTab.primary.id ? currentTab.secondary! : currentTab.primary
        target.navigate(url); activePaneID = target.id
    }
    func open(_ item: ListedItem, pane: ShellPageViewModel? = nil) {
        let targetPane = pane ?? activePane
        if targetPane.isVirtual { activePaneID = targetPane.id; targetPane.selection = [item.url]; targetPane.synchronizeVirtualSelection(); targetPane.virtualAction?("open"); return }
        var item = item
        do {
            var target = URL(fileURLWithPath: item.url.path)
            var seen = Set<URL>()
            while (try target.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])).isAliasFile == true {
                guard seen.count < 32, seen.insert(target.standardizedFileURL).inserted else { throw CommandFailure("This alias contains a target cycle.") }
                if (try target.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
                    target = URL(fileURLWithPath: target.resolvingSymlinksInPath().path)
                } else {
                    target = URL(fileURLWithPath: try URL(resolvingAliasFileAt: target).path)
                }
            }
            if target != item.url { item = try ListedItem(url: target) }
        } catch { alert("Couldn’t resolve alias", error.localizedDescription); return }
        if item.isBrowsable { if SettingsService.shared.preferences.foldersInNewTab { newTab(item.url) } else { (pane ?? activePane).navigate(item.url) } }
        else if ArchiveService.supports(item.url) { openVirtualTab(.archive(item.url, "")) }
        else if NSWorkspace.shared.open(item.url) { NSDocumentController.shared.noteNewRecentDocumentURL(item.url) }
        else { alert("Couldn’t open this file", "No application could open ‘\(item.name)’.") }
    }
    func openSelection() {
        if handleVirtual("open") { return }; for item in activePane.selectedItems { open(item) } }
    private var pathRequests: [UUID: UUID] = [:]
    func openPath(_ path: String, pane: ShellPageViewModel) {
        let expanded = (path as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") { url = URL(fileURLWithPath: expanded) }
        else { url = (pane.location ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent(expanded) }
        let request = UUID(); pathRequests[pane.id] = request
        let origin = pane.location; let virtualOrigin = pane.virtualLocation
        Task {
            defer { if pathRequests[pane.id] == request { pathRequests.removeValue(forKey: pane.id) } }
            do {
                let item = try await Task.detached { try ListedItem(url: url.standardizedFileURL) }.value
                guard pathRequests[pane.id] == request, pane.location == origin, pane.virtualLocation == virtualOrigin else { return }
                open(item, pane: pane)
            } catch {
                guard pathRequests[pane.id] == request, pane.location == origin, pane.virtualLocation == virtualOrigin else { return }
                alert("Couldn’t open this location", error.localizedDescription)
            }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = L10n.text("Open folder"); panel.directoryURL = activePane.location
        if panel.runModal() == .OK, let url = panel.url { activePane.navigate(url) }
    }
    func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = L10n.text(title); alert.informativeText = L10n.text(message)
        alert.alertStyle = .warning; alert.addButton(withTitle: L10n.text("OK")); alert.runModal()
    }
    func askName(_ title: String, value: String, action: String) -> String? {
        FilesPrompt.name(title, value: value, action: action)
    }
    func create(directory: Bool) {
        if handleVirtual(directory ? "new" : "newFile") { return }
        guard !busy, let folder = activePane.operationDirectory,
              let name = askName(directory ? "New folder" : "New text file", value: directory ? "New folder" : "Untitled.txt", action: "Create") else { return }
        run("Creating \(name)") { try await self.storage.create(in: folder, name: name, directory: directory) }
    }
    func flatten() {
        guard !busy, activePane.selectedItems.count == 1, let item = activePane.selectedItems.first, item.isBrowsable else { return }
        let prompt = NSAlert(); prompt.messageText = L10n.text("Flatten ‘\(item.name)’?")
        prompt.informativeText = L10n.text("Move nested files to this folder. Existing names and symbolic links are left in place. Empty subfolders go to Trash. You can undo this operation.")
        prompt.addButton(withTitle: L10n.text("Flatten")); prompt.addButton(withTitle: L10n.text("Cancel"))
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        run("Flattening folder") { try await self.storage.flatten(item.url) }
    }
    func createFromTemplate() {
        guard !busy, let folder = activePane.operationDirectory else { return }
        let panel = NSOpenPanel(); panel.title = L10n.text("Choose a template file"); panel.canChooseDirectories = false; panel.canChooseFiles = true
        guard panel.runModal() == .OK, let source = panel.url,
              let name = askName("New file from template", value: source.lastPathComponent, action: "Create") else { return }
        run("Creating from template") { try await self.storage.createFromTemplate(source, in: folder, name: name) }
    }
    func rename() {
        if handleVirtual("rename") { return }
        if activePane.selectedItems.count > 1 { present(.rename); return }
        guard !busy, activePane.selectedItems.count == 1, let item = activePane.selectedItems.first else { return }
        InlineRenameRequest.begin(pane: activePane, item: item) { [weak self] name in
            guard let self, self.confirmExtensionChange(from: item.name, to: name, directory: item.isDirectory) else { return }
            self.run("Renaming \(item.name)") { try await self.storage.rename(item.url, to: name) }
        }
    }
    func confirmExtensionChange(from oldName: String, to newName: String, directory: Bool) -> Bool {
        guard SettingsService.shared.preferences.extensionWarning, !directory, (oldName as NSString).pathExtension != (newName as NSString).pathExtension else { return true }
        let warning = NSAlert(); warning.messageText = L10n.text("Change file extension?")
        warning.informativeText = L10n.text("Changing the extension may prevent the file from opening in its usual application.")
        warning.addButton(withTitle: L10n.text("Cancel")); warning.addButton(withTitle: L10n.text("Rename"))
        return warning.runModal() == .alertSecondButtonReturn
    }
    private func routeToText(_ selector: Selector) -> Bool {
        guard NSApp.keyWindow?.firstResponder is NSTextView else { return false }
        NSApp.sendAction(selector, to: nil, from: nil); return true
    }
    func copy(cut: Bool = false) {
        if routeToText(NSSelectorFromString(cut ? "cut:" : "copy:")) { return }
        if cut || activePane.isVirtual {
            let references = activePane.selectedItems.compactMap { activePane.reference($0) }; guard !references.isEmpty else { return }
            run(cut ? "Preparing move" : "Preparing copy", recordingUndo: false) { try await TransferClipboard.prepare(references, cut: cut) }; return
        }
        let urls = activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let board = NSPasteboard.general; board.clearContents(); board.writeObjects(urls.map { $0 as NSURL })
        cutChangeCount = cut ? board.changeCount : nil
        statusMessage = "\(urls.count) item(s) ready to \(cut ? "move" : "copy")"
    }
    func clearSelection() { if handleVirtual("clear") { return }; activePane.selection = [] }
    func copyPath(quoted: Bool = false, current: Bool = false) {
        let pane = activePane
        var paths: [String]
        if let archive = pane.archiveURL {
            let selected = current ? [] : pane.archiveSession.selected.sorted()
            paths = selected.isEmpty ? [archive.path + "/" + pane.archiveSession.prefix] : selected.map { archive.path + "/" + $0 }
        } else if pane.isVirtual {
            let session = pane.networkSession
            var components = URLComponents(); components.scheme = session.connection.kind == .sftp ? "sftp" : session.connection.kind == .ftps ? "ftps" : "ftp"
            components.host = session.connection.host; components.port = session.connection.port
            let selected = current ? [] : pane.selectedItems.map { $0.url.path }
            paths = (selected.isEmpty ? [session.path] : selected).compactMap { components.path = $0; return components.url?.absoluteString }
        } else {
            paths = current ? [] : pane.selectedItems.map { $0.url.path }
            if paths.isEmpty, let location = pane.operationDirectory ?? pane.location { paths = [location.path] }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ClipboardPaths.format(paths, quoted: quoted), forType: .string)
    }
    func paste(forceMove: Bool = false, destination: URL? = nil) {
        if destination == nil && routeToText(NSSelectorFromString("paste:")) { return }
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return }
        if activePane.isVirtual || TransferClipboard.currentCut != nil { receiveFiles(urls, pane: activePane, destination: destination, cut: TransferClipboard.currentCut, moveSources: forceMove); return }
        guard let folder = destination ?? activePane.operationDirectory else { return }
        perform(forceMove ? .move : .copy, urls: urls, destination: folder)
        cutChangeCount = nil
    }
    func selectAll() {
        if routeToText(NSSelectorFromString("selectAll:")) { return }

        activePane.selection = Set((activePane.columnItems.isEmpty ? activePane.visibleItems : activePane.columnItems).map(\.url))
        if activePane.isVirtual { activePane.synchronizeVirtualSelection() }
    }
    func trash() {
        if handleVirtual("trash") { return }
        let items = activePane.selectedItems
        guard !items.isEmpty, !busy else { return }
        if !SettingsService.shared.preferences.confirmTrash { perform(.trash, urls: items.map(\.url)); return }
        let dialog = NSAlert(); dialog.messageText = L10n.text("Move \(items.count == 1 ? "‘\(items[0].name)’" : "\(items.count) items") to Trash?")
        dialog.informativeText = L10n.text("You can restore these items with Undo or from the Trash.")
        dialog.addButton(withTitle: L10n.text("Move to Trash")); dialog.addButton(withTitle: L10n.text("Cancel"))
        if dialog.runModal() == .alertFirstButtonReturn { perform(.trash, urls: items.map(\.url)) }
    }
    func duplicate() {
        guard let folder = activePane.operationDirectory else { return }
        perform(.copy, urls: activePane.selectedItems.map(\.url), destination: folder)
    }
    func perform(_ kind: FileOperation, urls: [URL], destination: URL? = nil) {
        guard !urls.isEmpty else { return }
        var conflict: ConflictPolicy = .keepBoth
        if kind != .trash, let destination {
            let conflicts = urls.filter { source in
                let target = destination.appendingPathComponent(source.lastPathComponent)
                return target.standardizedFileURL != source.standardizedFileURL && (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil
            }
            if !conflicts.isEmpty {
                let prompt = NSAlert(); prompt.messageText = L10n.text("\(conflicts.count) destination name(s) already exist")
                prompt.informativeText = conflicts.prefix(5).map(\.lastPathComponent).joined(separator: "\n") + "\n\n" + L10n.text("Keep both creates numbered names. Replace moves previous versions to Trash and supports Undo. Folders are replaced as a whole.")
                ["Keep both", "Replace", "Skip existing", "Cancel"].forEach { prompt.addButton(withTitle: L10n.text($0)) }
                switch prompt.runModal().rawValue {
                case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue: conflict = .keepBoth
                case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue: conflict = .replace
                case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue: conflict = .skip
                default: return
                }
            }
        }
        let policy = conflict
        let label = kind == .copy ? "Copying" : kind == .move ? "Moving" : "Moving to Trash"
        let operationID = UUID()
        run(label) {
            self.operationID = operationID
            let report = await self.storage.perform(kind, sources: urls, destination: destination, conflict: policy) { done, total, name in
                Task { @MainActor in
                    guard self.operationID == operationID, self.busy else { return }
                    self.operationProgress = Double(done) / Double(max(total, 1))
                    self.operationTitle = name.isEmpty ? label : "\(label) · \(name)"
                }
            }
            if kind == .trash { TrashRegistry.shared.record(report.undo) }
            return report
        }
    }
    func undo() {
        if routeToText(NSSelectorFromString("undo:")) { return }
        guard !busy, let steps = undoStack.popLast() else { return }
        run("Undoing", recordingUndo: false) {
            let report = await self.storage.undo(steps)
            if !report.undo.isEmpty { self.undoStack.append(report.undo) }
            if !report.inverse.isEmpty { self.redoStack.append(report.inverse) }
            return report
        }
    }
    func redo() {
        guard !busy, let steps = redoStack.popLast() else { return }
        run("Redoing", recordingUndo: false) {
            let report = await self.storage.undo(steps)
            if !report.undo.isEmpty { self.redoStack.append(report.undo) }
            if !report.inverse.isEmpty { self.undoStack.append(report.inverse) }
            return report
        }
    }
    func present(_ kind: ToolKind) {
        if activePane.isVirtual && kind == .attributes {
            alert("Extended attributes", "This archive or server protocol does not expose macOS extended attributes. Extract or download the item to manage attributes on its local copy."); return
        }
        if activePane.isVirtual && [.properties, .hashes, .permissions].contains(kind) { tool = ToolRequest(kind: .virtualProperties, urls: activePane.selectedItems.map(\.url), directory: FileManager.default.homeDirectoryForCurrentUser, initialPage: kind == .hashes ? "Hashes" : kind == .permissions ? "Security" : "General"); return }
        if kind == .archive, let url = activePane.selectedItems.first?.url { openVirtualTab(.archive(url, "")); return }
        if kind == .network { openVirtualTab(.network(nil, "/")); return }
        tool = ToolRequest(kind: kind, urls: activePane.selectedItems.map(\.url), directory: activePane.operationDirectory ?? FileManager.default.homeDirectoryForCurrentUser)
    }
    @discardableResult func run(_ title: String, recordingUndo: Bool = true, onCancel: (() -> Void)? = nil, operation: @escaping () async throws -> OperationReport) -> UUID {
        let id = UUID()
        operationRecords.append(OperationRecord(id: id, title: title, date: Date(), state: "Queued"))
        DiagnosticsStore.append("Queued " + title)
        let job = PendingOperation(id: id, title: title, pane: activePane, recordingUndo: recordingUndo, onCancel: onCancel, action: operation)
        if busy { pendingOperations.append(job); queuedCount = pendingOperations.count }
        else { start(job) }
        return id
    }
    private func start(_ job: PendingOperation) {
        currentOperation = job.id
        operationTitle = job.title; operationProgress = 0
        setOperation(job.id, state: "Running")
        OperationActivity.shared.count += 1
        operationTask = Task {
            defer { OperationActivity.shared.count -= 1 }
            do {
                let report = try await job.action()
                if job.recordingUndo && !report.undo.isEmpty { redoStack.removeAll(); undoStack.append(report.undo); if undoStack.count > 30 { undoStack.removeFirst() } }
                statusMessage = "\(report.completed.count) item(s) completed" + (report.renamedCount > 0 ? " · Both versions kept for \(report.renamedCount) name conflict(s)" : "")
                setOperation(job.id, state: Task.isCancelled ? "Cancelled" : report.errors.isEmpty ? "Completed" : "Completed with errors", detail: ([statusMessage] + report.errors).joined(separator: "\n"))
                refreshAll()
                if let folder = job.pane.operationDirectory { job.pane.selection = Set(report.completed.filter { $0.deletingLastPathComponent() == folder }) }
                DiagnosticsStore.append("Completed \(report.completed.count) items; \(report.errors.count) errors")
                if !report.errors.isEmpty && !Task.isCancelled { alert("Some items couldn’t be completed", report.errors.prefix(8).joined(separator: "\n")) }
            } catch {
                setOperation(job.id, state: Task.isCancelled ? "Cancelled" : "Failed", detail: error.localizedDescription)
                refreshAll()
                if !Task.isCancelled { alert("Operation failed", error.localizedDescription) }
            }
            currentOperation = nil; operationTitle = nil; operationTask = nil; operationID = UUID()
            if !pendingOperations.isEmpty { let next = pendingOperations.removeFirst(); queuedCount = pendingOperations.count; start(next) }
        }
    }
    private func setOperation(_ id: UUID, state: String, detail: String = "") {
        DiagnosticsStore.append(id.uuidString + " " + state)
        if let index = operationRecords.firstIndex(where: { $0.id == id }) { operationRecords[index].state = state; operationRecords[index].detail = detail }
    }
    func cancelJob(_ id: UUID) { if currentOperation == id { cancelOperation() } else { cancelQueued(id) } }
    func cancelQueued(_ id: UUID) {
        pendingOperations.first { $0.id == id }?.onCancel?()
        pendingOperations.removeAll { $0.id == id }; queuedCount = pendingOperations.count
        setOperation(id, state: "Cancelled", detail: "Cancelled before starting. No files were changed.")
    }
    func cancelOperation() { operationTask?.cancel(); statusMessage = "Cancelling the current operation…" }
    func refreshAll() { for tab in tabs { tab.primary.refresh(); tab.secondary?.refresh() } }
    func reveal() { NSWorkspace.shared.activateFileViewerSelecting(activePane.selectedItems.map(\.url)) }
    func terminal(at supplied: URL? = nil) {
        guard let url = supplied ?? activePane.location,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    func quickLook() {
        if handleVirtual("quickLook") { return }
        guard !activePane.selectedItems.isEmpty else { return }
        PreviewController.shared.show(activePane.selectedItems.map(\.url))
    }
}
