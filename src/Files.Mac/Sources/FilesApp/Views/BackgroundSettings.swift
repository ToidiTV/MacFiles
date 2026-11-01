import SwiftUI
import AppKit
import ServiceManagement
import FilesShared

struct BackgroundAppMenu: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(L10n.text("Open MacFiles")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button(L10n.text("Quit MacFiles")) { NSApp.terminate(nil) }
    }
}
struct BackgroundSettings: View {
    @ObservedObject private var settings = SettingsService.shared
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var error = ""
    var body: some View {
        Section(L10n.text("Background")) {
            Toggle(L10n.text("Launch at login"), isOn: Binding(get: { login }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    login = SMAppService.mainApp.status == .enabled
                    error = SMAppService.mainApp.status == .requiresApproval ? L10n.text("Approve MacFiles in Login Items in System Settings.") : ""
                } catch { self.error = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
            }))
            Button(L10n.text("Open Login Items settings")) { SMAppService.openSystemSettingsLoginItems() }
            Toggle(L10n.text("Keep running after closing windows"), isOn: $settings.preferences.closeToBackground)
            Toggle(L10n.text("Show menu bar icon"), isOn: $settings.preferences.showMenuBarIcon).disabled(settings.preferences.closeToBackground)
            Text(L10n.text("Background mode keeps the menu bar icon available so you can reopen MacFiles or quit it.")).font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).textSelection(.enabled) }
        }
    }
}
