import Foundation
import CryptoKit

public enum TransferFingerprint {
    public static func digest(_ url: URL) throws -> Data {
        var hash = SHA256()
        func visit(_ item: URL, relative: String) throws {
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
            let kind = attributes[.type] as? FileAttributeType
            hash.update(data: Data((relative + "\0" + (kind?.rawValue ?? "") + "\0").utf8))
            if kind == .typeSymbolicLink {
                let value = Data(try FileManager.default.destinationOfSymbolicLink(atPath: item.path).utf8)
                hash.update(data: Data("\(value.count):".utf8)); hash.update(data: value)
            }
            else if kind == .typeDirectory {
                for child in try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { try visit(child, relative: relative + "/" + child.lastPathComponent) }
            } else if kind == .typeRegular {
                hash.update(data: Data("\((attributes[.size] as? NSNumber)?.uint64Value ?? 0):".utf8))
                let handle = try FileHandle(forReadingFrom: item); defer { try? handle.close() }
                while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
            } else { throw CommandFailure("Unsupported file type in transfer.") }
            hash.update(data: Data([0]))
        }
        try visit(url, relative: ""); return Data(hash.finalize())
    }
}

public actor RemoteUndoRegistry {
    public static let shared = RemoteUndoRegistry()
    private var providers: [UUID: RemoteProvider] = [:]
    private var endpoints: [UUID: RemoteConnection]
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        endpoints = defaults.data(forKey: "remoteUndoEndpointsV1").flatMap { try? JSONDecoder().decode([UUID: RemoteConnection].self, from: $0) } ?? [:]
    }
    public func register(_ provider: RemoteProvider) -> UUID {
        let connection = provider.connection
        let id = endpoints.first { _, value in value.kind == connection.kind && value.host == connection.host && value.port == connection.port && value.username == connection.username }?.key ?? UUID()
        endpoints[id] = connection; providers[id] = provider
        defaults.set(try? JSONEncoder().encode(endpoints), forKey: "remoteUndoEndpointsV1")
        return id
    }
    public func undo(_ id: UUID, steps: [RemoteUndoStep]) async throws -> [RemoteUndoStep] {
        guard let provider = providers[id] else { throw CommandFailure("Reconnect to the same server and account, then retry Undo. The remote recovery data remains in .MacFiles-Recovery.") }
        return try await provider.undoRemote(steps)
    }
}
