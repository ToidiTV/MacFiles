import AppKit
import SwiftUI
import QuickLookThumbnailing
import FilesShared
import UniformTypeIdentifiers

final class ExplorerCollection: NSCollectionView, NSGestureRecognizerDelegate {
    var openItem: ((IndexPath) -> Void)?
    var activate: (() -> Void)?
    var hoverItem: ((IndexPath) -> Void)?
    var singleOpen: ((IndexPath) -> Void)?
    var goUp: (() -> Void)?
    var dragged = false
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard SettingsService.shared.preferences.singleClickFiles || SettingsService.shared.preferences.singleClickFolders else { return false }
        return !(hitTest(convert(event.locationInWindow, from: nil)) is NSButton)
    }
    @objc func singleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, let index = indexPathForItem(at: recognizer.location(in: self)),
              NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
        singleOpen?(index)
    }
    let hover = HoverSelection()
    override func updateTrackingAreas() { super.updateTrackingAreas(); hover.track(self) }
    override func mouseMoved(with event: NSEvent) {
        let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        hover.schedule { [weak self] in if let self, let index, self.item(at: index) != nil { self.hoverItem?(index) } }
    }
    override func mouseExited(with event: NSEvent) { hover.cancel() }
    var itemMenu: ((IndexPath?) -> NSMenu)?
    override func mouseDown(with event: NSEvent) {
        hover.cancel(); dragged = false; activate?()
        let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        if index == nil, event.clickCount == 2, SettingsService.shared.preferences.doubleClickUp { goUp?(); return }
        super.mouseDown(with: event)
        if event.clickCount == 2, let index { openItem?(index) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        activate?()
        let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        if let index, !selectionIndexPaths.contains(index) { selectionIndexPaths = [index] }
        return itemMenu?(index)
    }
}

final class ExplorerIconContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { let hit = super.hitTest(point); return hit is NSButton ? hit : hit == nil ? nil : self }
}

