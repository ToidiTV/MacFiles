import SwiftUI
import AppKit
import FilesStorage
import FilesShared

@MainActor final class NetworkBrowserSession: ObservableObject {
    @Published var connection = RemoteConnection(name: "", kind: .ftps, host: "", port: 21, username: "")
    @Published var password = ""
    @Published var remember = false
    @Published var provider: RemoteProvider?
    @Published var path = "/"
    @Published var address = "/"
    @Published var history: [String] = []
    @Published var historyIndex = -1
    @Published var items: [RemoteItem] = []
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var message = ""
    @Published var task: Task<Void, Never>?
    @Published var share = "smb://"
    @Published var jobID: UUID?
    @Published var undoStack: [[RemoteUndoStep]] = []
    @Published var redoStack: [[RemoteUndoStep]] = []
    @Published var conflict = ConflictPolicy.keepBoth
    @Published var preview: URL?
    @Published var reloadToken = UUID()
    func recordNavigation(_ location: String, historyIndex index: Int? = nil) {
        if let index { historyIndex = index }
        else if !history.indices.contains(historyIndex) || history[historyIndex] != location {
            history = Array(history.prefix(historyIndex + 1)); history.append(location); historyIndex = history.count - 1
        }
    }
    func shutdown() { task?.cancel() }
}

