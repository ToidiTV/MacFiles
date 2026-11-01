import SwiftUI
import AppKit
import FilesShared

@MainActor enum ExplorerFont {
    static func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let name = SettingsService.shared.preferences.fontFamily
        return name == "System" || design == .monospaced ? .system(size: size, weight: weight, design: design) : .custom(name, size: size).weight(weight)
    }
    static func native(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = SettingsService.shared.preferences.fontFamily
        return name == "System" ? .systemFont(ofSize: size, weight: weight) : NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
struct ExplorerBackdrop: NSViewRepresentable {
    let kind: String
    func makeNSView(context: Context) -> NSVisualEffectView { let view = NSVisualEffectView(); view.blendingMode = .behindWindow; view.state = .active; return view }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = kind == "Sidebar" ? .sidebar : kind == "HUD" ? .hudWindow : .underWindowBackground }
}
struct ContextAppearanceSettings: View {
    @ObservedObject private var settings = SettingsService.shared
    let search: String
    private let actions = ["Open in new tab", "Open in new window", "Open in other pane", "Copy path", "CreateFolderWithSelection", "Make alias…", "Pin to sidebar", "Compress…", "Flatten folder…", "Share…", "Open in Terminal", "Edit tags…", "Extended attributes…"]
    var body: some View {
        if search.isEmpty || ["Font", "Font and material", "Backdrop material"].contains(where: { L10n.text($0).localizedStandardContains(search) }) {
            Section(L10n.text("Font and material")) {
                Picker(L10n.text("Font"), selection: $settings.preferences.fontFamily) {
                    Text(L10n.text("System")).tag("System")
                    ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker(L10n.text("Backdrop material"), selection: $settings.preferences.backdrop) {
                    ForEach(["Solid", "Sidebar", "Under window", "HUD"], id: \.self) { Text(L10n.text($0)).tag($0) }
                }
                Text(L10n.text("Backdrop materials use macOS visual effects. Standard system controls and monospaced content retain their system fonts.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if search.isEmpty || L10n.text("Context menu").localizedStandardContains(search) || actions.contains(where: { L10n.text($0).localizedStandardContains(search) }) {
            Section(L10n.text("Context menu")) {
                ForEach(actions, id: \.self) { title in
                    Toggle(L10n.text(title), isOn: Binding(get: { !settings.preferences.hiddenContextActions.contains(title) }, set: { shown in
                        settings.preferences.hiddenContextActions.removeAll { $0 == title }
                        if !shown { settings.preferences.hiddenContextActions.append(title) }
                    }))
                }
                Button(L10n.text("Reset")) { settings.preferences.hiddenContextActions = [] }
            }
        }
    }
}
