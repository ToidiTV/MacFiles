import Foundation
import Security

public enum GitHubCredentials {
    private static let service = "com.toidi.macfiles.github"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "github.com"] }
    public static var username: String { UserDefaults.standard.string(forKey: "githubAccountName") ?? "" }
    public static func save(username: String, token: String) throws {
        guard !username.isEmpty, username.count <= 100, !token.isEmpty, token.count <= 4096,
              !username.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "=" || $0 == "\0" }),
              !token.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\0" }) else { throw CommandFailure("Enter a GitHub username and a valid access token.") }
        let data = Data((username + "\n" + token).utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CommandFailure("Could not save GitHub credentials in Keychain.") }
        } else if status != errSecSuccess { throw CommandFailure("Could not update GitHub credentials in Keychain.") }
        UserDefaults.standard.set(username, forKey: "githubAccountName")
    }
    public static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CommandFailure("Could not remove GitHub credentials from Keychain.") }
        UserDefaults.standard.removeObject(forKey: "githubAccountName")
    }
    public static var gitArguments: [String] {
        guard !username.isEmpty else { return [] }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/macfiles-git-credential")
        let path = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : SevenZipService.executable.deletingLastPathComponent().appendingPathComponent("macfiles-git-credential")
        guard FileManager.default.isExecutableFile(atPath: path.path) else { return [] }
        let quoted = "'" + path.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return ["-c", "credential.https://github.com.helper=", "-c", "credential.https://github.com.helper=!" + quoted]
    }
}
