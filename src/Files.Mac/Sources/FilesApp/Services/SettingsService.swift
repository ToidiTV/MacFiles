import AppKit
import Combine
import FilesShared
import FilesStorage

@MainActor final class SettingsService: ObservableObject {
    @Published var namedTags: [NamedTag] { didSet { defaults.set(try? JSONEncoder().encode(namedTags), forKey: "namedTagsV1") } }
    @Published var preferences: ExplorerPreferences { didSet { defaults.set(try? JSONEncoder().encode(preferences), forKey: "explorerPreferencesV1"); defaults.set(preferences.sizeUnits, forKey: "displaySizeUnits"); defaults.set(preferences.dateFormat, forKey: "displayDateFormat") } }
    @Published var layoutSizes: [String: Int] { didSet { defaults.set(layoutSizes, forKey: "layoutSizes") } }
    @Published var showDotfiles: Bool { didSet { defaults.set(showDotfiles, forKey: "showDotfiles") } }
    @Published var filterVisible: Bool { didSet { defaults.set(filterVisible, forKey: "filterVisible") } }
    @Published var backgroundImagePath: String { didSet { defaults.set(backgroundImagePath, forKey: "backgroundImagePath") } }
    @Published var backgroundImageOpacity: Double { didSet { defaults.set(backgroundImageOpacity, forKey: "backgroundImageOpacity") } }
    @Published var idePath: String { didSet { defaults.set(idePath, forKey: "idePath") } }
    @Published var shortcuts: ShortcutConfiguration { didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcutsV1") } }
    @Published var cloudFolders: [CloudProviderFolder] { didSet { defaults.set(try? JSONEncoder().encode(cloudFolders), forKey: "cloudProviderFoldersV1") } }
    static let shared = SettingsService()
    private let defaults = UserDefaults.standard
    @Published var sidebarVisible: Bool { didSet { defaults.set(sidebarVisible, forKey: "sidebarVisible") } }
    @Published var toolbarVisible: Bool { didSet { defaults.set(toolbarVisible, forKey: "toolbarVisible") } }
    @Published var showExtensions: Bool { didSet { defaults.set(showExtensions, forKey: "showExtensions") } }
    @Published var visibleColumns: [String] { didSet { defaults.set(visibleColumns, forKey: "visibleColumns") } }
    @Published var autoFitColumns: Bool { didSet { defaults.set(autoFitColumns, forKey: "autoFitColumns") } }
    @Published var showHidden: Bool { didSet { defaults.set(showHidden, forKey: "showHidden") } }
    @Published var filesFirst: Bool { didSet { if filesFirst && foldersFirst { foldersFirst = false }; defaults.set(filesFirst, forKey: "filesFirst") } }
    @Published var foldersFirst: Bool { didSet { if foldersFirst && filesFirst { filesFirst = false }; defaults.set(foldersFirst, forKey: "foldersFirst") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance"); applyAppearance() } }
    @Published var defaultLayout: LayoutMode { didSet { defaults.set(defaultLayout.rawValue, forKey: "defaultLayout") } }
    @Published var favorites: [Favorite] { didSet { if let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: "favorites") } } }
    @Published var recentFolders: [String] { didSet { defaults.set(recentFolders, forKey: "recentFolders") } }
    @Published var restoreTabs: Bool { didSet { defaults.set(restoreTabs, forKey: "restoreTabs") } }

    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: "accentHex") } }
    @Published var backgroundHex: String { didSet { defaults.set(backgroundHex, forKey: "backgroundHex") } }
    @Published var compactRows: Bool { didSet { defaults.set(compactRows, forKey: "compactRows") } }
    @Published var libraries: [FolderLibrary] { didSet { defaults.set(try? JSONEncoder().encode(libraries), forKey: "libraries") } }
    @Published var language: String { didSet {
        defaults.set(language, forKey: "language")
        if language == "System" { defaults.removeObject(forKey: "AppleLanguages") } else { defaults.set([language], forKey: "AppleLanguages") }
    } }
    @Published var toolbar: ToolbarConfiguration { didSet { defaults.set(try? JSONEncoder().encode(toolbar), forKey: "toolbarV1") } }
    @Published var savedSearches: [SavedSearch] { didSet { defaults.set(try? JSONEncoder().encode(savedSearches), forKey: "savedSearches") } }
    var presentations: [String: FolderPresentation] { didSet { defaults.set(try? JSONEncoder().encode(presentations), forKey: "folderPresentations") } }
    private init() {
        namedTags = defaults.data(forKey: "namedTagsV1").flatMap { try? JSONDecoder().decode([NamedTag].self, from: $0) }.flatMap { NamedTag.valid($0) ? $0 : nil } ?? []
        preferences = defaults.data(forKey: "explorerPreferencesV1").flatMap { try? JSONDecoder().decode(ExplorerPreferences.self, from: $0) }.flatMap { $0.isValid ? $0 : nil } ?? ExplorerPreferences()
        layoutSizes = defaults.dictionary(forKey: "layoutSizes") as? [String: Int] ?? [:]
        showDotfiles = defaults.object(forKey: "showDotfiles") as? Bool ?? defaults.bool(forKey: "showHidden")
        filterVisible = defaults.object(forKey: "filterVisible") as? Bool ?? false
        backgroundImagePath = defaults.string(forKey: "backgroundImagePath") ?? ""
        backgroundImageOpacity = defaults.object(forKey: "backgroundImageOpacity") as? Double ?? 0.2
        idePath = defaults.string(forKey: "idePath") ?? ""
        visibleColumns = defaults.stringArray(forKey: "visibleColumns") ?? ["name", "modified", "kind", "size", "cloud"]
        autoFitColumns = defaults.bool(forKey: "autoFitColumns")
        NativeLocalization.configure(bundle: .module)
        cloudFolders = CloudProviderFolder.registered
        shortcuts = defaults.data(forKey: "shortcutsV1").flatMap { try? JSONDecoder().decode(ShortcutConfiguration.self, from: $0).validated() } ?? ShortcutConfiguration()
        savedSearches = defaults.data(forKey: "savedSearches").flatMap { try? JSONDecoder().decode([SavedSearch].self, from: $0) } ?? []
        toolbar = defaults.data(forKey: "toolbarV1").flatMap { try? JSONDecoder().decode(ToolbarConfiguration.self, from: $0).validated() } ?? .standard
        language = defaults.string(forKey: "language") ?? "System"
        accentHex = defaults.string(forKey: "accentHex") ?? "0A6EE0"
        backgroundHex = defaults.string(forKey: "backgroundHex") ?? ""
        compactRows = defaults.bool(forKey: "compactRows")
        libraries = defaults.data(forKey: "libraries").flatMap { try? JSONDecoder().decode([FolderLibrary].self, from: $0) } ?? []
        presentations = defaults.data(forKey: "folderPresentations").flatMap { try? JSONDecoder().decode([String: FolderPresentation].self, from: $0) } ?? [:]
        sidebarVisible = defaults.object(forKey: "sidebarVisible") as? Bool ?? true
        toolbarVisible = defaults.object(forKey: "toolbarVisible") as? Bool ?? true
        showExtensions = defaults.object(forKey: "showExtensions") as? Bool ?? true
        showHidden = defaults.bool(forKey: "showHidden")
        filesFirst = defaults.bool(forKey: "filesFirst")
        foldersFirst = defaults.object(forKey: "foldersFirst") as? Bool ?? true
        restoreTabs = defaults.object(forKey: "restoreTabs") as? Bool ?? true
        appearance = defaults.string(forKey: "appearance") ?? "System"
        defaultLayout = LayoutMode(rawValue: defaults.string(forKey: "defaultLayout") ?? "") ?? .details
        recentFolders = defaults.stringArray(forKey: "recentFolders") ?? []
        favorites = defaults.data(forKey: "favorites").flatMap { try? JSONDecoder().decode([Favorite].self, from: $0) } ?? Self.standardFavorites
    }
    static var standardFavorites: [Favorite] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("Desktop", "desktopcomputer"), ("Downloads", "arrow.down.circle"),
                ("Documents", "doc.text"), ("Pictures", "photo"), ("Music", "music.note"),
                ("Movies", "film")].map { Favorite(name: $0.0, url: home.appendingPathComponent($0.0), symbol: $0.1) }
    }
    var defaultPresentation: FolderPresentation { FolderPresentation(layout: defaultLayout, sort: preferences.defaultSort, ascending: preferences.defaultAscending, group: preferences.defaultGroup, groupAscending: preferences.defaultGroupAscending, groupDateUnit: preferences.defaultGroupDateUnit) }
    func presentation(for url: URL) -> FolderPresentation? { preferences.syncFolderPreferences ? defaultPresentation : presentations[url.isFileURL ? url.path : url.absoluteString] ?? defaultPresentation }
    func rememberPresentation(_ presentation: FolderPresentation, at url: URL) {
        if preferences.syncFolderPreferences {
            defaultLayout = presentation.layout
            var value = preferences; value.defaultSort = presentation.sort; value.defaultAscending = presentation.ascending
            value.defaultGroup = presentation.group ?? .none; value.defaultGroupAscending = presentation.groupAscending ?? true; value.defaultGroupDateUnit = presentation.groupDateUnit ?? .relative
            if preferences != value { preferences = value }
        }
        presentations[url.isFileURL ? url.path : url.absoluteString] = presentation
        defaults.set(try? JSONEncoder().encode(presentations), forKey: "folderPresentations")
    }
    func applyTheme(_ theme: ExplorerTheme) {
        accentHex = theme.accent; backgroundHex = theme.background; appearance = theme.appearance; compactRows = theme.compactRows
    }
    var currentTheme: ExplorerTheme { ExplorerTheme(name: "My MacFiles theme", accent: accentHex, background: backgroundHex, appearance: appearance, compactRows: compactRows) }
    func applyAppearance() {
        NSApp.appearance = appearance == "Dark" ? NSAppearance(named: .darkAqua) : appearance == "Light" ? NSAppearance(named: .aqua) : nil
    }
    func isVisible(_ item: ListedItem) -> Bool { item.name.hasPrefix(".") ? showDotfiles : (!item.isHidden || showHidden) }
    func pin(_ url: URL) {
        guard !favorites.contains(where: { $0.path == url.path }) else { return }
        favorites.append(Favorite(name: url.lastPathComponent, url: url))
    }
    func remember(_ url: URL) {
        recentFolders.removeAll { $0 == url.path }
        recentFolders.insert(url.path, at: 0)
        recentFolders = Array(recentFolders.prefix(12))
    }
}

enum L10n {
    static func items(_ count: Int) -> String { NativeLocalization.plural("NativeItemCount", count: count) }
    static func selected(_ count: Int) -> String { NativeLocalization.plural("NativeSelectedCount", count: count) }
    static var languages: [String] { Bundle.module.localizations.filter { $0 != "Base" }.sorted() }
    static func text(_ key: String) -> String { NativeLocalization.text(key) }
}
