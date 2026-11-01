import SwiftUI
import AppKit
import FilesShared

@MainActor final class WallpaperSlideshow: ObservableObject {
    static let shared = WallpaperSlideshow()
    @Published var paths: [String] { didSet { UserDefaults.standard.set(paths, forKey: "slideshowPaths") } }
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval, forKey: "slideshowInterval") } }
    @Published private(set) var running = false
    @Published private(set) var error = ""
    private var timer: Timer?
    private var index = 0
    private init() {
        paths = UserDefaults.standard.stringArray(forKey: "slideshowPaths") ?? []
        interval = max(10, UserDefaults.standard.double(forKey: "slideshowInterval"))
    }
    func resumeIfEnabled() { if !running && UserDefaults.standard.bool(forKey: "slideshowEnabled") { start() } }
    func start() {
        stop(); guard !paths.isEmpty else { return }
        interval = max(10, min(interval, 86400)); running = true; UserDefaults.standard.set(true, forKey: "slideshowEnabled")
        advance()
        guard running else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.advance() } }
    }
    func stop() { timer?.invalidate(); timer = nil; running = false; UserDefaults.standard.set(false, forKey: "slideshowEnabled") }
    func advance() {
        guard !paths.isEmpty else { stop(); return }
        let url = URL(fileURLWithPath: paths[index % paths.count]); index += 1
        do {
            for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue]) }
            error = ""
        } catch { self.error = error.localizedDescription; stop() }
    }
}
struct WallpaperSlideshowView: View {
    @ObservedObject private var slideshow = WallpaperSlideshow.shared
    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.text("The slideshow changes desktop wallpaper while MacFiles is running. It resumes at launch when enabled. macOS controls the lock screen wallpaper separately.")).font(.caption)
            List(slideshow.paths, id: \.self) { path in HStack { Text(URL(fileURLWithPath: path).lastPathComponent); Spacer(); Button(L10n.text("Remove")) { slideshow.stop(); slideshow.paths.removeAll { $0 == path } } } }
            HStack {
                Button(L10n.text("Add images…")) { choose() }
                Text(L10n.text("Interval in seconds"))
                TextField("", value: $slideshow.interval, format: .number).frame(width: 70).disabled(slideshow.running)
                Spacer()
                Button(L10n.text("Start")) { slideshow.start() }.disabled(slideshow.paths.isEmpty || slideshow.running)
                Button(L10n.text("Stop")) { slideshow.stop() }.disabled(!slideshow.running)
            }
            Text(slideshow.error).font(.caption).foregroundStyle(.red)
        }.padding(20)
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        slideshow.stop(); slideshow.paths = Array(Set(slideshow.paths + panel.urls.map(\.path))).sorted()
    }
}
