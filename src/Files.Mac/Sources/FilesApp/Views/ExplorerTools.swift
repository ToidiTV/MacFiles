import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct AdvancedSearchView: View {
    @ObservedObject private var settings = SettingsService.shared
    @State private var savedRoots: [URL]?
    @State private var searchID = UUID()
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @State private var options = SearchOptions()
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var filterDate = false
    @State private var date = Date().addingTimeInterval(-7 * 86400)
    @State private var results: [ListedItem] = []
    @State private var selection = Set<URL>()
    @State private var busy = false
    @State private var message = ""
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Menu(L10n.text("Saved searches")) { ForEach(settings.savedSearches) { saved in Button(saved.name) { apply(saved) } } }
                Button(L10n.text("Save search…")) { saveSearch() }
                Spacer()
            }
            Text((savedRoots ?? [request.directory]).map(\.path).joined(separator: ", ")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack { TextField(L10n.text("Name"), text: $options.name); Toggle(L10n.text("Regular expression"), isOn: $options.regularExpression); Picker(L10n.text("Kind"), selection: $options.kind) { Text(L10n.text("Any")).tag("Any"); Text(L10n.text("Files")).tag("Files"); Text(L10n.text("Folders")).tag("Folders") }.frame(width: 170) }
            HStack { TextField(L10n.text("Extensions: txt, swift, pdf"), text: $options.fileExtension); TextField(L10n.text("Tag"), text: $options.tag); TextField(L10n.text("Contains UTF-8 text"), text: $options.text) }
            HStack {
                TextField(L10n.text("Minimum bytes"), text: $minimum); TextField(L10n.text("Maximum bytes"), text: $maximum)
                Toggle(L10n.text("Modified after"), isOn: $filterDate); DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().disabled(!filterDate)
                Toggle(L10n.text("Hidden"), isOn: $options.hidden)
            }
            HStack {
                Text(L10n.text("Content search includes text, PDF, Office and OpenDocument files. Unsupported, locked and online-only files are counted as skipped.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if busy { ProgressView().controlSize(.small); Button(L10n.text("Stop")) { task?.cancel() } }
                Button(L10n.text("Search")) { search() }.buttonStyle(.borderedProminent).disabled(busy)
            }
            Table(results, selection: $selection) {
                TableColumn(L10n.text("Name"), value: \.name)
                TableColumn(L10n.text("Location")) { Text($0.url.deletingLastPathComponent().path).lineLimit(1).truncationMode(.middle) }
                TableColumn(L10n.text("Size")) { Text($0.sizeLabel) }.width(85)
            }.contextMenu(forSelectionType: URL.self) { urls in
                Button(L10n.text("Open containing folder")) { show(urls.first) }
                Button(L10n.text("Copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls.map { $0 as NSURL }) }
            } primaryAction: { urls in show(urls.first) }
            HStack { Text(L10n.text(message)).font(.caption).textSelection(.enabled); Spacer(); Button(L10n.text("Show in folder")) { show(selection.first) }.disabled(selection.count != 1) }
        }.padding(20).onAppear { if let saved = request.savedSearch { apply(saved) } }.onDisappear { task?.cancel() }
    }
    private func apply(_ saved: SavedSearch) {
        task?.cancel(); busy = false
        options = saved.options; savedRoots = saved.roots
        minimum = options.minimumBytes.map(String.init) ?? ""; maximum = options.maximumBytes.map(String.init) ?? ""
        filterDate = options.modifiedAfter != nil; date = options.modifiedAfter ?? Date(); search()
    }
    private func saveSearch() {
        guard let name = model.askName("Save search", value: options.name.isEmpty ? "My search" : options.name, action: "Save"), !name.isEmpty else { return }
        var savedOptions = options; savedOptions.minimumBytes = Int64(minimum); savedOptions.maximumBytes = Int64(maximum); savedOptions.modifiedAfter = filterDate ? date : nil
        settings.savedSearches.append(SavedSearch(name: name, roots: savedRoots ?? model.activePane.library?.folders ?? [request.directory], options: savedOptions))
    }
    private func show(_ url: URL?) {
        guard let url else { return }
        model.tool = nil; model.newTab(url.deletingLastPathComponent(), activate: true); model.activePane.selection = [url]
    }
    private func search() {
        if !minimum.isEmpty && Int64(minimum) == nil || !maximum.isEmpty && Int64(maximum) == nil { message = "Enter whole numbers for byte limits."; return }
        options.minimumBytes = Int64(minimum); options.maximumBytes = Int64(maximum); options.modifiedAfter = filterDate ? date : nil
        if let low = options.minimumBytes, let high = options.maximumBytes, low > high { message = "Minimum size exceeds maximum size."; return }
        let options = options; let natural = settings.preferences.naturalLanguageSearch && !options.regularExpression; let roots = savedRoots ?? model.activePane.library?.folders ?? [request.directory]
        let id = UUID(); searchID = id
        busy = true; message = "Searching…"; results = []; selection = []
        task = Task {
            let work = Task.detached {
                let resolved = natural ? await NaturalLanguageSearch.translate(options.name, base: options) ?? options : options
                try Task.checkCancellation(); return try SearchService.search(roots, options: resolved)
            }
            do {
                let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard searchID == id else { return }
                results = result.items; message = "\(results.count) results · \(result.skipped) skipped"
            } catch is CancellationError { if searchID == id { message = "Search stopped." } }
            catch { if searchID == id { message = error.localizedDescription } }
            if searchID == id { busy = false }
        }
    }
}

struct AttributesView: View {
    let request: ToolRequest
    @State private var attributes: [ExtendedAttribute] = []
    @State private var selected: String?
    @State private var name = ""
    @State private var value = ""
    @State private var encoding = "UTF-8"
    @State private var message = ""
    private var url: URL? { request.urls.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(url?.path ?? "Select a file").font(.caption).textSelection(.enabled)
            Text(L10n.text("Native macOS extended attributes")).font(.headline)
            HSplitView {
                Table(attributes, selection: $selected) {
                    TableColumn(L10n.text("Name"), value: \.name)
                    TableColumn(L10n.text("Bytes")) { Text(L10n.text("\($0.data.count)")) }.width(60)
                }.frame(minWidth: 290)
                VStack {
                    TextField(L10n.text("Attribute name"), text: $name)
                    Picker(L10n.text("Encoding"), selection: $encoding) { Text(L10n.text("UTF-8")).tag("UTF-8"); Text(L10n.text("Base64")).tag("Base64") }
                    TextEditor(text: $value).font(ExplorerFont.font(size: 12, design: .monospaced))
                    HStack {
                        Button(L10n.text("New")) { selected = nil; name = ""; value = "" }
                        Button(L10n.text("Export bytes…")) { export() }.disabled(selected == nil)
                        Spacer(); Button(L10n.text("Save attribute")) { save() }.disabled(name.isEmpty || url == nil)
                    }
                }.frame(minWidth: 350)
            }
            HStack { Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L10n.text("Remove attribute…")) { remove() }.disabled(selected == nil) }
        }.padding(20).task { reload() }.onChange(of: selected) { populate() }.onChange(of: encoding) { populate() }
    }
    private func reload() { guard let url else { return }; do { attributes = try ExtendedAttributes.list(url) } catch { message = error.localizedDescription } }
    private func populate() {
        guard let entry = attributes.first(where: { $0.name == selected }) else { return }
        name = entry.name
        if encoding == "UTF-8", let text = String(data: entry.data, encoding: .utf8), !text.contains("\0") { value = text }
        else { encoding = "Base64"; value = entry.data.base64EncodedString() }
    }
    private func save() {
        guard let url else { return }
        let data = encoding == "UTF-8" ? Data(value.utf8) : Data(base64Encoded: value.filter { !$0.isWhitespace })
        guard let data else { message = "Invalid Base64 data."; return }
        do { try ExtendedAttributes.write(name, data: data, to: url); reload(); selected = name; message = "Saved." }
        catch { message = error.localizedDescription }
    }
    private func remove() {
        guard let url, let selected else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("Remove ‘\(selected)’?"); alert.informativeText = L10n.text("This removes the attribute from this file. Export its bytes first if you need a backup.")
        alert.addButton(withTitle: L10n.text("Cancel")); alert.addButton(withTitle: L10n.text("Remove"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try ExtendedAttributes.remove(selected, from: url); self.selected = nil; name = ""; value = ""; reload() } catch { message = error.localizedDescription }
    }
    private func export() {
        guard let entry = attributes.first(where: { $0.name == selected }) else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.name + ".bin"
        if panel.runModal() == .OK, let target = panel.url { do { try entry.data.write(to: target, options: .atomic) } catch { message = error.localizedDescription } }
    }
}

@MainActor final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published var urls: [URL] { didSet { UserDefaults.standard.set(urls.map(\.path), forKey: "fileShelf") } }
    private init() { urls = (UserDefaults.standard.stringArray(forKey: "fileShelf") ?? []).map { URL(fileURLWithPath: $0) } }
    func add(_ items: [URL]) { for item in items where !urls.contains(item) { urls.append(item) } }
}
struct FileShelfView: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject private var shelf = ShelfStore.shared
    let destination: URL
    @State private var selection = Set<URL>()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Collect file references from different folders, then copy or move them together.")).foregroundStyle(.secondary)
            List(shelf.urls, id: \.self, selection: $selection) { url in
                HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22); Text(url.lastPathComponent); Spacer(); Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            HStack {
                Button(L10n.text("Add current selection")) { shelf.add(model.activePane.selectedItems.map(\.url)) }.disabled(model.activePane.selection.isEmpty)
                Button(L10n.text("Remove references")) { shelf.urls.removeAll { selection.contains($0) }; selection = [] }.disabled(selection.isEmpty)
                Spacer()
                Button(L10n.text("Copy here")) { transfer(.copy) }.disabled(selection.isEmpty || model.busy)
                Button(L10n.text("Move here")) { transfer(.move) }.disabled(selection.isEmpty || model.busy)
            }
            Text(L10n.text("Destination: \(destination.path)")).font(.caption).textSelection(.enabled)
        }.padding(20)
    }
    private func transfer(_ kind: FileOperation) { model.tool = nil; model.perform(kind, urls: shelf.urls.filter { selection.contains($0) }, destination: destination) }
}

