import AppKit
import Combine
import FilesShared
import FilesStorage
import UniformTypeIdentifiers

@MainActor final class ShellPageViewModel: ObservableObject, Identifiable {
    let id = UUID()
    private var virtualSubscriptions: [AnyCancellable] = []
    @Published var virtualLocation: VirtualLocation?
    let archiveSession = ArchiveBrowserSession()
    let networkSession = NetworkBrowserSession()
    var virtualAction: ((String) -> Void)?
    var virtualPaste: (([URL], URL?, Bool) async throws -> OperationReport)?
    var canGoBack: Bool { archiveURL != nil ? archiveSession.historyIndex > 0 : isVirtual ? networkSession.historyIndex > 0 : history.canGoBack }
    var canGoForward: Bool { archiveURL != nil ? archiveSession.historyIndex + 1 < archiveSession.history.count : isVirtual ? networkSession.historyIndex + 1 < networkSession.history.count : history.canGoForward }
    var isVirtual: Bool { virtualLocation != nil }
    var archiveURL: URL? { if case .archive(let url, _) = virtualLocation { return url }; return nil }
    func openVirtual(_ location: VirtualLocation) {
        folderSizeTask?.cancel(); loadTask?.cancel(); cloudTask?.cancel(); watchers.forEach { $0.stop() }; watchers = []
        virtualLocation = location; items = []; selection = []; library = nil; loading = false
        switch location {
        case .archive(_, let path): archiveSession.prefix = path
        case .network(let id, let path):
            networkSession.path = path
            if let saved = ConnectionStore.shared.connections.first(where: { $0.id == id }) { networkSession.connection = saved; networkSession.connection.initialPath = path; networkSession.password = ConnectionStore.shared.password(for: saved); networkSession.remember = !networkSession.password.isEmpty }
        }
    }
    @Published private(set) var history: NavigationHistory
    @Published private(set) var items: [ListedItem] = []
    @Published var library: FolderLibrary?
    @Published var columnItems: [ListedItem] = []
    @Published var columnDirectory: URL?
    var focusedItemURL: URL?
    @Published var selection: Set<URL> = []
    @Published var query = "" { didSet { if archiveURL != nil { archiveSession.search = query }; if recursiveSearch { refresh() } } }
    @Published var layout: LayoutMode { didSet { savePresentation() } }
    @Published var groupAscending = true { didSet { savePresentation() } }
    @Published var groupDateUnit: GroupDateUnit = .relative { didSet { savePresentation() } }
    @Published var group: GroupField = .none { didSet { savePresentation() } }
    @Published var sort: SortField = .name { didSet { savePresentation() } }
    @Published var ascending = true { didSet { savePresentation() } }
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var skipped = 0
    @Published private(set) var recursiveSearch = false
    var onNavigate: ((URL?) -> Void)?
    private var loadTask: Task<Void, Never>?
    private var watchers: [DirectoryWatcher] = []
    private var libraryHistory: [Int: FolderLibrary] = [:]
    private var refreshTask: Task<Void, Never>?
    private var folderSizeTask: Task<Void, Never>?
    private var selectionAfterLoad: URL?
    private var cloudTask: Task<Void, Never>?
    private var generation = UUID()
    private var restoringPresentation = false
    var location: URL? { history.current }
    var title: String {
        if let archiveURL { return archiveURL.lastPathComponent }
        if isVirtual { return networkSession.connection.host.isEmpty ? "Network" : networkSession.connection.host }
        return library?.name ?? location.map { $0.path == "/" ? "Macintosh HD" : $0.lastPathComponent } ?? "Home" }
    var operationDirectory: URL? { isVirtual ? nil : columnDirectory ?? location }
    var selectedItems: [ListedItem] {
        var seen = Set<URL>()
        return (visibleItems + columnItems).filter { selection.contains($0.url) && seen.insert($0.url).inserted }
    }

