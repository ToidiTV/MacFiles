import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct GalleryLayout: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    private var current: ListedItem? { pane.selectedItems.first ?? pane.visibleItems.first }
    var body: some View {
        VStack(spacing: 0) {
            if let current {
                if current.isBrowsable {
                    VStack(spacing: 18) {
                        FileIcon(item: current, size: 110)
                        Text(current.name).font(.title2)
                        Button(L10n.text("Open folder")) { model.open(current, pane: pane) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !current.cloud.canPreview {
                    VStack { Label(L10n.text(current.cloud.availability.label), systemImage: current.cloud.availability.symbol); Button(L10n.text("Download")) { pane.selection = [current.url]; model.activePaneID = pane.id; model.downloadCloudSelection() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { FilePreview(item: current, pane: pane).frame(maxWidth: .infinity, maxHeight: .infinity) }
                HStack { Text(current.name).font(.headline); Spacer(); Text(current.kind).foregroundStyle(.secondary); Text(current.sizeLabel).foregroundStyle(.secondary) }.padding(14)
                Divider()
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(pane.visibleItems) { item in
                        FileItemInteraction(item: item, pane: pane, model: model, select: {
                            if NSEvent.modifierFlags.contains(.command) { if pane.selection.contains(item.url) { pane.selection.remove(item.url) } else { pane.selection.insert(item.url) } }
                            else { pane.selection = [item.url] }; model.activePaneID = pane.id
                        }) {
                            VStack(spacing: 6) { FileIcon(item: item, size: 65); InlineFileName(item: item, pane: pane).frame(width: 106, height: 20) }.padding(8)
                                .background(current?.id == item.id ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.frame(width: 122, height: 106)
                    }
                }.padding(10)
            }.frame(height: 125)
        }
    }
}

struct ColumnsLayout: View {
    @ObservedObject private var settings = SettingsService.shared
    private var rowHeight: Double { LayoutSizing.rowHeight(LayoutSizing.level(.columns, sizes: settings.layoutSizes)) }
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @State private var descendants: [[ListedItem]] = []
    @State private var choices: [URL] = []
    @State private var errors: String?
    @State private var reloadTask: Task<Void, Never>?
    private var columns: [[ListedItem]] { [pane.visibleItems] + descendants }
    var body: some View {
        VStack(spacing: 0) {
            if let errors { Text(L10n.text(errors)).font(.caption).foregroundStyle(.red).padding(8) }
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, items in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(items) { item in
                                    FileItemInteraction(item: item, pane: pane, model: model, select: { select(item, column: index) }) {
                                        HStack(spacing: 8) {
                                            FileIcon(item: item); InlineFileName(item: item, pane: pane).frame(height: 20); Spacer(minLength: 0)
                                            if item.isBrowsable { Image(systemName: "chevron.right").font(ExplorerFont.font(size: 9)).foregroundStyle(.secondary) }
                                        }.padding(.horizontal, 10).frame(height: rowHeight)
                                            .background(choices.indices.contains(index) && choices[index] == item.url ? Palette.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4))
                                    }.frame(height: rowHeight)
                                }
                            }.padding(5)
                        }.frame(width: 240)
                        Divider()
                    }
                    if let url = choices.last, let item = columns.flatMap({ $0 }).first(where: { $0.url == url }), !item.isBrowsable, item.cloud.canPreview {
                        FilePreview(item: item, pane: pane).frame(width: 320)
                    }
                }.frame(maxHeight: .infinity)
            }
        }.onChange(of: pane.presentationLocation) { reset() }
            .onChange(of: pane.items) { reloadColumns() }
            .onChange(of: pane.archiveSession.entries) { reloadColumns() }
            .onChange(of: pane.networkSession.items) { reloadColumns() }
            .onChange(of: pane.visibleItems) { reloadColumns() }
            .onChange(of: pane.sort) { reloadColumns() }
            .onChange(of: pane.ascending) { reloadColumns() }
            .onDisappear { reset() }
    }
    private func reset() {
        reloadTask?.cancel(); descendants = []; choices = []; errors = nil; pane.columnItems = []; pane.columnDirectory = nil
    }
    private func reloadColumns() {
        reloadTask?.cancel()
        let paths = choices; let directory = pane.columnDirectory
        reloadTask = Task {
            do {
                var levels: [[ListedItem]] = []; var selected: [URL] = []; var listing = pane.visibleItems
                for path in paths {
                    guard let item = listing.first(where: { $0.url == path }) else { break }
                    selected.append(path)
                    guard item.isBrowsable else { break }
                    listing = pane.orderedItems(try await pane.children(item)); levels.append(listing)
                }
                try Task.checkCancellation(); descendants = levels; choices = selected
                if let directory, let index = selected.firstIndex(of: directory), levels.indices.contains(index) { pane.columnItems = levels[index] }
                else { pane.columnItems = [] }
                pane.selection.formIntersection(Set(([pane.visibleItems] + levels).flatMap { $0 }.map(\.url)))
                if pane.isVirtual { pane.synchronizeVirtualSelection() }
            } catch { if !Task.isCancelled { errors = error.localizedDescription } }
        }
    }
    private func select(_ item: ListedItem, column: Int) {
        model.activePaneID = pane.id
        choices = Array(choices.prefix(column)); choices.append(item.url)
        descendants = Array(descendants.prefix(column))
        pane.columnItems = columns[column]; pane.columnDirectory = item.url.deletingLastPathComponent()
        pane.selection = [item.url]
        errors = nil
        guard item.isBrowsable, SettingsService.shared.preferences.singleClickColumns || (NSApp.currentEvent?.clickCount ?? 0) >= 2 else { return }
        Task {
            do {
                let listing = try await pane.children(item)
                guard choices.indices.contains(column), choices[column] == item.url else { return }
                descendants = Array(descendants.prefix(column))
                descendants.append(pane.orderedItems(listing))
            } catch { errors = error.localizedDescription }
        }
    }
}