final class ExplorerIconItem: NSCollectionViewItem {
    private var representedURL: URL?
    private var itemConstraints: [NSLayoutConstraint] = []
    private let cloudBadge = NSImageView()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    var toggleSelection: ((Bool) -> Void)?
    @objc private func toggleCheckbox() { toggleSelection?(checkbox.state == .on) }
    override var isSelected: Bool { didSet { updateSelection() } }
    override func loadView() {
        let container = ExplorerIconContentView(); container.wantsLayer = true; container.layer?.cornerRadius = 7
        view = container
        let icon = NSImageView(); icon.imageScaling = .scaleProportionallyUpOrDown; icon.translatesAutoresizingMaskIntoConstraints = false
        let text = RenameableTextField(frame: .zero); text.alignment = .center; text.font = ExplorerFont.native(size: 12)
        text.isSelectable = false; text.maximumNumberOfLines = 2; text.lineBreakMode = .byTruncatingMiddle; text.translatesAutoresizingMaskIntoConstraints = false
        cloudBadge.translatesAutoresizingMaskIntoConstraints = false; cloudBadge.contentTintColor = .controlAccentColor
        container.addSubview(icon); container.addSubview(text); container.addSubview(cloudBadge); imageView = icon; textField = text
        checkbox.target = self; checkbox.action = #selector(toggleCheckbox); checkbox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checkbox)
        NSLayoutConstraint.activate([checkbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 3), checkbox.topAnchor.constraint(equalTo: container.topAnchor, constant: 3)])
    }
    private func arrange(_ layout: LayoutMode) {
        guard let icon = imageView, let text = textField else { return }
        NSLayoutConstraint.deactivate(itemConstraints)
        let size = layout == .list ? LayoutSizing.rowHeight(LayoutSizing.level(layout, sizes: SettingsService.shared.layoutSizes)) - 10 : layout == .tiles ? Double([32, 48, 64, 80][LayoutSizing.level(layout, sizes: SettingsService.shared.layoutSizes)]) : layout.iconSize
        itemConstraints = [icon.widthAnchor.constraint(equalToConstant: size), icon.heightAnchor.constraint(equalToConstant: size), cloudBadge.widthAnchor.constraint(equalToConstant: 16), cloudBadge.heightAnchor.constraint(equalToConstant: 16), cloudBadge.trailingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 3), cloudBadge.bottomAnchor.constraint(equalTo: icon.bottomAnchor)]
        if layout.horizontal {
            text.alignment = .natural; text.maximumNumberOfLines = layout == .tiles ? 3 : 1
            itemConstraints += [icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsService.shared.preferences.selectionCheckboxes ? 30 : 8), icon.centerYAnchor.constraint(equalTo: view.centerYAnchor), text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: view.centerYAnchor)]
        } else {
            text.alignment = .center; text.maximumNumberOfLines = 2
            itemConstraints += [icon.topAnchor.constraint(equalTo: view.topAnchor, constant: 10), icon.centerXAnchor.constraint(equalTo: view.centerXAnchor), text.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8), text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5), text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5), text.heightAnchor.constraint(equalToConstant: 34)]
        }
        NSLayoutConstraint.activate(itemConstraints)
    }
    func configure(_ item: ListedItem, layout: LayoutMode, paneID: UUID) {
        view.userInterfaceLayoutDirection = NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight
        checkbox.isHidden = !SettingsService.shared.preferences.selectionCheckboxes
        checkbox.setAccessibilityLabel(L10n.text("Select") + " " + item.displayName)
        arrange(layout)
        representedURL = item.url; (textField as? RenameableTextField)?.configure(display: layout == .tiles ? "\(item.displayName)\n\(item.localizedKind) · \(item.sizeLabel)" : item.displayName, item: item, paneID: paneID); view.toolTip = item.url.path
        imageView?.image = item.isBrowsable && !item.hasCustomIcon ? FilesArtwork.image("FilesFolder") : item.url.isFileURL ? NSWorkspace.shared.icon(forFile: item.url.path) : NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data)
        if !item.isDirectory && UTType(filenameExtension: item.url.pathExtension)?.conforms(to: .plainText) == true { imageView?.image = FilesArtwork.documentImage }
        imageView?.contentTintColor = nil
        view.alphaValue = item.isHidden ? 0.55 : 1
        cloudBadge.image = item.cloud.isCloud ? NSImage(systemSymbolName: item.cloud.availability.symbol, accessibilityDescription: L10n.text(item.cloud.availability.label)) : nil
        cloudBadge.toolTip = L10n.text(item.cloud.detail)
        updateSelection()
        guard UTType(filenameExtension: item.url.pathExtension)?.conforms(to: .plainText) != true, SettingsService.shared.preferences.showThumbnails, item.url.isFileURL, !item.isBrowsable, !item.hasCustomIcon, item.cloud.canPreview else { return }
        let key = "\(item.url.path):\(item.modified?.timeIntervalSince1970 ?? 0):\(layout.iconSize)" as NSString
        if let image = ThumbnailCache.shared.image(for: key) { imageView?.image = image; return }
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: NSSize(width: max(140, layout.iconSize), height: max(140, layout.iconSize)), scale: 2, representationTypes: .all)
        Task { [weak self] in
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                ThumbnailCache.shared.store(thumbnail.nsImage, for: key)
                if self?.representedURL == item.url, SettingsService.shared.preferences.showThumbnails { self?.imageView?.image = thumbnail.nsImage }
            }
        }
    }
    private func updateSelection() {
        checkbox.state = isSelected ? .on : .off
        view.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor
        view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        view.layer?.borderWidth = isSelected ? 1.5 : 0
    }
}

final class ExplorerGroupHeader: NSView {
    let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame); label.font = .boldSystemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
}

