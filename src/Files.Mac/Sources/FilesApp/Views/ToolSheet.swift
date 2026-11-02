import SwiftUI
import AppKit
import FilesShared
import FilesStorage

enum ToolKind: String {
    case tagBrowser = "Tagged items", diagnostics = "Diagnostics", settingsFile = "Settings file", slideshow = "Wallpaper slideshow"
    case virtualProperties = "Item properties"
    case providers = "Cloud accounts"
    case mediaMetadata = "Edit media metadata"
    case shortcuts = "Keyboard shortcuts"
    case operations = "Operations", toolbar = "Customize toolbar", properties = "Properties", cloud = "Cloud status"
    case extract = "Extract archive"
    case archive = "Archive", compress = "Compress", rename = "Bulk rename", git = "Git repository"
    case trash = "Trash", attributes = "Extended attributes", search = "Advanced search", palette = "Command palette", shelf = "File shelf"
    case tags = "Edit tags", hashes = "File hashes", permissions = "Permissions", network = "Connect to server"
}
struct ToolRequest: Identifiable {
    let id = UUID()
    let kind: ToolKind
    let urls: [URL]
    let directory: URL
    var savedSearch: SavedSearch? = nil
    var initialPage = "General"
    var archiveSelection = Set<String>()
    var archivePassword = ""
    var extractionPlacement: ExtractionPlacement? = nil
    var chooseExtractionDestination = true
}
struct ToolSheet: View {
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @Environment(\.dismissTool) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text(request.kind == .virtualProperties ? "Properties" : request.kind == .compress ? "Create archive" : request.kind.rawValue)).font(ExplorerFont.font(size: request.kind == .properties || request.kind == .virtualProperties ? 13 : 22, weight: .semibold))
                Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }.buttonStyle(.plain).help(L10n.text("Close")).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 24).frame(height: request.kind == .properties || request.kind == .virtualProperties ? 36 : 64)
            Divider()
            switch request.kind {
            case .tagBrowser: TagBrowserView(model: model)
            case .diagnostics: DiagnosticsView()
            case .settingsFile: SettingsFileView()
            case .slideshow: WallpaperSlideshowView()
            case .virtualProperties: VirtualPropertiesView(model: model, pane: model.activePane, urls: request.urls, initialPage: request.initialPage)
            case .providers: CloudProvidersView(model: model)
            case .mediaMetadata: if let url = request.urls.first { MediaMetadataView(model: model, url: url) }
            case .shortcuts: ShortcutCustomizationView()
            case .operations: OperationsView(model: model)
            case .toolbar: ToolbarCustomizationView()
            case .properties: PropertiesView(model: model, request: request)
            case .cloud: CloudStatusView(model: model, urls: request.urls.isEmpty ? [request.directory] : request.urls)
            case .attributes: AttributesView(request: request)
            case .search: AdvancedSearchView(model: model, request: request)
            case .palette: CommandPaletteView(model: model)
            case .shelf: FileShelfView(model: model, destination: request.directory)
            case .archive: ArchiveBrowser(model: model, pane: model.activePane, session: model.activePane.archiveSession, request: request)
            case .extract: ExtractArchiveView(model: model, request: request)
            case .compress: CompressView(model: model, request: request)
            case .rename: BulkRenameView(model: model, request: request)
            case .git: GitRepositoryView(model: model, folder: request.directory)
            case .tags, .hashes, .permissions: MetadataToolView(model: model, request: request)
            case .trash: TrashBrowserView(model: model)
            case .network: NetworkBrowserView(model: model, pane: model.activePane, session: model.activePane.networkSession, destination: request.directory)
            }
            if ![ToolKind.compress, .rename, .extract].contains(request.kind) {
                Divider()
                HStack { Spacer(); Button(L10n.text("Close")) { dismiss() }.frame(minWidth: 96) }.padding(12).background(Palette.background)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.locale, NativeLocalization.locale)
            .environment(\.layoutDirection, NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

@MainActor final class ArchiveBrowserSession: ObservableObject {
    @Published var entries: [ArchiveMember] = []
    @Published var selected = Set<String>()
    @Published var prefix = "" { didSet { if oldValue != prefix && !moving { history = Array(history.prefix(historyIndex + 1)); history.append(prefix); historyIndex = history.count - 1 } } }
    @Published var history = [""]
    @Published var historyIndex = 0
    private var moving = false
    func step(_ offset: Int) { let index = historyIndex + offset; guard history.indices.contains(index) else { return }; moving = true; historyIndex = index; prefix = history[index]; selected = []; moving = false }
    @Published var search = ""
    @Published var password = ""
    @Published var error: String?
    @Published var loading = false
    @Published var preview: URL?
    @Published var temporary: URL?
    @Published var previewTask: Task<Void, Never>?
    @Published var reloadToken = UUID()
    func shutdown() { previewTask?.cancel(); if let temporary { try? FileManager.default.removeItem(at: temporary) }; temporary = nil }
}

struct ArchiveBrowser: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject var session: ArchiveBrowserSession
    let request: ToolRequest
    @Environment(\.dismissTool) private var dismiss
    private var entries: [ArchiveMember] { get { session.entries } nonmutating set { session.entries = newValue } }
    private var selected: Set<String> { get { session.selected } nonmutating set { session.selected = newValue } }
    private var prefix: String { get { session.prefix } nonmutating set { session.prefix = newValue } }
    private var search: String { get { session.search } nonmutating set { session.search = newValue } }
    private var password: String { get { session.password } nonmutating set { session.password = newValue } }
    private var error: String? { get { session.error } nonmutating set { session.error = newValue } }
    private var loading: Bool { get { session.loading } nonmutating set { session.loading = newValue } }
    private var preview: URL? { get { session.preview } nonmutating set { session.preview = newValue } }
    private var temporary: URL? { get { session.temporary } nonmutating set { session.temporary = newValue } }
    private var previewTask: Task<Void, Never>? { get { session.previewTask } nonmutating set { session.previewTask = newValue } }
    private let archive = ArchiveService()
    private var visible: [ArchiveMember] {
        search.isEmpty ? ArchiveMember.children(of: prefix, in: entries) : entries.filter { $0.path.localizedStandardContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if let error {
                HStack {
                    Text(L10n.text(error)).foregroundStyle(.red).textSelection(.enabled)
                    SecureField(L10n.text("Archive password (if needed)"), text: $session.password).frame(width: 180)
                    Button(L10n.text("Reload")) { load() }
                }.padding(12)
            }
            if loading { ProgressView().controlSize(.small).padding(8) }
            HSplitView {
            SharedFileLayout(model: model, pane: pane).overlay {
                    if pane.visibleItems.isEmpty && !loading {
                        VStack(spacing: 12) {
                            Image(systemName: pane.query.isEmpty ? "folder" : "magnifyingglass").font(ExplorerFont.font(size: 35, weight: .light)).foregroundStyle(.tertiary)
                            Text(L10n.text(pane.query.isEmpty ? "This folder is empty" : "No matching items")).foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }
            if let preview { QuickLookView(url: preview).frame(minWidth: 220, idealWidth: 280) }
            }
        }.task {
            pane.virtualAction = handleCommand
            pane.virtualPaste = { urls, destination, verify in
                guard let source = request.urls.first else { throw ArchiveFailure("No archive is open.") }
                let target = destination ?? pane.columnDirectory
                let path = target.map { String($0.path.dropFirst()) + "/" } ?? prefix
                let report = try await archive.edit(source, change: .add(urls, prefix: path, verifyContents: verify), password: password)
                do { entries = try await archive.list(source, password: password) } catch { self.error = error.localizedDescription }
                return report
            }
            if entries.isEmpty { load() }
        }.onChange(of: session.reloadToken) { load() }.onChange(of: prefix) { pane.query = ""; pane.selection = []; pane.columnItems = []; pane.columnDirectory = nil; pane.restorePresentation() }
        .onChange(of: selected) { let urls = Set(selected.map { pane.virtualURL($0) }); if pane.selection != urls { pane.selection = urls } }
        .dropDestination(for: URL.self) { urls, _ in guard !urls.isEmpty, !model.busy else { return false }; edit(.add(urls, prefix: prefix)); return true }
        .onDisappear { if pane.archiveURL == request.urls.first { pane.virtualAction = nil; pane.virtualPaste = nil } }
    }
    private func openSelected() {
        guard let path = selected.first, let entry = entries.first(where: { $0.path == path }) ?? visible.first(where: { $0.path == path }) else { return }
        if entry.directory { prefix = entry.path.hasSuffix("/") ? entry.path : entry.path + "/"; selected = []; search = ""; return }
        guard !entry.link, let source = request.urls.first else { return }
        previewTask?.cancel(); preview = nil; loading = true
        let password = password
        previewTask = Task {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-preview-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let report = try await archive.extract(source, to: folder, selected: [path], password: password)
                try Task.checkCancellation()
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                temporary = folder
                preview = report.completed.first?.appendingPathComponent(path)
            } catch { try? FileManager.default.removeItem(at: folder); if !Task.isCancelled { self.error = error.localizedDescription } }
            loading = false
        }
    }
    private func load() {
        guard let url = request.urls.first, !loading else { return }
        loading = true; error = nil
        Task {
            do { entries = try await archive.list(url, password: password) }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func handleCommand(_ action: String) {
        switch action {
        case "extractAll": extract([]); case "extractSelected": extract(selected); case "addFiles": addEntries()
        case "open", "quickLook": openSelected(); case "copy": model.copy(); case "cut": model.copy(cut: true); case "paste": model.paste()
        case "new": createEntry(directory: true); case "newFile": createEntry(directory: false)
        case "rename": renameEntry(); case "trash": removeEntries(); case "refresh": load()
        case "selectAll": model.selectAll(); case "clear": selected = []; pane.selection = []; case "invert": pane.selection = Set((pane.columnItems.isEmpty ? pane.visibleItems : pane.columnItems).map(\.url)).subtracting(pane.selection); pane.synchronizeVirtualSelection()
        case "back": session.step(-1); case "forward": session.step(1); case "up": pane.up(); case "undo": model.undo(); case "redo": model.redo()
        default: model.alert("Action unavailable", "Use Copy or Extract to transfer archive contents.")
        }
    }
    private func createEntry(directory: Bool) {
        guard let name = model.askName(directory ? "New archive folder" : "New archive file", value: directory ? "New folder" : "Untitled.txt", action: "Create") else { return }
        edit(.create(name, prefix: pane.columnDirectory.map { String($0.path.dropFirst()) + "/" } ?? prefix, directory: directory))
    }
    private func pasteEntries() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { edit(.add(urls, prefix: prefix)) }
    }
    private func copyEntries() {
        guard !selected.isEmpty, let source = request.urls.first else { return }
        let paths = selected; let password = password
        model.run("Copying archive entries", recordingUndo: false) {
            let temporary = try ClipboardStaging.create()
            do {
                let report = try await archive.extract(source, to: temporary, selected: paths, password: password)
                guard let root = report.completed.first else { throw ArchiveFailure("No files were extracted.") }
                let roots = paths.filter { path in !paths.contains { other in path != other && path.hasPrefix(other.hasSuffix("/") ? other : other + "/") } }
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(roots.map { root.appendingPathComponent($0) as NSURL })
                var result = OperationReport(); result.completed = roots.map { root.appendingPathComponent($0) }; return result
            } catch { try? FileManager.default.removeItem(at: temporary); throw error }
        }
    }
    private func edit(_ change: ArchiveEdit) {
        guard let url = request.urls.first else { return }; let password = password
        model.run("Updating archive") {
            let report = try await archive.edit(url, change: change, password: password)
            selected = []; do { entries = try await archive.list(url, password: password) } catch { self.error = error.localizedDescription }; return report
        }
    }
    private func addEntries() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { edit(.add(panel.urls, prefix: prefix)) }
    }
    private func renameEntry() {
        guard let path = selected.first, let item = pane.selectedItems.first else { return }
        InlineRenameRequest.begin(pane: pane, item: item) { name in
            guard model.confirmExtensionChange(from: item.name, to: name, directory: item.isDirectory) else { return }
            edit(.rename(path, to: name))
        }
    }
    private func removeEntries() {
        let alert = NSAlert(); alert.messageText = L10n.text("Remove selected entries from the archive?"); alert.informativeText = L10n.text("The original archive remains recoverable with Undo."); alert.addButton(withTitle: L10n.text("Cancel")); alert.addButton(withTitle: L10n.text("Remove"))
        if alert.runModal() == .alertSecondButtonReturn { edit(.remove(selected)) }
    }
    private func extract(_ selection: Set<String>) {
        guard let url = request.urls.first else { return }
        model.tool = ToolRequest(kind: .extract, urls: [url], directory: request.directory, archiveSelection: selection, archivePassword: password)
    }
}

struct CompressView: View {
    @State private var volumeMiB = ""
    @State private var level = 5
    @State private var dictionaryKiB = 0
    @State private var wordSize = 0
    @State private var threads = min(ProcessInfo.processInfo.activeProcessorCount, 256)
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @Environment(\.dismissTool) private var dismiss
    @State private var name = "Archive"
    @State private var format: ArchiveFormat = .zip
    @State private var password = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 4) {
                    FilesDialogCard { HStack { Text(L10n.text("Name")); Spacer(); TextField(L10n.text("Name"), text: $name).textFieldStyle(.roundedBorder).frame(width: 260) } }
                    FilesDialogCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker(L10n.text("Format"), selection: $format) { ForEach(ArchiveFormat.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                            if format == .zip || format == .sevenZip {
                                Picker(L10n.text("CompressionLevel"), selection: $level) {
                                    Text(L10n.text("CompressionLevelUltra")).tag(9); Text(L10n.text("CompressionLevelHigh")).tag(7)
                                    Text(L10n.text("CompressionLevelNormal")).tag(5); Text(L10n.text("CompressionLevelLow")).tag(3)
                                    Text(L10n.text("CompressionLevelFast")).tag(1); Text(L10n.text("CompressionLevelNone")).tag(0)
                                }
                                Picker(L10n.text("DictionarySize"), selection: $dictionaryKiB) {
                                    Text(L10n.text("Auto")).tag(0)
                                    ForEach([64, 256, 1024, 4096, 16384, 32768, 65536], id: \.self) { size in Text(size < 1024 ? "\(size) KiB" : "\(size / 1024) MiB").tag(size) }
                                }.disabled(format != .sevenZip || level == 0)
                                Picker(L10n.text("WordSize"), selection: $wordSize) {
                                    Text(L10n.text("Auto")).tag(0)
                                    ForEach([8, 16, 32, 64, 128, 256, 273], id: \.self) { Text(String($0)).tag($0) }
                                }.disabled(format != .sevenZip || level == 0)
                                Stepper(value: $threads, in: 1...min(ProcessInfo.processInfo.activeProcessorCount, 256)) { Text(L10n.text("CPUThreads") + ": \(threads)") }
                                SecureField(L10n.text("Password (optional, AES-256)"), text: $password).textFieldStyle(.roundedBorder)
                                TextField(L10n.text("Split into volumes (MiB, optional)"), text: $volumeMiB).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    FilesDialogCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("Destination: \(request.directory.path)")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(L10n.items(request.urls.count))
                            ForEach(request.urls, id: \.self) { Text($0.lastPathComponent).lineLimit(1) }
                        }
                    }
                }.padding(.horizontal, 24).padding(.vertical, 16)
            }
            Divider()
            HStack {
                Spacer()
            Button(L10n.text("Create archive")) {
                do { try MacStorageService.validateName(name) } catch { model.alert("Invalid name", error.localizedDescription); return }
                let destination = request.directory.appendingPathComponent(name + "." + format.extensionName)
                let archive = ArchiveService(); let format = format; let password = format == .zip || format == .sevenZip ? password : ""
                var volumeBytes: Int64?
                if !volumeMiB.isEmpty && (format == .zip || format == .sevenZip) {
                    guard let value = Int64(volumeMiB), (1...1_048_576).contains(value) else { model.alert("Invalid volume size", "Enter a size from 1 to 1,048,576 MiB."); return }
                    volumeBytes = value * 1024 * 1024
                }
                let options: ArchiveCompressionOptions? = format == .zip || format == .sevenZip ? .init(level: level, dictionaryKiB: dictionaryKiB, wordSize: wordSize, threads: threads) : nil
                model.run("Compressing \(destination.lastPathComponent)") { try await archive.compress(request.urls, to: destination, format: format, password: password, volumeBytes: volumeBytes, options: options) }
                dismiss()
            }.buttonStyle(FilesPrimaryButtonStyle()).disabled(request.urls.isEmpty || model.busy || (try? MacStorageService.validateName(name)) == nil)
                Button(L10n.text("Cancel")) { dismiss() }.frame(minWidth: 96)
            }.padding(24).background(Palette.background)
        }.onAppear { if request.urls.count == 1 { name = request.urls[0].deletingPathExtension().lastPathComponent } }
    }
}

