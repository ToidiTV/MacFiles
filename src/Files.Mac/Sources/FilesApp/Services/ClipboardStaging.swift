import AppKit

@MainActor enum ClipboardStaging {
    private static var root: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacFiles/Clipboard") }
    static func contains(_ url: URL) -> Bool { url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") }
    static func create() throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }
    static func cleanExpired() {
        let held = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [])) ?? []
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
            guard !held.contains(where: { $0.path.hasPrefix(folder.path + "/") }),
                  let created = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate, created < Date().addingTimeInterval(-7 * 24 * 3600) else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
