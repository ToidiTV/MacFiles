import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FilesShared
import FilesStorage

struct InfoPane: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    @State private var folderSize = ""
    @State private var calculating = false
    @State private var sizeTask: Task<Void, Never>?
    private var item: ListedItem? { pane.selectedItems.first ?? pane.location.flatMap { try? ListedItem(url: $0) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("Details")).font(ExplorerFont.font(size: 13, weight: .semibold))
                Spacer()
                ToolButton(symbol: "xmark", help: "Close details") { model.showInfo = false }
            }.padding(10)
            Divider()
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !item.isBrowsable && item.cloud.canPreview && pane.selection.count <= 1 {
                            FilePreview(item: item, pane: pane).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 7))
                        } else {
                            HStack { Spacer(); FileIcon(item: item, size: 78); Spacer() }.padding(.vertical, 22)
                        }
                        Text(pane.selection.count > 1 ? L10n.selected(pane.selection.count) : item.name)
                            .font(ExplorerFont.font(size: 17, weight: .semibold)).textSelection(.enabled)
                        Divider()
                        if pane.selection.count > 1 {
                            detail("Files size", ByteCountFormatter.string(fromByteCount: pane.selectedItems.filter { !$0.isBrowsable }.reduce(0) { $0 + $1.size }, countStyle: .file))
                            Text(L10n.text("Folder contents are not included in this total.")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            detail("Kind", item.localizedKind)
                            detail("Location", item.url.deletingLastPathComponent().path)
                            if !item.isBrowsable { detail("Size", item.sizeLabel) }
                            else {
                                if !folderSize.isEmpty { detail("Folder contents", folderSize) }
                                if calculating { ProgressView().controlSize(.small); Button(L10n.text("Cancel calculation")) { sizeTask?.cancel(); calculating = false } }
                                else { Button(L10n.text("Calculate folder size")) { if pane.isVirtual { model.present(.properties) } else { calculateSize(item.url) } }.controlSize(.small) }
                            }
                            if let date = item.modified { detail("Modified", FileDisplayFormat.date(date)) }
                            if let date = item.created { detail("Created", FileDisplayFormat.date(date)) }
                            if !item.tags.isEmpty { detail("Tags", item.tags.joined(separator: ", ")) }
                            if item.isSymbolicLink { detail("Link target", item.url.resolvingSymlinksInPath().path) }
                        }
                        Button(L10n.text("Properties…")) { model.present(.properties) }.controlSize(.small)
                        Button(L10n.text("Copy path")) { model.copyPath() }.controlSize(.small)
                    }.padding(18)
                }
            } else { Spacer(); Text(L10n.text("Select an item to see its details.")).foregroundStyle(.secondary).padding(); Spacer() }
        }.onChange(of: item?.url) { sizeTask?.cancel(); folderSize = ""; calculating = false }.onDisappear { sizeTask?.cancel() }
        .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.top, 6)
    }
    private func calculateSize(_ url: URL) {
        calculating = true
        sizeTask = Task {
            let work = Task.detached { try MetadataService.directorySize(url) }
            do {
                let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled else { return }
                folderSize = "\(ByteCountFormatter.string(fromByteCount: result.0, countStyle: .file)) · \(result.1) items"
            } catch { if !Task.isCancelled { folderSize = error.localizedDescription } }
            if !Task.isCancelled { calculating = false }
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(label)).font(ExplorerFont.font(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(ExplorerFont.font(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: MainPageViewModel
    var onClose: () -> Void
    @State private var category = "General"
    @State private var search = ""
    private func matches(_ keys: [String]) -> Bool { search.isEmpty ? SettingsCategory.contains(keys.first ?? "", in: category) : keys.contains { L10n.text($0).localizedStandardContains(search) } }
    @ObservedObject var settings = SettingsService.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button { onClose() } label: { Image(systemName: "arrow.left") }.buttonStyle(.plain).help(L10n.text("Back"))
                    Text(L10n.text("Settings")).font(.system(size: 20, weight: .semibold))
                }.padding(.horizontal, 12).padding(.vertical, 16)
                TextField(L10n.text("Search settings"), text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 12).padding(.bottom, 12)
                ForEach(SettingsCategory.all) { item in
                    SidebarButton(title: item.id, symbol: item.symbol, selected: category == item.id && search.isEmpty) { category = item.id; search = "" }
                }
                Spacer()
            }.padding(.horizontal, 8).frame(width: 224)
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text(search.isEmpty ? category : "Search settings")).font(.system(size: 28, weight: .semibold)).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
            if search.isEmpty && category == "Actions" {
                ShortcutCustomizationView(embedded: true).padding(12)
            } else {
            Form {
                if !SettingsSearchIndex.hasMatch(search) { Text(L10n.text("No settings match your search.")).foregroundStyle(.secondary) }
                if matches(["Appearance", "Theme", "System", "Light", "Dark", "Default folder layout"]) {
                Section(L10n.text("Appearance")) {
                    Picker(L10n.text("Theme"), selection: $settings.appearance) {
                        Text(L10n.text("System")).tag("System"); Text(L10n.text("Light")).tag("Light"); Text(L10n.text("Dark")).tag("Dark")
                    }
                    Picker(L10n.text("Default folder layout"), selection: $settings.defaultLayout) {
                        ForEach(LayoutMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                    }
                }
                }
                if matches(["Custom theme", "Background preset", "Accent color (hex)", "Background color (blank = system)", "Compact file rows", "Background image opacity", "Remove background image", "Import theme…", "Export theme…", "Reset"]) {
                Section(L10n.text("Custom theme")) {
                    Picker(L10n.text("Background preset"), selection: $settings.backgroundHex) {
                        ForEach(BackgroundPresets.values, id: \.name) { preset in Text(L10n.text(preset.name)).tag(preset.hex) }
                        if !BackgroundPresets.values.contains(where: { $0.hex == settings.backgroundHex }) { Text(L10n.text("Custom")).tag(settings.backgroundHex) }
                    }
                    TextField(L10n.text("Accent color (hex)"), text: $settings.accentHex)
                    TextField(L10n.text("Background color (blank = system)"), text: $settings.backgroundHex)
                    Toggle(L10n.text("Compact file rows"), isOn: $settings.compactRows)
                    Text(settings.backgroundImagePath).font(.caption).lineLimit(1)
                    Slider(value: $settings.backgroundImageOpacity, in: 0...1) { Text(L10n.text("Background image opacity")) }
                    Button(L10n.text("Remove background image")) { settings.backgroundImagePath = "" }
                    HStack {
                        Button(L10n.text("Import theme…")) { importTheme() }
                        Button(L10n.text("Export theme…")) { exportTheme() }
                        Button(L10n.text("Reset")) { settings.accentHex = "0A6EE0"; settings.backgroundHex = ""; settings.compactRows = false }
                    }
                }
                }
                if matches(["Libraries", "Remove", "Create library…"]) {
                Section(L10n.text("Libraries")) {
                    ForEach(settings.libraries) { library in
                        HStack {
                            Text(library.name); Spacer(); Text(L10n.text("\(library.folders.count) folders")).foregroundStyle(.secondary)
                            Button(L10n.text("Remove")) { settings.libraries.removeAll { $0.id == library.id } }
                        }
                    }
                    Button(L10n.text("Create library…")) { createLibrary() }
                }
                }
                if matches(["Language", "App language (restart to apply)", "System", "Restart MacFiles"]) {
                Section(L10n.text("Language")) {
                    Picker(L10n.text("App language (restart to apply)"), selection: $settings.language) {
                        Text(L10n.text("System")).tag("System")
                        ForEach(L10n.languages, id: \.self) { code in
                            Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                        }
                    }
                    Button(L10n.text("Restart MacFiles")) { restart() }
                }
                }
                if matches(["Browsing", "Show hidden files", "Show dotfiles", "List folders before files", "Restore tabs at launch"]) {
                Section(L10n.text("Browsing")) {
                    Toggle(L10n.text("Show hidden files"), isOn: $settings.showHidden)
                    Toggle(L10n.text("Show dotfiles"), isOn: $settings.showDotfiles)
                    Toggle(L10n.text("List folders before files"), isOn: $settings.foldersFirst)
                }
                }
                if matches(["macOS integration", "Use MacFiles for folder URLs…", "Restore previous folder viewer", "Finder's desktop and other apps' Open/Save dialogs remain managed by macOS."]) {
                Section(L10n.text("macOS integration")) {
                    Button(L10n.text("Use MacFiles for folder URLs…")) { FolderHandler.useMacFiles() }
                    Button(L10n.text("Restore previous folder viewer")) { FolderHandler.restore() }
                    Text(L10n.text("Finder's desktop and other apps' Open/Save dialogs remain managed by macOS.")).font(.caption).foregroundStyle(.secondary)
                }
                }
                if matches(["File operations", "When names conflict, choose Keep both, Replace, or Skip. Replaced versions and deleted items go to the macOS Trash. Undo and redo are retained across launches and shared by open windows."]) {
                Section(L10n.text("File operations")) {
                    Text(L10n.text("When names conflict, choose Keep both, Replace, or Skip. Replaced versions and deleted items go to the macOS Trash. Undo and redo are retained across launches and shared by open windows."))
                        .font(ExplorerFont.font(size: 12)).foregroundStyle(.secondary)
                }
                }
                if matches(["About MacFiles", "Based on the Files Community explorer’s shell, MVVM, command, and storage architecture. Built with Swift, AppKit, and SwiftUI.", "Reset pinned folders"]) {
                Section(L10n.text("About MacFiles")) {
                    Text(L10n.text("Based on the Files Community explorer’s shell, MVVM, command, and storage architecture. Built with Swift, AppKit, and SwiftUI."))
                        .font(ExplorerFont.font(size: 12)).foregroundStyle(.secondary)
                    Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") + " · " + ProcessInfo.processInfo.operatingSystemVersionString).font(.caption).textSelection(.enabled)
                    HStack {
                        Button(L10n.text("Copy app version")) { copyAbout(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") }
                        Button(L10n.text("Copy macOS version")) { copyAbout(ProcessInfo.processInfo.operatingSystemVersionString) }
                    }
                    Link(L10n.text("Source code"), destination: URL(string: "https://github.com/files-community/Files")!)
                    Link(L10n.text("Upstream Files issues"), destination: URL(string: "https://github.com/files-community/Files/issues")!)
                    Button(L10n.text("Reset pinned folders")) { settings.favorites = SettingsService.standardFavorites }
                }
                }
                AdditionalSettings(search: search, category: category)
                if search.isEmpty && category == "Actions" {
                    Section(L10n.text("Actions")) {
                        Button(L10n.text("Keyboard shortcuts")) { model.present(.shortcuts) }
                        Button(L10n.text("Customize toolbar…")) { model.present(.toolbar) }
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.trailing, 8).padding(.bottom, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.locale, NativeLocalization.locale)
            .environment(\.layoutDirection, NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight)
    }
    private func importTheme() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let theme = try JSONDecoder().decode(ExplorerTheme.self, from: Data(contentsOf: url))
            guard Palette.color(theme.accent) != nil, theme.background.isEmpty || Palette.color(theme.background) != nil,
                  ["System", "Light", "Dark"].contains(theme.appearance) else { throw NSError(domain: "MacFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid theme colors or appearance."]) }
            settings.applyTheme(theme)
        } catch { NSAlert(error: error).runModal() }
    }
    private func exportTheme() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MacFiles-theme.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(settings.currentTheme).write(to: url, options: .atomic) }
        catch { NSAlert(error: error).runModal() }
    }
    private func restart() {
        guard OperationActivity.shared.count == 0 else {
            let alert = NSAlert(); alert.messageText = L10n.text("A file operation is still running"); alert.informativeText = L10n.text("Let the current operation finish before quitting."); alert.runModal(); return
        }
        onClose()
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet); sheet.orderOut(nil) }
        }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            Task { @MainActor in
                if let error { let alert = NSAlert(); alert.messageText = L10n.text("Couldn’t restart MacFiles"); alert.informativeText = error.localizedDescription; alert.runModal() }
                else if application != nil { NSApp.terminate(nil) }
            }
        }
    }
    private func copyAbout(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func createLibrary() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true; panel.prompt = L10n.text("Add to library")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("Library name")
        let field = NSTextField(string: "My library"); field.frame = NSRect(x: 0, y: 0, width: 300, height: 25)
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("Create")); alert.addButton(withTitle: L10n.text("Cancel")); alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        settings.libraries.append(FolderLibrary(name: field.stringValue, folders: panel.urls))
    }

}
