import AppKit
import SwiftUI
import FilesShared
import FilesStorage
import UniformTypeIdentifiers

final class ExplorerTable: NSTableView {
    var makeMenu: ((Int) -> NSMenu)?
    var activate: (() -> Void)?
    var goUp: (() -> Void)?
    let hover = HoverSelection()
    override func updateTrackingAreas() { super.updateTrackingAreas(); hover.track(self) }
    override func mouseMoved(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        hover.schedule { [weak self] in guard let self, row >= 0, row < self.numberOfRows, self.delegate?.tableView?(self, isGroupRow: row) != true else { return }; self.activate?(); self.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }
    override func mouseExited(with event: NSEvent) { hover.cancel() }
    override func mouseDown(with event: NSEvent) {
        hover.cancel(); activate?()
        if event.clickCount == 2, row(at: convert(event.locationInWindow, from: nil)) < 0, SettingsService.shared.preferences.doubleClickUp { goUp?(); return }
        super.mouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        activate?()
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return makeMenu?(row)
    }
}

struct FileTableView: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var pane: ShellPageViewModel
    @ObservedObject var model: MainPageViewModel
    let items: [ListedItem]

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder; scroll.drawsBackground = false; scroll.autohidesScrollers = true
        let table = ExplorerTable(); table.backgroundColor = Palette.nativeSurface
        table.style = .fullWidth; table.rowHeight = 34; table.intercellSpacing = NSSize(width: 8, height: 0)
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true; table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        let columns: [(String, String, CGFloat)] = [("selection", "Select", 28), ("name", "Name", 300), ("modified", "Date modified", 160), ("kind", "Kind", 140), ("size", "Size", 90), ("cloud", "Cloud status", 145), ("created", "Date created", 160), ("tags", "Tags", 140), ("path", "Path", 250)]
        for (key, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); column.title = key == "selection" ? "" : L10n.text(title)
            column.width = width; column.minWidth = key == "selection" ? 28 : key == "name" ? 160 : 70
            if key == "selection" { column.maxWidth = 28 } else { column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true) }
            if key == "size" { column.headerCell.alignment = .right }
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.action = #selector(Coordinator.singleClickItem); table.doubleAction = #selector(Coordinator.openItem)
        table.registerForDraggedTypes(FileDrag.types); table.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.makeMenu = { [weak coordinator = context.coordinator] row in coordinator?.menu(row) ?? NSMenu() }
        table.goUp = { [weak coordinator = context.coordinator] in coordinator?.parent.pane.up() }
        table.activate = { [weak coordinator = context.coordinator] in coordinator?.activate() }
        scroll.documentView = table; context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        table.setDraggingSourceOperationMask(pane.isVirtual ? .copy : [.copy, .move], forLocal: false)
        table.setDraggingSourceOperationMask(pane.isVirtual ? .copy : [.copy, .move], forLocal: true)
        table.userInterfaceLayoutDirection = NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight
        coordinator.dateFormatter.locale = NativeLocalization.locale
        for column in table.tableColumns { column.isHidden = column.identifier.rawValue == "selection" ? !SettingsService.shared.preferences.selectionCheckboxes : column.identifier.rawValue != "name" && !SettingsService.shared.visibleColumns.contains(column.identifier.rawValue) }
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = SettingsService.shared.compactRows ? 26 : LayoutSizing.rowHeight(LayoutSizing.level(.details, sizes: SettingsService.shared.layoutSizes))
        coordinator.updating = true
        if coordinator.displayed != items || coordinator.group != pane.group || coordinator.groupAscending != pane.groupAscending || coordinator.groupDateUnit != pane.groupDateUnit || coordinator.iconRevision != model.iconRevision {
            coordinator.iconRevision = model.iconRevision
            coordinator.displayed = items; coordinator.group = pane.group; coordinator.groupAscending = pane.groupAscending; coordinator.groupDateUnit = pane.groupDateUnit; coordinator.rebuildRows(); table.hover.cancel(); table.reloadData()
            if SettingsService.shared.autoFitColumns { coordinator.fitColumns() }
        }
        let indexes = IndexSet(coordinator.rows.indices.filter { row in coordinator.rows[row].item.map { pane.selection.contains($0.url) } ?? false })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
        let key: String
        switch pane.sort { case .originalFolder, .deleted: key = ""; case .name: key = "name"; case .modified: key = "modified"; case .kind: key = "kind"; case .size: key = "size"; case .created: key = "created"; case .tags: key = "tags"; case .path: key = "path"; case .cloud: key = "cloud" }
        if table.sortDescriptors.first?.key != key || table.sortDescriptors.first?.ascending != pane.ascending {
            table.sortDescriptors = [NSSortDescriptor(key: key, ascending: pane.ascending)]
        }
        if let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "selection" }), SettingsService.shared.preferences.selectionCheckboxes {
            let range = table.rows(in: table.visibleRect)
            if range.location != NSNotFound { for row in range.location..<NSMaxRange(range) {
                if let button = table.view(atColumn: column, row: row, makeIfNecessary: false) as? NSButton, let item = coordinator.rowItem(row) { button.state = pane.selection.contains(item.url) ? .on : .off }
            } }
        }
        coordinator.updating = false
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var table: ExplorerTable?
        var displayed: [ListedItem] = []
        var iconRevision = -1
        var groupAscending = true
        var groupDateUnit: GroupDateUnit = .relative
        var group: GroupField = .none
        var rows: [(title: String?, item: ListedItem?)] = []
        func rebuildRows() {
            rows = ItemGrouping.groups(displayed, by: group, ascending: groupAscending, dateUnit: groupDateUnit).flatMap { section in
                (group == .none ? [] : [(title: "\(section.localizedTitle(for: group)) · \(section.items.count)", item: Optional<ListedItem>.none)]) + section.items.map { (title: Optional<String>.none, item: Optional($0)) }
            }
        }
        func fitColumns() {
            guard let table else { return }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
            for column in table.tableColumns where !column.isHidden && column.identifier.rawValue != "selection" {
                var width = (column.title as NSString).size(withAttributes: attributes).width + 36
                for item in displayed.prefix(1000) {
                    let text: String
                    switch column.identifier.rawValue {
                    case "name": text = item.displayName
                    case "modified": text = item.modified.map { FileDisplayFormat.date($0) } ?? "—"
                    case "created": text = item.created.map { FileDisplayFormat.date($0) } ?? "—"
                    case "kind": text = item.localizedKind
                    case "tags": text = item.tags.joined(separator: ", ")
                    case "path": text = item.url.path
                    case "cloud": text = L10n.text(item.cloud.availability.label)
                    default: text = item.sizeLabel
                    }
                    width = max(width, (text as NSString).size(withAttributes: attributes).width + (column.identifier.rawValue == "name" ? 48 : 20))
                }
                column.width = min(500, max(column.minWidth, width))
            }
        }
        func rowItem(_ row: Int) -> ListedItem? { rows.indices.contains(row) ? rows[row].item : nil }
        var updating = false
        var menuActions: [() -> Void] = []
        let dateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter }()
        private var renameObserver: NSObjectProtocol?
        init(_ parent: FileTableView) {
            self.parent = parent; super.init()
            renameObserver = NotificationCenter.default.addObserver(forName: InlineRenameRequest.prepare, object: nil, queue: .main) { [weak self] note in
                guard let self, let request = note.object as? InlineRenameRequest, request.paneID == self.parent.pane.id,
                      let table = self.table, table.window != nil, let row = self.rows.firstIndex(where: { $0.item?.url == request.item.url }),
                      let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return }
                table.scrollRowToVisible(row); _ = table.view(atColumn: column, row: row, makeIfNecessary: true)
            }
        }
        deinit { if let renameObserver { NotificationCenter.default.removeObserver(renameObserver) } }
        func activate() { parent.model.activePaneID = parent.pane.id }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            if let title = rows[row].title { let label = NSTextField(labelWithString: title); label.font = ExplorerFont.native(size: 12, weight: .semibold); return label }
            guard let item = rows[row].item, let column = tableColumn else { return nil }
            let id = column.identifier
            if id.rawValue == "selection" {
                let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheckbox(_:)))
                button.tag = row; button.state = parent.pane.selection.contains(item.url) ? .on : .off
                button.setAccessibilityLabel(L10n.text("Select") + " " + item.displayName)
                return button
            }
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
            if cell.textField == nil {
                cell.identifier = id
                let text = RenameableTextField(frame: .zero); text.font = ExplorerFont.native(size: 12)
                text.lineBreakMode = .byTruncatingMiddle; text.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(text); cell.textField = text
                var leading: CGFloat = 6
                if id.rawValue == "name" {
                    let icon = NSImageView(); icon.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(icon); cell.imageView = icon
                    NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                        icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20)])
                    leading = 38
                }
                NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            switch id.rawValue {
            case "name":
                (cell.textField as? RenameableTextField)?.configure(display: item.displayName, item: item, paneID: parent.pane.id)
                cell.imageView?.image = item.isBrowsable && !item.hasCustomIcon ? FilesArtwork.image("FilesFolder") : item.url.isFileURL ? NSWorkspace.shared.icon(forFile: item.url.path) : NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data)
                cell.imageView?.contentTintColor = nil
            case "modified": cell.textField?.stringValue = item.modified.map { FileDisplayFormat.date($0) } ?? "—"
            case "created": cell.textField?.stringValue = item.created.map { FileDisplayFormat.date($0) } ?? "—"
            case "tags": cell.textField?.stringValue = item.tags.joined(separator: ", ")
            case "path": cell.textField?.stringValue = item.url.path
            case "kind": cell.textField?.stringValue = item.localizedKind
            case "cloud": cell.textField?.stringValue = L10n.text(item.cloud.availability.label); cell.toolTip = L10n.text(item.cloud.detail)
            default: cell.textField?.stringValue = item.sizeLabel; cell.textField?.alignment = .right
            }
            cell.textField?.textColor = id.rawValue == "name" ? .labelColor : .secondaryLabelColor
            cell.alphaValue = item.isHidden ? 0.55 : 1
            cell.toolTip = id.rawValue == "cloud" ? item.cloud.detail : item.url.path
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            parent.pane.selection = Set(table.selectedRowIndexes.compactMap { rowItem($0)?.url })
            if let row = table.selectedRowIndexes.first { parent.pane.focusedItemURL = rowItem(row)?.url }
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating, let descriptor = tableView.sortDescriptors.first else { return }
            switch descriptor.key {
            case "modified": parent.pane.sort = .modified
            case "created": parent.pane.sort = .created
            case "tags": parent.pane.sort = .tags
            case "path": parent.pane.sort = .path
            case "cloud": parent.pane.sort = .cloud
            case "kind": parent.pane.sort = .kind
            case "size": parent.pane.sort = .size
            default: parent.pane.sort = .name
            }
            parent.pane.ascending = descriptor.ascending
        }
        @objc func toggleCheckbox(_ sender: NSButton) {
            guard let item = rowItem(sender.tag) else { return }; activate(); parent.pane.focusedItemURL = item.url
            if sender.state == .on { parent.pane.selection.insert(item.url) } else { parent.pane.selection.remove(item.url) }
        }
        @objc func singleClickItem() {
            guard let table, let item = rowItem(table.clickedRow), NSApp.currentEvent?.type == .leftMouseUp,
                  NSApp.currentEvent?.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty == true,
                  SettingsService.shared.preferences.opensOnSingleClick(directory: item.isBrowsable) else { return }
            activate(); parent.model.open(item, pane: parent.pane)
        }
        @objc func openItem() {
            guard let table, let item = rowItem(table.clickedRow) else { return }
            activate(); parent.model.open(item, pane: parent.pane)
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            rowItem(row).flatMap { FileDrag.writer($0, pane: parent.pane) }
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {

            guard !parent.model.busy, !parent.pane.isVirtual || parent.pane.virtualPaste != nil else { return [] }
            if operation != .on || rowItem(row)?.isBrowsable != true {
                tableView.setDropRow(-1, dropOperation: .on)
            }
            return FileDrag.operation(info.draggingPasteboard, mask: info.draggingSourceOperationMask)
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let destination = dropOperation == .on && rowItem(row)?.isBrowsable == true ? rowItem(row)?.url : parent.pane.operationDirectory
            return FileDrag.accept(info, model: parent.model, pane: parent.pane, destination: destination)
        }
        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows.indices.contains(row) && rows[row].title != nil }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rowItem(row) != nil }
        func menu(_ row: Int) -> NSMenu {
            menuActions = []; let menu = NSMenu()
            func add(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
                guard !SettingsService.shared.preferences.hiddenContextActions.contains(title) else { return }
                let item = NSMenuItem(title: L10n.text(title), action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self; item.tag = menuActions.count; item.isEnabled = enabled
                menuActions.append(action); menu.addItem(item)
            }
            menu.autoenablesItems = false
            let model = parent.model
            if parent.pane.isVirtual {
                for action: ExplorerAction in [.cut, .copy, .paste, .rename, .trash, .properties, .quickLook, .share, .openWith] {
                    add(parent.pane.actionTitle(action), enabled: model.canExecute(action, in: parent.pane)) { model.execute(action) }
                }
                menu.addItem(.separator()); add("New folder…", enabled: model.canExecute(.new)) { model.create(directory: true) }
                add("Refresh") { self.parent.pane.refresh() }; return menu
            }
            if let item = rows.isEmpty ? (displayed.indices.contains(row) ? displayed[row] : nil) : rowItem(row) {
                add("Open") { model.openSelection() }
                if item.isBrowsable {
                    add("Open in new tab") { model.newTab(item.url) }
                    add("Open in new window") { self.parent.openWindow(id: "folder", value: item.url) }
                    add("Open in other pane") { model.openOtherPane(item.url) }
                    add("PasteItemToSelectionDescription", enabled: !model.busy && model.canPaste) { model.paste(destination: item.url) }
                    add("Flatten folder…", enabled: !model.busy) { model.flatten() }
                    add("Pin to sidebar") { SettingsService.shared.pin(item.url) }
                }
                add("Quick Look") { model.quickLook() }
                add("Open with…") { model.openWith() }
                add("Share…") { model.share() }
                add("Make alias…", enabled: parent.pane.selection.count == 1) { model.makeAlias() }
                if item.isPackage { add("Show package contents") { self.parent.pane.navigate(item.url) } }
                menu.addItem(.separator())
                add("Cut") { model.copy(cut: true) }; add("Copy") { model.copy() }; add("Copy path") { model.copyPath() }
                add("CreateFolderWithSelection", enabled: !model.busy) { model.createFolderWithSelection() }
                add("Duplicate", enabled: !model.busy) { model.duplicate() }
                add("Rename…", enabled: !model.busy) { model.rename() }
                add("Compress…", enabled: !model.busy) { model.present(.compress) }
                if MediaService.isImage(item.url) {
                    add("Rotate left", enabled: !model.busy) { model.rotateImages(clockwise: false) }
                    add("Rotate right", enabled: !model.busy) { model.rotateImages(clockwise: true) }
                    add("Set as wallpaper", enabled: parent.pane.selection.count == 1) { model.setWallpaper() }
                }
                if MediaService.isEditable(item.url) { add("Edit media metadata…", enabled: parent.pane.selection.count == 1 && !model.busy) { model.present(.mediaMetadata) } }
                add("Edit tags…") { model.present(.tags) }
                add("Calculate hashes…", enabled: !item.isBrowsable && parent.pane.selection.count == 1) { model.present(.hashes) }
                add("Extended attributes…", enabled: parent.pane.selection.count == 1) { model.present(.attributes) }
                add("Add to shelf") { ShelfStore.shared.add(model.activePane.selectedItems.map(\.url)) }
                add("Permissions…") { model.present(.permissions) }
                menu.addItem(.separator())
                add("Move to Trash…", enabled: !model.busy) { model.trash() }
                menu.addItem(.separator())
                add("Properties") { model.present(.properties) }
                if item.cloud.isCloud {
                    add("Cloud status…") { model.present(.cloud) }
                    add("Download", enabled: !item.isDirectory && !model.busy) { model.downloadCloudSelection() }
                }
                add("Reveal in Finder") { model.reveal() }
            } else {
                add("New folder…", enabled: !model.busy) { model.create(directory: true) }
                add("New text file…", enabled: !model.busy) { model.create(directory: false) }
                add("Paste", enabled: model.canPaste) { model.paste() }
                menu.addItem(.separator()); add("Open in Terminal") { model.terminal() }
                add("Refresh") { self.parent.pane.refresh() }
            }
            return menu
        }
        @objc func menuAction(_ sender: NSMenuItem) { if menuActions.indices.contains(sender.tag) { menuActions[sender.tag]() } }
    }
}
