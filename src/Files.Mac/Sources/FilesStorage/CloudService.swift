import Foundation
import FilesShared

public enum CloudService {
    public static func downloadAsync(_ urls: [URL]) async throws -> OperationReport {
        let work = Task.detached { try download(urls) }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    public static func download(_ urls: [URL]) throws -> OperationReport {
        var report = OperationReport()
        for url in urls {
            do {
                try Task.checkCancellation()
                let item = try ListedItem(url: url)
                guard item.cloud.isCloud, !item.isDirectory, !item.isSymbolicLink else { throw CommandFailure("Choose a regular cloud file to download.") }
                if item.cloud.isICloud { try FileManager.default.startDownloadingUbiquitousItem(at: url) }
                else {
                    // Reading through the provider's filesystem requests materialization. No bytes are rewritten.
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation() }
                }
                report.completed.append(url)
            } catch is CancellationError { throw CancellationError() }
            catch { report.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return report
    }
    public static func evictICloud(_ url: URL) throws {
        var url = url; url.removeAllCachedResourceValues()
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey, .isDirectoryKey, .isSymbolicLinkKey])
        guard values.isUbiquitousItem == true, values.ubiquitousItemIsUploaded == true, values.ubiquitousItemIsUploading != true, values.ubiquitousItemHasUnresolvedConflicts != true, values.isDirectory != true, values.isSymbolicLink != true else { throw CommandFailure("Only an uploaded iCloud file without conflicts can have its local download removed.") }
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}