struct NetworkBrowserView: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject var session: NetworkBrowserSession
    let destination: URL
    @ObservedObject var store = ConnectionStore.shared
    private var connection: RemoteConnection { get { session.connection } nonmutating set { session.connection = newValue } }
    private var password: String { get { session.password } nonmutating set { session.password = newValue } }
    private var remember: Bool { get { session.remember } nonmutating set { session.remember = newValue } }
    private var provider: RemoteProvider? { get { session.provider } nonmutating set { session.provider = newValue } }
    private var path: String { get { session.path } nonmutating set { session.path = newValue } }
    private var items: [RemoteItem] { get { session.items } nonmutating set { session.items = newValue } }
    private var selected: Set<String> { get { session.selected } nonmutating set { session.selected = newValue } }
    private var busy: Bool { get { session.busy } nonmutating set { session.busy = newValue } }
    private var message: String { get { session.message } nonmutating set { session.message = newValue } }
    private var task: Task<Void, Never>? { get { session.task } nonmutating set { session.task = newValue } }
    private var share: String { get { session.share } nonmutating set { session.share = newValue } }
    private var selection: [RemoteItem] { pane.selectedItems.map { .init(name: $0.name, directory: $0.isDirectory, size: $0.size) } }
    var body: some View {
        VStack(spacing: 12) {
            if provider == nil {
                HStack {
                    if !store.connections.isEmpty {
                        Menu(L10n.text("Saved connections")) {
                            ForEach(store.connections) { saved in
                                Button(saved.name.isEmpty ? saved.host : saved.name) {
                                    connection = saved; password = store.password(for: saved); remember = !password.isEmpty; path = saved.initialPath
                                }
                            }
                        }.frame(width: 200)
                        Button(L10n.text("Forget saved")) { store.remove(connection) }.disabled(!store.connections.contains(where: { $0.id == connection.id }))
                    }
                    Spacer()
                }
                ScrollView {
                  VStack(spacing: 12) {
                    FilesDialogCard {
                      VStack(alignment: .leading, spacing: 12) {
                    Picker(L10n.text("Protocol"), selection: $session.connection.kind) { ForEach(RemoteProtocol.allCases, id: \.self) { Text(L10n.text($0 == .sftp ? "SFTP (SSH)" : $0.rawValue)).tag($0) } }
                    TextField(L10n.text("Name"), text: $session.connection.name)
                    TextField(L10n.text("Server"), text: $session.connection.host)
                    HStack { Text(L10n.text("Port")); TextField(L10n.text("Port"), value: $session.connection.port, format: .number.grouping(.never)).frame(width: 90) }
                      }
                    }
                    FilesDialogCard {
                      VStack(alignment: .leading, spacing: 12) {
                    TextField(L10n.text("Username"), text: $session.connection.username)
                    SecureField(L10n.text(connection.kind == .sftp ? "Password / key passphrase (optional)" : "Password"), text: $session.password)
                    Toggle(L10n.text("Remember password in Keychain"), isOn: $session.remember)
                    if connection.kind == .sftp {
                        Text(L10n.text("Uses SSH keys or the password above. Host-key verification remains enabled.")).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("Review server fingerprint…")) { reviewHost() }.disabled(busy || connection.host.isEmpty)
                    }
                    TextField(L10n.text("Start folder"), text: $session.connection.initialPath)
                      }
                    }
                  }.textFieldStyle(.roundedBorder).padding(1)
                }
                HStack {
                    Spacer()
                    Button(L10n.text("Connect")) { connect() }.buttonStyle(FilesPrimaryButtonStyle()).disabled(busy || connection.host.isEmpty)
                }
                Divider().padding(.vertical, 8)
                HStack {
                    TextField(L10n.text("SMB, AFP, or WebDAV share"), text: $session.share)
                    Button(L10n.text("Mount share…")) {
                        guard let url = URL(string: share), ["smb", "afp", "http", "https"].contains(url.scheme ?? "") else { message = "Enter an SMB, AFP, or WebDAV address."; return }
                        // macOS handles the authenticated mount flow; mounted shares appear under Drives.
                        if url.scheme == "http" || url.scheme == "https" {
                            var components = URLComponents(url: url, resolvingAgainstBaseURL: false); components?.scheme = url.scheme == "https" ? "davs" : "dav"
                            if let mountURL = components?.url { NSWorkspace.shared.open(mountURL) }
                        } else { NSWorkspace.shared.open(url) }
                    }
                }
                Text(L10n.text("Cloud providers installed on this Mac appear in the sidebar through their native File Provider folders.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                SharedFileLayout(model: model, pane: pane).overlay {
                    if pane.visibleItems.isEmpty && !busy {
                        VStack(spacing: 12) {
                            Image(systemName: pane.query.isEmpty ? "folder" : "magnifyingglass").font(ExplorerFont.font(size: 35, weight: .light)).foregroundStyle(.tertiary)
                            Text(L10n.text(pane.query.isEmpty ? "This folder is empty" : "No matching items")).foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }
                if let preview = session.preview { QuickLookView(url: preview).frame(height: 220) }
            }
            if busy { HStack { ProgressView().controlSize(.small); Text(L10n.text("Working…")); Spacer(); Button(L10n.text("Cancel")) { if let id = session.jobID { model.cancelJob(id) } else { task?.cancel() } } } }
            if !message.isEmpty { ScrollView { Text(L10n.text(message)).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 65) }
        }.dropDestination(for: URL.self) { urls, _ in
            guard provider != nil, !busy, !urls.isEmpty else { return false }
            uploadFiles(urls); return true
        }.padding(provider == nil ? 20 : 0).task(id: provider == nil) {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)); try Task.checkCancellation() } catch { return }
                guard let provider, !busy, !model.busy else { continue }
                let location = path
                do {
                    let updated = try await provider.list(location)
                    guard !Task.isCancelled, path == location, !busy, !model.busy else { continue }
                    items = updated
                    if pane.columnDirectory == nil { pane.selection.formIntersection(Set(pane.visibleItems.map(\.url))) }
                } catch { if !Task.isCancelled { message = error.localizedDescription } }
            }
        }.onAppear { pane.virtualAction = handleCommand
            pane.virtualPaste = { urls, destination, verify in
                guard let provider else { throw CommandFailure("Connect to the server first.") }
                let location = (destination ?? pane.columnDirectory)?.path ?? path
                var result = OperationReport()
                let registration = await RemoteUndoRegistry.shared.register(provider)
                for url in urls {
                    do {
                        let report = try await provider.uploadWithConflicts(url, to: location, conflict: session.conflict, verifyContents: verify)
                        if !report.skipped { result.completed.append(url); result.undo.append(.remote(registration, report.undo)) }
                    } catch { result.errors.append(error.localizedDescription); break }
                }
                do { items = try await provider.list(path) } catch { message = error.localizedDescription }
                return result
            }
        }.onChange(of: path) { session.address = path; pane.columnItems = []; pane.columnDirectory = nil; pane.restorePresentation() }.onChange(of: selected) { let urls = Set(selected.map { pane.virtualURL((try? RemoteProvider.child(pane.columnDirectory?.path ?? path, $0)) ?? $0) }); if pane.selection != urls { pane.selection = urls } }.onChange(of: connection.kind) { connection.port = connection.kind == .sftp ? 22 : 21 }
            .onChange(of: session.reloadToken) { if provider != nil { load(path) } }.onDisappear { pane.virtualAction = nil; pane.virtualPaste = nil }
    }
    private func step(_ offset: Int) { let index = session.historyIndex + offset; if session.history.indices.contains(index) { load(session.history[index], historyIndex: index) } }
    private func handleCommand(_ action: String) {
        guard provider != nil else { return }
        if action.hasPrefix("navigate:") { load(String(action.dropFirst(9))); return }
        switch action {
        case "upload": upload(); case "download": download()
        case "disconnect": task?.cancel(); provider = nil; items = []; selected = []; pane.selection = []; pane.columnItems = []; pane.columnDirectory = nil; message = ""

        case "back": step(-1); case "forward": step(1); case "up": let parent = (path as NSString).deletingLastPathComponent; load(parent.isEmpty ? "/" : parent)
        case "open", "quickLook": openSelected()
        case "new": newFolder(); case "newFile": newFile()
        case "rename": rename(); case "trash": delete(); case "refresh": load(path); case "undo": undoRemote(); case "redo": redoRemote()
        case "selectAll": model.selectAll(); case "clear": selected = []; pane.selection = []; case "invert": pane.selection = Set((pane.columnItems.isEmpty ? pane.visibleItems : pane.columnItems).map(\.url)).subtracting(pane.selection); pane.synchronizeVirtualSelection()
        case "copy": model.copy(); case "cut": model.copy(cut: true)
        case "paste": model.paste()
        default: model.alert("Action unavailable", "Use Copy and Paste or Download to transfer remote items.")
        }
    }
    private func openSelected() {
        guard let item = selection.first, selection.count == 1 else { return }
        if item.directory { if let child = try? RemoteProvider.child(path, item.name) { load(pane.selectedItems.first?.url.path ?? child) }; return }
        let location = pane.selectedItems.first?.url.deletingLastPathComponent().path ?? path
        execute { provider in
            let folder = try ClipboardStaging.create()
            session.preview = try await provider.download(item, from: location, to: folder)
        }
    }
    private func uploadFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }; let path = pane.columnDirectory?.path ?? path; let conflict = session.conflict
        execute { provider in
            for url in urls { let result = try await provider.uploadWithConflicts(url, to: path, conflict: conflict); if !result.undo.isEmpty { session.undoStack.append(result.undo); session.redoStack = [] } }
        }
    }
    private func newFile() {
        guard let name = model.askName("New remote file", value: "Untitled.txt", action: "Create"), (try? RemoteProvider.child("/", name)) != nil else { return }
        let path = pane.columnDirectory?.path ?? path
        execute { provider in
            let folder = try ClipboardStaging.create(); defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent(name); try Data().write(to: file)
            let result = try await provider.uploadWithConflicts(file, to: path, conflict: .keepBoth)
            session.undoStack.append(result.undo); session.redoStack = []
        }
    }
    private func copyRemote() {
        let entries = selection; let path = pane.columnDirectory?.path ?? path; guard !entries.isEmpty else { return }
        execute { provider in
            let folder = try ClipboardStaging.create()
            var urls: [URL] = []; for item in entries { urls.append(try await provider.download(item, from: path, to: folder)) }
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        }
    }
    private func reviewHost() {
        let host = connection.host; let port = connection.port; busy = true
        task = Task {
            defer { busy = false }
            do {
                let proposal = try await SSHHostService.inspect(host: host, port: port)
                try Task.checkCancellation()
                let alert = NSAlert(); alert.messageText = L10n.text("Trust this SSH server?")
                alert.informativeText = L10n.text("Compare these SHA-256 fingerprints with your server administrator before trusting \(host):\(port).\n\n") + proposal.fingerprints
                alert.addButton(withTitle: L10n.text("Cancel")); alert.addButton(withTitle: L10n.text("Trust verified fingerprints"))
                if alert.runModal() == .alertSecondButtonReturn { try SSHHostService.trust(proposal); message = "Verified host keys saved for MacFiles." }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    private func connect() {
        if !connection.initialPath.hasPrefix("/") { connection.initialPath = "/" + connection.initialPath }
        let candidate = RemoteProvider(connection: connection, password: password)
        busy = true; message = ""
        task = Task {
            do {
                items = try await candidate.list(connection.initialPath); _ = await RemoteUndoRegistry.shared.register(candidate); provider = candidate; path = connection.initialPath; session.history = [path]; session.historyIndex = 0
                try store.save(connection, password: remember ? password : nil)
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func load(_ location: String, historyIndex: Int? = nil) {
        guard let provider, !busy else { return }
        let normalized = location.hasPrefix("/") ? location : "/" + location
        busy = true; message = ""
        task = Task {
            do { items = try await provider.list(normalized); path = normalized; pane.query = ""; selected = []; pane.selection = []
                session.recordNavigation(normalized, historyIndex: historyIndex) }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func execute(_ operation: @escaping (RemoteProvider) async throws -> Void) {
        guard let provider, !busy else { return }; busy = true; message = ""
        let location = path
        session.jobID = model.run("Remote operation on \(connection.host)", recordingUndo: true, onCancel: { busy = false; session.jobID = nil; message = "Cancelled before starting." }) {
            defer { busy = false; session.jobID = nil }
            var report = OperationReport()
            do { try await operation(provider); items = try await provider.list(location); selected = []; message = "Operation completed." }
            catch { message = error.localizedDescription; report.errors.append(error.localizedDescription) }
            let steps = session.undoStack.flatMap { $0 }; session.undoStack = []; session.redoStack = []
            if !steps.isEmpty { let id = await RemoteUndoRegistry.shared.register(provider); report.undo = [.remote(id, steps)] }
            return report
        }
    }
    private func download() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.directoryURL = destination; panel.prompt = L10n.text("Download here")
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let entries = selection; let path = pane.columnDirectory?.path ?? path
        execute { provider in for item in entries { _ = try await provider.download(item, from: path, to: target) } }
    }
    private func upload() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true; panel.directoryURL = destination; panel.prompt = L10n.text("Upload")
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls; let path = pane.columnDirectory?.path ?? path; let conflict = session.conflict
        execute { provider in
            for url in urls { let result = try await provider.uploadWithConflicts(url, to: path, conflict: conflict); if !result.undo.isEmpty { session.undoStack.append(result.undo); session.redoStack = [] } }
        }
    }
    private func newFolder() {
        guard let name = model.askName("New remote folder", value: "New folder", action: "Create") else { return }
        let path = pane.columnDirectory?.path ?? path; execute { provider in
            let from = try RemoteProvider.child(path, name)
            let recovery = try await provider.recoveryPath(in: path, name: name)
            try await provider.mkdir(name, in: path)
            session.undoStack.append([RemoteUndoStep(from: from, to: recovery)]); session.redoStack = []
        }
    }
    private func rename() {
        guard let item = selection.first, let listed = pane.selectedItems.first else { return }
        let location = pane.columnDirectory?.path ?? path
        InlineRenameRequest.begin(pane: pane, item: listed) { name in
            guard model.confirmExtensionChange(from: item.name, to: name, directory: item.directory) else { return }
            execute { let result = try await $0.renameWithUndo(item, to: name, in: location); session.undoStack.append(result.undo); session.redoStack = [] }
        }
    }
    private func undoRemote() { model.undo() }
    private func redoRemote() { model.redo() }
    private func delete() {
        let dialog = NSAlert(); dialog.messageText = L10n.text("Move \(selection.count) remote items to recovery?")
        dialog.informativeText = L10n.text("Items move into .MacFiles-Recovery on this server, including folder contents. Use Undo remote to restore them during this session.")
        dialog.addButton(withTitle: L10n.text("Cancel")); dialog.addButton(withTitle: L10n.text("Move to recovery"))
        guard dialog.runModal() == .alertSecondButtonReturn else { return }
        let entries = selection; let path = pane.columnDirectory?.path ?? path
        execute { provider in for item in entries { let result = try await provider.trash(item, in: path); session.undoStack.append(result.undo); session.redoStack = [] } }
    }
}
