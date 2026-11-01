import SwiftUI
import AppKit
import FilesStorage

struct MediaMetadataView: View {
    @ObservedObject var model: MainPageViewModel
    let url: URL
    @State private var fields = MediaFields()
    @State private var loaded = false
    @State private var message = ""
    var body: some View {
        Form {
            Text(url.lastPathComponent).font(.headline)
            TextField(L10n.text("Title"), text: $fields.title); TextField(L10n.text("Artist / author"), text: $fields.artist)
            if !MediaService.isImage(url) { TextField(L10n.text("Album"), text: $fields.album) }
            TextField(L10n.text("Copyright"), text: $fields.copyright); TextField(L10n.text("Description"), text: $fields.comment)
            if MediaService.isImage(url) { TextField(L10n.text("Keywords (comma separated)"), text: $fields.keywords) }
            Text(L10n.text("Writes embedded metadata. Image files may be re-encoded; the original remains recoverable with Undo. Audio and video edits preserve encoded tracks. Unsupported containers keep the original.")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text(message)).font(.caption)
            Button(L10n.text("Save metadata")) {
                let values = fields
                model.run("Updating media metadata") { try await MediaService.edit(url, fields: values) }
                model.tool = nil
            }.disabled(!loaded || model.busy)
        }.padding(20).task {
            do { let result = try await MediaService.fields(url); try Task.checkCancellation(); fields = result; loaded = true }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
}
extension MainPageViewModel {
    func rotateImages(clockwise: Bool) {
        let urls = activePane.selectedItems.filter { MediaService.isImage($0.url) && !$0.isSymbolicLink }.map(\.url)
        guard !urls.isEmpty else { return }
        run(clockwise ? "Rotating right" : "Rotating left") {
            var result = OperationReport()
            for url in urls {
                if Task.isCancelled { break }
                do { let report = try await MediaService.edit(url, clockwise: clockwise); result.completed += report.completed; result.undo += report.undo; result.errors += report.errors }
                catch { result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            return result
        }
    }
    func setWallpaper() {
        guard let url = activePane.selectedItems.first?.url, MediaService.isImage(url) else { return }
        do { for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue]) } }
        catch { alert("Wallpaper could not be changed", error.localizedDescription) }
    }
}
