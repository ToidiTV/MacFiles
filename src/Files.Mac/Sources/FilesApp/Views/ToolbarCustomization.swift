import SwiftUI
import AppKit
import FilesShared
import FilesStorage

extension MainPageViewModel {
    func canExecute(_ action: ExplorerAction, in candidate: ShellPageViewModel? = nil) -> Bool {
        let activePane = candidate ?? self.activePane
        let items = activePane.selectedItems
        if activePane.isVirtual {
            let pane = activePane; let writable = pane.archiveURL.map { ArchiveService.editableFormat($0) != nil } ?? (pane.networkSession.provider != nil)
            let working = busy || (pane.archiveURL != nil ? pane.archiveSession.loading : pane.networkSession.busy)
            switch action {
            case .new: return writable && !working
            case .properties, .hashes, .copy, .quickLook, .share, .openWith: return !items.isEmpty && !working
            case .permissions: return writable && !items.isEmpty && !working
            case .attributes: return false
            case .rename: return writable && items.count == 1 && !working
            case .cut, .trash: return writable && !items.isEmpty && !working
            case .paste: return writable && canPaste && !working
            case .undo: return !working && !undoStack.isEmpty
            case .redo: return !working && redoAvailable
            case .duplicate, .bulkRename, .compress, .tags, .alias, .rotateLeft, .rotateRight, .wallpaper, .mediaMetadata, .download, .cloud, .terminal: return false
            default: break
            }
        }
        switch action {
        case .rotateLeft, .rotateRight: return !items.isEmpty && items.allSatisfy { MediaService.isImage($0.url) } && !busy
        case .wallpaper: return items.count == 1 && MediaService.isImage(items[0].url)
        case .mediaMetadata: return items.count == 1 && MediaService.isEditable(items[0].url) && !busy
        case .cut, .copy, .trash, .duplicate, .bulkRename, .compress, .tags, .permissions, .share, .openWith, .quickLook: return !items.isEmpty && !busy
        case .rename, .alias, .attributes: return items.count == 1 && !busy
        case .hashes: return items.count == 1 && !items[0].isDirectory && !busy
        case .download: return items.contains { $0.cloud.isCloud && !$0.isDirectory } && !busy
        case .cloud: return items.contains { $0.cloud.isCloud }
        case .undo: return !undoStack.isEmpty && !busy
        case .redo: return !redoStack.isEmpty && !busy
        case .paste: return activePane.operationDirectory != nil && canPaste
        case .new: return activePane.operationDirectory != nil && !busy
        default: return true
        }
    }
    func execute(_ action: ExplorerAction) {
        guard canExecute(action) else { return }
        switch action {
        case .rotateLeft: rotateImages(clockwise: false); case .rotateRight: rotateImages(clockwise: true); case .wallpaper: setWallpaper(); case .mediaMetadata: present(.mediaMetadata)
        case .cut: copy(cut: true); case .copy: copy(); case .paste: paste(); case .rename: rename(); case .trash: trash(); case .duplicate: duplicate()
        case .properties: present(.properties); case .quickLook: quickLook(); case .share: share(); case .openWith: openWith(); case .alias: makeAlias()
        case .compress: present(.compress); case .bulkRename: present(.rename); case .tags: present(.tags); case .hashes: present(.hashes); case .attributes: present(.attributes); case .permissions: present(.permissions)
        case .search: present(.search); case .palette: present(.palette); case .shelf: present(.shelf); case .git: present(.git); case .network: present(.network)
        case .split: toggleSplit(); case .info: showInfo.toggle(); case .refresh: activePane.refresh(); case .terminal: terminal(); case .hidden: SettingsService.shared.showHidden.toggle()
        case .undo: undo(); case .redo: redo(); case .download: downloadCloudSelection(); case .cloud: present(.cloud)
        case .new: create(directory: true)
        default: break
        }
    }
}

