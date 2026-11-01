// Copyright (c) 2026 MacFiles contributors. Licensed under the MIT License.
import Foundation
import Darwin
import UniformTypeIdentifiers

public struct ListedItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public var originalLocation: URL? = nil
    public var deleted: Date? = nil
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    public let isHidden: Bool
    public var size: Int64
    public var directorySizeCalculated = false
    public let modified: Date?
    public let created: Date?
    public let kind: String
    public let tags: [String]
    public let cloud: CloudState
    public let hasCustomIcon: Bool
    public var isBrowsable: Bool { isDirectory && !isPackage }
    public var localizedKind: String { isBrowsable ? NativeLocalization.text("Folder") : kind == "File" ? NativeLocalization.text("File") : kind }
    public var displayName: String {
        guard UserDefaults.standard.object(forKey: "showExtensions") as? Bool == false, !isDirectory, !name.hasPrefix(".") else { return name }
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? name : stem
    }
    public var sizeLabel: String { isBrowsable && !directorySizeCalculated ? "—" : FileDisplayFormat.size(size) }

    public static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey, .tagNamesKey
    ]

    public init(virtualURL: URL, name: String, directory: Bool, size: Int64, modified: Date? = nil, symbolicLink: Bool = false) {
        self.url = virtualURL; self.name = name; isDirectory = directory; isPackage = false; isSymbolicLink = symbolicLink
        isHidden = name.hasPrefix("."); self.size = size; self.modified = modified; created = nil
        kind = directory ? "Folder" : UTType(filenameExtension: (name as NSString).pathExtension)?.localizedDescription ?? "File"
        tags = []; cloud = .local; hasCustomIcon = false
    }
    public init(url: URL) throws {
        var current = url; current.removeAllCachedResourceValues()
        let values = try current.resourceValues(forKeys: Self.keys)
        self.url = url.standardizedFileURL
        name = url.lastPathComponent
        isDirectory = values.isDirectory ?? false
        isPackage = values.isPackage ?? false
        isSymbolicLink = values.isSymbolicLink ?? false
        isHidden = values.isHidden ?? name.hasPrefix(".")
        size = Int64(values.fileSize ?? 0)
        modified = values.contentModificationDate
        created = values.creationDate
        kind = values.localizedTypeDescription ?? (isDirectory ? "Folder" : "File")
        tags = values.tagNames ?? []
        cloud = CloudState.read(url)
        var finderInfo = [UInt8](repeating: 0, count: 32)
        let read = getxattr(url.path, "com.apple.FinderInfo", &finderInfo, finderInfo.count, 0, XATTR_NOFOLLOW)
        hasCustomIcon = read >= 10 && (finderInfo[8] & 0x04) != 0
    }
}

public enum SortField: String, CaseIterable, Codable, Sendable {
    case originalFolder = "Original location", deleted = "Date deleted"
    case name = "Name", modified = "Date modified", kind = "Kind", size = "Size", created = "Date created", tags = "Tags", path = "Path", cloud = "Cloud status"
}

public enum LayoutMode: String, CaseIterable, Codable, Sendable {
    case adaptive = "Adaptive"
    case details = "Details", icons = "Icons", smallIcons = "Small icons", mediumIcons = "Medium icons", largeIcons = "Large icons", extraLargeIcons = "Extra large icons", list = "List", tiles = "Tiles", columns = "Columns", gallery = "Gallery"
    public var iconSize: Double {
        switch self { case .smallIcons, .list: return 24; case .mediumIcons, .tiles: return 48; case .largeIcons: return 104; case .extraLargeIcons: return 160; default: return 68 }
    }
    public var horizontal: Bool { self == .list || self == .tiles }
    public var cellWidth: Double { horizontal ? (self == .tiles ? 300 : 230) : max(110, iconSize + 55) }
    public var cellHeight: Double { horizontal ? (self == .tiles ? 78 : 34) : iconSize + 64 }
}

public struct NavigationHistory: Sendable {
    public private(set) var locations: [URL?] = [nil]
    public private(set) var index = 0
    public var current: URL? { locations[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < locations.count }
    public init(initial: URL? = nil) { locations = [initial] }
    public mutating func visit(_ url: URL?) {
        guard current != url else { return }
        locations = Array(locations.prefix(index + 1))
        locations.append(url)
        index = locations.count - 1
    }
    public mutating func back() { if canGoBack { index -= 1 } }
    public mutating func forward() { if canGoForward { index += 1 } }
}

public struct Favorite: Identifiable, Codable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let symbol: String
    public var url: URL { URL(fileURLWithPath: path) }
    public init(name: String, url: URL, symbol: String = "folder") {
        self.name = name; path = url.path; self.symbol = symbol
    }
}
