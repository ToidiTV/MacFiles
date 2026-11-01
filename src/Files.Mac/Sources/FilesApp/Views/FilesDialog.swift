import SwiftUI
import AppKit
import FilesStorage

private struct FilesDismissKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var dismissTool: () -> Void { get { self[FilesDismissKey.self] } set { self[FilesDismissKey.self] = newValue } }
}
struct FilesDialogOverlay: View {
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    private var compact: Bool { [.compress, .rename, .tags, .permissions].contains(request.kind) }
    private var preferredWidth: CGFloat { request.kind == .network ? 600 : compact ? 488 : 850 }
    private var preferredHeight: CGFloat { request.kind == .compress ? 440 : compact ? 550 : 640 }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.28).contentShape(Rectangle())
                ToolSheet(model: model, request: request)
                    .environment(\.dismissTool, { model.tool = nil })
                    .frame(width: min(preferredWidth, geometry.size.width - 32), height: min(preferredHeight, geometry.size.height - 32))
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .buttonStyle(FilesDialogButtonStyle())
                    .onAppear { NSApp.keyWindow?.makeFirstResponder(nil) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
struct FilesDialogButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).frame(minHeight: 30)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Palette.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
struct FilesDialogCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line)) }
}
struct PropertiesSidebar: View {
    let pages: [String]
    @Binding var selection: String
    private func symbol(_ page: String) -> String {
        switch page {
        case "General": return "info.circle"
        case "Details": return "list.bullet.rectangle"
        case "Security": return "lock.shield"
        case "Hashes": return "number"
        case "Customization": return "paintbrush"
        case "Cloud": return "icloud"
        case "Shortcut": return "arrow.turn.up.right"
        case "Library": return "books.vertical"
        case "Signatures": return "signature"
        case "Compatibility": return "app"
        case "Preview": return "eye"
        default: return "list.bullet"
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(pages, id: \.self) { page in
                    Button { selection = page } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(page)).frame(width: 18).foregroundStyle(Palette.accent)
                            Text(L10n.text(page)).font(ExplorerFont.font(size: 13)).lineLimit(1)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
                            .background(selection == page ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(alignment: .leading) { if selection == page { RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3, height: 16) } }
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == page ? .isSelected : [])
                }
            }.padding(8)
        }.frame(width: 200).background(Palette.background)
    }
}
struct PropertyRows: View {
    let values: [PropertyValue]
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(values) { value in
                    HStack(alignment: .top, spacing: 12) {
                        Text(L10n.text(value.name)).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                        Text(value.value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(ExplorerFont.font(size: 13)).padding(.vertical, 10)
                    Divider()
                }
            }.padding(.horizontal, 12)
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 4))
    }
}
