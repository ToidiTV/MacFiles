import SwiftUI
import AppKit
import FilesShared

struct ShellView: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var settings = SettingsService.shared
    var body: some View {
        VStack(spacing: 0) {
            if !model.compactOverlay { TabBar(model: model) }
            if !model.showSettings { NavigationBar(model: model, pane: model.activePane).padding(.horizontal, 8).padding(.vertical, 6) }
            if model.showSettings {
                SettingsView(model: model, onClose: { model.showSettings = false })
            } else {
            HSplitView {
                if settings.sidebarVisible && !model.compactOverlay { SidebarView(model: model).frame(width: 224) }
                VStack(spacing: 0) {
                    HSplitView {
                        let tab = model.currentTab
                        if model.compactOverlay {
                            ExplorerPane(model: model, pane: model.activePane).frame(minWidth: 300)
                        } else if tab.verticalSplit, let secondary = tab.secondary {
                            VSplitView {
                                ExplorerPane(model: model, pane: tab.primary).frame(minHeight: 220)
                                ExplorerPane(model: model, pane: secondary).frame(minHeight: 220)
                            }.frame(minWidth: 350)
                        } else {
                            ExplorerPane(model: model, pane: tab.primary).frame(minWidth: 350)
                            if let secondary = tab.secondary { ExplorerPane(model: model, pane: secondary).frame(minWidth: 350) }
                        }
                        if model.showInfo && !model.compactOverlay { InfoPane(model: model, pane: model.activePane).frame(minWidth: 230, idealWidth: 260, maxWidth: 360) }
                    }
                    if let title = model.operationTitle {
                        VStack(spacing: 6) {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(title).lineLimit(1).font(ExplorerFont.font(size: 11))
                                Spacer()
                                Button(L10n.text("Operations (\(model.queuedCount) queued)")) { model.present(.operations) }.controlSize(.small)
                                Button(L10n.text("Cancel operation")) { model.cancelOperation() }.controlSize(.small)
                            }
                            ProgressView(value: model.operationProgress)
                        }.padding(12).background(Palette.surface)
                    }
                }.padding(.trailing, 8).padding(.bottom, 4)
            }
            }
        }
        .background {
            if let image = NSImage(contentsOfFile: settings.backgroundImagePath) {
                ExplorerBackground(image: image, preferences: settings.preferences).opacity(settings.backgroundImageOpacity)
            }
        }
        .background(Palette.background)
        .background { if settings.preferences.backdrop != "Solid" { ExplorerBackdrop(kind: settings.preferences.backdrop) } }
        .font(ExplorerFont.font(size: 13)).tint(Palette.accent)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: model.compactOverlay ? 400 : model.currentTab.secondary == nil || model.currentTab.verticalSplit ? 860 : 1100, minHeight: model.compactOverlay ? 350 : 560)
        .disabled(model.tool != nil)
        .accessibilityHidden(model.tool != nil)
        .overlay { if let request = model.tool { FilesDialogOverlay(model: model, request: request).id(request.id) } }
        .onChange(of: model.selectedTab) { model.showSettings = false }
        .onChange(of: settings.preferences) {
            ThumbnailCache.shared.images.totalCostLimit = settings.preferences.thumbnailCacheMB * 1024 * 1024
            if !settings.preferences.cacheThumbnails { ThumbnailCache.shared.clear() }
            model.iconRevision += 1
            if settings.preferences.syncFolderPreferences { model.tabs.flatMap { [$0.primary, $0.secondary].compactMap { $0 } }.forEach { $0.restorePresentation() } }
        }
        .onChange(of: settings.defaultLayout) {
            if settings.preferences.syncFolderPreferences { model.tabs.flatMap { [$0.primary, $0.secondary].compactMap { $0 } }.forEach { $0.restorePresentation() } }
        }
        .onChange(of: settings.layoutSizes) { model.iconRevision += 1 }
        .onChange(of: settings.visibleColumns) { model.iconRevision += 1 }
        .onChange(of: settings.autoFitColumns) { model.iconRevision += 1 }
        .onChange(of: settings.showExtensions) { model.iconRevision += 1 }
        .onChange(of: settings.showDotfiles) { model.refreshAll() }
        .onChange(of: settings.showHidden) { model.refreshAll() }
        .onChange(of: settings.filesFirst) { model.objectWillChange.send() }
        .onChange(of: settings.foldersFirst) { model.objectWillChange.send() }
    }
}

