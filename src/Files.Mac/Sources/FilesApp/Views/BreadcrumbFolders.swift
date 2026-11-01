import SwiftUI
import FilesStorage

struct BreadcrumbFolders: View {
    @ObservedObject var pane: ShellPageViewModel
    let url: URL
    @State private var showing = false
    @State private var folders: [String] = []
    @State private var loading = false
    @State private var error = ""
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "chevron.right").font(ExplorerFont.font(size: 9)).foregroundStyle(.secondary)
                .frame(width: 16, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).help(L10n.text("Folders"))
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if loading { ProgressView().controlSize(.small).padding(12) }
                    else if !error.isEmpty { Text(error).font(.caption).padding(12) }
                    else if folders.isEmpty { Text(L10n.text("This folder is empty")).foregroundStyle(.secondary).padding(12) }
                    else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(folders, id: \.self) { name in
                                    Button {
                                        showing = false
                                        let child = url.appendingPathComponent(name)
                                        if pane.isVirtual { pane.navigateVirtualPath(child.path) } else { pane.navigate(child) }
                                    } label: {
                                        HStack(spacing: 10) {
                                            FilesArtwork(symbol: "folder").frame(width: 18, height: 18)
                                            Text(name).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }.padding(8).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(height: min(CGFloat(folders.count) * 36, 288))
                    }
                }.frame(width: 260).padding(4).task { await load() }
            }
    }
    @MainActor private func load() async {
        loading = true; error = ""; folders = []
        defer { loading = false }
        do {
            let values: [String]
            if pane.archiveURL != nil {
                let prefix = url.path == "/" ? "" : String(url.path.dropFirst()) + "/"
                values = Array(Set(pane.archiveSession.entries.compactMap { entry -> String? in
                    guard entry.path.hasPrefix(prefix) else { return nil }
                    let tail = String(entry.path.dropFirst(prefix.count))
                    let parts = tail.split(separator: "/")
                    guard let first = parts.first, parts.count > 1 || entry.directory else { return nil }
                    return String(first)
                }))
            } else if pane.isVirtual, let provider = pane.networkSession.provider {
                values = try await provider.list(url.path).filter(\.directory).map(\.name)
            } else if !pane.isVirtual {
                let folder = url
                values = try await Task.detached {
                    try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent)
                }.value
            } else { values = [] }
            try Task.checkCancellation()
            folders = values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
