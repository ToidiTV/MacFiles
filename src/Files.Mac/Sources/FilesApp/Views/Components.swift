import SwiftUI
import AppKit
import Quartz
import QuickLookThumbnailing
import FilesShared
import UniformTypeIdentifiers

enum Palette {
    static let nativeSurface = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.153, green: 0.153, blue: 0.153, alpha: 1) : .white
    }
    static let nativeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.125, green: 0.125, blue: 0.125, alpha: 1) : NSColor(srgbRed: 0.953, green: 0.953, blue: 0.953, alpha: 1)
    }
    @MainActor static var accent: Color { color(SettingsService.shared.accentHex) ?? Color(red: 0.04, green: 0.43, blue: 0.88) }
    @MainActor static var background: Color { (color(SettingsService.shared.backgroundHex) ?? Color(nsColor: nativeBackground)).opacity(SettingsService.shared.preferences.backdrop == "Solid" ? 1 : 0.65) }
    static func color(_ hex: String) -> Color? {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard [6, 8].contains(normalized.count), let value = UInt32(normalized, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: normalized.count == 8 ? Double((value >> 24) & 255) / 255 : 1)
    }
    static let surface = Color(nsColor: nativeSurface)
    static let line = Color.primary.opacity(0.09)
    static let folder = Color(red: 0.98, green: 0.73, blue: 0.19)
}

struct ToolButton: View {
    let symbol: String
    let help: String
    var enabled = true
    var active = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(ExplorerFont.font(size: 14, weight: .regular))
                .foregroundStyle(active ? Palette.accent : Color.primary.opacity(enabled ? 0.8 : 0.25))
                .frame(width: 31, height: 30)
                .background(active ? Palette.accent.opacity(0.1) : hover ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).disabled(!enabled).help(L10n.text(help)).accessibilityLabel(L10n.text(help))
        .onHover { hover = $0 }
    }
}

@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    let images = NSCache<NSString, NSImage>()
    init() { images.countLimit = 400 }
    func image(for key: NSString) -> NSImage? { SettingsService.shared.preferences.cacheThumbnails ? images.object(forKey: key) : nil }
    func store(_ image: NSImage, for key: NSString) {
        guard SettingsService.shared.preferences.cacheThumbnails else { images.removeAllObjects(); return }
        images.totalCostLimit = SettingsService.shared.preferences.thumbnailCacheMB * 1024 * 1024
        let cost = image.representations.reduce(0) { $0 + max(1, $1.pixelsWide) * max(1, $1.pixelsHigh) * 4 }
        images.setObject(image, forKey: key, cost: cost)
    }
    func clear() { images.removeAllObjects() }
}

struct FileIcon: View {
    @ObservedObject private var settings = SettingsService.shared
    let item: ListedItem
    var size: CGFloat = 20
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if item.isBrowsable && !item.hasCustomIcon {
                Image(systemName: "folder.fill").resizable().scaledToFit().foregroundStyle(Palette.folder.gradient)
                    .padding(size > 30 ? 4 : 0)
            } else {
                Image(nsImage: item.hasCustomIcon ? NSWorkspace.shared.icon(forFile: item.url.path) : (settings.preferences.showThumbnails ? thumbnail : nil) ?? (item.url.isFileURL ? NSWorkspace.shared.icon(forFile: item.url.path) : NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data))).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomLeading) {
            if item.isSymbolicLink { Image(systemName: "arrow.turn.up.right").font(ExplorerFont.font(size: size > 30 ? 14 : 8, weight: .bold)).foregroundStyle(.primary).background(.background, in: Circle()) }
        }
        .overlay(alignment: .topTrailing) {
            if item.cloud.isCloud && size > 30 { Image(systemName: item.cloud.availability.symbol).font(ExplorerFont.font(size: 14)).foregroundStyle(Palette.accent).padding(2).background(.background, in: Circle()).help(L10n.text(item.cloud.detail)) }
        }
        .task(id: "\(item.url.path)-\(item.modified?.timeIntervalSince1970 ?? 0)-\(size)-\(settings.preferences.showThumbnails)") {
            guard SettingsService.shared.preferences.showThumbnails, item.url.isFileURL, size > 30, !item.isBrowsable, !item.hasCustomIcon, item.cloud.canPreview else { return }
            let key = "\(item.url.path):\(item.modified?.timeIntervalSince1970 ?? 0)" as NSString
            if let cached = ThumbnailCache.shared.image(for: key) { thumbnail = cached; return }
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 160, height: 160), scale: 2, representationTypes: .all)
            if let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request), !Task.isCancelled {
                thumbnail = result.nsImage; ThumbnailCache.shared.store(result.nsImage, for: key)
            }
        }
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) != url as NSURL { view.previewItem = url as NSURL }
    }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