struct TabBar: View {
    @ObservedObject var model: MainPageViewModel
    var body: some View {
        HStack(spacing: 4) {

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(model.tabs) { tab in
                        HStack(spacing: 9) {
                            FilesArtwork(symbol: model.selectedTab == tab.id && model.showSettings ? "gearshape" : tab.primary.archiveURL != nil ? "archivebox" : tab.primary.isVirtual ? "network" : tab.primary.location == nil ? "house" : "folder").frame(width: 16, height: 16)
                            Text(model.selectedTab == tab.id && model.showSettings ? L10n.text("Settings") : tab.primary.title).font(ExplorerFont.font(size: 12, weight: model.selectedTab == tab.id ? .medium : .regular)).lineLimit(1)
                            if tab.secondary != nil { Image(systemName: "rectangle.split.2x1").foregroundStyle(.secondary) }
                            Spacer(minLength: 12)
                            Button { if model.selectedTab == tab.id && model.showSettings { model.showSettings = false } else { model.closeTab(tab.id) } } label: { Image(systemName: "xmark").font(ExplorerFont.font(size: 9)).frame(width: 20, height: 20).contentShape(Rectangle()) }
                                .buttonStyle(.plain).help(L10n.text("Close tab"))
                        }
                        .padding(.leading, 12).padding(.trailing, 6).frame(width: 240, height: 32)
                        .background(model.selectedTab == tab.id ? Palette.surface : Color.primary.opacity(0.025), in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
                        .contentShape(Rectangle()).onTapGesture { model.showSettings = false; model.selectTab(tab.id) }
                        .contextMenu {
                            Button(L10n.text("Duplicate tab")) { model.newTab(snapshot: TabSnapshot(primary: tab.primary.snapshot, secondary: tab.secondary?.snapshot, verticalSplit: tab.verticalSplit)) }
                            Button(L10n.text("Close tab")) { model.closeTab(tab.id) }
                            Button(L10n.text("Close tabs to the left")) { for other in model.tabs.prefix(while: { $0.id != tab.id }) { model.closeTab(other.id) } }
                            Button(L10n.text("Close tabs to the right")) { for other in model.tabs.drop(while: { $0.id != tab.id }).dropFirst() { model.closeTab(other.id) } }
                            Button(L10n.text("Close other tabs")) { for other in model.tabs where other.id != tab.id { model.closeTab(other.id) } }
                        }
                        .draggable(tab.id.uuidString)
                        .dropDestination(for: String.self) { strings, _ in
                            guard let value = strings.first, let id = UUID(uuidString: value), model.tabs.contains(where: { $0.id == id }) else { return false }
                            model.moveTab(id, before: tab.id); return true
                        }
                    }
                }
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: CGFloat(model.tabs.count) * 243)
            if SettingsService.shared.preferences.showTabActions {
                Menu {
                    Button(L10n.text("New tab")) { model.newTab() }
                    Button(L10n.text("Reopen closed tab")) { model.reopenTab() }
                    Divider()
                    ForEach(model.tabs) { tab in Button(tab.primary.title) { model.selectTab(tab.id) } }
                } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).help(L10n.text("Tab actions"))
            }
            if SettingsService.shared.preferences.showShelfButton { ToolButton(symbol: "tray", help: "Shelf") { model.present(.shelf) } }
            ToolButton(symbol: "plus", help: "New tab · ⌘T") { model.newTab() }
            Spacer(minLength: 6)
            FilesWindowButtons()
        }.padding(.top, 4).padding(.leading, 8).background(TabWheelRegion { delta in
            guard let index = model.tabs.firstIndex(where: { $0.id == model.selectedTab }) else { return }
            let forward = (delta > 0) != SettingsService.shared.preferences.reverseTabScroll
            let next = index + (forward ? 1 : -1)
            if model.tabs.indices.contains(next) { model.selectTab(model.tabs[next].id) }
        })
    }
}

