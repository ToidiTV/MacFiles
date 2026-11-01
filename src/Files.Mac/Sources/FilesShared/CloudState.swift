import Foundation
import Darwin

public enum CloudAvailability: String, Codable, Sendable {
    case local, onlineOnly, downloading, uploading, uploaded, downloaded, pending, conflict, error, providerLocal
    public var label: String {
        switch self {
        case .local: return ""; case .onlineOnly: return "Online only"; case .downloading: return "Downloading"; case .uploading: return "Uploading"
        case .uploaded: return "Synced"; case .downloaded: return "Downloaded"; case .pending: return "Waiting to sync"; case .conflict: return "Sync conflict"; case .error: return "Sync error"; case .providerLocal: return "Available locally"
        }
    }
    public var symbol: String {
        switch self {
        case .local: return ""; case .onlineOnly: return "icloud.and.arrow.down"; case .downloading, .uploading, .pending: return "arrow.triangle.2.circlepath"
        case .uploaded: return "checkmark.icloud"; case .downloaded, .providerLocal: return "checkmark.circle"; case .conflict, .error: return "exclamationmark.icloud"
        }
    }
}
public struct CloudState: Hashable, Sendable {
    public var provider: String?
    public var availability: CloudAvailability
    public var isICloud: Bool
    public var detail: String
    public var isCloud: Bool { provider != nil }
    public var canPreview: Bool { availability != .onlineOnly && availability != .downloading }
    public static let local = CloudState(provider: nil, availability: .local, isICloud: false, detail: "")
    public static func providerName(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        if let custom = CloudProviderFolder.registered.sorted(by: { $0.url.path.count > $1.url.path.count }).first(where: { url.path == $0.url.path || url.path.hasPrefix($0.url.path + "/") }) { return custom.name }
        let cloudRoot = home.appendingPathComponent("Library/CloudStorage").path + "/"
        if url.path.hasPrefix(cloudRoot) { return String(url.path.dropFirst(cloudRoot.count).split(separator: "/").first ?? "Cloud provider") }
        if url.path.hasPrefix(home.appendingPathComponent("Library/Mobile Documents").path + "/") { return "iCloud Drive" }
        return nil
    }
    public static func classify(isICloud: Bool, provider: String?, dataless: Bool, status: URLUbiquitousItemDownloadingStatus?, uploading: Bool, downloading: Bool, uploaded: Bool?, conflict: Bool, error: String?) -> CloudState {
        guard isICloud || provider != nil else { return .local }
        let state: CloudAvailability
        if error != nil { state = .error }
        else if conflict { state = .conflict }
        else if downloading { state = .downloading }
        else if uploading { state = .uploading }
        else if dataless || status == .notDownloaded { state = .onlineOnly }
        else if isICloud && uploaded == false { state = .pending }
        else if isICloud && uploaded == true && status == .current { state = .uploaded }
        else if isICloud && status != nil { state = .downloaded }
        else { state = .providerLocal }
        let detail = error ?? (isICloud ? state.label : "\(state.label). Sync completion is managed by the provider and is not reported through public file metadata.")
        return CloudState(provider: isICloud ? "iCloud Drive" : provider, availability: state, isICloud: isICloud, detail: detail)
    }
    public static func read(_ url: URL) -> CloudState {
        var url = url; url.removeAllCachedResourceValues()
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey]
        let values = try? url.resourceValues(forKeys: keys)
        var info = stat(); let dataless = lstat(url.path, &info) == 0 && (info.st_flags & UInt32(SF_DATALESS)) != 0
        return classify(isICloud: values?.isUbiquitousItem == true, provider: providerName(url), dataless: dataless, status: values?.ubiquitousItemDownloadingStatus, uploading: values?.ubiquitousItemIsUploading == true, downloading: values?.ubiquitousItemIsDownloading == true, uploaded: values?.ubiquitousItemIsUploaded, conflict: values?.ubiquitousItemHasUnresolvedConflicts == true, error: (values?.ubiquitousItemDownloadingError ?? values?.ubiquitousItemUploadingError)?.localizedDescription)
    }
}