struct NativeIconGrid: NSViewRepresentable {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    let items: [ListedItem]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let collection = ExplorerCollection(); collection.backgroundColors = [Palette.nativeSurface]
        let layout = NSCollectionViewFlowLayout(); layout.itemSize = NSSize(width: 125, height: 132)
        layout.minimumInteritemSpacing = 8; layout.minimumLineSpacing = 8; layout.sectionInset = NSEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        collection.collectionViewLayout = layout
        collection.register(ExplorerIconItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("File"))
        collection.register(ExplorerGroupHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("Header"))
        let click = NSClickGestureRecognizer(target: collection, action: #selector(ExplorerCollection.singleClick(_:)))
        click.delegate = collection
        click.numberOfClicksRequired = 1; click.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(click)
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.delegate = context.coordinator; collection.dataSource = context.coordinator
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collection.registerForDraggedTypes(FileDrag.types)
        collection.activate = { [weak coordinator = context.coordinator] in coordinator?.parent.model.activePaneID = coordinator?.parent.pane.id ?? UUID() }
        collection.openItem = { [weak coordinator = context.coordinator] index in
            guard let coordinator, let item = coordinator.item(at: index) else { return }
            coordinator.parent.model.open(item, pane: coordinator.parent.pane)
        }
        collection.hoverItem = { [weak coordinator = context.coordinator] index in
            guard let coordinator, let item = coordinator.item(at: index) else { return }
            coordinator.parent.model.activePaneID = coordinator.parent.pane.id
            coordinator.parent.pane.focusedItemURL = item.url; coordinator.parent.pane.selection = [item.url]
        }
        collection.singleOpen = { [weak coordinator = context.coordinator] index in
            guard let coordinator, let item = coordinator.item(at: index), SettingsService.shared.preferences.opensOnSingleClick(directory: item.isBrowsable) else { return }
            coordinator.parent.model.open(item, pane: coordinator.parent.pane)
        }
        collection.goUp = { [weak coordinator = context.coordinator] in coordinator?.parent.pane.up() }
        collection.itemMenu = { [weak coordinator = context.coordinator] index in coordinator?.menu(index) ?? NSMenu() }
        context.coordinator.collection = collection; scroll.documentView = collection
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.collection?.isSelectable = context.environment.isEnabled
        context.coordinator.collection?.userInterfaceLayoutDirection = NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight
        context.coordinator.collection?.setDraggingSourceOperationMask(pane.isVirtual ? .copy : [.copy, .move], forLocal: false)
        context.coordinator.collection?.setDraggingSourceOperationMask(pane.isVirtual ? .copy : [.copy, .move], forLocal: true)
        let coordinator = context.coordinator; coordinator.parent = self
        guard coordinator.collection?.dragged != true else { return }
        coordinator.updating = true
        if coordinator.displayed != items || coordinator.iconRevision != model.iconRevision || coordinator.group != pane.group || coordinator.groupAscending != pane.groupAscending || coordinator.groupDateUnit != pane.groupDateUnit || coordinator.layout != pane.effectiveLayout {
            coordinator.iconRevision = model.iconRevision; coordinator.displayed = items; coordinator.group = pane.group; coordinator.groupAscending = pane.groupAscending; coordinator.groupDateUnit = pane.groupDateUnit; coordinator.layout = pane.effectiveLayout
            coordinator.groups = ItemGrouping.groups(items, by: pane.group, ascending: pane.groupAscending, dateUnit: pane.groupDateUnit)
            if let flow = coordinator.collection?.collectionViewLayout as? NSCollectionViewFlowLayout {
                flow.itemSize = NSSize(width: pane.effectiveLayout.cellWidth, height: pane.effectiveLayout == .list ? LayoutSizing.rowHeight(LayoutSizing.level(.list, sizes: SettingsService.shared.layoutSizes)) : pane.effectiveLayout == .tiles ? Double([64, 78, 96, 112][LayoutSizing.level(.tiles, sizes: SettingsService.shared.layoutSizes)]) : pane.effectiveLayout.cellHeight)
                flow.headerReferenceSize = pane.group == .none ? .zero : NSSize(width: 100, height: 32)
                flow.invalidateLayout()
            }
            coordinator.collection?.hover.cancel(); coordinator.collection?.reloadData()
        }
        let selected = Set(coordinator.groups.enumerated().flatMap { section, group in group.items.enumerated().compactMap { index, item in pane.selection.contains(item.url) ? IndexPath(item: index, section: section) : nil } })
        if coordinator.collection?.selectionIndexPaths != selected { coordinator.collection?.selectionIndexPaths = selected }
        coordinator.updating = false
    }
    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: NativeIconGrid
        var displayed: [ListedItem] = []
        var iconRevision = -1
        var groups: [ItemGroup] = []
        var groupAscending = true
        var groupDateUnit: GroupDateUnit = .relative
        var group = GroupField.none
        var layout = LayoutMode.icons
        weak var collection: ExplorerCollection?
        var updating = false
        var menuCoordinator: FileTableView.Coordinator?
        private var renameObserver: NSObjectProtocol?
        init(_ parent: NativeIconGrid) {
            self.parent = parent; super.init()
            renameObserver = NotificationCenter.default.addObserver(forName: InlineRenameRequest.prepare, object: nil, queue: .main) { [weak self] note in
                guard let self, let request = note.object as? InlineRenameRequest, request.paneID == self.parent.pane.id, let collection = self.collection, collection.window != nil else { return }
                for (section, group) in self.groups.enumerated() {
                    if let index = group.items.firstIndex(where: { $0.url == request.item.url }) {
                        collection.scrollToItems(at: [IndexPath(item: index, section: section)], scrollPosition: .nearestVerticalEdge)
                        collection.layoutSubtreeIfNeeded(); break
                    }
                }
            }
        }
        deinit { if let renameObserver { NotificationCenter.default.removeObserver(renameObserver) } }
        func numberOfSections(in collectionView: NSCollectionView) -> Int { groups.count }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { groups[section].items.count }
        func item(at index: IndexPath) -> ListedItem? { groups.indices.contains(index.section) && groups[index.section].items.indices.contains(index.item) ? groups[index.section].items[index.item] : nil }
        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
            let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("Header"), for: indexPath) as! ExplorerGroupHeader
            view.userInterfaceLayoutDirection = NativeLocalization.isRightToLeft ? .rightToLeft : .leftToRight
            view.label.stringValue = "\(groups[indexPath.section].localizedTitle(for: group)) · \(groups[indexPath.section].items.count)"; return view
        }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("File"), for: indexPath) as! ExplorerIconItem
            if let item = item(at: indexPath) {
                cell.configure(item, layout: layout, paneID: parent.pane.id)
                cell.toggleSelection = { [weak self] selected in
                    guard let self else { return }; self.parent.model.activePaneID = self.parent.pane.id; self.parent.pane.focusedItemURL = item.url
                    if selected { self.parent.pane.selection.insert(item.url) } else { self.parent.pane.selection.remove(item.url) }
                }
            }; return cell
        }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { if let index = indexPaths.sorted().first { parent.pane.focusedItemURL = item(at: index)?.url }; updateSelection() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateSelection() }
        func updateSelection() {
            guard !updating, let collection else { return }
            parent.pane.selection = Set(collection.selectionIndexPaths.compactMap { item(at: $0)?.url })
        }
        func menu(_ index: IndexPath?) -> NSMenu {
            let row = index.flatMap { item(at: $0) }.flatMap { displayed.firstIndex(of: $0) } ?? -1
            updateSelection()
            let coordinator = FileTableView.Coordinator(FileTableView(pane: parent.pane, model: parent.model, items: displayed))
            coordinator.displayed = displayed; menuCoordinator = coordinator
            return coordinator.menu(row)
        }
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { item(at: indexPath).flatMap { FileDrag.writer($0, pane: parent.pane) } }
        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
            (collectionView as? ExplorerCollection)?.dragged = true
        }
        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
            (collectionView as? ExplorerCollection)?.dragged = false
            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                self.updating = true; collectionView.reloadData()
                collectionView.selectionIndexPaths = Set(self.groups.enumerated().flatMap { section, group in group.items.enumerated().compactMap { index, item in self.parent.pane.selection.contains(item.url) ? IndexPath(item: index, section: section) : nil } })
                self.updating = false; self.parent.pane.objectWillChange.send()
            }
        }
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard !parent.model.busy, !parent.pane.isVirtual || parent.pane.virtualPaste != nil else { return [] }
            let point = collectionView.convert(draggingInfo.draggingLocation, from: nil)
            if let target = collectionView.indexPathForItem(at: point), item(at: target)?.isBrowsable == true {
                proposedIndexPath.pointee = target as NSIndexPath; dropOperation.pointee = .on
            } else { dropOperation.pointee = .before }
            return FileDrag.operation(draggingInfo.draggingPasteboard, mask: draggingInfo.draggingSourceOperationMask)
        }
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            let item = item(at: indexPath)
            let target = dropOperation == .on && item?.isBrowsable == true ? item?.url : parent.pane.operationDirectory
            return FileDrag.accept(draggingInfo, model: parent.model, pane: parent.pane, destination: target)
        }
    }
}
