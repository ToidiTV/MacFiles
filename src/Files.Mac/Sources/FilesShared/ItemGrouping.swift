import Foundation

public enum GroupField: String, CaseIterable, Codable, Sendable {
    case created = "Date created", cloud = "Cloud status", path = "Path", originalFolder = "Original location", deleted = "Date deleted"
    case none = "None", kind = "Kind", modified = "Date modified", size = "Size", tag = "Tag", name = "First letter"
}
public enum GroupDateUnit: String, CaseIterable, Codable, Sendable {
    case relative = "Default", year = "Year", month = "Month", day = "Day"
}
public struct ItemGroup: Sendable {
    public let title: String
    public let items: [ListedItem]
    public func localizedTitle(for field: GroupField) -> String {
        switch field {
        case .size, .modified, .created, .deleted, .cloud: return NativeLocalization.text(title)
        case .kind: return items.allSatisfy(\.isBrowsable) ? NativeLocalization.text("Folders") : title
        case .tag: return items.allSatisfy { $0.tags.isEmpty } ? NativeLocalization.text("Untagged") : title
        case .name, .none, .path, .originalFolder: return title
        }
    }
}
public enum ItemGrouping {
    public static func groups(_ items: [ListedItem], by field: GroupField, now: Date = Date(), ascending: Bool = true, dateUnit: GroupDateUnit = .relative) -> [ItemGroup] {
        guard field != .none else { return [ItemGroup(title: "", items: items)] }
        let calendar = Calendar.current
        func key(_ item: ListedItem) -> String {
            switch field {
            case .none: return ""
            case .path: return item.url.deletingLastPathComponent().path
            case .originalFolder: return item.originalLocation?.deletingLastPathComponent().path ?? "Unknown"
            case .cloud: return item.cloud.availability.label.isEmpty ? "Local" : item.cloud.availability.label
            case .kind: return item.isBrowsable ? "Folders" : item.kind
            case .name: return String(item.name.prefix(1)).uppercased()
            case .tag: return item.tags.sorted().first ?? "Untagged"
            case .size:
                if item.isBrowsable { return "Folders" }
                if item.size == 0 { return "Empty" }
                if item.size < 1024 * 1024 { return "Under 1 MB" }
                if item.size < 100 * 1024 * 1024 { return "1–100 MB" }
                if item.size < 1024 * 1024 * 1024 { return "100 MB–1 GB" }
                return "Over 1 GB"
            case .modified, .created, .deleted:
                let date = field == .created ? item.created : field == .deleted ? item.deleted : item.modified
                guard let modified = date else { return "Unknown" }
                if dateUnit != .relative {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = calendar
                    formatter.dateFormat = dateUnit == .year ? "yyyy" : dateUnit == .month ? "yyyy-MM" : "yyyy-MM-dd"
                    return formatter.string(from: modified)
                }
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: modified), to: calendar.startOfDay(for: now)).day ?? 0
                if days <= 0 { return "Today" }; if days == 1 { return "Yesterday" }; if days < 7 { return "Last 7 days" }; if days < 30 { return "Last 30 days" }; return "Older"
            }
        }
        let grouped = Dictionary(grouping: items, by: key)
        let order = [GroupField.modified, .created, .deleted].contains(field) && dateUnit == .relative ? ["Today", "Yesterday", "Last 7 days", "Last 30 days", "Older", "Unknown"] : field == .size ? ["Folders", "Empty", "Under 1 MB", "1–100 MB", "100 MB–1 GB", "Over 1 GB"] : []
        let keys = grouped.keys.sorted { a, b in
            if !order.isEmpty { return (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99) }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return (ascending ? keys : keys.reversed()).map { ItemGroup(title: $0, items: grouped[$0] ?? []) }
    }
}