    var effectiveLayout: LayoutMode { layout == .adaptive ? AdaptiveLayout.resolve(visibleItems) : layout }
    var visibleItems: [ListedItem] {
        let source = isVirtual ? virtualItems.filter { SettingsService.shared.isVisible($0) } : items
        let values = query.isEmpty || recursiveSearch ? source : source.filter { $0.name.localizedStandardContains(query) }
        return orderedItems(values)
    }
    func orderedItems(_ source: [ListedItem], includeHidden: Bool = false) -> [ListedItem] {
        let values = source.filter { includeHidden || SettingsService.shared.isVisible($0) }
        let foldersFirst = SettingsService.shared.foldersFirst
        return values.sorted { a, b in
            if a.isBrowsable != b.isBrowsable {
                if foldersFirst { return a.isBrowsable }
                if SettingsService.shared.filesFirst { return !a.isBrowsable }
            }
            let comparison: ComparisonResult
            switch sort {
            case .originalFolder: comparison = (a.originalLocation?.deletingLastPathComponent().path ?? "").localizedStandardCompare(b.originalLocation?.deletingLastPathComponent().path ?? "")
            case .deleted: comparison = (a.deleted ?? .distantPast).compare(b.deleted ?? .distantPast)
            case .created: comparison = (a.created ?? .distantPast).compare(b.created ?? .distantPast)
            case .tags: comparison = a.tags.sorted().joined(separator: ", ").localizedStandardCompare(b.tags.sorted().joined(separator: ", "))
            case .path: comparison = a.url.path.localizedStandardCompare(b.url.path)
            case .cloud: comparison = a.cloud.availability.rawValue.localizedStandardCompare(b.cloud.availability.rawValue)
            case .name: comparison = a.name.localizedStandardCompare(b.name)
            case .kind: comparison = a.kind.localizedStandardCompare(b.kind)
            case .size: comparison = a.size == b.size ? .orderedSame : a.size < b.size ? .orderedAscending : .orderedDescending
            case .modified: comparison = (a.modified ?? .distantPast).compare(b.modified ?? .distantPast)
            }
            let resolved = comparison == .orderedSame ? a.name.localizedStandardCompare(b.name) : comparison
            return ascending ? resolved == .orderedAscending : resolved == .orderedDescending
        }
    }

