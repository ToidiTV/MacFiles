import Foundation
import FilesShared

public enum NativeTags {
    private static let managedKey = "com.toidi.macfiles.tags"
    public static func managed(_ url: URL) throws -> [NamedTag] {
        guard let data = try ExtendedAttributes.list(url).first(where: { $0.name == managedKey })?.data else { return [] }
        guard data.count <= 1_048_576 else { throw CommandFailure("Invalid tag metadata.") }
        let tags = try JSONDecoder().decode([NamedTag].self, from: data)
        guard NamedTag.valid(tags) else { throw CommandFailure("Invalid tag metadata.") }
        return tags
    }
    private static let key = "com.apple.metadata:_kMDItemUserTags"
    public static func read(_ url: URL) throws -> [String] {
        guard let attribute = try ExtendedAttributes.list(url).first(where: { $0.name == key }) else { return [] }
        guard let tags = try PropertyListSerialization.propertyList(from: attribute.data, format: nil) as? [String] else { throw CommandFailure("Invalid tag metadata.") }
        return tags
    }
    private static func name(_ tag: String) -> String { tag.components(separatedBy: "\n").first ?? tag }
    public static func replace(_ old: NamedTag, with replacement: NamedTag?, at url: URL) throws {
        var tags = try read(url)
        guard tags.contains(where: { name($0).localizedCaseInsensitiveCompare(old.name) == .orderedSame }) else { return }
        tags.removeAll { name($0).localizedCaseInsensitiveCompare(old.name) == .orderedSame }
        if let replacement {
            guard replacement.isValid else { throw CommandFailure("Invalid tag name or color.") }
            tags.removeAll { name($0).localizedCaseInsensitiveCompare(replacement.name) == .orderedSame }
            tags.append(replacement.name + "\n" + String(replacement.color))
        }
        var records = try managed(url).filter { record in record.id != old.id && tags.contains(where: { name($0).localizedCaseInsensitiveCompare(record.name) == .orderedSame }) }
        records.removeAll { $0.name.localizedCaseInsensitiveCompare(old.name) == .orderedSame || $0.name.localizedCaseInsensitiveCompare(replacement?.name ?? "") == .orderedSame }
        if let replacement { records.append(replacement) }
        try save(tags, records: records, at: url)
    }
    public static func apply(_ names: [String], catalog: [NamedTag], to urls: [URL]) throws {
        for url in urls {
            try Task.checkCancellation()
            let existing = try read(url)
            let tags = Array(Set(names)).sorted().map { name -> String in
                if let tag = catalog.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return tag.name + "\n" + String(tag.color) }
                return existing.first(where: { self.name($0) == name }) ?? name
            }
            let records = catalog.filter { tag in names.contains { $0.localizedCaseInsensitiveCompare(tag.name) == .orderedSame } }
            try save(tags, records: records, at: url)
        }
    }
    private static func save(_ tags: [String], records: [NamedTag], at url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        let attributes = try ExtendedAttributes.list(url)
        let old = attributes.first { $0.name == key }?.data
        try ExtendedAttributes.write(key, data: data, to: url)
        do { try ExtendedAttributes.write(managedKey, data: try JSONEncoder().encode(records), to: url) }
        catch {
            let original = error
            do { if let old { try ExtendedAttributes.write(key, data: old, to: url) } else { try ExtendedAttributes.remove(key, from: url) } }
            catch { throw CommandFailure("Tag update failed and original metadata could not be restored: " + error.localizedDescription) }
            throw original
        }
    }
}
