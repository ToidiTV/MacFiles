import Foundation

public enum ExplorerAction: String, Codable, CaseIterable, Identifiable {
    case rotateLeft, rotateRight, wallpaper, mediaMetadata
    case new, cut, copy, paste, rename, trash, duplicate, properties, quickLook, share, openWith, alias
    case compress, bulkRename, tags, hashes, attributes, permissions, search, palette, shelf, git, network
    case sort, layout, split, info, refresh, terminal, hidden, undo, redo, download, cloud, separator
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rotateLeft: return "Rotate left"; case .rotateRight: return "Rotate right"; case .wallpaper: return "Set as wallpaper"; case .mediaMetadata: return "Edit media metadata"
        case .new: return "New"; case .cut: return "Cut"; case .copy: return "Copy"; case .paste: return "Paste"
        case .rename: return "Rename"; case .trash: return "Move to Trash"; case .duplicate: return "Duplicate"
        case .properties: return "Properties"; case .quickLook: return "Quick Look"; case .share: return "Share"; case .openWith: return "Open with"; case .alias: return "Make alias"
        case .compress: return "Compress"; case .bulkRename: return "Bulk rename"; case .tags: return "Tags"; case .hashes: return "Hashes"; case .attributes: return "Extended attributes"; case .permissions: return "Permissions"
        case .search: return "Advanced search"; case .palette: return "Command palette"; case .shelf: return "File shelf"; case .git: return "Git repository"; case .network: return "Connect to server"
        case .sort: return "Sort"; case .layout: return "Layout"; case .split: return "Dual pane"; case .info: return "Details pane"; case .refresh: return "Refresh"; case .terminal: return "Terminal"
        case .hidden: return "Hidden files"; case .undo: return "Undo"; case .redo: return "Redo"; case .download: return "Download"; case .cloud: return "Cloud status"; case .separator: return "Separator"
        }
    }
    public var symbol: String {
        switch self {
        case .rotateLeft: return "rotate.left"; case .rotateRight: return "rotate.right"; case .wallpaper: return "desktopcomputer"; case .mediaMetadata: return "slider.horizontal.3"
        case .new: return "plus.circle"; case .cut: return "scissors"; case .copy: return "square.on.square"; case .paste: return "document.on.clipboard"
        case .rename, .bulkRename: return "character.cursor.ibeam"; case .trash: return "trash"; case .duplicate: return "plus.square.on.square"
        case .properties, .info: return "sidebar.right"; case .quickLook: return "eye"; case .share: return "square.and.arrow.up"; case .openWith: return "app"; case .alias: return "arrow.turn.up.right"
        case .compress: return "archivebox"; case .tags: return "tag"; case .hashes: return "number"; case .attributes: return "list.bullet.rectangle"; case .permissions: return "lock.shield"
        case .search: return "magnifyingglass"; case .palette: return "command"; case .shelf: return "tray.full"; case .git: return "point.3.connected.trianglepath.dotted"; case .network: return "network"
        case .sort: return "arrow.up.arrow.down"; case .layout: return "square.grid.2x2"; case .split: return "rectangle.split.2x1"; case .refresh: return "arrow.clockwise"; case .terminal: return "terminal"
        case .hidden: return "eye.slash"; case .undo: return "arrow.uturn.backward"; case .redo: return "arrow.uturn.forward"; case .download: return "icloud.and.arrow.down"; case .cloud: return "icloud"; case .separator: return "line.diagonal"
        }
    }
}
public enum ToolbarContext: String, Codable, CaseIterable, Identifiable {
    case always = "Always visible", browsing = "No selection", file = "Single file", folder = "Single folder", multiple = "Multiple items", cloud = "Cloud items"
    public var id: String { rawValue }
}
public struct ToolbarEntry: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var action: ExplorerAction
    public var showIcon = true
    public var showLabel = false
    public init(_ action: ExplorerAction, showLabel: Bool = false) { self.action = action; self.showLabel = showLabel }
}
public struct ToolbarConfiguration: Codable, Equatable {
    public var contexts: [String: [ToolbarEntry]]
    public init(contexts: [String: [ToolbarEntry]]) { self.contexts = contexts }
    public static var standard: ToolbarConfiguration {
        ToolbarConfiguration(contexts: [ToolbarContext.always.rawValue: [.init(.new, showLabel: true), .init(.separator), .init(.cut), .init(.copy), .init(.paste), .init(.rename), .init(.share), .init(.trash), .init(.properties), .init(.separator), .init(.sort), .init(.layout), .init(.split), .init(.info)], ToolbarContext.cloud.rawValue: [.init(.cloud), .init(.download)]])
    }
    public func entries(for context: ToolbarContext) -> [ToolbarEntry] { contexts[context.rawValue] ?? [] }
    public func resolved(context: ToolbarContext, cloud: Bool) -> [ToolbarEntry] {
        let all = entries(for: .always) + entries(for: context) + (cloud ? entries(for: .cloud) : [])
        var seen = Set<ExplorerAction>()
        return all.filter { $0.action == .separator || seen.insert($0.action).inserted }
    }
    public func validated() throws -> ToolbarConfiguration {
        guard contexts.keys.allSatisfy({ ToolbarContext(rawValue: $0) != nil }), contexts.values.allSatisfy({ $0.count <= 60 }) else { throw CocoaError(.coderReadCorrupt) }
        var copy = self
        for key in copy.contexts.keys {
            var seen = Set<UUID>()
            copy.contexts[key] = copy.contexts[key]?.map { entry in
                var entry = entry
                if !seen.insert(entry.id).inserted { entry.id = UUID() }
                if !entry.showIcon && !entry.showLabel { entry.showIcon = true }
                return entry
            }
        }
        return copy
    }
}