struct PaletteCommand: Identifiable {
    var id: String { title }
    let title: String
    let action: () -> Void
}
struct CommandPaletteView: View {
    @ObservedObject var model: MainPageViewModel
    @State private var query = ""
    @FocusState private var focused: Bool
    private var commands: [PaletteCommand] {
        var values: [PaletteCommand] = [
            .init(title: "New tab", action: { model.newTab() }), .init(title: "Open folder…", action: { model.chooseFolder() }),
            .init(title: "New folder…", action: { model.create(directory: true) }), .init(title: "New text file…", action: { model.create(directory: false) }),
            .init(title: "Copy", action: { model.copy() }), .init(title: "Cut", action: { model.copy(cut: true) }), .init(title: "Paste", action: { model.paste() }),
            .init(title: "Rename…", action: { model.rename() }), .init(title: "Duplicate", action: { model.duplicate() }),
            .init(title: "Move to Trash…", action: { model.trash() }), .init(title: "Undo", action: { model.undo() }), .init(title: "Redo", action: { model.redo() }),
            .init(title: "Quick Look", action: { model.quickLook() }), .init(title: "Toggle dual pane", action: { model.toggleSplit() }),
            .init(title: "Open in Terminal", action: { model.terminal() }), .init(title: "Add selection to shelf", action: { ShelfStore.shared.add(model.activePane.selectedItems.map(\.url)) }),
            .init(title: "Settings…", action: { model.showSettings = true })
        ]
        values += ShortcutConfiguration.parityCommands.map { command in .init(title: command.title, action: { model.executeShortcut(command.id) }) }
        values += LayoutMode.allCases.map { layout in .init(title: layout.rawValue + " layout", action: { model.activePane.layout = layout }) }
        values += [ToolKind.operations, .toolbar, .properties, .cloud, .compress, .archive, .rename, .tags, .hashes, .permissions, .attributes, .git, .network, .trash, .search, .shelf].map { kind in .init(title: kind.rawValue + "…", action: { model.present(kind) }) }
        return values.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }
    var body: some View {
        VStack {
            TextField(L10n.text("Search commands"), text: $query).textFieldStyle(.roundedBorder).focused($focused).onSubmit { if let first = commands.first { run(first) } }.padding(16)
            List(commands) { command in Button(command.title) { run(command) }.buttonStyle(.plain).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading) }
        }.onAppear { focused = true }
    }
    private func run(_ command: PaletteCommand) { model.tool = nil; DispatchQueue.main.async { command.action() } }
}
