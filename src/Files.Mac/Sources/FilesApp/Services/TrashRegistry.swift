import Foundation
import FilesShared
import FilesStorage

struct TrashRecord: Codable {
    let trashed: URL
    let original: URL
    let date: Date
    let identity: FileIdentity?
}
@MainActor final class TrashRegistry {
    static let shared = TrashRegistry()
    private(set) var records: [TrashRecord]
    private init() {
        records = UserDefaults.standard.data(forKey: "trashRecords").flatMap { try? JSONDecoder().decode([TrashRecord].self, from: $0) } ?? []
    }
    func record(_ steps: [UndoStep]) {
        for step in steps {
            if case .move(let trashed, let original, let identity) = step {
                records.removeAll { $0.trashed == trashed }
                records.append(TrashRecord(trashed: trashed, original: original, date: Date(), identity: identity))
            }
        }
        save()
    }
    func original(_ url: URL) -> TrashRecord? { records.last { $0.trashed == url && ($0.identity == nil || $0.identity == FileIdentity(url)) } }
    func remove(_ urls: [URL]) { records.removeAll { urls.contains($0.trashed) }; save() }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: "trashRecords") }
}
