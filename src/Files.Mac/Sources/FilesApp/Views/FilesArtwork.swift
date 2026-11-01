import SwiftUI
import AppKit

struct FilesArtwork: View {
    let symbol: String
    static func image(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
    static let documentImage = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
        let page = NSBezierPath(); page.move(to: NSPoint(x: 12, y: 2)); page.line(to: NSPoint(x: 52, y: 2)); page.line(to: NSPoint(x: 52, y: 47)); page.line(to: NSPoint(x: 37, y: 62)); page.line(to: NSPoint(x: 12, y: 62)); page.close()
        NSColor.white.setFill(); page.fill(); NSColor.gray.setStroke(); page.lineWidth = 0.8; page.stroke()
        let fold = NSBezierPath(); fold.move(to: NSPoint(x: 37, y: 62)); fold.line(to: NSPoint(x: 37, y: 47)); fold.line(to: NSPoint(x: 52, y: 47)); fold.lineWidth = 0.8; fold.stroke()
        NSColor(srgbRed: 0.83, green: 0.83, blue: 0.83, alpha: 1).setStroke()
        for y in stride(from: 10, through: 42, by: 4) { let line = NSBezierPath(); line.move(to: NSPoint(x: 16, y: y)); line.line(to: NSPoint(x: 48, y: y)); line.lineWidth = 0.5; line.stroke() }
        return true
    }
    private var resource: String? {
        switch symbol {
        case "house": return "FilesHome"
        case "folder", "folder.fill": return "FilesFolder"
        case "internaldrive", "externaldrive": return "FilesDrives"
        case "icloud": return "FilesCloudDrives"
        case "network": return "FilesNetwork"
        case "tag": return "FilesTags"
        case "books.vertical": return "FilesLibraries"
        default: return nil
        }
    }
    private var color: Color {
        switch symbol {
        case "arrow.down.circle": return Color(red: 0.05, green: 0.67, blue: 0.56)
        case "music.note": return Color(red: 0.87, green: 0.42, blue: 0.43)
        case "doc.text": return Color(red: 0.42, green: 0.58, blue: 0.72)
        default: return Palette.accent
        }
    }
    var body: some View {
        if let resource, let image = Self.image(resource) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(color)
        }
    }
}

struct FilesWindowButtons: View {
    var body: some View {
        HStack(spacing: 0) {
            FilesCaptionButton(symbol: "minus", title: "Minimize") { NSApp.keyWindow?.miniaturize(nil) }
            FilesCaptionButton(symbol: "square", title: "Zoom") { NSApp.keyWindow?.zoom(nil) }
            FilesCaptionButton(symbol: "xmark", title: "Close window", close: true) { NSApp.keyWindow?.performClose(nil) }
        }
    }
}
private struct FilesCaptionButton: View {
    let symbol: String
    let title: String
    var close = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .regular))
                .frame(width: 46, height: 32)
                .foregroundStyle(hover && close ? Color.white : Color.primary)
                .background(hover ? close ? Color.red : Color.primary.opacity(0.07) : Color.clear)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }.help(L10n.text(title)).accessibilityLabel(L10n.text(title))
    }
}
