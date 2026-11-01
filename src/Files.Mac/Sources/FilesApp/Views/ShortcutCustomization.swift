import SwiftUI
import AppKit
import FilesShared

extension KeyChord {
    init?(event: NSEvent) {
        let special: [UInt16: String] = [36: "return", 76: "return", 49: "space", 51: "delete", 117: "forwarddelete", 53: "escape", 48: "tab", 126: "up", 125: "down", 123: "left", 124: "right", 122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"]
        guard let key = special[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.lowercased(), !key.isEmpty else { return nil }
        let flags = event.modifierFlags
        self.init(key, command: flags.contains(.command), option: flags.contains(.option), control: flags.contains(.control), shift: flags.contains(.shift))
    }
    var shortcut: KeyboardShortcut {
        let keys: [String: KeyEquivalent] = ["return": .return, "space": .space, "delete": .delete, "forwarddelete": .deleteForward, "escape": .escape, "tab": .tab, "up": .upArrow, "down": .downArrow, "left": .leftArrow, "right": .rightArrow]
        var equivalent = keys[key] ?? KeyEquivalent(key.first ?? " ")
        if key.hasPrefix("f"), let number = Int(key.dropFirst()), (1...20).contains(number), let scalar = UnicodeScalar(0xF703 + number) { equivalent = KeyEquivalent(Character(scalar)) }
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }; if option { modifiers.insert(.option) }; if control { modifiers.insert(.control) }; if shift { modifiers.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }
}
struct FileShortcutModifier: ViewModifier {
    let id: String
    @ObservedObject var settings = SettingsService.shared
    func body(content: Content) -> some View { content.keyboardShortcut(settings.shortcuts.chords(for: id).first?.shortcut) }
}
extension View { func fileShortcut(_ id: String) -> some View { modifier(FileShortcutModifier(id: id)) } }

extension MainPageViewModel {
    func executeShortcut(_ id: String) {
        if activePane.isVirtual && ["new", "newFile", "open", "quickLook", "rename", "trash", "selectAll", "invert", "clear", "back", "forward", "up", "refresh", "undo", "redo"].contains(id) { _ = handleVirtual(id); return }
        switch id {
        case "toggleSelect": toggleFocusedSelection()
        case "compressZip": quickCompress(.zip)
        case "compress7z": quickCompress(.sevenZip)
        case "extractHere": extractSelection(.here)
        case "extractSmart": extractSelection(.smart)
        case "extractChild": extractSelection(.childFolder)
        case "extractTo": extractSelection(.here, chooseDestination: true)
        case "textEdit": openInEditor()
        case "openIDE": openInIDE()
        case "repoIDE": openInIDE(repository: true)
        case "chooseIDE": chooseIDE()
        case "playAll": playSelection()
        case "installFont": installSelection(font: true)
        case "installCertificate": installSelection(font: false)
        case "classicProperties": classicProperties()
        case "aliasDialog": createAliasFromDialog()
        case "pasteAliases": pasteAliases()
        case "permanentDelete": deletePermanently()
        case "browseTags": present(.tagBrowser)
        case "removeTags": removeSelectionTags()
        case "pinFolders": pinSelection(remove: false)
        case "unpinFolders": pinSelection(remove: true)
        case "adaptiveLayout": activePane.layout = .adaptive
        case "increaseSize": changeLayoutSize(1)
        case "decreaseSize": changeLayoutSize(-1)
        case "nextLayout": cycleLayout(1)
        case "previousLayout": cycleLayout(-1)
        case "dotfiles": SettingsService.shared.showDotfiles.toggle()
        case "filterHeader": SettingsService.shared.filterVisible.toggle()
        case "enterCompact": setCompactOverlay(true)
        case "exitCompact": setCompactOverlay(false)
        case "compactOverlay": setCompactOverlay(!compactOverlay)
        case "appBackground": chooseAppBackground()
        case "slideshow": present(.slideshow)
        case "wallpaperSettings": openWallpaperSettings()
        case "diskUtility": openDiskUtility()
        case "storageSettings": openStorageSettings()
        case "settingsFile": present(.settingsFile)
        case "diagnostics": present(.diagnostics)
        case "logFolder": revealLog()
        case "releaseNotes": openPortNotes()
        case "help": openHelp()

        case "newTab": newTab(); case "chooseFolder": chooseFolder(); case "closeTab": closeTab(selectedTab); case "reopenTab": reopenTab()
        case "nextTab": nextTab(1); case "previousTab": nextTab(-1); case "newFile": create(directory: false); case "template": createFromTemplate()
        case "moveHere": paste(forceMove: true); case "selectAll": selectAll(); case "invert": invertSelection(); case "clear": activePane.selection = []
        case "copyPath": copyPath(); case "settings": showSettings = true
        case "back": activePane.back(); case "forward": activePane.forward(); case "up": activePane.up(); case "home": activePane.navigate(nil)
        case "address": focusAddress += 1; case "filter": focusSearch += 1
        case "detailsLayout": activePane.layout = .details; case "iconsLayout": activePane.layout = .icons; case "columnsLayout": activePane.layout = .columns; case "galleryLayout": activePane.layout = .gallery
        case "verticalSplit": arrangePanes(vertical: true); case "horizontalSplit": arrangePanes(vertical: false); case "focusPane": focusOtherPane()
        case "onTop": if let window = NSApp.keyWindow { window.level = window.level == .floating ? .normal : .floating }
        case "fullScreen": NSApp.keyWindow?.toggleFullScreen(nil); case "open": openSelection()
        case "toolbar": present(.toolbar); case "shortcuts": present(.shortcuts); case "operations": present(.operations); case "archive": present(.archive); case "flatten": flatten(); case "shelfAdd": ShelfStore.shared.add(activePane.selectedItems.map(\.url))
        default: if let action = ExplorerAction(rawValue: id) { execute(action) }
        }
    }
}

struct ShortcutCustomizationView: View {
    var embedded = false
    @State private var draft = SettingsService.shared.shortcuts
    @State private var selected = "copy"
    @State private var query = ""
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message = ""
    @Environment(\.dismissTool) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(L10n.text("Search commands"), text: $query)
            HSplitView {
                List(ShortcutConfiguration.catalog.filter { query.isEmpty || $0.title.localizedStandardContains(query) }, selection: $selected) { command in
                    HStack { Text(L10n.text(command.title)); Spacer(); Text(draft.chords(for: command.id).map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }.tag(command.id)
                }.frame(minWidth: 320)
                VStack(alignment: .leading, spacing: 15) {
                    Text(L10n.text(ShortcutConfiguration.catalog.first { $0.id == selected }?.title ?? "Command")).font(.headline)
                    ForEach(draft.chords(for: selected), id: \.self) { chord in HStack { Text(chord.label).monospaced(); Spacer(); Button(L10n.text("Remove")) { draft.overrides[selected] = draft.chords(for: selected).filter { $0 != chord } } } }
                    Button(recording ? "Press the shortcut…" : "Record shortcut") { beginRecording() }.disabled(recording)
                    Button(L10n.text("Restore command defaults")) { draft.overrides.removeValue(forKey: selected) }
                    Text(L10n.text("Shortcuts apply in the explorer. Text fields keep native editing behavior. Resolve duplicate assignments before applying.")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(15).frame(minWidth: 220)
            }
            Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary)
            HStack { Button(L10n.text("Reset all")) { draft = ShortcutConfiguration() }; Button(L10n.text("Import…")) { importFile() }; Button(L10n.text("Export…")) { exportFile() }; Spacer(); Button(L10n.text("Apply")) { do { SettingsService.shared.shortcuts = try draft.validated(); if !embedded { dismiss() } } catch { message = error.localizedDescription } } }
        }.padding(20).onDisappear { stopRecording() }.onChange(of: selected) { stopRecording() }
    }
    private func stopRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
    private func beginRecording() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let chord = KeyChord(event: event) else { return event }
            stopRecording()
            if ShortcutConfiguration.reserved.contains(chord) { message = "\(chord.label) is reserved."; return nil }
            if let other = draft.action(for: chord), other != selected { message = "Already assigned to \(ShortcutConfiguration.catalog.first { $0.id == other }?.title ?? other). Remove that assignment first."; return nil }
            var values = draft.chords(for: selected); if !values.contains(chord) { values.append(chord) }; draft.overrides[selected] = values; message = ""; return nil
        }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { do { draft = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(contentsOf: url)).validated(); message = "Imported. Apply to save." } catch { message = error.localizedDescription } }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MacFiles-shortcuts.json"
        if panel.runModal() == .OK, let url = panel.url { do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(draft.validated()).write(to: url, options: .atomic) } catch { message = error.localizedDescription } }
    }
}