    init(location: URL? = nil) {
        history = NavigationHistory(initial: location)
        layout = SettingsService.shared.defaultLayout
        virtualSubscriptions = [archiveSession.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }, networkSession.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }]
        restorePresentation()
        refresh()
    }
    func navigate(_ url: URL?) {
        virtualLocation = nil; archiveSession.shutdown(); networkSession.shutdown()
        library = nil
        history.visit(url?.standardizedFileURL)
        libraryHistory = libraryHistory.filter { $0.key < history.index }
        didNavigate()
    }
    func openLibrary(_ library: FolderLibrary) {
        guard let folder = library.folders.first else { return }
        self.library = library; history.visit(folder); libraryHistory = libraryHistory.filter { $0.key <= history.index }; libraryHistory[history.index] = library; didNavigate()
    }
    var navigationPath: String { archiveURL != nil ? "/" + archiveSession.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : networkSession.path }
    @discardableResult func navigateVirtualPath(_ input: String) -> Bool {
        guard isVirtual, input.hasPrefix("/"), !input.contains("\0") else { return false }
        var components: [String] = []
        for part in input.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !components.isEmpty { components.removeLast() }; continue }
            components.append(String(part))
        }
        let path = components.joined(separator: "/")
        if archiveURL != nil {
            guard path.isEmpty || archiveSession.entries.contains(where: { $0.path.hasPrefix(path + "/") || $0.directory && $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path }) else { return false }
            archiveSession.prefix = path.isEmpty ? "" : path + "/"; archiveSession.selected = []; archiveSession.search = ""
        } else { guard let virtualAction else { return false }; virtualAction("navigate:/" + path) }
        query = ""; selection = []; columnItems = []; columnDirectory = nil
        return true
    }
    func back() { if archiveURL != nil { stepArchive(-1); return }; if isVirtual { virtualAction?("back"); return }; guard history.canGoBack else { return }; history.back(); library = libraryHistory[history.index]; didNavigate() }
    func forward() { if archiveURL != nil { stepArchive(1); return }; if isVirtual { virtualAction?("forward"); return }; guard history.canGoForward else { return }; history.forward(); library = libraryHistory[history.index]; didNavigate() }
    private func stepArchive(_ offset: Int) {
        guard archiveSession.history.indices.contains(archiveSession.historyIndex + offset) else { return }
        archiveSession.step(offset); query = ""; selection = []; columnItems = []; columnDirectory = nil
        restorePresentation()
    }
    func up() {
        if let archiveURL, archiveSession.prefix.isEmpty { navigate(archiveURL.deletingLastPathComponent()); selectionAfterLoad = archiveURL; return }
        if archiveURL != nil { let path = archiveSession.prefix.split(separator: "/").dropLast().joined(separator: "/"); navigateVirtualPath("/" + path); return }
        if isVirtual { virtualAction?("up"); return }
        guard let location else { return }
        navigate(location.path == "/" ? nil : location.deletingLastPathComponent())
        if SettingsService.shared.preferences.selectPreviousFolder { selectionAfterLoad = location }
    }
    private func didNavigate() {
        selectionAfterLoad = nil
        recursiveSearch = false; query = ""; selection = []; items = []; columnItems = []; columnDirectory = nil
        restorePresentation()
        onNavigate?(location)
        refresh()
    }
    func refresh(search: Bool = false) {
        if isVirtual { archiveSession.reloadToken = UUID(); networkSession.reloadToken = UUID(); return }
        folderSizeTask?.cancel(); cloudTask?.cancel(); refreshTask?.cancel(); loadTask?.cancel(); watchers.forEach { $0.stop() }; watchers = []
        let token = UUID(); generation = token
        error = nil; skipped = 0; recursiveSearch = search
        if search { items = []; selection = [] }
        guard let location else { items = []; loading = false; return }
        loading = true
        let hidden = SettingsService.shared.showHidden || SettingsService.shared.showDotfiles
        let term = query
        let roots = library?.folders ?? [location]
        let natural = search && SettingsService.shared.preferences.naturalLanguageSearch
        let work = Task.detached(priority: .userInitiated) {
            if natural {
                var base = SearchOptions(); base.name = term; base.hidden = hidden
                if let options = await NaturalLanguageSearch.translate(term, base: base) {
                    try Task.checkCancellation(); return try SearchService.search(roots, options: options)
                }
            }
            return try MacDirectoryService.listLocations(roots, query: search ? term : nil, hidden: hidden)
        }
        loadTask = Task { [weak self] in
            do {
                let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.items = result.items; self.skipped = result.skipped; self.loading = false
                self.selection.formIntersection(Set((result.items + self.columnItems).map(\.url)))
                if let previous = self.selectionAfterLoad, result.items.contains(where: { $0.url == previous }) { self.selection = [previous]; self.focusedItemURL = previous }; self.selectionAfterLoad = nil
                if SettingsService.shared.preferences.calculateFolderSizes {
                    let folders = result.items.filter(\.isBrowsable)
                    self.folderSizeTask = Task { [weak self] in
                        for folder in folders {
                            guard !Task.isCancelled else { return }
                            let work = Task.detached(priority: .utility) { try MetadataService.directorySize(folder.url).0 }
                            let size = await withTaskCancellationHandler { try? await work.value } onCancel: { work.cancel() }
                            guard let self, self.generation == token, !Task.isCancelled else { return }
                            if let size, let index = self.items.firstIndex(where: { $0.url == folder.url }) { self.items[index].size = size; self.items[index].directorySizeCalculated = true }
                        }
                    }
                }
                if !search && result.items.contains(where: { $0.cloud.isCloud }) {
                    self.cloudTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        self?.refresh()
                    }
                }
                if !search {
                    self.watchers = roots.map { root in
                        let watcher = DirectoryWatcher()
                        watcher.watch(root) { [weak self] in Task { @MainActor in self?.scheduleRefresh() } }
                        return watcher
                    }
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.items = []; self.loading = false; self.error = error.localizedDescription
            }
        }
    }
    func stopSearch() { loadTask?.cancel(); loading = false }
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    var snapshot: PaneSnapshot {
        let virtual: VirtualLocation? = archiveURL.map { .archive($0, archiveSession.prefix) } ?? (isVirtual ? .network(networkSession.connection.id, networkSession.path) : nil)
        return PaneSnapshot(location: location, layout: layout, sort: sort, ascending: ascending, library: library, group: group, groupAscending: groupAscending, groupDateUnit: groupDateUnit, virtualLocation: virtual)
    }
    func restore(_ snapshot: PaneSnapshot) {
        restoringPresentation = true
        layout = snapshot.layout; sort = snapshot.sort; ascending = snapshot.ascending; group = snapshot.group ?? .none; groupAscending = snapshot.groupAscending ?? true; groupDateUnit = snapshot.groupDateUnit ?? .relative
        if let library = snapshot.library { self.library = library; libraryHistory[history.index] = library; refresh() }
        if let virtual = snapshot.virtualLocation { openVirtual(virtual) }
        restoringPresentation = false
    }
    var presentationLocation: URL? {
        guard isVirtual else { return location }
        var value = URLComponents(); value.scheme = "macfiles-presentation"
        value.host = archiveURL != nil ? "archive" : networkSession.connection.id.uuidString
        value.path = archiveURL?.path ?? networkSession.path
        if archiveURL != nil { value.queryItems = [.init(name: "folder", value: archiveSession.prefix)] }
        return value.url
    }
    func restorePresentation() {
        guard let location = presentationLocation, let saved = SettingsService.shared.presentation(for: location) else { return }
        restoringPresentation = true
        layout = saved.layout; sort = saved.sort; ascending = saved.ascending; group = saved.group ?? .none; groupAscending = saved.groupAscending ?? true; groupDateUnit = saved.groupDateUnit ?? .relative
        restoringPresentation = false
    }
    private func savePresentation() {
        guard !restoringPresentation, let location = presentationLocation else { return }
        SettingsService.shared.rememberPresentation(FolderPresentation(layout: layout, sort: sort, ascending: ascending, group: group, groupAscending: groupAscending, groupDateUnit: groupDateUnit), at: location)
    }
    func shutdown() { folderSizeTask?.cancel(); virtualPaste = nil; virtualAction = nil; archiveSession.shutdown(); networkSession.shutdown(); cloudTask?.cancel(); loadTask?.cancel(); refreshTask?.cancel(); watchers.forEach { $0.stop() }; watchers = [] }
}

@MainActor struct ExplorerTab: Identifiable {
    let id: UUID
    let primary: ShellPageViewModel
    var secondary: ShellPageViewModel?
    var verticalSplit = false
    init(location: URL? = nil) { id = UUID(); primary = ShellPageViewModel(location: location) }
}