struct ExplorerPane: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject var settings = SettingsService.shared
    private var active: Bool { model.activePane.id == pane.id }
    var body: some View {
        VStack(spacing: 4) {
            if settings.toolbarVisible && (pane.location != nil || pane.isVirtual) { CustomCommandBar(model: model, pane: pane) }
            VStack(spacing: 0) {
                if let library = pane.library {
                    HStack { Label(library.name, systemImage: "books.vertical"); Spacer(); Text(L10n.text("\(library.folders.count) folders · saves to \(pane.location?.lastPathComponent ?? "")")).foregroundStyle(.secondary) }.font(.caption).padding(10)
                    Divider()
                }
                if let url = pane.archiveURL {
                    ArchiveBrowser(model: model, pane: pane, session: pane.archiveSession, request: ToolRequest(kind: .archive, urls: [url], directory: url.deletingLastPathComponent()))
                } else if pane.isVirtual {
                    NetworkBrowserView(model: model, pane: pane, session: pane.networkSession, destination: FileManager.default.homeDirectoryForCurrentUser)
                } else if pane.location == nil {
                    HomeView(model: model, pane: pane)
                } else if let error = pane.error {
                    ContentUnavailableView {
                        Label(L10n.text("Couldn’t open folder"), systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(L10n.text(error)).textSelection(.enabled)
                    } actions: {
                        Button(L10n.text("Try again")) { pane.refresh() }
                        Button(L10n.text("Choose folder…")) { model.activePaneID = pane.id; model.chooseFolder() }
                    }
                } else {
                    if pane.recursiveSearch {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(Palette.accent)
                            Text(L10n.text("Results in this folder and subfolders")).font(ExplorerFont.font(size: 11))
                            Spacer()
                            Button(L10n.text("Clear")) { pane.query = ""; pane.refresh() }.buttonStyle(.plain).font(ExplorerFont.font(size: 11))
                        }.padding(10).background(Palette.accent.opacity(0.06))
                        Divider()
                    }
                    ZStack {
                        SharedFileLayout(model: model, pane: pane)
                        if pane.loading {
                            VStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(pane.recursiveSearch ? "Searching…" : "Loading…").font(.caption)
                                if pane.recursiveSearch { Button(L10n.text("Stop")) { pane.stopSearch() }.controlSize(.small) }
                            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        } else if pane.visibleItems.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: pane.query.isEmpty ? "folder" : "magnifyingglass").font(ExplorerFont.font(size: 35, weight: .light)).foregroundStyle(.tertiary)
                                Text(pane.query.isEmpty ? "This folder is empty" : "No matching items").foregroundStyle(.secondary)
                                if !pane.query.isEmpty && !pane.recursiveSearch {
                                    Button(L10n.text("Search subfolders")) { pane.refresh(search: true) }
                                }
                            }.allowsHitTesting(!pane.query.isEmpty)
                        }
                    }
                }
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.currentTab.secondary != nil && active ? Palette.accent.opacity(0.65) : Palette.line, lineWidth: 1))
            if settings.preferences.showStatusBar { StatusBar(model: model, pane: pane) }
        }
        .padding(.leading, 4)
        .simultaneousGesture(TapGesture().onEnded { model.activePaneID = pane.id })
    }
}

