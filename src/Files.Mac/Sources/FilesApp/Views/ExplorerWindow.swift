import SwiftUI
import AppKit

struct ExplorerWindow: View {
    @Environment(\.openWindow) private var openWindow
    let delegate: AppDelegate
    @StateObject private var model: MainPageViewModel
    init(delegate: AppDelegate, initialLocation: URL? = nil) {
        self.delegate = delegate
        _model = StateObject(wrappedValue: MainPageViewModel(initialLocation: initialLocation))
    }
    @ObservedObject private var settings = SettingsService.shared
    private var language: String { settings.language == "System" ? Locale.preferredLanguages.first ?? "en" : settings.language }
    var body: some View {
        ShellView(model: model)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.layoutDirection, ["ar", "fa", "he"].contains(String(language.prefix(2))) ? .rightToLeft : .leftToRight)
            .focusedSceneObject(model)
            .background(WindowRegistration { window in delegate.register(window, model: model) })
            .onAppear { SettingsService.shared.applyAppearance(); delegate.installKeyboardMonitor(); delegate.openFolderWindow = { openWindow(id: "folder", value: $0) } }
    }
}

struct WindowRegistration: NSViewRepresentable {
    let register: (NSWindow) -> Void
    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView(); view.register = register; return view
    }
    func updateNSView(_ view: RegistrationView, context: Context) { view.register = register }
    final class RegistrationView: NSView {
        var register: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window {
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(button)?.isHidden = true }
            register?(window)
        } }
    }
}

@MainActor final class WeakWindowModel {
    weak var model: MainPageViewModel?
    init(_ model: MainPageViewModel) { self.model = model }
}

@MainActor final class ActiveExplorer: ObservableObject {
    static let shared = ActiveExplorer()
    @Published var model: MainPageViewModel?
}

struct FocusedExplorerCommands: Commands {
    @ObservedObject private var active = ActiveExplorer.shared
    var body: some Commands {
        if let model = active.model { ExplorerCommands(model: model) }
    }
}
