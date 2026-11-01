import SwiftUI
import FilesStorage

struct OperationRecord: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    var state: String
    var detail = ""
}
@MainActor struct PendingOperation {
    let id: UUID
    let title: String
    let pane: ShellPageViewModel
    let recordingUndo: Bool
    var onCancel: (() -> Void)? = nil
    let action: () async throws -> OperationReport
}
struct OperationsView: View {
    @ObservedObject var model: MainPageViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L10n.text("File operations in this window")).font(.headline); Spacer(); Button(L10n.text("Clear finished")) { model.operationRecords.removeAll { !["Queued", "Running"].contains($0.state) } } }
            List(model.operationRecords.reversed()) { record in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(L10n.text(record.title)).bold(); Spacer(); Text(L10n.text(record.state)); Text(record.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary) }
                    if record.state == "Running" { ProgressView(value: model.operationProgress); Button(L10n.text("Cancel")) { model.cancelOperation() } }
                    if record.state == "Queued" { Button(L10n.text("Cancel queued operation")) { model.cancelQueued(record.id) } }
                    if !record.detail.isEmpty { Text(L10n.text(record.detail)).font(.caption).textSelection(.enabled) }
                }.padding(.vertical, 6)
            }
            Text(L10n.text("Paste and drop transfers queue behind the current operation. Completed changes remain available through Undo. Copy cancellation stops the staged transfer before publishing it. Undo history is restored across launches.")).font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }
}
