import Foundation

public enum VirtualLocation: Codable, Equatable, Sendable {
    case archive(URL, String)
    case network(UUID?, String)
}
public struct PaneSnapshot: Codable {
    public let virtualLocation: VirtualLocation?
    public let location: URL?
    public let layout: LayoutMode
    public let sort: SortField
    public let ascending: Bool
    public let library: FolderLibrary?
    public let group: GroupField?
    public let groupAscending: Bool?
    public let groupDateUnit: GroupDateUnit?
    public init(location: URL?, layout: LayoutMode, sort: SortField, ascending: Bool, library: FolderLibrary? = nil, group: GroupField = .none, groupAscending: Bool = true, groupDateUnit: GroupDateUnit = .relative, virtualLocation: VirtualLocation? = nil) {
        self.virtualLocation = virtualLocation
        self.location = location; self.layout = layout; self.sort = sort; self.ascending = ascending; self.library = library; self.group = group; self.groupAscending = groupAscending; self.groupDateUnit = groupDateUnit
    }
}
public struct TabSnapshot: Codable {
    public let primary: PaneSnapshot
    public let secondary: PaneSnapshot?
    public let verticalSplit: Bool?
    public init(primary: PaneSnapshot, secondary: PaneSnapshot?, verticalSplit: Bool = false) { self.primary = primary; self.secondary = secondary; self.verticalSplit = verticalSplit }
}
public struct FolderPresentation: Codable {
    public let group: GroupField?
    public let groupAscending: Bool?
    public let groupDateUnit: GroupDateUnit?
    public let layout: LayoutMode
    public let sort: SortField
    public let ascending: Bool
    public init(layout: LayoutMode, sort: SortField, ascending: Bool, group: GroupField = .none, groupAscending: Bool = true, groupDateUnit: GroupDateUnit = .relative) { self.layout = layout; self.sort = sort; self.ascending = ascending; self.group = group; self.groupAscending = groupAscending; self.groupDateUnit = groupDateUnit }
}
public struct ExplorerTheme: Codable {
    public var name: String
    public var accent: String
    public var background: String
    public var appearance: String
    public var compactRows: Bool
    public init(name: String, accent: String, background: String, appearance: String, compactRows: Bool) {
        self.name = name; self.accent = accent; self.background = background; self.appearance = appearance; self.compactRows = compactRows
    }
}
public struct FolderLibrary: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var folders: [URL]
    public init(name: String, folders: [URL]) { id = UUID(); self.name = name; self.folders = folders }
}
