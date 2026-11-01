import SwiftUI
import AppKit
import FilesShared
import FilesStorage

struct SharedFileLayout: View {
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    var body: some View {
        FileDropSurface(model: model, pane: pane) {
          Group {
            if pane.effectiveLayout == .details { FileTableView(pane: pane, model: model, items: pane.visibleItems) }
            else if pane.effectiveLayout == .columns { ColumnsLayout(model: model, pane: pane) }
            else if pane.effectiveLayout == .gallery { GalleryLayout(model: model, pane: pane) }
            else { NativeIconGrid(model: model, pane: pane, items: pane.visibleItems) }
          }
        }.onChange(of: pane.selection) { if pane.isVirtual { pane.synchronizeVirtualSelection() } }
    }
}

struct FilePreview: View {
    let item: ListedItem
    @ObservedObject var pane: ShellPageViewModel
    @State private var url: URL?
    @State private var error: String?
    var body: some View {
        Group {
            if let url { QuickLookView(url: url) }
            else if let error { Text(L10n.text(error)).font(.caption).foregroundStyle(.secondary).padding() }
            else { ProgressView() }
        }.task(id: item.url) {
            url = nil; error = nil
            do {
                if item.url.isFileURL { url = item.url; return }
                guard let reference = pane.reference(item) else { return }
                let folder = try ClipboardStaging.create()
                let file = try await reference.materialize(in: folder)
                try Task.checkCancellation(); url = file
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct FileDropSurface<Content: View>: NSViewRepresentable {
    let model: MainPageViewModel
    let pane: ShellPageViewModel
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction
    @ViewBuilder let content: () -> Content
    private func rendered() -> AnyView { AnyView(content().environment(\.locale, locale).environment(\.layoutDirection, direction)) }
    func makeNSView(context: Context) -> FileDropHost<Content> { FileDropHost(root: rendered()) }
    func updateNSView(_ view: FileDropHost<Content>, context: Context) { view.host.rootView = rendered(); view.model = model; view.pane = pane }
}
final class FileDropHost<Content: View>: NSView {
    let host: NSHostingView<AnyView>
    var model: MainPageViewModel?
    var pane: ShellPageViewModel?
    init(root: AnyView) {
        host = NSHostingView(rootView: root); super.init(frame: .zero); registerForDraggedTypes(FileDrag.types)
        host.translatesAutoresizingMaskIntoConstraints = false; addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor), host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model, let pane, !model.busy, !pane.isVirtual || pane.virtualPaste != nil else { return [] }; return FileDrag.operation(sender.draggingPasteboard, mask: sender.draggingSourceOperationMask)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model, let pane else { return false }
        return FileDrag.accept(sender, model: model, pane: pane, destination: pane.columnDirectory)
    }
}
