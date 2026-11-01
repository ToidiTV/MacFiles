import Foundation

public enum ExtractionPlacement: String, CaseIterable, Sendable {
    case here, smart, childFolder
}
public actor ArchiveWorkflows {
    public init() {}
    public func compress(_ sources: [URL], in destination: URL, format: ArchiveFormat) async throws -> OperationReport {
        guard !sources.isEmpty else { return OperationReport() }
        let base = sources.count == 1 ? sources[0].deletingPathExtension().lastPathComponent : destination.lastPathComponent
        var target = destination.appendingPathComponent(base + "." + format.extensionName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent("\(base) (\(suffix)).\(format.extensionName)"); suffix += 1
        }
        return try await ArchiveService().compress(sources, to: target, format: format)
    }
    public func extract(_ source: URL, in destination: URL, placement: ExtractionPlacement, password: String = "") async throws -> OperationReport {
        let archive = ArchiveService()
        if placement == .childFolder { return try await archive.extract(source, to: destination, password: password) }
        let entries = try await archive.list(source, password: password)
        let roots = Set(entries.compactMap { $0.path.split(separator: "/").first(where: { $0 != "." }).map(String.init) })
        if placement == .smart && roots.count > 1 { return try await archive.extract(source, to: destination, password: password) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-extraction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let staged = try await archive.extract(source, to: temporary, password: password)
        guard let root = staged.completed.first else { return staged }
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return await MacStorageService.shared.perform(.copy, sources: contents, destination: destination, conflict: .keepBoth)
    }
}
