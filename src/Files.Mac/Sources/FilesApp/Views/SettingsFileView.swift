import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct SettingsDocument: Codable {
    var namedTags: [NamedTag]?
    var preferences: ExplorerPreferences?
    var folderPresentations: [String: FolderPresentation]?
    var recentFolders: [String]?
    var layoutSizes: [String: Int]?
    var schemaVersion = 1
    var appearance: String
    var defaultLayout: LayoutMode
    var accentHex: String
    var backgroundHex: String
    var compactRows: Bool
    var language: String
    var showHidden: Bool
    var showDotfiles: Bool
    var showExtensions: Bool
    var foldersFirst: Bool
    var filesFirst: Bool
    var restoreTabs: Bool
    var sidebarVisible: Bool
    var toolbarVisible: Bool
    var filterVisible: Bool
    var visibleColumns: [String]
    var autoFitColumns: Bool
    var backgroundImagePath: String
    var backgroundImageOpacity: Double
    var idePath: String
    var favorites: [Favorite]
    var libraries: [FolderLibrary]
    var savedSearches: [SavedSearch]
    var shortcuts: ShortcutConfiguration
    var toolbar: ToolbarConfiguration
    var cloudFolders: [CloudProviderFolder]
    @MainActor init(_ settings: SettingsService) {
        namedTags = settings.namedTags
        preferences = settings.preferences
        folderPresentations = settings.presentations
        recentFolders = settings.recentFolders
        layoutSizes = settings.layoutSizes
        appearance = settings.appearance
        defaultLayout = settings.defaultLayout
        accentHex = settings.accentHex
        backgroundHex = settings.backgroundHex
        compactRows = settings.compactRows
        language = settings.language
        showHidden = settings.showHidden
        showDotfiles = settings.showDotfiles
        showExtensions = settings.showExtensions
        foldersFirst = settings.foldersFirst
        filesFirst = settings.filesFirst
        restoreTabs = settings.restoreTabs
        sidebarVisible = settings.sidebarVisible
        toolbarVisible = settings.toolbarVisible
        filterVisible = settings.filterVisible
        visibleColumns = settings.visibleColumns
        autoFitColumns = settings.autoFitColumns
        backgroundImagePath = settings.backgroundImagePath
        backgroundImageOpacity = settings.backgroundImageOpacity
        idePath = settings.idePath
        favorites = settings.favorites
        libraries = settings.libraries
        savedSearches = settings.savedSearches
        shortcuts = settings.shortcuts
        toolbar = settings.toolbar
        cloudFolders = settings.cloudFolders
    }
    func validate() throws {
        _ = try shortcuts.validated()
        _ = try toolbar.validated()
        guard NamedTag.valid(namedTags ?? []), preferences?.isValid != false,
              (layoutSizes ?? [:]).allSatisfy({ key, value in LayoutSizing.families.contains { $0.rawValue == key } && (0..<LayoutSizing.count(LayoutMode(rawValue: key) ?? .details)).contains(value) }),
              schemaVersion == 1, ["System", "Light", "Dark"].contains(appearance),
              Palette.color(accentHex) != nil, backgroundHex.isEmpty || Palette.color(backgroundHex) != nil,
              backgroundImageOpacity.isFinite, (0...1).contains(backgroundImageOpacity),
              !(filesFirst && foldersFirst),
              Set(visibleColumns).isSubset(of: ["name", "modified", "created", "kind", "size", "cloud", "tags", "path"]),
              favorites.allSatisfy({ $0.path.hasPrefix("/") }), favorites.count < 10000,
              language == "System" || Bundle.module.localizations.contains(language)
        else { throw CommandFailure("Invalid settings document.") }
    }
    @MainActor func apply(_ settings: SettingsService) throws {
        try validate()
        if let namedTags { settings.namedTags = namedTags }
        if let preferences { settings.preferences = preferences }
        if let folderPresentations { settings.presentations = folderPresentations }
        if let recentFolders { settings.recentFolders = recentFolders }
        settings.layoutSizes = layoutSizes ?? [:]
        settings.appearance = appearance
        settings.defaultLayout = defaultLayout
        settings.accentHex = accentHex
        settings.backgroundHex = backgroundHex
        settings.compactRows = compactRows
        settings.language = language
        settings.showHidden = showHidden
        settings.showDotfiles = showDotfiles
        settings.showExtensions = showExtensions
        settings.foldersFirst = foldersFirst
        settings.filesFirst = filesFirst
        settings.restoreTabs = restoreTabs
        settings.sidebarVisible = sidebarVisible
        settings.toolbarVisible = toolbarVisible
        settings.filterVisible = filterVisible
        settings.visibleColumns = visibleColumns
        settings.autoFitColumns = autoFitColumns
        settings.backgroundImagePath = backgroundImagePath
        settings.backgroundImageOpacity = backgroundImageOpacity
        settings.idePath = idePath
        settings.favorites = favorites
        settings.libraries = libraries
        settings.savedSearches = savedSearches
        settings.shortcuts = try shortcuts.validated()
        settings.toolbar = try toolbar.validated()
        settings.cloudFolders = cloudFolders
    }
}
struct SettingsFileView: View {
    @State private var text = ""
    @State private var message = ""
    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacFiles/settings.json") }
    var body: some View {
        VStack(spacing: 12) {
            Text(url.path).font(.caption).textSelection(.enabled)
            Text(L10n.text("Edit or import the settings document, then Apply to validate and save. Language changes require a restart.")).font(.caption)
            TextEditor(text: $text).font(.system(.caption, design: .monospaced))
            HStack {
                Button(L10n.text("Import…")) { importFile() }
                Button(L10n.text("Export…")) { exportFile() }
                Button(L10n.text("Reload")) { loadCurrent() }
                Spacer(); Button(L10n.text("Apply")) { apply() }.buttonStyle(.borderedProminent)
            }
            Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary)
        }.padding(20).onAppear { loadCurrent() }
    }
    private func loadCurrent() {
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; text = String(decoding: try encoder.encode(SettingsDocument(SettingsService.shared)), as: UTF8.self) }
        catch { message = error.localizedDescription }
    }
    private func apply() {
        do {
            let data = Data(text.utf8); let document = try JSONDecoder().decode(SettingsDocument.self, from: data)
            try document.validate()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try document.apply(SettingsService.shared); message = "Settings saved."
        } catch { message = error.localizedDescription }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { text = try String(contentsOf: url, encoding: .utf8) } catch { message = error.localizedDescription }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MacFiles-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription }
    }
}
