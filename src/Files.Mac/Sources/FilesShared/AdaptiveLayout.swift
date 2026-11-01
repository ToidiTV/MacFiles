import Foundation
import UniformTypeIdentifiers

public enum AdaptiveLayout {
    public static func resolve(_ items: [ListedItem]) -> LayoutMode {
        guard !items.isEmpty else { return .details }
        let media = items.filter { item in
            guard !item.isBrowsable, let type = UTType(filenameExtension: item.url.pathExtension) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .audio) || type.conforms(to: .movie)
        }.count
        return Double(media) / Double(items.count) > 0.6 ? .icons : .details
    }
}
