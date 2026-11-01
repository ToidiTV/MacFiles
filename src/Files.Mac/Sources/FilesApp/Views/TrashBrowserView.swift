import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct TrashBrowserView: View {
    @ObservedObject var model: MainPageViewModel
    @StateObject private var presentation = ShellPageViewModel()
    @State private var items: [ListedItem] = []
    @State private var selected = Set<URL>()
    @State private var message = ""
    @State private var loading = false
    private var selection: [ListedItem] { items.filter { selected.contains($0.url) } }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.text("Trash on this Mac and connected volumes")).font(.headline)
                Spacer(); Button(L10n.text("Refresh")) { load() }
                if loading { ProgressView().controlSize(.small) }
            }
            HStack {
                Picker(L10n.text("Sort by"), selection: $presentation.sort) { ForEach(SortField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Ascending"), isOn: $presentation.ascending)
                Picker(L10n.text("Group by"), selection: $presentation.group) { ForEach(GroupField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Group ascending"), isOn: $presentation.groupAscending)
            }
            Picker(L10n.text("Group by date unit"), selection: $presentation.groupDateUnit) { ForEach(GroupDateUnit.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
            Table(groupedItems, selection: $selected) {
                TableColumn(L10n.text("Group by")) { item in Text(presentation.group == .none ? "" : groupTitles[item.url] ?? "") }
                TableColumn(L10n.text("Name"), value: \.name)
                TableColumn(L10n.text("Original location")) { item in Text(TrashRegistry.shared.original(item.url)?.original.path ?? "Choose a destination to restore").lineLimit(1).truncationMode(.middle) }
                TableColumn(L10n.text("Date deleted")) { Text($0.deleted.map { FileDisplayFormat.date($0) } ?? "—") }
                TableColumn(L10n.text("Size")) { Text($0.sizeLabel) }.width(90)
            }
            if !message.isEmpty { Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button(L10n.text("Restore all")) { restoreOriginal(all: true) }.disabled(items.isEmpty || loading)
                Button(L10n.text("Restore original location")) { restoreOriginal() }.disabled(selection.isEmpty || selection.contains { TrashRegistry.shared.original($0.url) == nil })
                Button(L10n.text("Restore to…")) { restoreTo() }.disabled(selection.isEmpty)
                Spacer()
                Button(L10n.text("Delete selected permanently…")) { permanentlyDelete(selection.map(\.url)) }.disabled(selection.isEmpty)
                Button(L10n.text("Empty accessible Trash…")) { permanentlyDelete(items.map(\.url)) }.disabled(items.isEmpty)
            }.disabled(model.busy)
        }.padding(20).task { load() }.onDisappear { presentation.shutdown() }.onChange(of: model.operationTitle) { if !model.busy { load() } }
    }
    private var groups: [ItemGroup] { ItemGrouping.groups(presentation.orderedItems(items, includeHidden: true), by: presentation.group, ascending: presentation.groupAscending, dateUnit: presentation.groupDateUnit) }
    private var groupedItems: [ListedItem] { groups.flatMap(\.items) }
    private var groupTitles: [URL: String] { Dictionary(uniqueKeysWithValues: groups.flatMap { group in group.items.map { ($0.url, group.localizedTitle(for: presentation.group)) } }) }
    private func load() {
        guard !loading else { return }; loading = true
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let roots = [home] + model.volumes.filter { $0.path != "/" }.map { $0.appendingPathComponent(".Trashes/\(getuid())") }
        Task {
            let result = await Task.detached { () -> ([ListedItem], Int) in
                var result: [ListedItem] = []; var inaccessible = 0
                for root in roots {
                    do { result += try MacDirectoryService.list(root, hidden: true).items.filter { $0.name != ".DS_Store" } }
                    catch {
                        let code = (error as NSError).code
                        if !((error as NSError).domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(code)) { inaccessible += 1 }
                    }
                }
                return (result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, inaccessible)
            }.value
            items = result.0.map { item in var value = item; let record = TrashRegistry.shared.original(item.url); value.originalLocation = record?.original; value.deleted = record?.date; return value }; selected.formIntersection(Set(items.map(\.url)))
            message = result.1 > 0 ? "\(result.1) Trash location(s) could not be read. macOS may require Full Disk Access for Trash. Items listed here remain available to manage." : "Original locations are remembered for items deleted by MacFiles, including across launches."
            loading = false
        }
    }
    private func restoreOriginal(all: Bool = false) {
        let chosen = all ? items : selection
        let records = chosen.compactMap { TrashRegistry.shared.original($0.url) }
        if records.count < chosen.count { message = "Some items have no recorded original location. Select them and use Restore to…" }
        guard !records.isEmpty else { return }
        model.run("Restoring from Trash") {
            let report = await model.storage.undo(records.map { .move(from: $0.trashed, to: $0.original, identity: $0.identity) })
            TrashRegistry.shared.remove(records.filter { report.completed.contains($0.original) }.map(\.trashed))
            var result = OperationReport(); result.completed = report.completed; result.errors = report.errors; result.undo = report.inverse
            return result
        }
    }
    private func restoreTo() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = L10n.text("Restore here")
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let urls = selection.map(\.url)
        model.run("Restoring from Trash") {
            let result = await model.storage.perform(.move, sources: urls, destination: target)
            TrashRegistry.shared.remove(urls.filter { !FileManager.default.fileExists(atPath: $0.path) })
            return result
        }
    }
    private func permanentlyDelete(_ urls: [URL]) {
        let prompt = NSAlert(); prompt.messageText = L10n.text("Permanently delete \(urls.count) items?")
        prompt.informativeText = L10n.text("These items will be removed from Trash. This cannot be undone.")
        prompt.addButton(withTitle: L10n.text("Cancel")); prompt.addButton(withTitle: L10n.text("Delete permanently"))
        guard prompt.runModal() == .alertSecondButtonReturn else { return }
        model.run("Deleting permanently", recordingUndo: false) {
            let report = await model.storage.permanentlyDelete(urls)
            TrashRegistry.shared.remove(report.completed)
            return report
        }
    }
}
