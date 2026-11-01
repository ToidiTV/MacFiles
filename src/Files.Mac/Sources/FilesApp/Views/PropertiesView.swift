import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct PropertiesView: View {
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @State private var page = "General"
    @State private var values: [PropertyValue] = []
    @State private var text = ""
    @State private var message = ""
    @State private var busy = false
    @State private var hidden = false
    @State private var locked = false
    @State private var permissions = "644"
    @State private var owner = ""
    @State private var group = ""
    @State private var identity: FileIdentity?
    @State private var originalACL = ""
    @State private var name = ""
    @State private var target = ""
    @State private var folderLayout = LayoutMode.details
    @State private var task: Task<Void, Never>?
    private var urls: [URL] { request.urls.isEmpty ? [request.directory] : request.urls }
    private var url: URL { urls[0] }
    private var single: Bool { urls.count == 1 }
    private var pages: [String] {
        var pages = ["General", "Details", "Security", "Customization", "Hashes", "Extended attributes", "Cloud"]
        if single {
            let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
            if values?.isAliasFile == true || values?.isSymbolicLink == true { pages.append("Shortcut") }
            pages += ["Compatibility", "Signatures"]
        }
        if model.activePane.library != nil { pages.append("Library") }
        return pages
    }
    var body: some View {
        HStack(spacing: 0) {
            PropertiesSidebar(pages: pages, selection: $page)
            VStack(alignment: .leading, spacing: 12) {
                Text(single ? url.lastPathComponent : L10n.items(urls.count)).font(.headline).lineLimit(1)
                if busy { HStack { ProgressView().controlSize(.small); Text(L10n.text("Loading…")); Button(L10n.text("Cancel")) { task?.cancel(); busy = false } } }
                content
                if !message.isEmpty { Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 8))
        }.task { if pages.contains(request.initialPage) { page = request.initialPage }; load() }.onChange(of: page) { load() }.onDisappear { task?.cancel() }
    }
    @ViewBuilder private var content: some View {
        switch page {
        case "General":
            if single { HStack { TextField(L10n.text("Name"), text: $name); Button(L10n.text("Rename")) { rename() }.disabled(busy || name == url.lastPathComponent) } }
            propertyTable
            if single {
                HStack { Toggle(L10n.text("Hidden"), isOn: $hidden); Toggle(L10n.text("Locked"), isOn: $locked); Spacer(); Button(L10n.text("Apply attributes")) { applyFlags() }.disabled(busy) }
                HStack {
                    Button(L10n.text("Calculate total size")) { calculateSize() }.disabled(busy)
                    Button(L10n.text("Open with…")) { model.openWith(urls: urls) }.disabled(request.urls.isEmpty)
                    Button(L10n.text("Reveal")) { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                }
            } else { Button(L10n.text("Calculate combined size")) { calculateSize() }.disabled(busy) }
        case "Details":
            Text(L10n.text("Indexed document, image, audio, video and filesystem metadata supplied by Spotlight. Tags can be edited with the Tags tool.")).font(.caption).foregroundStyle(.secondary)
            propertyTable
            if single && MediaService.isEditable(url) { Button(L10n.text("Edit media metadata…")) { model.tool = ToolRequest(kind: .mediaMetadata, urls: urls, directory: request.directory) } }
            Button(L10n.text("Edit tags…")) { model.tool = ToolRequest(kind: .tags, urls: urls, directory: request.directory) }
        case "Security":
            if single {
                HStack { TextField(L10n.text("Owner UID"), text: $owner); TextField(L10n.text("Group GID"), text: $group); Button(L10n.text("Apply owner/group…")) { applyOwner() }.disabled(busy) }
                HStack { TextField(L10n.text("POSIX permissions"), text: $permissions); Button(L10n.text("Apply file permissions")) { applyPermissions() }.disabled(busy) }
                Text(L10n.text("Access control list — native macOS syntax")).font(.subheadline)
                TextEditor(text: $text).font(ExplorerFont.font(size: 11, design: .monospaced)).border(.quaternary)
                HStack { Button(L10n.text("Reload")) { load() }; Button(L10n.text("Export ACL…")) { exportACL() }; Spacer(); Button(L10n.text("Apply ACL…")) { applyACL() }.disabled(text == originalACL || busy) }
                Text(L10n.text("Edits apply to this item only. Ownership changes require existing system permission; MacFiles does not elevate itself.")).font(.caption).foregroundStyle(.secondary)
            } else { Text(L10n.text("Choose one item to edit ownership or ACLs.")); Button(L10n.text("Edit POSIX permissions for selection")) { model.tool = ToolRequest(kind: .permissions, urls: urls, directory: request.directory) } }
        case "Customization":
            if single {
                HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 85, height: 85); Text(url.path).font(.caption).textSelection(.enabled) }
                HStack { Button(L10n.text("Choose custom icon…")) { setIcon() }; Button(L10n.text("Reset icon")) { if !NSWorkspace.shared.setIcon(nil, forFile: url.path, options: []) { message = "The icon could not be reset." } else { model.iconRevision += 1; model.refreshAll() } } }
                if (try? ListedItem(url: url).isDirectory) == true {
                    Text(L10n.text("Folder presentation")).font(.headline)
                    Picker(L10n.text("Layout"), selection: $folderLayout) { ForEach(LayoutMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                    Button(L10n.text("Save folder layout")) { saveFolderLayout() }
                }
                Text(L10n.text("The custom icon and saved layout belong to the selected item.")).font(.caption).foregroundStyle(.secondary)
            } else { Text(L10n.text("Choose a single file or folder to customize its icon.")) }
            Spacer()
        case "Hashes":
            if single, (try? ListedItem(url: url).isDirectory) != true { MetadataToolView(model: model, request: ToolRequest(kind: .hashes, urls: urls, directory: request.directory)) }
            else { Text(L10n.text("Hashes are available for a single file.")); Spacer() }
        case "Extended attributes":
            if single { AttributesView(request: ToolRequest(kind: .attributes, urls: urls, directory: request.directory)) } else { Text(L10n.text("Choose one item to view extended attributes.")); Spacer() }
        case "Cloud": CloudStatusView(model: model, urls: urls)
        case "Shortcut":
            TextField(L10n.text("Target"), text: $target)
            HStack { Button(L10n.text("Open target folder")) { model.newTab(URL(fileURLWithPath: target).deletingLastPathComponent()); model.tool = nil }; Button(L10n.text("Retarget…")) { retarget() } }
            Text(L10n.text("macOS aliases and symbolic links refer to a target path. Windows shortcut arguments and Run as administrator flags do not have alias equivalents.")).font(.caption).foregroundStyle(.secondary)
            Spacer()
        case "Library": LibraryPropertiesView(model: model)
        case "Compatibility":
            propertyTable
            Text(L10n.text("macOS uses Mach-O architectures and the application's minimum OS version. Windows compatibility modes, DPI overrides and administrator flags cannot be applied to a native Mac app.")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("Open with application…")) { model.openWith(urls: urls) }; Spacer()
        case "Signatures":
            ScrollView { Text(text).font(ExplorerFont.font(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Button(L10n.text("Copy report")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        default: EmptyView()
        }
    }
    private var propertyTable: some View {
        PropertyRows(values: values)
    }
    private func load() {
        task?.cancel(); values = []; text = ""; message = ""; busy = false
        folderLayout = SettingsService.shared.presentation(for: url)?.layout ?? .details
        guard ["General", "Details", "Security", "Shortcut", "Compatibility", "Signatures"].contains(page) else { return }
        let page = page; let urls = urls; let url = url; busy = true
        task = Task {
            do {
                switch page {
                case "General":
                    let result = try await Task.detached { try PropertiesService.general(urls) }.value
                    try Task.checkCancellation(); values = result; name = url.lastPathComponent
                    let attributes = try url.resourceValues(forKeys: [.isHiddenKey, .isUserImmutableKey]); hidden = attributes.isHidden == true; locked = attributes.isUserImmutable == true
                case "Details":
                    let result = await Task.detached { PropertiesService.metadata(url) }.value; try Task.checkCancellation(); values = result
                case "Security":
                    let security = try await Task.detached { try PropertiesService.security(url) }.value
                    try Task.checkCancellation(); owner = String(security.uid); group = String(security.gid); permissions = security.mode; text = security.acl; originalACL = text; identity = FileIdentity(url)
                    message = "Owner: \(security.owner) · Group: \(security.group)"
                case "Shortcut":
                    if (try url.resourceValues(forKeys: [.isAliasFileKey])).isAliasFile == true { target = try URL(resolvingAliasFileAt: url).path }
                    else { target = url.resolvingSymlinksInPath().path }
                case "Compatibility":
                    let result = try await PropertiesService.applicationInfo(url); try Task.checkCancellation(); values = result
                case "Signatures":
                    let result = try await PropertiesService.signature(url); try Task.checkCancellation(); text = result
                default: break
                }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            if !Task.isCancelled { busy = false }
        }
    }
    private func rename() { let name = name; model.tool = nil; model.run("Renaming") { try await model.storage.rename(url, to: name) } }
    private func applyFlags() { do { try PropertiesService.setFlags(hidden: hidden, locked: locked, at: url); model.refreshAll(); message = "Attributes updated." } catch { message = error.localizedDescription } }
    private func applyPermissions() { do { try MetadataService.setPermissions(permissions, for: urls); message = "Permissions updated." } catch { message = error.localizedDescription } }
    private func confirm(_ title: String, _ detail: String) -> Bool {
        let alert = NSAlert(); alert.messageText = L10n.text(title); alert.informativeText = L10n.text(detail); alert.addButton(withTitle: L10n.text("Cancel")); alert.addButton(withTitle: L10n.text("Apply")); return alert.runModal() == .alertSecondButtonReturn
    }
    private func applyOwner() {
        guard let uid = UInt32(owner), let gid = UInt32(group) else { message = "Enter numeric user and group IDs."; return }
        guard confirm("Change ownership?", "Apply UID \(uid) and GID \(gid) to this item only.") else { return }
        do { try PropertiesService.setOwner(uid: uid, gid: gid, at: url, expected: identity); message = "Ownership updated." } catch { message = error.localizedDescription }
    }
    private func applyACL() {
        do {
            try PropertiesService.validateACL(text)
            guard confirm("Replace this item's ACL?", "This changes which users can access the item. Export the existing ACL first if you need a backup.") else { return }
            try PropertiesService.setACL(text, at: url, expected: identity); originalACL = text; message = "ACL updated."
        } catch { message = error.localizedDescription }
    }
    private func exportACL() { let panel = NSSavePanel(); panel.nameFieldStringValue = url.lastPathComponent + ".acl.txt"; if panel.runModal() == .OK, let target = panel.url { do { try originalACL.write(to: target, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription } } }
    private func calculateSize() {
        let urls = urls
        busy = true
        task = Task {
            let work = Task.detached { () throws -> (Int64, Int) in
                var bytes: Int64 = 0; var count = 0
                let roots = urls.filter { item in !urls.contains { $0 != item && item.path.hasPrefix($0.path + "/") } }
                for url in roots {
                    let item = try ListedItem(url: url)
                    if item.isDirectory && !item.isSymbolicLink { let size = try MetadataService.directorySize(url); bytes += size.0; count += size.1 }
                    else { bytes += item.size; count += 1 }
                }; return (bytes, count)
            }
            do { let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }; if !Task.isCancelled { message = "\(result.1) items · \(result.0) bytes (\(ByteCountFormatter.string(fromByteCount: result.0, countStyle: .file)))" } }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
            if !Task.isCancelled { busy = false }
        }
    }
    private func saveFolderLayout() {
        let settings = SettingsService.shared
        let previous = settings.presentation(for: url)
        settings.rememberPresentation(FolderPresentation(layout: folderLayout, sort: previous?.sort ?? .name, ascending: previous?.ascending ?? true, group: previous?.group ?? .none, groupAscending: previous?.groupAscending ?? true, groupDateUnit: previous?.groupDateUnit ?? .relative), at: url)
        if model.activePane.location == url { model.activePane.layout = folderLayout }
        message = "Folder layout saved."
    }
    private func setIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let source = panel.url, let image = NSImage(contentsOf: source) {
            if NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) { model.iconRevision += 1; model.refreshAll(); message = "Custom icon applied." } else { message = "The icon could not be changed." }
        }
    }
    private func retarget() {
        guard confirm("Change the shortcut target?", "The shortcut will point to \(target). The target file itself is not modified.") else { return }
        let destination = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        model.tool = nil; model.run("Retargeting shortcut") { try await model.storage.retargetShortcut(url, to: destination) }
    }
}

struct LibraryPropertiesView: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var settings = SettingsService.shared
    @State private var name = ""
    @State private var folders: [URL] = []
    @State private var selection: URL?
    var body: some View {
        VStack {
            TextField(L10n.text("Library name"), text: $name)
            List(folders, id: \.self, selection: $selection) { url in HStack { Text(url.path); Spacer(); if url == folders.first { Text(L10n.text("Default save location")).font(.caption) } } }
            HStack {
                Button(L10n.text("Add folder…")) { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { for url in panel.urls where !folders.contains(url) { folders.append(url) } } }
                Button(L10n.text("Remove")) { folders.removeAll { $0 == selection }; selection = nil }.disabled(selection == nil)
                Button(L10n.text("Set default")) { if let selection { folders.removeAll { $0 == selection }; folders.insert(selection, at: 0) } }.disabled(selection == nil)
                Spacer(); Button(L10n.text("Apply")) { save() }.disabled(folders.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.onAppear { if let library = model.activePane.library { name = library.name; folders = library.folders } }
    }
    private func save() {
        guard var library = model.activePane.library else { return }
        library.name = name; library.folders = folders
        if let index = settings.libraries.firstIndex(where: { $0.id == library.id }) { settings.libraries[index] = library }
        model.activePane.openLibrary(library)
    }
}
