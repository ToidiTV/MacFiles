import SwiftUI
import FilesShared
import FilesStorage

struct TagSettingsSection: View {
    @ObservedObject private var settings = SettingsService.shared
    @State private var editing: UUID?
    @State private var name = ""
    @State private var color = 0
    @State private var customHex = ""
    @State private var busy = false
    @State private var message = ""
    @State private var pendingDelete: NamedTag?
    private let colors: [(String, Color)] = [("None", .secondary), ("Gray", .gray), ("Green", .green), ("Purple", .purple), ("Blue", .blue), ("Yellow", .yellow), ("Red", .red), ("Orange", .orange)]
    var body: some View {
        Section(L10n.text("Manage tags")) {
            Text(L10n.text("Renaming or deleting a saved tag updates files found by Spotlight. Unindexed or inaccessible files may retain the old tag. Finder uses the macOS palette; custom colors and stable IDs are retained by MacFiles.")).font(.caption).foregroundStyle(.secondary)
            ForEach(settings.namedTags) { tag in
                HStack {
                    Circle().fill(tag.customHex.flatMap(Palette.color) ?? colors[tag.color].1).frame(width: 10, height: 10)
                    Text(tag.name); Spacer()
                    Button(L10n.text("Edit")) { editing = tag.id; name = tag.name; color = tag.color; customHex = tag.customHex ?? "" }
                    Button(L10n.text("Delete")) { pendingDelete = tag }
                }.disabled(busy)
            }
            HStack {
                TextField(L10n.text("Tag name"), text: $name)
                Picker(L10n.text("Tag color"), selection: $color) { ForEach(colors.indices, id: \.self) { Text(L10n.text(colors[$0].0)).tag($0) } }.frame(width: 180)
                Button(L10n.text(editing == nil ? "Add" : "Save")) { save() }
                    .disabled(!NamedTag(name: name.trimmingCharacters(in: .whitespaces), color: color, customHex: customHex.isEmpty ? nil : customHex).isValid)
                if editing != nil { Button(L10n.text("Cancel")) { editing = nil; name = "" } }
            }.disabled(busy)
            TextField(L10n.text("Custom tag color (hex, optional)"), text: $customHex).disabled(busy)
            if busy { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }.confirmationDialog(L10n.text("Delete saved tag and remove it from indexed files?"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            if let tag = pendingDelete { Button(L10n.text("Delete"), role: .destructive) { update(tag, replacement: nil) } }
            Button(L10n.text("Cancel"), role: .cancel) { pendingDelete = nil }
        }
    }
    private func save() {
        let tag = NamedTag(id: editing ?? UUID(), name: name.trimmingCharacters(in: .whitespaces), color: color, customHex: customHex.isEmpty ? nil : customHex)
        var updated = settings.namedTags.filter { $0.id != tag.id }; updated.append(tag)
        guard NamedTag.valid(updated) else { message = L10n.text("Tag names must be unique."); return }
        if let old = settings.namedTags.first(where: { $0.id == editing }) { update(old, replacement: tag) }
        else { settings.namedTags.append(tag); name = ""; message = "" }
    }
    private func update(_ old: NamedTag, replacement: NamedTag?) {
        busy = true; message = ""
        Task {
            do {
                let result = try await ProcessService.run("/usr/bin/mdfind", ["-0", "kMDItemUserTags == '*'"])
                let urls = result.data.split(separator: 0).map { URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)) }
                let failures = await Task.detached { () -> [String] in
                    var failures: [String] = []
                    for url in urls {
                        do { try NativeTags.replace(old, with: replacement, at: url) }
                        catch { failures.append(url.path + ": " + error.localizedDescription) }
                    }
                    return failures
                }.value
                if failures.isEmpty {
                    settings.namedTags.removeAll { $0.id == old.id }
                    if let replacement { settings.namedTags.append(replacement) }
                    editing = nil; name = ""; message = L10n.text("Indexed files updated.")
                } else {
                    message = L10n.text("Some files could not be updated. The saved tag was retained so you can retry.") + "\n" + failures.prefix(20).joined(separator: "\n")
                }
            } catch { message = error.localizedDescription }
            busy = false; pendingDelete = nil
        }
    }
}
