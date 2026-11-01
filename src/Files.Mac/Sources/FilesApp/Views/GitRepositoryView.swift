import SwiftUI
import AppKit
import FilesStorage

struct GitRepositoryView: View {
    @ObservedObject var model: MainPageViewModel
    let folder: URL
    @State private var repository: GitRepository?
    @State private var selected = Set<String>()
    @State private var commitMessage = ""
    @State private var branchName = ""
    @State private var cloneURL = ""
    @State private var detail = ""
    @State private var error: String?
    @State private var busy = false
    @State private var stagedDiff = false
    @State private var tab = "Changes"
    @State private var jobID: UUID?
    @State private var task: Task<Void, Never>?
    private let git = GitService()
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Palette.accent)
                Text(repository?.root.path ?? folder.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                if busy { ProgressView().controlSize(.small); Button(L10n.text("Cancel")) { if let jobID { model.cancelJob(jobID) } else { task?.cancel() } } }
                Button(L10n.text("Refresh")) { reload() }.disabled(busy)
            }
            if let error { Text(L10n.text(error)).foregroundStyle(.red).lineLimit(4).textSelection(.enabled) }
            if let repository {
                HStack {
                    Menu(repository.branch) {
                        ForEach(repository.branches, id: \.self) { branch in
                            Button(branch) { execute { try await git.switchBranch(branch, at: repository.root, create: false); return "Switched to \(branch)" } }
                        }
                    }.frame(width: 200)
                    TextField(L10n.text("New branch"), text: $branchName).frame(width: 160)
                    Button(L10n.text("Create")) { let name = branchName; execute { try await git.switchBranch(name, at: repository.root, create: true); return "Created \(name)" } }.disabled(branchName.isEmpty)
                    Spacer()
                    ForEach(["Fetch", "Pull", "Push", "Sync"], id: \.self) { action in
                        Button(L10n.text(action)) { execute { try await git.operation(action, at: repository.root) } }
                    }
                }.disabled(busy)
                Picker(L10n.text("View"), selection: $tab) { Text(L10n.text("Changes")).tag("Changes"); Text(L10n.text("History")).tag("History"); Text(L10n.text("Remotes")).tag("Remotes") }.pickerStyle(.segmented)
                if tab == "Changes" {
                    HSplitView {
                        VStack {
                            Table(repository.changes, selection: $selected) {
                                TableColumn(L10n.text("Status")) { Text($0.status).font(.system(.body, design: .monospaced)) }.width(50)
                                TableColumn(L10n.text("File"), value: \.path)
                            }
                            HStack {
                                Button(L10n.text("Stage selected")) { execute { try await git.stage(Array(selected), at: repository.root); return "Staged selected files" } }.disabled(selected.isEmpty || busy)
                                Button(L10n.text("Unstage")) { execute { try await git.unstage(Array(selected), at: repository.root); return "Unstaged selected files" } }.disabled(selected.isEmpty || busy)
                                Button(L10n.text("Stage all")) { execute { try await git.stage(repository.changes.map(\.path), at: repository.root); return "Staged all changes" } }.disabled(busy)
                            }
                        }.frame(minWidth: 340)
                        VStack {
                            Toggle(L10n.text("Show staged diff"), isOn: $stagedDiff)
                            ScrollView([.horizontal, .vertical]) { Text(detail).font(ExplorerFont.font(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        }.padding(8).frame(minWidth: 300)
                    }
                    HStack {
                        TextField(L10n.text("Commit message"), text: $commitMessage)
                        Button(L10n.text("Commit staged")) {
                            let message = commitMessage
                            execute { try await git.commit(message, at: repository.root); return "Commit created" }
                        }.buttonStyle(.borderedProminent).disabled(busy || commitMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    ScrollView { Text(tab == "History" ? repository.log : repository.remotes).font(ExplorerFont.font(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
            } else {
                Spacer()
                Image(systemName: "point.3.connected.trianglepath.dotted").font(ExplorerFont.font(size: 38)).foregroundStyle(.secondary)
                Text(L10n.text("Open a repository, initialize this folder, or clone a repository."))
                Button(L10n.text("Initialize repository here")) { execute { try await git.operation("Initialize", at: folder) } }.disabled(busy)
                HStack {
                    TextField(L10n.text("Repository URL"), text: $cloneURL)
                    Button(L10n.text("Clone…")) { clone() }.disabled(busy || cloneURL.isEmpty)
                }.frame(maxWidth: 650)
                Spacer()
            }
        }.padding(20).task { reload() }
            .onChange(of: selected) { loadDiff() }.onChange(of: stagedDiff) { loadDiff() }
            .onDisappear { task?.cancel(); model.refreshAll() }
    }
    private func reload() {
        guard !busy else { return }; busy = true; error = nil
        task = Task {
            do { repository = try await git.inspect(folder) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func execute(_ action: @escaping () async throws -> String) {
        guard !busy else { return }; busy = true; error = nil
        jobID = model.run("Git operation in \(folder.lastPathComponent)", recordingUndo: false, onCancel: { busy = false; jobID = nil }) {
            defer { busy = false; jobID = nil }
            do { detail = try await action(); repository = try await git.inspect(folder); return OperationReport() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
    private func loadDiff() {
        guard let repository, let path = selected.first else { detail = "Select a file to view its diff."; return }
        Task {
            do { let diff = try await git.diff(path, at: repository.root, staged: stagedDiff); if selected.contains(path) { detail = diff } }
            catch { detail = error.localizedDescription }
        }
    }
    private func clone() {
        let panel = NSSavePanel(); panel.title = L10n.text("Clone repository"); panel.prompt = L10n.text("Clone")
        panel.nameFieldStringValue = URL(string: cloneURL)?.deletingPathExtension().lastPathComponent ?? "Repository"
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let remote = cloneURL
        execute { try await git.clone(remote, to: destination); model.newTab(destination); return "Cloned \(destination.lastPathComponent)" }
    }
}
