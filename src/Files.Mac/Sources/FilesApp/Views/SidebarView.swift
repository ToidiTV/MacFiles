import SwiftUI
import FilesShared
import FilesStorage

struct SidebarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var settings = SettingsService.shared
    private var cloud: [Favorite] {
        CloudProviderFolder.detected().map { Favorite(name: $0.name, url: $0.url, symbol: "icloud") }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    SidebarButton(title: "Home", symbol: "house", selected: model.activePane.location == nil) { model.activePane.navigate(nil) }
                    section("Pinned")
                    ForEach(settings.favorites) { favorite in
                        FolderTreeRow(model: model, title: favorite.name, url: favorite.url, symbol: favorite.symbol, depth: 0)
                            .contextMenu {
                                Button(L10n.text("Open in new window")) { openWindow(id: "folder", value: favorite.url) }
                                Button(L10n.text("Copy")) { model.copyReferences([favorite.url]) }
                                Button(L10n.text("Open in Terminal")) { model.terminal(at: favorite.url) }
                                Button(L10n.text("Open in new tab")) { model.newTab(favorite.url) }
                                Button(L10n.text("Open in other pane")) { model.openOtherPane(favorite.url) }
                                Divider()
                                Button(L10n.text("Unpin")) { settings.favorites.removeAll { $0.id == favorite.id } }
                            }
                    }
                    SidebarButton(title: "Trash", symbol: "trash", selected: model.activePane.location?.lastPathComponent == ".Trash") {
                        model.present(.trash)
                    }
                    if !settings.libraries.isEmpty {
                        section("Libraries")
                        ForEach(settings.libraries) { library in
                            SidebarButton(title: library.name, symbol: "books.vertical", selected: model.activePane.library?.id == library.id) {
                                model.activePane.openLibrary(library)
                            }.contextMenu {
                                Button(L10n.text("Open all folders in tabs")) { for folder in library.folders { model.newTab(folder) } }
                                Button(L10n.text("Library properties…")) { model.activePane.openLibrary(library); model.present(.properties) }
                                Button(L10n.text("Remove library")) { settings.libraries.removeAll { $0.id == library.id } }
                            }
                        }
                    }
                    if !settings.savedSearches.isEmpty {
                        section("Saved searches")
                        ForEach(settings.savedSearches) { saved in
                            SidebarButton(title: saved.name, symbol: "magnifyingglass", selected: false) {
                                model.tool = ToolRequest(kind: .search, urls: [], directory: saved.roots.first ?? FileManager.default.homeDirectoryForCurrentUser, savedSearch: saved)
                            }.contextMenu { Button(L10n.text("Remove saved search")) { settings.savedSearches.removeAll { $0.id == saved.id } } }
                        }
                    }
                    section("Drives")
                    ForEach(model.volumes, id: \.self) { volume in
                        FolderTreeRow(model: model, title: volumeName(volume), url: volume,
                                      symbol: volume.path == "/" ? "internaldrive" : "externaldrive", depth: 0)
                            .contextMenu {
                                Button(L10n.text("Open in new tab")) { model.newTab(volume) }
                                Button(L10n.text("Format drive in Disk Utility…")) { model.openDiskUtility() }
                                Button(L10n.text("Storage settings…")) { model.openStorageSettings() }
                                Button(L10n.text("Properties…")) { model.tool = ToolRequest(kind: .properties, urls: [volume], directory: volume) }
                                if volume.path != "/" { Button(L10n.text("Eject")) { model.eject(volume) } }
                            }
                    }
                    if !cloud.isEmpty {
                        section("Cloud storage")
                        Button(L10n.text("Manage cloud accounts…")) { model.present(.providers) }.buttonStyle(.plain).font(.caption).padding(.leading, 14)
                        ForEach(cloud) { favorite in
                            FolderTreeRow(model: model, title: favorite.name, url: favorite.url, symbol: favorite.symbol, depth: 0)
                        }
                    }
                }.padding(.horizontal, 8).padding(.top, 4)
            }
            Divider().padding(.horizontal, 12)
            HStack {
                SidebarButton(title: "Settings", symbol: "gearshape", selected: false) { model.showSettings = true }
            }.padding(9)
        }
    }
    private func section(_ title: String) -> some View {
        Text(L10n.text(title)).font(ExplorerFont.font(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.leading, 12).padding(.top, 22).padding(.bottom, 7)
    }
}

func volumeName(_ url: URL) -> String {
    (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
}

struct SidebarButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                FilesArtwork(symbol: symbol).frame(width: 16, height: 16)
                Text(L10n.text(title)).font(ExplorerFont.font(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 30)
                .background(selected ? Palette.surface : hover ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) { if selected { RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3, height: 17) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct FolderTreeRow: View {
    @ObservedObject var model: MainPageViewModel
    let title: String
    let url: URL
    let symbol: String
    let depth: Int
    @State private var expanded = false
    @State private var children: [ListedItem] = []
    @State private var loading = false
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                SidebarButton(title: title, symbol: symbol, selected: model.activePane.location == url) { model.activePane.navigate(url) }
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(ExplorerFont.font(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary).frame(width: 14, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).help(expanded ? "Collapse folder" : "Expand folder")
            }.padding(.leading, CGFloat(depth) * 12)
            if expanded {
                if loading { ProgressView().controlSize(.mini).padding(.leading, CGFloat(depth + 1) * 12 + 25) }
                if let failure { Text(failure).font(ExplorerFont.font(size: 10)).foregroundStyle(.secondary).lineLimit(2).padding(.leading, 25) }
                ForEach(children) { child in
                    AnyView(FolderTreeRow(model: model, title: child.name, url: child.url, symbol: "folder", depth: depth + 1))
                }
            }
        }
        .task(id: expanded) {
            guard expanded else { return }
            loading = true; failure = nil
            let hidden = SettingsService.shared.showHidden || SettingsService.shared.showDotfiles
            let task = Task.detached { try MacDirectoryService.list(url, hidden: hidden) }
            do {
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard !Task.isCancelled else { return }
                children = result.items.filter { $0.isBrowsable && !$0.isSymbolicLink && SettingsService.shared.isVisible($0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch { if !Task.isCancelled { failure = "Folder unavailable" } }
            loading = false
        }
    }
}
