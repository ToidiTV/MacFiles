import Foundation

public struct KeyChord: Codable, Hashable, Sendable {
    public var key: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    public init(_ key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key.lowercased(); self.command = command; self.option = option; self.control = control; self.shift = shift
    }
    public var label: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased() }
    public var valid: Bool { key.count == 1 || ["return", "space", "delete", "forwarddelete", "escape", "tab", "up", "down", "left", "right"].contains(key) || (1...20).contains(where: { key == "f\($0)" }) }
}
public struct ShortcutDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let defaults: [KeyChord]
    public init(_ id: String, _ title: String, _ defaults: [KeyChord] = []) { self.id = id; self.title = title; self.defaults = defaults }
}
public struct ShortcutConfiguration: Codable, Equatable, Sendable {
    public var overrides: [String: [KeyChord]] = [:]
    public init() {}
    public func chords(for id: String) -> [KeyChord] { overrides[id] ?? Self.catalog.first { $0.id == id }?.defaults ?? [] }
    public func action(for chord: KeyChord) -> String? { Self.catalog.first { chords(for: $0.id).contains(chord) }?.id }
    public func validated() throws -> Self {
        let ids = Set(Self.catalog.map(\.id)); var seen = Set<KeyChord>()
        guard overrides.keys.allSatisfy(ids.contains) else { throw ShortcutError("Unknown shortcut command.") }
        for entry in Self.catalog {
            for chord in chords(for: entry.id) {
                guard chord.valid else { throw ShortcutError("Invalid key for \(entry.title).") }
                guard !Self.reserved.contains(chord) else { throw ShortcutError("\(chord.label) is reserved by macOS or the application window.") }
                guard seen.insert(chord).inserted else { throw ShortcutError("\(chord.label) is assigned more than once.") }
            }
        }
        return self
    }
    public static let reserved: Set<KeyChord> = [.init("q", command: true), .init("h", command: true), .init("m", command: true), .init("n", command: true)]
    public static let catalog: [ShortcutDefinition] = {
        func cmd(_ key: String, shift: Bool = false, option: Bool = false) -> KeyChord { .init(key, command: true, option: option, shift: shift) }
        let main: [ShortcutDefinition] = [
            .init("newTab", "New tab", [cmd("t"), .init("t", control: true)]), .init("chooseFolder", "Open folder", [cmd("o")]),
            .init("closeTab", "Close tab", [cmd("w"), .init("w", control: true)]), .init("reopenTab", "Reopen closed tab", [cmd("t", shift: true)]),
            .init("nextTab", "Next tab", [.init("tab", control: true)]), .init("previousTab", "Previous tab", [.init("tab", control: true, shift: true)]),
            .init("new", "New folder", [cmd("n", shift: true)]), .init("newFile", "New text file"), .init("template", "New from template"),
            .init("undo", "Undo file operation", [cmd("z")]), .init("redo", "Redo file operation", [cmd("z", shift: true)]),
            .init("cut", "Cut", [cmd("x"), .init("x", control: true)]), .init("copy", "Copy", [cmd("c"), .init("c", control: true)]),
            .init("paste", "Paste", [cmd("v"), .init("v", control: true)]), .init("moveHere", "Move here", [cmd("v", option: true)]),
            .init("selectAll", "Select all", [cmd("a"), .init("a", control: true)]), .init("invert", "Invert selection"), .init("clear", "Clear selection", [.init("escape")]),
            .init("copyPath", "Copy path", [cmd("c", shift: true)]), .init("duplicate", "Duplicate", [cmd("d")]), .init("rename", "Rename", [.init("f2")]),
            .init("trash", "Move to Trash", [cmd("delete"), .init("forwarddelete")]), .init("settings", "Settings", [cmd(",")]),
            .init("properties", "Properties", [cmd("i", option: true)]), .init("palette", "Command palette", [cmd("p", shift: true)]),
            .init("search", "Advanced search", [cmd("f", option: true)]), .init("git", "Git repository", [cmd("g", shift: true)]), .init("network", "Connect to server", [cmd("k")]),
            .init("back", "Back", [cmd("[")]), .init("forward", "Forward", [cmd("]")]), .init("up", "Up one level", [cmd("up")]),
            .init("home", "Home", [cmd("h", shift: true)]), .init("address", "Go to path", [cmd("l"), .init("l", control: true)]), .init("filter", "Search folder", [cmd("f")]),
            .init("refresh", "Refresh", [cmd("r"), .init("f5")]), .init("detailsLayout", "Details layout", [cmd("2")]), .init("iconsLayout", "Icons layout", [cmd("1")]),
            .init("columnsLayout", "Columns layout", [cmd("3")]), .init("galleryLayout", "Gallery layout", [cmd("4")]), .init("split", "Toggle dual pane", [cmd("d", shift: true)]),
            .init("verticalSplit", "Arrange panes top and bottom"), .init("horizontalSplit", "Arrange panes side by side"), .init("focusPane", "Focus other pane", [.init("tab", option: true)]),
            .init("onTop", "Keep window on top"), .init("fullScreen", "Toggle full screen"), .init("info", "Toggle details pane", [cmd("i")]),
            .init("hidden", "Show hidden files", [cmd(".", shift: true)]), .init("quickLook", "Quick Look", [.init("space")]), .init("open", "Open selection", [.init("return"), cmd("down")]),
            .init("toolbar", "Customize toolbar"), .init("shortcuts", "Keyboard shortcuts"), .init("operations", "Operations"), .init("archive", "Browse archive"), .init("flatten", "Flatten folder"), .init("shelfAdd", "Add selection to shelf")
        ]
        let existing = Set(main.map(\.id))
        return main + parityCommands + ExplorerAction.allCases.filter { !existing.contains($0.rawValue) && ![.separator, .sort, .layout].contains($0) }.map { .init($0.rawValue, $0.title) }
    }()
}
public struct ShortcutError: LocalizedError { public let message: String; public init(_ message: String) { self.message = message }; public var errorDescription: String? { message } }