@MainActor final class PreviewController {
    static let shared = PreviewController()
    private var window: NSWindow?
    func show(_ urls: [URL]) {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.center(); window = panel
        }
        window?.title = L10n.text("Quick Look")
        window?.contentView = NSHostingView(rootView: PreviewGallery(urls: urls))
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PreviewGallery: View {
    let urls: [URL]
    @State private var index = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(urls[index].lastPathComponent).font(.headline)
                Spacer()
                if urls.count > 1 {
                    Button { index = max(0, index - 1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                    Text(L10n.text("\(index + 1) / \(urls.count)")).foregroundStyle(.secondary)
                    Button { index = min(urls.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }.disabled(index == urls.count - 1)
                }
                Button(L10n.text("Open")) { NSWorkspace.shared.open(urls[index]) }
            }.padding(12)
            Divider()
            QuickLookView(url: urls[index])
        }.frame(minWidth: 450, minHeight: 320)
    }
}

struct ItemContextMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: MainPageViewModel
    @ObservedObject var pane: ShellPageViewModel
    let item: ListedItem?
    private func activate() {
        model.activePaneID = pane.id
        if let item, !pane.selection.contains(item.url) {
            if pane.layout == .columns { pane.columnItems = [item]; pane.columnDirectory = item.url.deletingLastPathComponent() }
            pane.selection = [item.url]
        }
    }
    var body: some View {
        if pane.isVirtual {
            ForEach([ExplorerAction.cut, .copy, .paste, .rename, .trash, .properties, .quickLook, .share, .openWith]) { action in
                Button(L10n.text(pane.actionTitle(action))) { activate(); model.execute(action) }.disabled(!model.canExecute(action, in: pane))
            }
        } else if let item {
            Button(L10n.text("Open")) { activate(); model.openSelection() }
            if item.isBrowsable {
                Button(L10n.text("Open in new window")) { openWindow(id: "folder", value: item.url) }
                Button(L10n.text("Open in new tab")) { model.newTab(item.url) }
                Button(L10n.text("Open in other pane")) { model.openOtherPane(item.url) }
                Button(L10n.text("PasteItemToSelectionDescription")) { activate(); model.paste(destination: item.url) }.disabled(model.busy || !model.canPaste)
                Button(L10n.text("Flatten folder…")) { activate(); model.flatten() }.disabled(model.busy)
                Button(L10n.text("Pin to sidebar")) { SettingsService.shared.pin(item.url) }
            }
            Button(L10n.text("Quick Look")) { activate(); model.quickLook() }
            Button(L10n.text("Open with…")) { activate(); model.openWith() }
            Button(L10n.text("Share…")) { activate(); model.share() }
            Button(L10n.text("Make alias…")) { activate(); model.makeAlias() }
            if item.isPackage { Button(L10n.text("Show package contents")) { pane.navigate(item.url) } }
            Divider()
            Button(L10n.text("Cut")) { activate(); model.copy(cut: true) }
            Button(L10n.text("Copy")) { activate(); model.copy() }
            Button(L10n.text("Copy path")) { activate(); model.copyPath() }
            Button(L10n.text("Duplicate")) { activate(); model.duplicate() }.disabled(model.busy)
            Button(L10n.text("Rename…")) { activate(); model.rename() }.disabled(model.busy)
            Button(L10n.text("Compress…")) { activate(); model.present(.compress) }.disabled(model.busy)
            Button(L10n.text("Edit tags…")) { activate(); model.present(.tags) }
            Button(L10n.text("Calculate hashes…")) { activate(); model.present(.hashes) }.disabled(item.isBrowsable)
            Button(L10n.text("Extended attributes…")) { activate(); model.present(.attributes) }
            Button(L10n.text("Add to shelf")) { activate(); ShelfStore.shared.add(model.activePane.selectedItems.map(\.url)) }
            Button(L10n.text("Permissions…")) { activate(); model.present(.permissions) }
            Divider()
            Button(L10n.text("Move to Trash…")) { activate(); model.trash() }.disabled(model.busy)
            Divider()
            Button(L10n.text("Properties")) { activate(); model.present(.properties) }
            if item.cloud.isCloud { Button(L10n.text("Cloud status…")) { activate(); model.present(.cloud) }; Button(L10n.text("Download")) { activate(); model.downloadCloudSelection() }.disabled(item.isDirectory || model.busy) }
            Button(L10n.text("Reveal in Finder")) { activate(); model.reveal() }
        } else {
            Button(L10n.text("New folder…")) { activate(); model.create(directory: true) }.disabled(model.busy)
            Button(L10n.text("New text file…")) { activate(); model.create(directory: false) }.disabled(model.busy)
            Button(L10n.text("Paste")) { activate(); model.paste() }.disabled(model.busy || !model.canPaste)
            Divider()
            Button(L10n.text("Open in Terminal")) { activate(); model.terminal() }
            Button(L10n.text("Pin this folder")) { if let url = pane.location { SettingsService.shared.pin(url) } }
            Button(L10n.text("Refresh")) { pane.refresh() }
        }
    }
}
