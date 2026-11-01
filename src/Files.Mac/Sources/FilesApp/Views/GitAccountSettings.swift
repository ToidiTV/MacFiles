import SwiftUI
import FilesShared
import FilesStorage

struct GitAccountSettings: View {
    @State private var username = GitHubCredentials.username
    @State private var token = ""
    @State private var saved = GitHubCredentials.username
    @State private var message = ""
    var body: some View {
        Section(L10n.text("GitHub account")) {
            Text(L10n.text("HTTPS Git operations can use a GitHub access token stored in your macOS Keychain. Choose the repositories and permissions when creating the token. Existing Git authentication remains in use when no MacFiles account is saved.")).font(.caption).foregroundStyle(.secondary)
            if !saved.isEmpty { Text(saved).font(.headline) }
            TextField(L10n.text("GitHub username"), text: $username)
            SecureField(L10n.text("Access token"), text: $token)
            Link(L10n.text("Create a GitHub token"), destination: URL(string: "https://github.com/settings/tokens?type=beta")!)
            HStack {
                Button(L10n.text("Save to Keychain")) {
                    do { try GitHubCredentials.save(username: username, token: token); saved = username; token = ""; message = L10n.text("Saved. The token will be used for GitHub HTTPS operations.") }
                    catch { message = error.localizedDescription }
                }.disabled(username.isEmpty || token.isEmpty)
                Button(L10n.text("Remove saved credentials")) {
                    do { try GitHubCredentials.remove(); saved = ""; token = ""; message = "" }
                    catch { message = error.localizedDescription }
                }.disabled(saved.isEmpty)
            }
            if !message.isEmpty { Text(message).font(.caption) }
        }.onDisappear { token = "" }
    }
}
