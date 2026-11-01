import SwiftUI
import AppKit
import FilesShared
import FilesStorage

extension MainPageViewModel {
    func downloadCloudSelection() {
        let urls = activePane.selectedItems.filter { $0.cloud.isCloud && !$0.isDirectory }.map(\.url)
        guard !urls.isEmpty else { return }
        run("Requesting cloud download", recordingUndo: false) { try await CloudService.downloadAsync(urls) }
    }
}
struct CloudStatusView: View {
    @ObservedObject var model: MainPageViewModel
    let urls: [URL]
    @State private var items: [ListedItem] = []
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Cloud availability and synchronization")).font(.headline)
            List(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(item.name).bold(); Spacer(); Label(L10n.text(item.cloud.availability.label.isEmpty ? "Local file" : item.cloud.availability.label), systemImage: item.cloud.availability.symbol.isEmpty ? "internaldrive" : item.cloud.availability.symbol) }
                    Text(item.cloud.provider ?? L10n.text("Not managed by a detected cloud provider")).font(.caption)
                    Text(L10n.text(item.cloud.detail)).font(.caption).foregroundStyle(.secondary)
                    if item.cloud.isCloud {
                        HStack {
                            Button(L10n.text("Download")) { download(item.url) }.disabled(item.isDirectory || model.busy)
                            if item.cloud.isICloud { Button(L10n.text("Remove local download…")) { evict(item.url) }.disabled(model.busy || item.isDirectory || item.cloud.availability != .uploaded) }
                            Button(L10n.text("Provider controls in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        }
                    }
                }.padding(.vertical, 8)
            }
            Text(L10n.text(message)).font(.caption).textSelection(.enabled)
            Text(L10n.text("Third-party providers do not expose a common public sync-completion API. Available locally describes downloaded bytes, not upload completion. Download requests do not pin files permanently.")).font(.caption).foregroundStyle(.secondary)
        }.padding(20).task {
            while !Task.isCancelled {
                items = await Task.detached { urls.compactMap { try? ListedItem(url: $0) } }.value
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    private func download(_ url: URL) { model.run("Requesting cloud download", recordingUndo: false) { try await CloudService.downloadAsync([url]) }; message = "Download requested. iCloud may complete it asynchronously." }
    private func evict(_ url: URL) {
        let alert = NSAlert(); alert.messageText = L10n.text("Remove the local download?"); alert.informativeText = L10n.text("The uploaded iCloud copy remains available. macOS will download it again when needed.")
        alert.addButton(withTitle: L10n.text("Cancel")); alert.addButton(withTitle: L10n.text("Remove download"))
        if alert.runModal() == .alertSecondButtonReturn {
            Task { do { try await Task.detached { try CloudService.evictICloud(url) }.value; message = "Local download removal requested." } catch { message = error.localizedDescription } }
        }
    }
}
