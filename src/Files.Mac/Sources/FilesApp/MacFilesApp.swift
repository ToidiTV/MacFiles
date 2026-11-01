import SwiftUI
import AppKit
import FilesShared

@main struct MacFilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var settings = SettingsService.shared
    var body: some Scene {
        WindowGroup("MacFiles", id: "main") { ExplorerWindow(delegate: delegate) }
        .defaultSize(width: 1100, height: 760).windowStyle(.hiddenTitleBar)
        .commands { FocusedExplorerCommands() }
        WindowGroup("MacFiles", id: "folder", for: URL.self) { $location in
            ExplorerWindow(delegate: delegate, initialLocation: location)
        }.defaultSize(width: 1100, height: 760).windowStyle(.hiddenTitleBar)
        MenuBarExtra("MacFiles", systemImage: "folder", isInserted: Binding(get: { settings.preferences.showMenuBarIcon || settings.preferences.closeToBackground }, set: { if settings.preferences.showMenuBarIcon != $0 { settings.preferences.showMenuBarIcon = $0 } })) { BackgroundAppMenu() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var openFolderWindow: ((URL) -> Void)?
    private var models: [ObjectIdentifier: WeakWindowModel] = [:]
    private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    var model: MainPageViewModel? {
        if let window = NSApp.keyWindow, let model = models[ObjectIdentifier(window)]?.model { return model }
        return models.values.compactMap(\.model).first
    }
    func register(_ window: NSWindow, model: MainPageViewModel) {
        let key = ObjectIdentifier(window)
        models[key] = WeakWindowModel(model)
        if window.isKeyWindow || ActiveExplorer.shared.model == nil { ActiveExplorer.shared.model = model }
        if !pendingURLs.isEmpty { let urls = pendingURLs; pendingURLs = []; application(NSApp, open: urls) }
        guard observers[key] == nil else { return }
        let focus = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak model] _ in
            Task { @MainActor in ActiveExplorer.shared.model = model }
        }
        let close = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if let observers = self?.observers.removeValue(forKey: key) { observers.forEach { NotificationCenter.default.removeObserver($0) } }
                self?.models.removeValue(forKey: key)
                ActiveExplorer.shared.model = self?.model
            }
        }
        observers[key] = [focus, close]
    }
    private var keyboardMonitor: Any?
    private var pendingURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        WallpaperSlideshow.shared.resumeIfEnabled()
        NSApp.setActivationPolicy(.regular); NSApp.servicesProvider = self; NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !SettingsService.shared.preferences.closeToBackground }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard OperationActivity.shared.count > 0 else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = L10n.text("A file operation is still running")
        alert.informativeText = L10n.text("Let the current operation finish before quitting.")
        alert.addButton(withTitle: L10n.text("Keep MacFiles open")); alert.runModal()
        return .terminateCancel
    }
    @objc func openInMacFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        application(NSApp, open: urls); NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard model != nil else { pendingURLs += urls; return }
        for url in urls {
            var directory: ObjCBool = false
            let target = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue ? url : url.deletingLastPathComponent()
            if SettingsService.shared.preferences.openExternalInNewWindow, let openFolderWindow { openFolderWindow(target) }
            else { model?.newTab(target, activate: true) }
        }
    }
    func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            if event.type == .scrollWheel { return !SettingsService.shared.preferences.smoothScrolling && !event.momentumPhase.isEmpty ? nil : event }
            guard let model = self?.model, NSApp.modalWindow == nil, !model.showSettings, model.tool == nil,
                  !(NSApp.keyWindow?.firstResponder is NSTextView), NSApp.keyWindow?.title == "MacFiles" else { return event }
            if let chord = KeyChord(event: event), let id = SettingsService.shared.shortcuts.action(for: chord) { model.executeShortcut(id); return nil }
            return event
        }
    }
}

