import SwiftUI
import AppKit
import FilesStorage

struct ExtractArchiveView: View {
    @ObservedObject var model: MainPageViewModel
    let request: ToolRequest
    @Environment(\.dismissTool) private var dismiss
    @State private var destination = ""
    @State private var password = ""
    @State private var openDestination = true
    @State private var error = ""
    @State private var recentDestinations: [String] = []
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if request.chooseExtractionDestination { FilesDialogCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("ExtractToPath"))
                            HStack {
                                TextField(L10n.text("Folder path"), text: $destination).textFieldStyle(.roundedBorder)
                                if !recentDestinations.isEmpty {
                                    Menu { ForEach(recentDestinations, id: \.self) { path in Button(path) { destination = path } } } label: { Image(systemName: "clock.arrow.circlepath") }
                                        .menuStyle(.borderlessButton).frame(width: 28).help(L10n.text("Recent folders"))
                                }
                                Button(L10n.text("Browse")) {
                                    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                                    panel.directoryURL = URL(fileURLWithPath: destination)
                                    if panel.runModal() == .OK, let url = panel.url { destination = url.path }
                                }
                            }
                        }
                    }
                    }
                    FilesDialogCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("Archive password"))
                            SecureField(L10n.text("Archive password (leave blank if unencrypted)"), text: $password).textFieldStyle(.roundedBorder)
                        }
                    }
                    if request.chooseExtractionDestination { Toggle(L10n.text("DecompressArchiveDialogOpenDestinationWhenComplete.Content"), isOn: $openDestination) }
                    if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
                }.padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("Extract")) { extract() }.buttonStyle(FilesPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction).disabled(destination.isEmpty || model.busy)
                Button(L10n.text("Cancel")) { dismiss() }.frame(minWidth: 96)
            }.padding(24)
        }.onAppear { destination = request.directory.path; password = request.archivePassword; recentDestinations = UserDefaults.standard.stringArray(forKey: "archiveExtractionLocations") ?? [] }
    }
    private func extract() {
        guard !request.urls.isEmpty else { return }
        let path = (destination as NSString).expandingTildeInPath
        var directory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
            error = L10n.text("Couldn’t open this location"); return
        }
        let target = URL(fileURLWithPath: path, isDirectory: true)
        let password = password, selection = request.archiveSelection, shouldOpen = openDestination
        let pane = model.activePane
        let sources = request.urls, placement = request.extractionPlacement
        let showDestination = shouldOpen && request.chooseExtractionDestination
        model.run("Extracting") {
            var result = OperationReport()
            for archive in sources {
                if Task.isCancelled { break }
                do {
                    let report: OperationReport
                    if let placement { report = try await ArchiveWorkflows().extract(archive, in: target, placement: placement, password: password) }
                    else { report = try await ArchiveService().extract(archive, to: target, selected: selection, password: password) }
                    result.completed += report.completed; result.undo += report.undo; result.errors += report.errors
                } catch { result.errors.append(error.localizedDescription) }
            }
            if !Task.isCancelled && result.errors.isEmpty && !result.completed.isEmpty {
                let old = UserDefaults.standard.stringArray(forKey: "archiveExtractionLocations") ?? []
                UserDefaults.standard.set(Array(([target.path] + old.filter { $0 != target.path }).prefix(10)), forKey: "archiveExtractionLocations")
                if showDestination { pane.navigate(target) }
            }
            return result
        }
        dismiss()
    }
}
