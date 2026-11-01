import SwiftUI
import FilesShared
import FilesStorage

struct VirtualPropertiesView: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    let urls: [URL]
    var initialPage = "General"
    @State private var page = "General"
    @State private var rows: [PropertyValue] = []
    @State private var message = ""
    @State private var permissions = "644"
    @State private var name = ""
    @State private var loaded: [URL: URL] = [:]
    @State private var references: [VirtualFileReference] = []
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    private let pages = ["General", "Details", "Security", "Hashes", "Preview", "Customization", "Compatibility", "Signatures"]
    var body: some View {
        HStack(spacing: 0) {
            PropertiesSidebar(pages: pages, selection: $page)
            VStack(alignment: .leading, spacing: 12) {
                Text(references.count == 1 ? references[0].item.name : L10n.items(references.count)).font(.headline)
                if busy { HStack { ProgressView().controlSize(.small); Button(L10n.text("Cancel")) { task?.cancel(); busy = false } } }
                if page == "General", references.count == 1 {
                    HStack { Text(name).textSelection(.enabled); Button(L10n.text("Rename")) { pane.selection = Set(urls); pane.synchronizeVirtualSelection(); model.tool = nil; pane.virtualAction?("rename") } }
                }
                if page == "General", !references.isEmpty { Button(L10n.text("Calculate total size")) { load(materialize: true) }.disabled(busy) }
                if page == "Security" {
                    Text(L10n.text(pane.archiveURL != nil ? "Permissions are stored in the archive. Changes rebuild it and support Undo." : "Permissions are enforced by the server. FTP servers must support SITE CHMOD; SFTP uses SSH permissions.")).font(.caption)
                    HStack { TextField(L10n.text("POSIX permissions"), text: $permissions); Button(L10n.text("Apply file permissions")) { applyPermissions() }.disabled(busy || references.isEmpty || (pane.archiveURL.map { ArchiveService.editableFormat($0) == nil } ?? false)) }
                }
                if page == "Customization" {
                    Picker(L10n.text("Layout"), selection: $pane.layout) { ForEach(LayoutMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                    Picker(L10n.text("Group by"), selection: $pane.group) { ForEach(GroupField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Group ascending"), isOn: $pane.groupAscending)
                Picker(L10n.text("Group by date unit"), selection: $pane.groupDateUnit) { ForEach(GroupDateUnit.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                    Text(L10n.text("Presentation is saved with this virtual location.")).font(.caption)
                } else if page == "Preview", let reference = references.first { FilePreview(item: reference.item, pane: pane) }
                else {
                    PropertyRows(values: rows)
                }
                if !message.isEmpty { Text(L10n.text(message)).font(.caption).textSelection(.enabled) }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 8))
        }.onAppear {
            references = (pane.visibleItems + pane.columnItems).filter { urls.contains($0.url) }.reduce(into: [VirtualFileReference]()) { result, item in if !result.contains(where: { $0.item.url == item.url }), let reference = pane.reference(item) { result.append(reference) } }
            name = references.first?.item.name ?? ""; page = initialPage; load()
        }.onChange(of: page) { load() }.onDisappear { task?.cancel() }
    }
    private func file(_ reference: VirtualFileReference) async throws -> URL {
        if let cached = loaded[reference.item.url] { return cached }
        let folder = try ClipboardStaging.create(); let url = try await reference.materialize(in: folder); loaded[reference.item.url] = url; return url
    }
    private func load(materialize: Bool = false) {
        task?.cancel(); busy = true; message = ""; rows = []
        task = Task {
            defer { if !Task.isCancelled { busy = false } }
            do {
                var result: [PropertyValue] = []
                for reference in references {
                    let item = reference.item
                    if references.count > 1 { result.append(.init("File", item.name)) }
                    switch page {
                    case "General":
                        result += [.init("Name", item.name), .init("Location", item.url.path), .init("Kind", item.localizedKind), .init("Size", item.sizeLabel)]
                        if let date = item.modified { result.append(.init("Modified", date.formatted(.dateTime.locale(NativeLocalization.locale)))) }
                        if materialize { let url = try await file(reference); let size = try await Task.detached { item.isDirectory ? try MetadataService.directorySize(url).0 : Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }.value; result.append(.init("Total size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) }
                    case "Details":
                        let url = try await file(reference); result += await Task.detached { PropertiesService.metadata(url) }.value
                        if MediaService.isEditable(url) { let fields = try await MediaService.fields(url); result += [.init("Title", fields.title), .init("Artist", fields.artist), .init("Album", fields.album), .init("Description", fields.comment)] }
                    case "Compatibility":
                        let url = try await file(reference); result += try await PropertiesService.applicationInfo(url)
                    case "Signatures":
                        let url = try await file(reference); result.append(.init("Signature", try await PropertiesService.signature(url)))
                    case "Hashes":
                        guard !item.isDirectory else { result.append(.init(item.name, "Choose a file to calculate hashes.")); continue }
                        let url = try await file(reference); let hashes = try await Task.detached { try MetadataService.hashes(url) }.value
                        result += [.init("MD5", hashes.md5), .init("SHA-1", hashes.sha1), .init("SHA-256", hashes.sha256), .init("SHA-512", hashes.sha512)]
                    case "Security":
                        switch reference.origin {
                        case .archive(_, _, let entry):
                            result += [.init("Encrypted", L10n.text(entry.encrypted ? "Yes" : "No")), .init("Symbolic link", L10n.text(entry.link ? "Yes" : "No"))]
                            if let mode = entry.posixPermissions { permissions = String(mode, radix: 8); result.append(.init("POSIX permissions", permissions)) }
                        case .remote(let provider, let connection, let path, let entry):
                            if let current = try await provider.list(path).first(where: { $0.name == entry.name }) {
                                if let mode = current.permissions { permissions = mode; result.append(.init("POSIX permissions", mode)) }
                                if let owner = current.owner { result.append(.init("Owner", owner)) }
                                if let group = current.group { result.append(.init("Group", group)) }
                                if let target = current.linkTarget { result.append(.init("Link target", target)) }
                            }
                            result += [.init("Protocol", connection.kind.rawValue), .init("Server", connection.host), .init("User", connection.username), .init("Trust", L10n.text(connection.kind == .sftp ? "SSH known-host verification" : connection.kind == .ftps ? "TLS certificate verification" : "Unencrypted FTP"))]
                        case .local: break
                        }
                    default: break
                    }
                }
                try Task.checkCancellation(); rows = result
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    private func applyPermissions() {
        guard let mode = UInt16(permissions, radix: 8), mode <= 0o777 else { message = "Enter permissions from 000 to 777."; return }
        let references = references
        model.run("Updating permissions") {
            var report = OperationReport()
            for reference in references {
                switch reference.origin {
                case .archive(let url, let password, let entry): let result = try await ArchiveService().edit(url, change: .permissions([entry.path], mode), password: password); report.undo += result.undo; report.completed += result.completed
                case .remote(let provider, _, let path, let entry): try await provider.setPermissions(mode, path: RemoteProvider.child(path, entry.name)); report.completed.append(reference.item.url)
                case .local: break
                }
            }
            message = "Permissions updated."; return report
        }
    }
}
