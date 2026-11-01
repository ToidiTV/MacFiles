import Foundation

public struct CloudProviderFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public var name: String
    public var url: URL
    public var application: URL?
    public init(name: String, url: URL, application: URL? = nil) { self.name = name; self.url = url; self.application = application }
    public static var registered: [CloudProviderFolder] {
        guard let data = UserDefaults.standard.data(forKey: "cloudProviderFoldersV1") else { return [] }
        return (try? JSONDecoder().decode([CloudProviderFolder].self, from: data)) ?? []
    }
    public static func detected(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CloudProviderFolder] {
        let fm = FileManager.default; let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var result: [CloudProviderFolder] = []
        if fm.fileExists(atPath: iCloud.path) { result.append(.init(name: "iCloud Drive", url: iCloud)) }
        let folder = home.appendingPathComponent("Library/CloudStorage")
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        result += urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map { .init(name: $0.lastPathComponent, url: $0) }
        for custom in registered { result.removeAll { $0.id == custom.id }; result.append(custom) }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