struct ExplorerCommands: Commands {
    @ObservedObject private var settings = SettingsService.shared
    @ObservedObject var model: MainPageViewModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        ParityCommandsMenu(model: model)
        CommandGroup(replacing: .newItem) {
            Button(L10n.text("New window")) { openWindow(id: "main") }.keyboardShortcut("n")
            Button(L10n.text("New tab")) { model.newTab() }.fileShortcut("newTab")
            Button(L10n.text("Open folder…")) { model.chooseFolder() }.fileShortcut("chooseFolder")
            Button(L10n.text("Close tab")) { model.closeTab(model.selectedTab) }.fileShortcut("closeTab")
            Button(L10n.text("Reopen closed tab")) { model.reopenTab() }.fileShortcut("reopenTab")
            Divider()
            Button(L10n.text("New folder…")) { model.create(directory: true) }.disabled((model.activePane.location == nil && !model.activePane.isVirtual) || model.busy).fileShortcut("new")
            Button(L10n.text("New text file…")) { model.create(directory: false) }.disabled((model.activePane.location == nil && !model.activePane.isVirtual) || model.busy).fileShortcut("newFile")
            Button(L10n.text("New from template…")) { model.createFromTemplate() }.disabled(model.activePane.location == nil || model.busy).fileShortcut("template")
        }
        CommandGroup(replacing: .undoRedo) {
            Button(L10n.text("Undo file operation")) { model.undo() }.disabled(model.busy).fileShortcut("undo")
            Button(L10n.text("Redo file operation")) { model.redo() }.disabled(!model.redoAvailable || model.busy).fileShortcut("redo")
        }
        CommandGroup(replacing: .pasteboard) {
            Button(L10n.text("Cut")) { model.copy(cut: true) }.fileShortcut("cut")
            Button(L10n.text("Copy")) { model.copy() }.fileShortcut("copy")
            Button(L10n.text("Paste")) { model.paste() }.fileShortcut("paste")
            Button(L10n.text("Move here")) { model.paste(forceMove: true) }.fileShortcut("moveHere")
            Button(L10n.text("Select all")) { model.selectAll() }.fileShortcut("selectAll")
            Button(L10n.text("Invert selection")) { model.invertSelection() }.fileShortcut("invert")
            Button(L10n.text("Clear selection")) { model.clearSelection() }.fileShortcut("clear")
            Divider()
            Button(L10n.text("CopyItemPathWithQuotes")) { model.copyPath(quoted: true) }
            Button(L10n.text("CopyPathWithQuotes")) { model.copyPath(quoted: true, current: true) }
            Button(L10n.text("CopyPathDescription")) { model.copyPath(current: true) }
            Button(L10n.text("Copy path")) { model.copyPath() }.fileShortcut("copyPath")
            Button(L10n.text("CreateFolderWithSelection")) { model.createFolderWithSelection() }.disabled(model.busy || model.activePane.isVirtual || model.activePane.selection.isEmpty)
            Button(L10n.text("Duplicate")) { model.duplicate() }.disabled(model.busy).fileShortcut("duplicate")
            Button(L10n.text("Rename…")) { model.rename() }.disabled(model.activePane.selection.isEmpty || model.busy).fileShortcut("rename")
            Button(L10n.text("Move to Trash…")) { model.trash() }.disabled(model.activePane.selection.isEmpty || model.busy).fileShortcut("trash")
        }
        CommandGroup(replacing: .appSettings) {
            Button(L10n.text("Settings…")) { model.showSettings = true }.fileShortcut("settings")
        }
        CommandMenu(L10n.text("Tools")) {
            Button(L10n.text("Operations…")) { model.present(.operations) }.fileShortcut("operations")
            Button(L10n.text("Keyboard shortcuts…")) { model.present(.shortcuts) }.fileShortcut("shortcuts")
            Button(L10n.text("Customize toolbar…")) { model.present(.toolbar) }.fileShortcut("toolbar")
            Button(L10n.text("Properties…")) { model.present(.properties) }.fileShortcut("properties")
            Button(L10n.text("Manage cloud accounts…")) { model.present(.providers) }
            Button(L10n.text("Cloud status…")) { model.present(.cloud) }.fileShortcut("cloud")
            Button(L10n.text("Command palette…")) { model.present(.palette) }.fileShortcut("palette")
            Button(L10n.text("Advanced search…")) { model.present(.search) }.fileShortcut("search")
            Button(L10n.text("File shelf…")) { model.present(.shelf) }.fileShortcut("shelf")
            Button(L10n.text("Add selection to shelf")) { ShelfStore.shared.add(model.activePane.selectedItems.map(\.url)) }.disabled(model.activePane.selection.isEmpty).fileShortcut("shelfAdd")
            Divider()
            Button(L10n.text("Flatten folder…")) { model.flatten() }.disabled(model.activePane.selectedItems.count != 1 || model.activePane.selectedItems.first?.isBrowsable != true).fileShortcut("flatten")
            Button(L10n.text("Compress…")) { model.present(.compress) }.disabled(model.activePane.selection.isEmpty).fileShortcut("compress")
            Button(L10n.text("Browse archive…")) { model.present(.archive) }.disabled(model.activePane.selection.count != 1).fileShortcut("archive")
            Button(L10n.text("Bulk rename…")) { model.present(.rename) }.disabled(model.activePane.selection.isEmpty).fileShortcut("bulkRename")
            Button(L10n.text("Edit tags…")) { model.present(.tags) }.disabled(model.activePane.selection.isEmpty).fileShortcut("tags")
            Button(L10n.text("Calculate hashes…")) { model.present(.hashes) }.disabled(model.activePane.selection.count != 1).fileShortcut("hashes")
            Button(L10n.text("Extended attributes…")) { model.present(.attributes) }.disabled(model.activePane.selection.count != 1).fileShortcut("attributes")
            Button(L10n.text("Permissions…")) { model.present(.permissions) }.disabled(model.activePane.selection.isEmpty).fileShortcut("permissions")
            Divider()
            Button(L10n.text("Git repository…")) { model.present(.git) }.fileShortcut("git")
            Button(L10n.text("Connect to server…")) { model.present(.network) }.fileShortcut("network")
        }
        CommandMenu(L10n.text("Navigate")) {
            Button(L10n.text("Back")) { model.activePane.back() }.disabled(!model.activePane.canGoBack).fileShortcut("back")
            Button(L10n.text("Forward")) { model.activePane.forward() }.disabled(!model.activePane.canGoForward).fileShortcut("forward")
            Button(L10n.text("Up one level")) { model.activePane.up() }.fileShortcut("up")
            Button(L10n.text("Home")) { model.activePane.navigate(nil) }.fileShortcut("home")
            Divider()
            Button(L10n.text("Go to path…")) { model.focusAddress += 1 }.fileShortcut("address")
            Button(L10n.text("Search folder")) { model.focusSearch += 1 }.fileShortcut("filter")
            Button(L10n.text("Refresh")) { model.activePane.refresh() }.fileShortcut("refresh")
            Button(L10n.text("Open in Terminal")) { model.terminal() }.fileShortcut("terminal")
        }
        CommandGroup(after: .toolbar) {
            Button(L10n.text("Details layout")) { model.activePane.layout = .details }.fileShortcut("detailsLayout")
            Button(L10n.text("Icons layout")) { model.activePane.layout = .icons }.fileShortcut("iconsLayout")
            Button(L10n.text("Columns layout")) { model.activePane.layout = .columns }.fileShortcut("columnsLayout")
            Button(L10n.text("Gallery layout")) { model.activePane.layout = .gallery }.fileShortcut("galleryLayout")
            Button(L10n.text("Toggle dual pane")) { model.toggleSplit() }.fileShortcut("split")
            Button(L10n.text("Arrange panes top and bottom")) { model.arrangePanes(vertical: true) }.fileShortcut("verticalSplit")
            Button(L10n.text("Arrange panes side by side")) { model.arrangePanes(vertical: false) }.fileShortcut("horizontalSplit")
            Button(L10n.text("Focus other pane")) { model.focusOtherPane() }.fileShortcut("focusPane")
            Button(L10n.text("Keep window on top")) { if let window = NSApp.keyWindow { window.level = window.level == .floating ? .normal : .floating } }.fileShortcut("onTop")
            Button(L10n.text("Toggle full screen")) { NSApp.keyWindow?.toggleFullScreen(nil) }.fileShortcut("fullScreen")
            Toggle(L10n.text("ToggleSidebar"), isOn: $settings.sidebarVisible)
            Toggle(L10n.text("ToggleToolbar"), isOn: $settings.toolbarVisible)
            Toggle(L10n.text("ShowFileExtensions"), isOn: $settings.showExtensions)
            Button(L10n.text("Toggle details pane")) { model.showInfo.toggle() }.fileShortcut("info")
            Button(L10n.text("Show hidden files")) { SettingsService.shared.showHidden.toggle() }.fileShortcut("hidden")
            Button(L10n.text("Quick Look")) { model.quickLook() }.fileShortcut("quickLook")
        }
    }
}