struct BulkRenameView: View {
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @Environment(\.dismissTool) private var dismiss
    @State private var mode = "Numbered names"
    @State private var base = "File"
    @State private var replacement = ""
    @State private var start = 1
    private var proposals: [RenameProposal] {
        request.urls.enumerated().map { index, url in
            let directory = (try? ListedItem(url: url).isBrowsable) == true
            let ext = directory ? "" : url.pathExtension
            let original = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            let stem: String
            switch mode {
            case "Find and replace": stem = base.isEmpty ? original : original.replacingOccurrences(of: base, with: replacement)
            case "Add prefix": stem = base + original
            case "Add suffix": stem = original + base
            default: stem = "\(base) (\(start + index))"
            }
            return RenameProposal(source: url, name: stem + (ext.isEmpty ? "" : ".\(ext)"))
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            FilesDialogCard {
                VStack(spacing: 12) {
                    Picker(L10n.text("Pattern"), selection: $mode) { ForEach(["Numbered names", "Find and replace", "Add prefix", "Add suffix"], id: \.self) { Text(L10n.text($0)) } }
                    TextField(mode == "Find and replace" ? "Find" : "Name", text: $base).textFieldStyle(.roundedBorder)
                    if mode == "Find and replace" { TextField(L10n.text("Replace with"), text: $replacement).textFieldStyle(.roundedBorder) }
                    if mode == "Numbered names" { Stepper("Start: \(start)", value: $start, in: 0...999999) }
                }
            }
            Table(proposals) {
                TableColumn(L10n.text("Original name")) { Text($0.source.lastPathComponent) }
                TableColumn(L10n.text("New name")) { Text($0.name).foregroundStyle(Palette.accent) }
            }
            Text(L10n.text("Extensions are preserved. Conflicts stop the batch before any names change.")).font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("Rename")) {
                    let proposals = proposals
                    model.run("Renaming items") { try await model.storage.bulkRename(proposals) }
                    dismiss()
                }.buttonStyle(FilesPrimaryButtonStyle()).disabled(model.busy || proposals.isEmpty)
                Button(L10n.text("Cancel")) { dismiss() }.frame(minWidth: 96)
            }
        }.padding(24)
    }
}

