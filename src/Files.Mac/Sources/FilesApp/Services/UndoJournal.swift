import Foundation
import Combine
import FilesStorage

@MainActor final class UndoJournal: ObservableObject {
    static let shared = UndoJournal()
    private struct Snapshot: Codable { var undo: [[UndoStep]]; var redo: [[UndoStep]] }
    @Published var undo: [[UndoStep]] = [] { didSet { save() } }
    @Published var redo: [[UndoStep]] = [] { didSet { save() } }
    private var loading = true
    private init() {
        if let data = UserDefaults.standard.data(forKey: "fileUndoJournalV1"), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) { undo = Array(snapshot.undo.suffix(30)); redo = Array(snapshot.redo.suffix(30)) }
        loading = false
    }
    private func save() {
        guard !loading else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(Snapshot(undo: Array(undo.suffix(30)), redo: Array(redo.suffix(30)))), forKey: "fileUndoJournalV1")
    }
}
