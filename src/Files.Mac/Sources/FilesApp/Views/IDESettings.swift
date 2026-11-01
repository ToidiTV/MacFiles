import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FilesShared

struct IDESettings: View {
    @ObservedObject private var settings = SettingsService.shared
    @State private var message = ""
    var body: some View {
        Section(L10n.text("Developer tools")) {
            Text(settings.idePath.isEmpty ? L10n.text("No IDE selected") : settings.idePath).font(.caption).textSelection(.enabled)
            HStack {
                Button(L10n.text("Choose IDE…")) {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false; panel.canChooseFiles = true
                    guard panel.runModal() == .OK, let url = panel.url, Bundle(url: url)?.executableURL != nil else { return }
                    settings.idePath = url.path; message = ""
                }
                Button(L10n.text("Test IDE")) {
                    let url = URL(fileURLWithPath: settings.idePath)
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        Task { @MainActor in message = error?.localizedDescription ?? L10n.text("IDE opened.") }
                    }
                }.disabled(settings.idePath.isEmpty)
                Button(L10n.text("Clear")) { settings.idePath = ""; message = "" }.disabled(settings.idePath.isEmpty)
            }
            Text(L10n.text("Open in IDE uses the selected application. Open repository in IDE resolves the Git repository root first.")).font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.caption) }
        }
    }
}
