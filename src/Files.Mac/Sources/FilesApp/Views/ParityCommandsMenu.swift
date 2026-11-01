import SwiftUI
import FilesShared
import FilesStorage
import UniformTypeIdentifiers

struct ParityCommandsMenu: Commands {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject private var settings = SettingsService.shared
    private var local: Bool { !model.activePane.isVirtual && model.activePane.operationDirectory != nil }
    private var selected: Bool { !model.activePane.selection.isEmpty }
    private var mediaSelected: Bool { selected && model.activePane.selectedItems.allSatisfy { item in
        guard !item.isDirectory, let type = UTType(filenameExtension: item.url.pathExtension) else { return false }; return type.conforms(to: .audio) || type.conforms(to: .movie)
    } }
    private func selectedExtensions(_ extensions: [String]) -> Bool { selected && model.activePane.selectedItems.allSatisfy { !$0.isDirectory && extensions.contains($0.url.pathExtension.lowercased()) } }
    private var archiveSelected: Bool { selected && model.activePane.selectedItems.allSatisfy { !$0.isDirectory && ArchiveService.supports($0.url) } }
    var body: some Commands {
        CommandMenu(L10n.text("File actions")) {
            Menu(L10n.text("Archive")) {
                Button(L10n.text("CompressIntoZip")) { model.quickCompress(.zip) }
                Button(L10n.text("CompressIntoSevenZip")) { model.quickCompress(.sevenZip) }
                Button(L10n.text("Compress…")) { model.present(.compress) }
                Divider()
                Button(L10n.text("ExtractHere")) { model.extractSelection(.here) }.disabled(!archiveSelected)
                Button(L10n.text("ExtractHereSmart")) { model.extractSelection(.smart) }.disabled(!archiveSelected)
                Button(L10n.text("Extract to child folder")) { model.extractSelection(.childFolder) }.disabled(!archiveSelected)
                Button(L10n.text("Extract to…")) { model.extractSelection(.here, chooseDestination: true) }.disabled(!archiveSelected)
            }.disabled(!local || !selected || model.busy)
            Menu(L10n.text("Open")) {
                Button(L10n.text("Edit in TextEdit")) { model.openInEditor() }.disabled(!selected)
                Button(L10n.text("Open in IDE")) { model.openInIDE() }
                Button(L10n.text("Open repository in IDE")) { model.openInIDE(repository: true) }
                Button(L10n.text("Choose IDE…")) { model.chooseIDE() }
                Divider()
                Button(L10n.text("PlayAll")) { model.playSelection() }.disabled(!mediaSelected)
                Button(L10n.text("InstallFont")) { model.installSelection(font: true) }.disabled(!selectedExtensions(["ttf", "otf", "ttc", "dfont"]))
                Button(L10n.text("InstallCertificate")) { model.installSelection(font: false) }.disabled(!selectedExtensions(["cer", "crt", "der", "pem", "p12", "pfx"]))
                Button(L10n.text("Finder Get Info…")) { model.classicProperties() }.disabled(!selected)
            }.disabled(!local)
            Menu(L10n.text("CreateShortcut")) {
                Button(L10n.text("Make alias…")) { model.makeAlias() }.disabled(!selected)
                Button(L10n.text("CreateShortcutFromDialogDescription")) { model.createAliasFromDialog() }
                Button(L10n.text("PasteShortcut")) { model.pasteAliases() }.disabled(!model.canPaste)
            }.disabled(!local || model.busy)
            Button(L10n.text("Delete selected permanently…")) { model.deletePermanently() }.disabled(!local || !selected || model.busy)
            Button(L10n.text("ToggleSelect")) { model.toggleFocusedSelection() }.fileShortcut("toggleSelect")
            Menu(L10n.text("Tags")) {
                Button(L10n.text("Browse tagged items…")) { model.present(.tagBrowser) }
                Button(L10n.text("RemoveTags")) { model.removeSelectionTags() }.disabled(!local || !selected || model.busy)
            }
            Menu(L10n.text("Sidebar")) {
                Button(L10n.text("Pin to sidebar")) { model.pinSelection(remove: false) }
                Button(L10n.text("Unpin")) { model.pinSelection(remove: true) }
            }.disabled(!local || (!model.activePane.selection.isEmpty && !model.activePane.selectedItems.allSatisfy(\.isBrowsable)))
            Menu(L10n.text("Layout")) {
                Button(L10n.text("Adaptive")) { model.activePane.layout = .adaptive }
                Button(L10n.text("Increase size")) { model.changeLayoutSize(1) }
                Button(L10n.text("Decrease size")) { model.changeLayoutSize(-1) }
                Button(L10n.text("Next layout")) { model.cycleLayout(1) }
                Button(L10n.text("Previous layout")) { model.cycleLayout(-1) }
                Toggle(L10n.text("Show dotfiles"), isOn: $settings.showDotfiles)
                Toggle(L10n.text("ToggleFilterHeader"), isOn: $settings.filterVisible)
                Button(L10n.text("EnterCompactOverlay")) { model.setCompactOverlay(true) }.disabled(model.compactOverlay)
                Button(L10n.text("ExitCompactOverlay")) { model.setCompactOverlay(false) }.disabled(!model.compactOverlay)
                Button(L10n.text("ToggleCompactOverlay")) { model.setCompactOverlay(!model.compactOverlay) }
            }
            Menu(L10n.text("Background")) {
                Button(L10n.text("SetAsAppBackground")) { model.chooseAppBackground() }
                Button(L10n.text("Wallpaper slideshow…")) { model.present(.slideshow) }
                Button(L10n.text("Lock screen and wallpaper settings…")) { model.openWallpaperSettings() }
            }
            Menu(L10n.text("macOS integration")) {
                Button(L10n.text("Format drive in Disk Utility…")) { model.openDiskUtility() }
                Button(L10n.text("Storage settings…")) { model.openStorageSettings() }
            }
            Divider()
            Button(L10n.text("Edit settings file…")) { model.present(.settingsFile) }
            Button(L10n.text("OpenLogFile")) { model.present(.diagnostics) }
            Button(L10n.text("Show log in folder")) { model.revealLog() }
            Button(L10n.text("Release notes")) { model.openPortNotes() }
            Button(L10n.text("Help")) { model.openHelp() }
        }
    }
}