struct CustomCommandBar: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject private var settings = SettingsService.shared
    private var context: ToolbarContext {
        let count = pane.selectedItems.count
        return count == 0 ? .browsing : count > 1 ? .multiple : pane.selectedItems[0].isBrowsable ? .folder : .file
    }
    private var entries: [ToolbarEntry] { settings.toolbar.resolved(context: context, cloud: pane.selectedItems.contains { $0.cloud.isCloud }) }
    private func activate(_ action: ExplorerAction) { model.activePaneID = pane.id; model.execute(action) }
    var body: some View {
        HStack(spacing: 3) {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(entries) { entry in
                            if entry.id == entries.first(where: { $0.action == .sort })?.id { Spacer(minLength: 24) }
                            control(entry)
                        }
                    }.frame(minWidth: geometry.size.width).frame(height: 32)
                }
            }.frame(height: 32)
            Menu {
                if pane.archiveURL != nil {
                    Button(L10n.text("Extract all…")) { pane.virtualAction?("extractAll") }.disabled(model.busy)
                    Button(L10n.text("Extract selected…")) { pane.virtualAction?("extractSelected") }.disabled(pane.selection.isEmpty || model.busy)
                    Button(L10n.text("Add files…")) { pane.virtualAction?("addFiles") }.disabled(model.busy)
                    Divider()
                } else if pane.isVirtual {
                    Button(L10n.text("Upload files…")) { pane.virtualAction?("upload") }.disabled(pane.networkSession.provider == nil || pane.networkSession.busy)
                    Button(L10n.text("Download files…")) { pane.virtualAction?("download") }.disabled(pane.selection.isEmpty || pane.networkSession.busy)
                    Menu(L10n.text("Conflicts")) {
                        Picker(L10n.text("When an item exists"), selection: Binding(get: { pane.networkSession.conflict }, set: { pane.networkSession.conflict = $0 })) {
                            Text(L10n.text("Keep both")).tag(ConflictPolicy.keepBoth)
                            Text(L10n.text("Skip")).tag(ConflictPolicy.skip)
                            Text(L10n.text("Replace, keeping backup")).tag(ConflictPolicy.replace)
                        }
                    }
                    Button(L10n.text("Disconnect")) { pane.virtualAction?("disconnect") }.disabled(pane.networkSession.provider == nil || pane.networkSession.busy)
                    Divider()
                }
                ForEach(ExplorerAction.allCases.filter { ![.separator, .sort, .layout, .new].contains($0) }) { action in
                    Button { activate(action) } label: { Label(L10n.text(pane.actionTitle(action)), systemImage: action.symbol) }.disabled(!enabled(action))
                }
                Divider()
                Button(L10n.text("Operations…")) { model.present(.operations) }
                Button(L10n.text("Customize toolbar…")) { model.activePaneID = pane.id; model.present(.toolbar) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help(L10n.text("More actions"))
        }.tint(.primary).padding(.horizontal, 8).padding(.vertical, 7).background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
            .contextMenu { Button(L10n.text("Customize toolbar…")) { model.present(.toolbar) } }
    }
    private func enabled(_ action: ExplorerAction) -> Bool {
        model.canExecute(action, in: pane)
    }

    private func label(_ entry: ToolbarEntry) -> some View {
        HStack(spacing: 5) {
            if entry.showIcon { Image(systemName: entry.action.symbol) }
            if entry.showLabel { Text(L10n.text(pane.actionTitle(entry.action))) }
        }.font(ExplorerFont.font(size: 12)).padding(.horizontal, 6).frame(minWidth: 28, minHeight: 29)
    }
    @ViewBuilder private func control(_ entry: ToolbarEntry) -> some View {
        switch entry.action {
        case .separator: Divider().frame(height: 20).padding(.horizontal, 3)
        case .new:
            Menu {
                Button(L10n.text("New folder…")) { activate(.new) }
                Button(L10n.text("New text file…")) { model.activePaneID = pane.id; model.create(directory: false) }
                Button(L10n.text("New from template…")) { model.activePaneID = pane.id; model.createFromTemplate() }.disabled(pane.isVirtual)
            } label: { label(entry) }.menuStyle(.borderlessButton).fixedSize().disabled(!enabled(.new))
        case .sort:
            Menu {
                Picker(L10n.text("Sort by"), selection: $pane.sort) { ForEach(SortField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Ascending"), isOn: $pane.ascending)
                Picker(L10n.text("Group by"), selection: $pane.group) { ForEach(GroupField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Group ascending"), isOn: $pane.groupAscending)
                Picker(L10n.text("Group by date unit"), selection: $pane.groupDateUnit) { ForEach(GroupDateUnit.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Button(L10n.text("SortFoldersFirst")) { settings.filesFirst = false; settings.foldersFirst = true }
                Button(L10n.text("SortFilesFirst")) { settings.foldersFirst = false; settings.filesFirst = true }
                Button(L10n.text("SortFilesAndFoldersTogether")) { settings.foldersFirst = false; settings.filesFirst = false }
            } label: { label(entry) }.menuStyle(.borderlessButton).fixedSize().help(L10n.text("Sort"))
        case .layout:
            Menu {
                Picker(L10n.text("Layout"), selection: $pane.layout) { ForEach(LayoutMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Show hidden files"), isOn: $settings.showHidden)
                Menu(L10n.text("Columns")) {
                    ForEach(["modified", "created", "kind", "size", "cloud", "tags", "path"], id: \.self) { key in
                        Toggle(L10n.text(["modified": "Date modified", "created": "Date created", "kind": "Kind", "size": "Size", "cloud": "Cloud status", "tags": "Tags", "path": "Path"][key]!), isOn: Binding(get: { settings.visibleColumns.contains(key) }, set: { enabled in
                            settings.visibleColumns.removeAll { $0 == key }; if enabled { settings.visibleColumns.append(key) }
                        }))
                    }
                    Divider()
                    Toggle(L10n.text("AutoFitColumns"), isOn: $settings.autoFitColumns)
                }
            } label: { label(entry) }.menuStyle(.borderlessButton).fixedSize().help(L10n.text("Layout"))
        default:
            Button { activate(entry.action) } label: { label(entry) }.buttonStyle(.plain).disabled(!enabled(entry.action)).help(L10n.text(pane.actionTitle(entry.action))).accessibilityLabel(L10n.text(pane.actionTitle(entry.action)))
        }
    }
}

struct ToolbarCustomizationView: View {
    @ObservedObject private var settings = SettingsService.shared
    @Environment(\.dismissTool) private var dismiss
    @State private var draft = SettingsService.shared.toolbar
    @State private var context = ToolbarContext.always
    @State private var query = ""
    @State private var message = ""
    private var entries: [ToolbarEntry] { draft.entries(for: context) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.text("Context"), selection: $context) { ForEach(ToolbarContext.allCases) { Text(L10n.text($0.rawValue)).tag($0) } }.frame(width: 330)
            Text(L10n.text("Always-visible items are combined with the current selection context. Cloud items add their own controls.")).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(entries) { entry in
                        if entry.action == .separator { Divider().frame(height: 23) }
                        else { HStack { if entry.showIcon { Image(systemName: entry.action.symbol) }; if entry.showLabel { Text(L10n.text(entry.action.title)) } }.padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 5)) }
                    }
                }
            }.frame(height: 45)
            HSplitView {
                VStack {
                    TextField(L10n.text("Search available actions"), text: $query)
                    List(ExplorerAction.allCases.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { action in
                        HStack { Label(L10n.text(action.title), systemImage: action.symbol); Spacer(); Button(L10n.text("Add")) { draft.contexts[context.rawValue, default: []].append(ToolbarEntry(action)) } }
                    }
                }.frame(minWidth: 250)
                List {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text(L10n.text(entry.action.title)).frame(maxWidth: .infinity, alignment: .leading)
                            if entry.action != .separator {
                                Toggle(L10n.text("Icon"), isOn: binding(entry.id, icon: true)).toggleStyle(.checkbox)
                                Toggle(L10n.text("Label"), isOn: binding(entry.id, icon: false)).toggleStyle(.checkbox)
                            }
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == entries.count - 1)
                            Button { draft.contexts[context.rawValue]?.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                        }.draggable(entry.id.uuidString).dropDestination(for: String.self) { values, _ in
                            guard let id = values.first.flatMap(UUID.init(uuidString:)), let old = entries.firstIndex(where: { $0.id == id }) else { return false }
                            var list = entries; let moved = list.remove(at: old); list.insert(moved, at: min(index, list.count)); draft.contexts[context.rawValue] = list; return true
                        }
                    }
                }.frame(minWidth: 430)
            }
            Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Reset all")) { draft = .standard }
                Button(L10n.text("Import…")) { importFile() }; Button(L10n.text("Export…")) { exportFile() }
                Spacer(); Button(L10n.text("Apply")) { do { settings.toolbar = try draft.validated(); dismiss() } catch { message = error.localizedDescription } }.buttonStyle(FilesPrimaryButtonStyle())
            }
        }.padding(20)
    }
    private func binding(_ id: UUID, icon: Bool) -> Binding<Bool> {
        Binding(get: { let item = entries.first { $0.id == id }; return icon ? item?.showIcon ?? true : item?.showLabel ?? false }, set: { value in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            if icon { draft.contexts[context.rawValue]?[index].showIcon = value } else { draft.contexts[context.rawValue]?[index].showLabel = value }
            if draft.contexts[context.rawValue]?[index].showIcon == false && draft.contexts[context.rawValue]?[index].showLabel == false {
                if icon { draft.contexts[context.rawValue]?[index].showLabel = true } else { draft.contexts[context.rawValue]?[index].showIcon = true }
            }
        })
    }
    private func move(_ index: Int, by delta: Int) { var list = entries; list.swapAt(index, index + delta); draft.contexts[context.rawValue] = list }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { do { draft = try JSONDecoder().decode(ToolbarConfiguration.self, from: Data(contentsOf: url)).validated() } catch { message = error.localizedDescription } }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MacFiles-toolbar.json"
        if panel.runModal() == .OK, let url = panel.url { do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(draft.validated()).write(to: url, options: .atomic) } catch { message = error.localizedDescription } }
    }
}

@MainActor extension ShellPageViewModel {
    func actionTitle(_ action: ExplorerAction) -> String {
        if isVirtual && action == .trash { return archiveURL == nil ? "Move to recovery folder…" : "Remove from archive" }
        return action.title
    }
}
