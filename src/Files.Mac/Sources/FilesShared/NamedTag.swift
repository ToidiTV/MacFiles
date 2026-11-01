import Foundation

public struct NamedTag: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var customHex: String?
    public var color: Int
    public init(id: UUID = UUID(), name: String, color: Int = 0, customHex: String? = nil) { self.id = id; self.name = name; self.color = color; self.customHex = customHex }
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !name.contains("\n") && !name.contains("\r") && !name.contains(",") && !name.contains("\0") && name.count <= 255 && (0...7).contains(color) && (customHex == nil || customHex!.count == 6 && UInt32(customHex!, radix: 16) != nil) }
    public static func valid(_ tags: [NamedTag]) -> Bool { tags.count <= 1000 && tags.allSatisfy(\.isValid) && Set(tags.map(\.id)).count == tags.count && Set(tags.map { $0.name.lowercased() }).count == tags.count }
}
