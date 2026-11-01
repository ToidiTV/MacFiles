import SwiftUI
import AppKit
import FilesShared

struct HomeAdditionalWidgets: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject private var settings = SettingsService.shared
    @State private var recent: [URL] = []
    @State private var selectedTag: NamedTag?
    var body: some View {
        if settings.preferences.showNetwork {
            FilesWidget(title: "Network", actionTitle: "Connect to server", action: { model.present(.network) }) {
                ForEach(model.volumes.filter { (try? $0.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false }, id: \.self) { url in
                    Button { pane.navigate(url) } label: { Label(url.lastPathComponent, systemImage: "network") }.buttonStyle(.plain)
                }
                Text(L10n.text("Mounted network locations appear here. Connect to a server to browse another location.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if settings.preferences.showTags {
            FilesWidget(title: "Tags", actionTitle: "Browse all tags", action: { selectedTag = NamedTag(name: "") }) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading) {
                    ForEach(settings.namedTags) { tag in Button { selectedTag = tag } label: { Label(tag.name, systemImage: "tag").foregroundStyle(tag.customHex.flatMap(Palette.color) ?? Palette.accent) }.buttonStyle(.bordered) }
                }
            }.sheet(item: $selectedTag) { tag in
                VStack { HStack { Text(L10n.text("Tags")).font(.headline); Spacer(); Button(L10n.text("Done")) { selectedTag = nil } }.padding(); TagBrowserView(model: model, tag: tag.name) }.frame(width: 800, height: 540)
            }
        }
        if settings.preferences.showRecentFiles {
            FilesWidget(title: "Recent files", actionTitle: recent.isEmpty ? nil : "Clear", action: { NSDocumentController.shared.clearRecentDocuments(nil); recent = [] }) {
                if recent.isEmpty { Text(L10n.text("Files you open will appear here.")).font(.caption).foregroundStyle(.secondary) }
                ForEach(recent.prefix(10), id: \.self) { url in
                    Button { if let item = try? ListedItem(url: url) { model.open(item, pane: pane) } } label: {
                        HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24); Text(url.lastPathComponent); Spacer(); Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.contentShape(Rectangle())
                    }.buttonStyle(.plain).contextMenu {
                        Button(L10n.text("Open file location")) { pane.navigate(url.deletingLastPathComponent()) }
                        Button(L10n.text("Copy path")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
                    }
                }
            }.onAppear { recent = NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) } }
        }

    }
}