public extension ShortcutConfiguration {
    static let parityCommands: [ShortcutDefinition] = [
        .init("toggleSelect", "Toggle selection", [.init("space", option: true)]),
        .init("compressZip", "Create zip archive"),
        .init("compress7z", "Create 7z archive"),
        .init("extractHere", "Extract here"),
        .init("extractSmart", "Extract here (Smart)"),
        .init("extractChild", "Extract to child folder"),
        .init("extractTo", "Extract to…"),
        .init("textEdit", "Edit in TextEdit"),
        .init("openIDE", "Open in IDE"),
        .init("repoIDE", "Open repository in IDE"),
        .init("chooseIDE", "Choose IDE…"),
        .init("playAll", "Play All"),
        .init("installFont", "Install font"),
        .init("installCertificate", "Install certificate"),
        .init("classicProperties", "Finder Get Info…"),
        .init("aliasDialog", "Create shortcut"),
        .init("pasteAliases", "Paste shortcut"),
        .init("permanentDelete", "Delete selected permanently…"),
        .init("browseTags", "Browse tagged items…"),
        .init("removeTags", "Remove tags"),
        .init("pinFolders", "Pin to sidebar"),
        .init("unpinFolders", "Unpin"),
        .init("adaptiveLayout", "Adaptive layout"),
        .init("increaseSize", "Increase size"),
        .init("decreaseSize", "Decrease size"),
        .init("nextLayout", "Next layout"),
        .init("previousLayout", "Previous layout"),
        .init("dotfiles", "Show dotfiles"),
        .init("filterHeader", "Toggle filter header"),
        .init("enterCompact", "Enter compact overlay"),
        .init("exitCompact", "Exit compact overlay"),
        .init("compactOverlay", "Toggle compact overlay"),
        .init("appBackground", "Set as app background"),
        .init("slideshow", "Wallpaper slideshow…"),
        .init("wallpaperSettings", "Lock screen and wallpaper settings…"),
        .init("diskUtility", "Format drive in Disk Utility…"),
        .init("storageSettings", "Storage settings…"),
        .init("settingsFile", "Edit settings file…"),
        .init("diagnostics", "Open log file"),
        .init("logFolder", "Show log in folder"),
        .init("releaseNotes", "Release notes"),
        .init("help", "Help")
    ]
}