struct MetadataToolView: View {
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @Environment(\.dismissTool) private var dismiss
    @ObservedObject private var settings = SettingsService.shared
    @State private var value = ""
    @State private var text = ""
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.urls.map(\.lastPathComponent).joined(separator: ", ")).font(.headline).lineLimit(2)
            if request.kind == .hashes {
                ScrollView { Text(text).font(ExplorerFont.font(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    if busy { ProgressView().controlSize(.small); Button(L10n.text("Cancel")) { task?.cancel() } }
                    Spacer(); Button(L10n.text("Copy hashes")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }.disabled(busy)
                }
            } else {
                if request.kind == .tags, !settings.namedTags.isEmpty {
                    Menu(L10n.text("Add saved tag")) {
                        ForEach(settings.namedTags) { tag in
                            Button(tag.name) {
                                var names = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                if !names.contains(tag.name) { names.append(tag.name) }; value = names.joined(separator: ", ")
                            }
                        }
                    }
                }
                TextField(request.kind == .tags ? "Tags, separated by commas" : "Permissions (e.g. 644 or 755)", text: $value)
                Text(request.kind == .tags ? "Updates native macOS tags for all selected items. Leave empty to remove tags." : "Applies owner, group, and other permissions to the selected items only.")
                    .font(.callout).foregroundStyle(.secondary)
                if !text.isEmpty { Text(text).foregroundStyle(.red) }
                Spacer()
                Button(L10n.text("Apply")) {
                    busy = true
                    let value = value; let catalog = settings.namedTags
                    task = Task {
                        do {
                            try await Task.detached {
                                if request.kind == .tags { try NativeTags.apply(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, catalog: catalog, to: request.urls) }
                                else { try MetadataService.setPermissions(value, for: request.urls) }
                            }.value
                            model.refreshAll(); dismiss()
                        } catch { text = error.localizedDescription }
                        busy = false
                    }
                }.buttonStyle(FilesPrimaryButtonStyle()).disabled(busy)
            }
        }.padding(24).onAppear { initialize() }.onDisappear { task?.cancel() }
    }
    private func initialize() {
        guard let url = request.urls.first else { return }
        if request.kind == .tags { value = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames?.joined(separator: ", ")) ?? "" }
        else if request.kind == .permissions {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            value = String(format: "%03o", (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0)
        } else {
            busy = true; text = "Calculating hashes…"
            task = Task {
                let work = Task.detached { try MetadataService.hashes(url) }
                do {
                    let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                    text = "MD5\n\(result.md5)\n\nSHA-1\n\(result.sha1)\n\nSHA-256\n\(result.sha256)\n\nSHA-512\n\(result.sha512)"
                } catch { text = error.localizedDescription }
                busy = false
            }
        }
    }
}
