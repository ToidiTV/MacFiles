import Foundation
import FilesShared
import UniformTypeIdentifiers

public struct SearchOptions: Codable, Sendable {
    public var nameTerms: [String]?
    public var naturalKinds: [String]?
    public var modifiedBefore: Date?
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var name = ""
    public var regularExpression = false
    public var fileExtension = ""
    public var tag = ""
    public var text = ""
    public var minimumBytes: Int64?
    public var maximumBytes: Int64?
    public var modifiedAfter: Date?
    public var kind = "Any"
    public var hidden = false
    public init() {}
}

public enum SearchService {
    public static func search(_ roots: [URL], options: SearchOptions) throws -> DirectoryListing {
        let expression = options.regularExpression && !options.name.isEmpty ? try NSRegularExpression(pattern: options.name, options: [.caseInsensitive]) : nil
        let extensions = Set(options.fileExtension.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        var seen = Set<URL>(); var result: [ListedItem] = []; var skipped = 0
        var flags: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.hidden { flags.insert(.skipsHiddenFiles) }
        for root in roots {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw StorageError.notDirectory }
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(ListedItem.keys), options: flags, errorHandler: { _, _ in skipped += 1; return true }) else { throw StorageError.notDirectory }
            for case let url as URL in walker {
                try Task.checkCancellation()
                guard seen.insert(url).inserted else { continue }
                do {
                    let item = try ListedItem(url: url)
                    if let expression {
                        guard expression.firstMatch(in: item.name, range: NSRange(item.name.startIndex..., in: item.name)) != nil else { continue }
                    } else if !options.name.isEmpty && !item.name.localizedStandardContains(options.name) { continue }
                    if let names = options.nameTerms, !names.isEmpty, !names.contains(where: { item.name.localizedStandardContains($0) }) { continue }
                    if let kinds = options.naturalKinds, !kinds.isEmpty {
                        let type = UTType(filenameExtension: url.pathExtension)
                        let matches = kinds.contains { kind in
                            switch kind {
                            case "folder": return item.isDirectory
                            case "picture": return type?.conforms(to: .image) == true
                            case "video": return type?.conforms(to: .movie) == true
                            case "music": return type?.conforms(to: .audio) == true
                            case "program": return type?.conforms(to: .executable) == true || type?.conforms(to: .application) == true
                            case "document": return type?.conforms(to: .text) == true || type?.conforms(to: .pdf) == true || ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "pages", "numbers", "key"].contains(url.pathExtension.lowercased())
                            default: return false
                            }
                        }; if !matches { continue }
                    }
                    if let date = options.modifiedBefore, (item.modified ?? .distantFuture) >= date { continue }
                    if let date = options.createdAfter, (item.created ?? .distantPast) < date { continue }
                    if let date = options.createdBefore, (item.created ?? .distantFuture) >= date { continue }
                    if options.kind == "Files" && item.isDirectory || options.kind == "Folders" && !item.isDirectory { continue }
                    if !extensions.isEmpty && !extensions.contains(url.pathExtension.lowercased()) { continue }
                    if !options.tag.isEmpty && !item.tags.contains(where: { $0.localizedCaseInsensitiveCompare(options.tag) == .orderedSame }) { continue }
                    if let min = options.minimumBytes, item.size < min { continue }
                    if let max = options.maximumBytes, item.size > max { continue }
                    if let date = options.modifiedAfter, (item.modified ?? .distantPast) < date { continue }
                    if !options.text.isEmpty {
                        guard !item.isDirectory && !item.isSymbolicLink else { continue }
                        guard item.cloud.canPreview else { skipped += 1; continue }
                        guard let found = try DocumentTextService.contains(options.text, in: url) else { skipped += 1; continue }
                        guard found else { continue }
                    }
                    result.append(item)
                } catch is CancellationError { throw CancellationError() }
                catch { skipped += 1 }
            }
        }
        return DirectoryListing(items: result, skipped: skipped)
    }
}

public struct SavedSearch: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var roots: [URL]
    public var options: SearchOptions
    public init(name: String, roots: [URL], options: SearchOptions) { id = UUID(); self.name = name; self.roots = roots; self.options = options }
}
