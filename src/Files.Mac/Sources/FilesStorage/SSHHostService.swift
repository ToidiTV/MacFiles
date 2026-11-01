import Foundation

public struct SSHHostProposal: Sendable {
    public let host: String
    public let port: Int
    public let keys: String
    public let fingerprints: String
}
public enum SSHHostService {
    public static var knownHosts: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacFiles/known_hosts") }
    public static func inspect(host: String, port: Int) async throws -> SSHHostProposal {
        guard !host.isEmpty, !host.hasPrefix("-"), !host.contains(where: { $0.isWhitespace || "@/\\\"'".contains($0) }), (1...65535).contains(port) else { throw CommandFailure("Invalid SSH host or port.") }
        let scan = try await ProcessService.run("/usr/bin/ssh-keyscan", ["-T", "8", "-p", String(port), host])
        let lines = scan.output.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let address = port == 22 ? host : "[\(host)]:\(port)"
        guard !lines.isEmpty, lines.allSatisfy({ line in let parts = line.split(separator: " "); return parts.count == 3 && parts[0] == Substring(address) && parts[1].hasPrefix("ssh-") || parts.count == 3 && parts[0] == Substring(address) && parts[1].hasPrefix("ecdsa-") }) else { throw CommandFailure("The server did not return a valid host-key list.") }
        let keys = lines.joined(separator: "\n") + "\n"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-host-\(UUID().uuidString)")
        try Data(keys.utf8).write(to: temp, options: .withoutOverwriting); defer { try? FileManager.default.removeItem(at: temp) }
        let fingerprints = try await ProcessService.run("/usr/bin/ssh-keygen", ["-lf", temp.path, "-E", "sha256"])
        return SSHHostProposal(host: host, port: port, keys: keys, fingerprints: fingerprints.output)
    }
    public static func trust(_ proposal: SSHHostProposal, at destination: URL = knownHosts) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
        let address = proposal.port == 22 ? proposal.host : "[\(proposal.host)]:\(proposal.port)"
        let previous = existing.components(separatedBy: .newlines).filter { $0.split(separator: " ").first == Substring(address) }
        let proposed = proposal.keys.components(separatedBy: .newlines)
        guard previous.allSatisfy(proposed.contains) else { throw CommandFailure("A different key is already trusted for this host. Review the changed key with the server administrator before replacing it.") }
        let extra = proposed.filter { !$0.isEmpty && !existing.components(separatedBy: .newlines).contains($0) }
        guard !extra.isEmpty else { return }
        try (existing + (existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n") + extra.joined(separator: "\n") + "\n").write(to: destination, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
