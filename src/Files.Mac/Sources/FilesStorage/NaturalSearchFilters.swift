import Foundation

public struct NaturalSearchFilters: Decodable, Sendable {
    public var names: [String]?
    public var extensions: [String]?
    public var kinds: [String]?
    public var modifiedAfter: String?
    public var modifiedBefore: String?
    public var createdAfter: String?
    public var createdBefore: String?
    public var minimumBytes: Int64?
    public var maximumBytes: Int64?
    public static func parse(_ text: String, base: SearchOptions) throws -> SearchOptions {
        guard text.utf8.count <= 16384 else { throw StorageError.invalidName }
        let filters = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        let kinds = Set(["picture", "video", "music", "document", "folder", "program"])
        guard [filters.names, filters.extensions, filters.kinds].allSatisfy({ ($0?.count ?? 0) <= 32 }),
              (filters.names ?? []).allSatisfy({ !$0.isEmpty && $0.count <= 255 }),
              (filters.extensions ?? []).allSatisfy({ !$0.isEmpty && $0.count <= 32 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." } }),
              (filters.kinds ?? []).allSatisfy(kinds.contains),
              filters.minimumBytes.map({ $0 >= 0 }) ?? true, filters.maximumBytes.map({ $0 >= 0 }) ?? true else { throw StorageError.invalidName }
        var result = base; result.name = ""; result.regularExpression = false
        result.nameTerms = filters.names; result.naturalKinds = filters.kinds
        if let extensions = filters.extensions, !extensions.isEmpty { result.fileExtension = extensions.joined(separator: ",") }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        func date(_ text: String?) throws -> Date? {
            guard let text else { return nil }
            guard let value = format.date(from: text), format.string(from: value) == text else { throw StorageError.invalidName }
            return value
        }
        result.modifiedAfter = try date(filters.modifiedAfter) ?? base.modifiedAfter
        result.modifiedBefore = try date(filters.modifiedBefore)
        result.createdAfter = try date(filters.createdAfter); result.createdBefore = try date(filters.createdBefore)
        result.minimumBytes = filters.minimumBytes ?? base.minimumBytes; result.maximumBytes = filters.maximumBytes ?? base.maximumBytes
        guard result.minimumBytes == nil || result.maximumBytes == nil || result.minimumBytes! <= result.maximumBytes!,
              result.modifiedAfter == nil || result.modifiedBefore == nil || result.modifiedAfter! < result.modifiedBefore!,
              result.createdAfter == nil || result.createdBefore == nil || result.createdAfter! < result.createdBefore! else { throw StorageError.invalidName }
        guard filters.names?.isEmpty == false || filters.extensions?.isEmpty == false || filters.kinds?.isEmpty == false || filters.modifiedAfter != nil || filters.modifiedBefore != nil || filters.createdAfter != nil || filters.createdBefore != nil || filters.minimumBytes != nil || filters.maximumBytes != nil else { throw StorageError.invalidName }
        return result
    }
}
