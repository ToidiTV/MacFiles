import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct TagBrowserView: View {
    @ObservedObject var model: MainPageViewModel
    @State var tag = ""
    @State private var items: [ListedItem] = []
    @State private var selected = Set<URL>()
    @State private var message = ""
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField(L10n.text("Tag (blank = all tags)"), text: $tag).onSubmit { search() }.disabled(searching)
                Button(L10n.text("Search")) { search() }.disabled(searching)
                if searching { ProgressView().controlSize(.small); Button(L10n.text("Stop")) { task?.cancel() } }
            }
            Text(L10n.text("Results come from the macOS Spotlight index. Unindexed folders are not included.")).font(.caption)
            Table(items, selection: $selected) {
                TableColumn(L10n.text("Name"), value: \.name)
                TableColumn(L10n.text("Tags")) { Text($0.tags.joined(separator: ", ")) }
                TableColumn(L10n.text("Path")) { Text($0.url.path).lineLimit(1) }
            }
            HStack {
                Button(L10n.text("OpenAllTaggedItems")) { open(items) }.disabled(items.isEmpty)
                Button(L10n.text("Open")) { open(items.filter { selected.contains($0.url) }) }.disabled(selected.isEmpty)
                Spacer(); Text(L10n.text(message)).font(.caption)
            }
        }.padding(20).task { search() }.onDisappear { task?.cancel() }
    }
    private func open(_ values: [ListedItem]) {
        for item in values { if item.isBrowsable { model.newTab(item.url) } else { NSWorkspace.shared.open(item.url) } }
    }
    private func search() {
        task?.cancel(); searching = true; message = ""; items = []; selected = []
        let wanted = tag
        task = Task {
            do {
                let result = try await ProcessService.run("/usr/bin/mdfind", ["-0", "kMDItemUserTags == '*'"])
                let urls = result.data.split(separator: 0).map { URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)) }
                let work = Task.detached { () -> [ListedItem] in
                    var found: [ListedItem] = []
                    for url in urls { if Task.isCancelled { break }; if let item = try? ListedItem(url: url), !item.tags.isEmpty, wanted.isEmpty || item.tags.contains(where: { $0.localizedCaseInsensitiveCompare(wanted) == .orderedSame }) { found.append(item) } }
                    return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
                let found = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled else { searching = false; return }
                items = found; message = L10n.items(found.count)
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            searching = false
        }
    }
}

@MainActor enum DiagnosticsStore {
    static var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacFiles/Logs/operations.log") }
    static func append(_ event: String) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var data = (try? Data(contentsOf: url)) ?? Data()
            if data.count > 1_000_000 { let suffix = data.suffix(500_000); data = suffix.firstIndex(of: 10).map { Data(suffix.suffix(from: suffix.index(after: $0))) } ?? Data() }
            data.append(Data((Date().ISO8601Format() + " " + event + "\n").utf8))
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { NSLog("MacFiles could not write diagnostics: %@", error.localizedDescription) }
    }
    static func read() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "No operations recorded." }
}
struct DiagnosticsView: View {
    @State private var text = ""
    var body: some View {
        VStack {
            HStack { Text(DiagnosticsStore.url.path).font(.caption).textSelection(.enabled); Spacer(); Button(L10n.text("Refresh")) { text = DiagnosticsStore.read() } }
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(20).onAppear { text = DiagnosticsStore.read() }
    }
}
extension MainPageViewModel {
    func revealLog() { if !FileManager.default.fileExists(atPath: DiagnosticsStore.url.path) { DiagnosticsStore.append("Diagnostics opened") }; NSWorkspace.shared.activateFileViewerSelecting([DiagnosticsStore.url]) }
    func classicProperties() {
        let urls = activePane.selectedItems.map(\.url).filter(\.isFileURL)
        guard !urls.isEmpty else { return }
        let escaped = urls.map { "POSIX file \"" + $0.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\"" }.joined(separator: ", ")
        let script = NSAppleScript(source: "tell application \"Finder\"\nactivate\nrepeat with selectedFile in {" + escaped + "}\nreveal (selectedFile as alias)\nopen information window of (selectedFile as alias)\nend repeat\nend tell")
        guard let script else { alert("Finder Get Info unavailable", "The system script could not be created."); present(.properties); return }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { alert("Finder Get Info unavailable", error?.description ?? "The system script could not be compiled."); present(.properties); return }
        script.executeAndReturnError(&error)
        if let error { alert("Finder Get Info unavailable", error.description); present(.properties) }
    }
}