struct NavigationBar: View {
    @ObservedObject private var settings = SettingsService.shared
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @State private var editing = false
    @State private var path = ""
    @FocusState private var addressFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var searching = false
    private var crumbs: [URL] {
        guard var current = pane.isVirtual ? URL(fileURLWithPath: pane.navigationPath) : pane.location else { return [] }
        var result = [current]
        while current.path != "/" && result.count < 30 { current.deleteLastPathComponent(); result.insert(current, at: 0) }
        return result
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 1) {
                ToolButton(symbol: "arrow.left", help: "Back · ⌘[", enabled: pane.canGoBack) { pane.back() }
                ToolButton(symbol: "arrow.right", help: "Forward · ⌘]", enabled: pane.canGoForward) { pane.forward() }
                ToolButton(symbol: "arrow.up", help: "Up one level · ⌘↑", enabled: pane.archiveURL != nil || (pane.isVirtual ? pane.navigationPath != "/" : pane.location != nil)) { pane.up() }
                ToolButton(symbol: "arrow.clockwise", help: "Refresh · ⌘R") { pane.refresh() }
                HStack(spacing: 5) {
                    Button { pane.navigate(nil) } label: { FilesArtwork(symbol: "house").frame(width: 18, height: 18) }.buttonStyle(.plain).help(L10n.text("Home"))
                    if searching || !pane.query.isEmpty {
                        TextField(L10n.text("Search \(pane.title)"), text: $pane.query)
                            .textFieldStyle(.plain).focused($searchFocused)
                            .onSubmit { if !pane.query.isEmpty { pane.refresh(search: true) } }
                            .onExitCommand { pane.query = ""; searching = false; searchFocused = false; pane.refresh() }
                        Button { pane.query = ""; searching = false; searchFocused = false; pane.refresh() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L10n.text("Clear"))
                    } else if editing {
                        TextField(L10n.text("Folder path"), text: $path).textFieldStyle(.plain).focused($addressFocused)
                            .onSubmit { if pane.isVirtual { if !pane.navigateVirtualPath(path) { model.alert("Couldn’t open this location", path) } } else { model.openPath(path, pane: pane) }; editing = false }
                            .onExitCommand { editing = false }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                if pane.location == nil && !pane.isVirtual { Text(L10n.text("Home")) }
                                ForEach(crumbs, id: \.self) { url in
                                    if url == crumbs.first { Image(systemName: "chevron.right").font(ExplorerFont.font(size: 9)).foregroundStyle(.tertiary) }
                                    Button(url.path == "/" ? (pane.isVirtual ? pane.title : "Macintosh HD") : url.lastPathComponent) { if pane.isVirtual { pane.navigateVirtualPath(url.path) } else { pane.navigate(url) } }.buttonStyle(.plain)
                                    BreadcrumbFolders(pane: pane, url: url)
                                }
                            }.font(ExplorerFont.font(size: 12)).fixedSize()
                        }
                        Button { beginEditing() } label: { Image(systemName: "chevron.right.to.line").font(ExplorerFont.font(size: 12)).foregroundStyle(.tertiary) }
                            .buttonStyle(.plain).help(L10n.text("Edit address · ⌘L"))
                    }
                    if !searching && pane.query.isEmpty {
                        Divider().frame(height: 20)
                        Button { beginSearch() } label: { Image(systemName: "magnifyingglass").frame(width: 28, height: 28) }.buttonStyle(.plain).help(L10n.text("Search folder"))
                    }
                }
                .padding(.horizontal, 11).frame(height: 36)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line))
                .padding(.leading, 5)
            }

            if settings.filterVisible && pane.location != nil {
                TextField(L10n.text("Search \(pane.title) · Return searches subfolders"), text: $pane.query)
                    .textFieldStyle(.roundedBorder).onSubmit { if !pane.query.isEmpty { pane.refresh(search: true) } }
            }
        }
        .onChange(of: model.focusAddress) { if model.activePane.id == pane.id { beginEditing() } }
        .onChange(of: model.focusSearch) { if model.activePane.id == pane.id { beginSearch() } }
        .onChange(of: addressFocused) { if !addressFocused { editing = false } }
        .onChange(of: pane.location) { editing = false; searching = false }
        .onChange(of: pane.navigationPath) { editing = false; searching = false }
        .onChange(of: pane.isVirtual) { editing = false; searching = false }
    }
    private func beginSearch() {
        searching = true; editing = false
        DispatchQueue.main.async { searchFocused = true }
    }
    private func beginEditing() {
        searching = false; searchFocused = false; pane.query = ""
        model.activePaneID = pane.id; path = pane.isVirtual ? pane.navigationPath : pane.location?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        editing = true
        DispatchQueue.main.async { addressFocused = true }
    }
}

struct StatusBar: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    var body: some View {
        HStack(spacing: 12) {
            if pane.location != nil || pane.isVirtual {
                if SettingsService.shared.preferences.separateItemCounts {
                    Text(L10n.text("\(pane.visibleItems.filter(\.isBrowsable).count) folders · \(pane.visibleItems.filter { !$0.isBrowsable }.count) files"))
                } else { Text(L10n.items(pane.visibleItems.count)) }
                if !pane.selection.isEmpty { Divider().frame(height: 12); Text(L10n.selected(pane.selection.count)) }
                if pane.skipped > 0 { Text(L10n.text("\(pane.skipped) inaccessible")).help(L10n.text("Some items could not be read.")) }
            } else { Text(L10n.text("Home")) }
            Spacer(minLength: 0)
            if SettingsService.shared.preferences.alwaysShowOperations && !model.busy { Button(L10n.text("Operations")) { model.present(.operations) }.buttonStyle(.plain) }
            if model.currentTab.secondary == nil { Text(L10n.text(model.statusMessage)).lineLimit(1).truncationMode(.middle) }
            if pane.location != nil || pane.isVirtual {
                Button { pane.layout = .details } label: { Image(systemName: "list.bullet").foregroundStyle(pane.layout == .details ? Palette.accent : .secondary) }.buttonStyle(.plain).help(L10n.text("Details layout"))
                Button { pane.layout = .icons } label: { Image(systemName: "square.grid.2x2").foregroundStyle(pane.layout == .icons ? Palette.accent : .secondary) }.buttonStyle(.plain).help(L10n.text("Icons layout"))
            }
        }.font(ExplorerFont.font(size: 11)).foregroundStyle(.secondary).frame(height: 20).padding(.horizontal, 9)
    }
}
