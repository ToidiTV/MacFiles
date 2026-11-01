import SwiftUI
import AppKit
import FilesShared

struct CloudProvidersView: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var settings = SettingsService.shared
    @State private var providers = CloudProviderFolder.detected()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Cloud accounts and folders")).font(.headline)
            List(providers) { provider in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Label(provider.name, systemImage: "icloud"); Spacer(); Text(FileManager.default.fileExists(atPath: provider.url.path) ? "Connected folder" : "Folder unavailable").foregroundStyle(.secondary) }
                    Text(provider.url.path).font(.caption).textSelection(.enabled)
                    HStack {
                        Button(L10n.text("Open folder")) { model.newTab(provider.url); model.tool = nil }
                        Button(L10n.text("Status")) { model.tool = ToolRequest(kind: .cloud, urls: [provider.url], directory: provider.url) }
                        if let app = provider.application { Button(L10n.text("Manage account in provider app")) { NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) } }
                        Button(provider.application == nil ? "Choose provider app…" : "Change provider app…") { chooseApplication(provider) }
                        if settings.cloudFolders.contains(where: { $0.id == provider.id }) { Button(L10n.text("Remove saved folder")) { settings.cloudFolders.removeAll { $0.id == provider.id }; reload() } }
                    }
                }.padding(.vertical, 8)
            }
            Text(L10n.text("Accounts, authentication and sync preferences are managed by each provider’s native app. Removing a saved folder here does not unlink its account or delete files.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Add cloud folder…")) { addFolder() }
                Button(L10n.text("Refresh")) { reload() }
                Spacer(); Button(L10n.text("Open System Settings for iCloud")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
            }
        }.padding(20)
    }
    private func reload() { providers = CloudProviderFolder.detected() }
    private func save(_ provider: CloudProviderFolder) { settings.cloudFolders.removeAll { $0.id == provider.id }; settings.cloudFolders.append(provider); reload() }
    private func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let name = model.askName("Cloud folder name", value: url.lastPathComponent, action: "Add") else { return }
        save(.init(name: name, url: url))
    }
    private func chooseApplication(_ provider: CloudProviderFolder) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { var updated = provider; updated.application = url; save(updated) }
    }
}
