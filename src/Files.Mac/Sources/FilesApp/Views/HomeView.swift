import SwiftUI
import FilesShared

struct HomeView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject var settings = SettingsService.shared
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if settings.preferences.showQuickAccess {
                FilesWidget(title: "Quick access") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(6, max(1, Int((geometry.size.width - 32) / 108)))), spacing: 8) {
                        ForEach(settings.favorites.prefix(9)) { favorite in
                            Button { pane.navigate(favorite.url) } label: {
                                VStack(spacing: 4) {
                                    FilesArtwork(symbol: favorite.symbol).frame(width: 32, height: 32)
                                    Text(favorite.name).font(ExplorerFont.font(size: 14)).lineLimit(1)
                                }.padding(8).frame(maxWidth: .infinity).frame(height: 72)
                                    .background(Palette.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line))
                                    .overlay(alignment: .topTrailing) { Image(systemName: "pin").font(.system(size: 9)).foregroundStyle(.secondary).padding(7) }
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).contextMenu {
                                Button(L10n.text("Open in new window")) { openWindow(id: "folder", value: favorite.url) }
                                Button(L10n.text("Copy")) { model.copyReferences([favorite.url]) }
                                Button(L10n.text("Open in Terminal")) { model.terminal(at: favorite.url) }
                                Button(L10n.text("Open in new tab")) { model.newTab(favorite.url) }
                                Button(L10n.text("Open in other pane")) { model.openOtherPane(favorite.url) }
                            }
                        }
                    }
                }
                }
                if settings.preferences.showDrives {
                FilesWidget(title: "Drives") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(model.volumes, id: \.self) { url in
                            DriveCard(url: url) { pane.navigate(url) }.contextMenu {
                                Button(L10n.text("Format drive in Disk Utility…")) { model.openDiskUtility() }
                                Button(L10n.text("Storage settings…")) { model.openStorageSettings() }
                            }
                        }
                    }
                }
                }
                HomeAdditionalWidgets(model: model, pane: pane)
                if settings.preferences.showRecentFolders {
                FilesWidget(title: "Recent folders", actionTitle: settings.recentFolders.isEmpty ? nil : "Clear", action: { settings.recentFolders = [] }) {
                    if settings.recentFolders.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").font(ExplorerFont.font(size: 22)).foregroundStyle(.tertiary)
                            Text(L10n.text("Folders you open will appear here.")).font(ExplorerFont.font(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                        }.padding(20).background(Palette.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(settings.recentFolders.prefix(6)), id: \.self) { path in
                                let url = URL(fileURLWithPath: path)
                                Button { pane.navigate(url) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill").foregroundStyle(Palette.folder).font(ExplorerFont.font(size: 20))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.lastPathComponent).font(ExplorerFont.font(size: 12))
                                            Text(path).font(ExplorerFont.font(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(ExplorerFont.font(size: 10)).foregroundStyle(.tertiary)
                                    }.padding(12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if path != settings.recentFolders.prefix(6).last { Divider().padding(.leading, 44) }
                            }
                        }.background(Palette.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                }
            }.padding(16)
        }
        }
    }

}

struct DriveCard: View {
    let url: URL
    let action: () -> Void
    private var capacity: URLResourceValues? { try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                FilesArtwork(symbol: url.path == "/" ? "internaldrive" : "externaldrive").frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 8) {
                    Text(volumeName(url)).font(ExplorerFont.font(size: 12, weight: .medium)).lineLimit(1)
                    if let total = capacity?.volumeTotalCapacity, let available = capacity?.volumeAvailableCapacity, total > 0 {
                        ProgressView(value: Double(total - available), total: Double(total)).tint(Palette.accent)
                        Text(L10n.text("\(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))"))
                            .font(ExplorerFont.font(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    } else { Text(url.path).font(ExplorerFont.font(size: 10)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading).frame(height: 105)
                .background(Palette.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
