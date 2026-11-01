import AppKit
import FilesShared
import FilesStorage
import UniformTypeIdentifiers

extension MainPageViewModel {
    func createAliasFromDialog() {
        guard !busy, let folder = activePane.operationDirectory else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.prompt = L10n.text("CreateShortcut")
        guard panel.runModal() == .OK, let source = panel.url,
              let name = askName("Create alias", value: source.lastPathComponent + " alias", action: "Create") else { return }
        run("Creating alias") { try await self.storage.createAlias(source, in: folder, name: name) }
    }
    func pasteAliases() {
        guard !busy, let folder = activePane.operationDirectory,
              let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return }
        guard !urls.contains(where: ClipboardStaging.contains) else { alert("Create alias", "Paste the files into a permanent folder before creating aliases to them."); return }
        run("Creating alias") {
            var report = OperationReport()
            for url in urls {
                if Task.isCancelled { break }
                do {
                    let result = try await self.storage.createUniqueAlias(url, in: folder)
                    report.completed += result.completed; report.undo += result.undo
                } catch { report.errors.append(error.localizedDescription) }
            }
            return report
        }
    }
    func deletePermanently() {
        guard !busy, !activePane.isVirtual else { return }
        let urls = activePane.selectedItems.map(\.url); guard !urls.isEmpty else { return }
        let prompt = NSAlert(); prompt.messageText = L10n.text("Delete permanently")
        prompt.informativeText = L10n.selected(urls.count) + "\n" + L10n.text("This cannot be undone.")
        prompt.addButton(withTitle: L10n.text("Cancel")); prompt.addButton(withTitle: L10n.text("Delete permanently"))
        guard prompt.runModal() == .alertSecondButtonReturn else { return }
        run("Deleting permanently", recordingUndo: false) { await self.storage.permanentlyDelete(urls) }
    }
    func openApplication(_ bundleID: String, urls: [URL]) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            alert("Application unavailable", bundleID); return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.alert("Couldn’t open files", error.localizedDescription) } }
        }
    }
    func openInEditor() { guard !activePane.isVirtual, !activePane.selectedItems.isEmpty else { return }; openApplication("com.apple.TextEdit", urls: activePane.selectedItems.map(\.url)) }
    func installSelection(font: Bool) {
        guard !activePane.isVirtual else { return }
        let allowed = font ? ["ttf", "otf", "ttc", "dfont"] : ["cer", "crt", "der", "pem", "p12", "pfx"]
        let urls = activePane.selectedItems.map(\.url).filter { allowed.contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else { return }
        openApplication(font ? "com.apple.FontBook" : "com.apple.keychainaccess", urls: urls)
    }
    func chooseIDE() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SettingsService.shared.idePath = url.path
    }
    func openInIDE(repository: Bool = false) {
        if SettingsService.shared.idePath.isEmpty { chooseIDE() }
        guard !SettingsService.shared.idePath.isEmpty, !activePane.isVirtual else { return }
        let app = URL(fileURLWithPath: SettingsService.shared.idePath)
        let selected = activePane.selectedItems.map(\.url)
        let folder = activePane.operationDirectory
        Task {
            do {
                let urls: [URL]
                if repository, let folder { urls = [try await GitService().inspect(folder).root] }
                else { urls = selected.isEmpty ? folder.map { [$0] } ?? [] : selected }
                guard !urls.isEmpty else { return }
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { Task { @MainActor in self.alert("Couldn’t open files", error.localizedDescription) } }
                }
            } catch { alert("Couldn’t open files", error.localizedDescription) }
        }
    }
    func openDiskUtility() { openApplication("com.apple.DiskUtility", urls: []) }
    func openStorageSettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) } }
    func openWallpaperSettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") { NSWorkspace.shared.open(url) } }
    func openPortNotes() {
        if let url = Bundle.main.url(forResource: "PORTING", withExtension: "md") { openApplication("com.apple.TextEdit", urls: [url]) }
    }
    func openHelp() { NSWorkspace.shared.open(URL(string: "https://files.community/docs")!) }
    func pinSelection(remove: Bool) {
        guard !activePane.isVirtual else { return }
        let settings = SettingsService.shared
        guard activePane.selectedItems.allSatisfy(\.isBrowsable) else { return }
        let urls = activePane.selection.isEmpty ? activePane.operationDirectory.map { [$0] } ?? [] : activePane.selectedItems.map(\.url)
        if remove { settings.favorites.removeAll { urls.contains($0.url) } }
        else { urls.forEach { settings.pin($0) } }
    }
    func playSelection() {
        let items = activePane.selectedItems
        guard !items.isEmpty, items.allSatisfy({ item in
            guard !item.isDirectory, let type = UTType(filenameExtension: item.url.pathExtension) else { return false }
            return type.conforms(to: .audio) || type.conforms(to: .movie)
        }) else { return }
        openSelection()
    }
    func removeSelectionTags() {
        let urls = activePane.selectedItems.map(\.url).filter(\.isFileURL)
        guard !busy, !urls.isEmpty else { return }
        run("Removing tags", recordingUndo: false) {
            var report = OperationReport()
            for url in urls {
                do { try MetadataService.setTags([], for: [url]); report.completed.append(url) }
                catch { report.errors.append(error.localizedDescription) }
            }
            return report
        }
    }
}

extension MainPageViewModel {
    func quickCompress(_ format: ArchiveFormat) {
        guard !busy, !activePane.isVirtual, let destination = activePane.operationDirectory else { return }
        let urls = activePane.selectedItems.map(\.url)
        run("Compressing") { try await ArchiveWorkflows().compress(urls, in: destination, format: format) }
    }
    func extractSelection(_ placement: ExtractionPlacement, chooseDestination: Bool = false) {
        guard !busy, !activePane.isVirtual, var destination = activePane.operationDirectory else { return }
        let sources = activePane.selectedItems.map(\.url)
        guard !sources.isEmpty, sources.allSatisfy({ ArchiveService.supports($0) }) else { return }
        if chooseDestination {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }; destination = url
        }
        let prompt = NSAlert(); prompt.messageText = L10n.text("Archive password (leave blank if unencrypted)")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); prompt.accessoryView = field
        prompt.addButton(withTitle: L10n.text("Extract")); prompt.addButton(withTitle: L10n.text("Cancel"))
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        let password = field.stringValue; let target = destination
        run("Extracting") {
            var result = OperationReport()
            for source in sources {
                if Task.isCancelled { break }
                do {
                    let report = try await ArchiveWorkflows().extract(source, in: target, placement: placement, password: password)
                    result.completed += report.completed; result.undo += report.undo; result.errors += report.errors
                } catch { result.errors.append(error.localizedDescription) }
            }
            return result
        }
    }
}
