import AppKit
import CoreServices
import UniformTypeIdentifiers
import FilesStorage

extension MainPageViewModel {
    func copyReferences(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }
    private func prepareVirtualSelection(_ completion: @escaping ([URL]) -> Void) {
        let references = activePane.selectedItems.compactMap { activePane.reference($0) }
        guard !references.isEmpty else { return }
        run("Copying files") {
            var urls: [URL] = []
            for reference in references { urls.append(try await reference.materialize(in: ClipboardStaging.create())) }
            try Task.checkCancellation()
            completion(urls)
            return OperationReport()
        }
    }
    func openWith(urls supplied: [URL]? = nil) {
        if supplied == nil && activePane.isVirtual { prepareVirtualSelection { self.openWith(urls: $0) }; return }
        let urls = supplied ?? activePane.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let panel = NSOpenPanel(); panel.title = L10n.text("Open with application"); panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false; panel.prompt = L10n.text("Open")
        guard panel.runModal() == .OK, let application = panel.url else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.alert("Couldn’t open files", error.localizedDescription) } }
        }
    }
    func share(urls supplied: [URL]? = nil) {
        if supplied == nil && activePane.isVirtual { prepareVirtualSelection { self.share(urls: $0) }; return }
        let urls = supplied ?? activePane.selectedItems.map(\.url)
        guard !urls.isEmpty, let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 90, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
    func createFolderWithSelection() {
        guard !busy, !activePane.isVirtual, let destination = activePane.operationDirectory else { return }
        let sources = activePane.selectedItems.map(\.url)
        guard !sources.isEmpty, let name = askName(L10n.text("CreateFolderWithSelection"), value: "", action: "Create") else { return }
        run("Moving files") {
            var report = try await self.storage.create(in: destination, name: name, directory: true)
            guard let folder = report.completed.first else { return report }
            let moved = await self.storage.perform(.move, sources: sources, destination: folder, conflict: .keepBoth)
            report.completed += moved.completed; report.errors += moved.errors
            report.undo = [.compound(report.undo + moved.undo)]
            return report
        }
    }
    func makeAlias() {
        guard !busy, let item = activePane.selectedItems.first, let folder = activePane.operationDirectory,
              let name = askName("Create alias", value: item.name + " alias", action: "Create") else { return }
        run("Creating alias") { try await self.storage.createAlias(item.url, in: folder, name: name) }
    }
    func eject(_ volume: URL) {
        Task {
            do { try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: volume) }.value }
            catch { alert("Couldn’t eject volume", error.localizedDescription) }
            refreshVolumes()
        }
    }
}

@MainActor enum FolderHandler {
    static func useMacFiles() {
        let prompt = NSAlert(); prompt.messageText = L10n.text("Use MacFiles for folder URLs?")
        prompt.informativeText = L10n.text("This changes the registered folder viewer. Finder still manages the desktop and macOS file dialogs. You can restore the previous viewer here.")
        prompt.addButton(withTitle: L10n.text("Use MacFiles")); prompt.addButton(withTitle: L10n.text("Cancel"))
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        if UserDefaults.standard.string(forKey: "previousFolderHandler") == nil,
           let previous = LSCopyDefaultRoleHandlerForContentType("public.folder" as CFString, .viewer)?.takeRetainedValue() {
            UserDefaults.standard.set(previous as String, forKey: "previousFolderHandler")
        }
        let status = LSSetDefaultRoleHandlerForContentType("public.folder" as CFString, .viewer, "com.toidi.macfiles" as CFString)
        if status != noErr { showError(status) }
    }
    static func restore() {
        let previous = UserDefaults.standard.string(forKey: "previousFolderHandler") ?? "com.apple.finder"
        let status = LSSetDefaultRoleHandlerForContentType("public.folder" as CFString, .viewer, previous as CFString)
        if status == noErr { UserDefaults.standard.removeObject(forKey: "previousFolderHandler") } else { showError(status) }
    }
    private static func showError(_ status: OSStatus) {
        let alert = NSAlert(); alert.messageText = L10n.text("Couldn’t change the folder viewer"); alert.informativeText = L10n.text("macOS returned \(status)."); alert.runModal()
    }
}
