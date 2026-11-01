import Foundation
import Security
import FilesStorage

@MainActor final class ConnectionStore: ObservableObject {
    static let shared = ConnectionStore()
    @Published var connections: [RemoteConnection] = []
    private let service = "com.toidi.macfiles.remote"
    private init() {
        if let data = UserDefaults.standard.data(forKey: "remoteConnections") { connections = (try? JSONDecoder().decode([RemoteConnection].self, from: data)) ?? [] }
    }
    func save(_ connection: RemoteConnection, password: String?) throws {
        connections.removeAll { $0.id == connection.id }; connections.append(connection)
        UserDefaults.standard.set(try JSONEncoder().encode(connections), forKey: "remoteConnections")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: connection.id.uuidString]
        guard let password else { SecItemDelete(query as CFDictionary); return }
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            if added != errSecSuccess { throw CommandFailure("Could not save the password in Keychain (\(added)).") }
        } else if status != errSecSuccess { throw CommandFailure("Could not update the password in Keychain (\(status)).") }
    }
    func password(for connection: RemoteConnection) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: connection.id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    func remove(_ connection: RemoteConnection) {
        connections.removeAll { $0.id == connection.id }
        UserDefaults.standard.set(try? JSONEncoder().encode(connections), forKey: "remoteConnections")
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: connection.id.uuidString] as CFDictionary)
    }
}
