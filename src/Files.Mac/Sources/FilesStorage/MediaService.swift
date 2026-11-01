import Foundation
import ImageIO
import CoreImage
import AVFoundation
import FilesShared

public struct MediaFields: Sendable {
    public var title = ""
    public var artist = ""
    public var album = ""
    public var copyright = ""
    public var comment = ""
    public var keywords = ""
    public init() {}
}
public enum MediaService {
    public static func isImage(_ url: URL) -> Bool { ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"].contains(url.pathExtension.lowercased()) }
    public static func isEditable(_ url: URL) -> Bool { isImage(url) || ["m4a", "m4v", "mp4", "mov"].contains(url.pathExtension.lowercased()) }
    public static func fields(_ url: URL) async throws -> MediaFields {
        var fields = MediaFields()
        if isImage(url) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { throw CommandFailure("Cannot read image metadata.") }
            let tiff = values[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            let iptc = values[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
            fields.title = iptc[kCGImagePropertyIPTCObjectName as String] as? String ?? ""
            fields.artist = tiff[kCGImagePropertyTIFFArtist as String] as? String ?? ""
            fields.copyright = tiff[kCGImagePropertyTIFFCopyright as String] as? String ?? ""
            fields.comment = tiff[kCGImagePropertyTIFFImageDescription as String] as? String ?? ""
            if let png = values[kCGImagePropertyPNGDictionary as String] as? [String: Any] {
                fields.title = png[kCGImagePropertyPNGTitle as String] as? String ?? fields.title
                fields.artist = png[kCGImagePropertyPNGAuthor as String] as? String ?? fields.artist
                fields.comment = png[kCGImagePropertyPNGDescription as String] as? String ?? fields.comment
                fields.copyright = png[kCGImagePropertyPNGCopyright as String] as? String ?? fields.copyright
            }
            fields.keywords = (iptc[kCGImagePropertyIPTCKeywords as String] as? [String] ?? []).joined(separator: ", ")
        } else {
            let metadata = try await AVURLAsset(url: url).load(.metadata)
            for item in metadata {
                let value = try await item.load(.stringValue) ?? ""
                if [.iTunesMetadataUserComment, .quickTimeUserDataComment].contains(item.identifier) { fields.comment = value }
                switch item.commonKey {
                case .commonKeyTitle: fields.title = value; case .commonKeyArtist: fields.artist = value; case .commonKeyAlbumName: fields.album = value
                case .commonKeyCopyrights: fields.copyright = value; case .commonKeyDescription: fields.comment = value; default: break
                }
            }
        }
        return fields
    }
    public static func writeImage(_ sourceURL: URL, to output: URL, clockwise: Bool? = nil, fields: MediaFields? = nil) throws {
        try Task.checkCancellation()
        guard isImage(sourceURL), let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source), let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else { throw CommandFailure("Choose a supported single-frame image (JPEG, PNG, TIFF or HEIC).") }
        var values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        var tiff = values[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        if let fields {
            var iptc = values[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
            iptc[kCGImagePropertyIPTCObjectName as String] = fields.title
            iptc[kCGImagePropertyIPTCKeywords as String] = fields.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            tiff[kCGImagePropertyTIFFArtist as String] = fields.artist; tiff[kCGImagePropertyTIFFCopyright as String] = fields.copyright; tiff[kCGImagePropertyTIFFImageDescription as String] = fields.comment
            values[kCGImagePropertyIPTCDictionary as String] = iptc
            if sourceURL.pathExtension.lowercased() == "png" {
                var png = values[kCGImagePropertyPNGDictionary as String] as? [String: Any] ?? [:]
                png[kCGImagePropertyPNGTitle as String] = fields.title; png[kCGImagePropertyPNGAuthor as String] = fields.artist
                png[kCGImagePropertyPNGDescription as String] = fields.comment; png[kCGImagePropertyPNGCopyright as String] = fields.copyright
                values[kCGImagePropertyPNGDictionary as String] = png
            }
        }
        values[kCGImagePropertyTIFFDictionary as String] = tiff
        if let clockwise {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CommandFailure("Cannot decode image.") }
            let orientation = (values[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
            let result = CIImage(cgImage: image).oriented(forExifOrientation: orientation).oriented(clockwise ? .right : .left)
            guard let rotated = CIContext(options: [.cacheIntermediates: false]).createCGImage(result, from: result.extent) else { throw CommandFailure("Cannot rotate image.") }
            values[kCGImagePropertyOrientation as String] = 1; tiff[kCGImagePropertyTIFFOrientation as String] = 1; values[kCGImagePropertyTIFFDictionary as String] = tiff
            values[kCGImagePropertyPixelWidth as String] = rotated.width; values[kCGImagePropertyPixelHeight as String] = rotated.height
            var exif = values[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            exif[kCGImagePropertyExifPixelXDimension as String] = rotated.width; exif[kCGImagePropertyExifPixelYDimension as String] = rotated.height; values[kCGImagePropertyExifDictionary as String] = exif
            CGImageDestinationAddImage(destination, rotated, values as CFDictionary)
        } else { CGImageDestinationAddImageFromSource(destination, source, 0, values as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { throw CommandFailure("Could not save the edited image; the original was kept.") }
    }
    public static func writeAV(_ source: URL, to output: URL, fields: MediaFields) async throws {
        if source.pathExtension.lowercased() != "mov" {
            let worker = Task.detached { try MP4Metadata.write(source, to: output, fields: fields) }
            try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            return
        }
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { throw CommandFailure("This media format cannot be edited by the native exporter.") }
        let type: AVFileType = source.pathExtension.lowercased() == "mov" ? .mov : source.pathExtension.lowercased() == "m4a" ? .m4a : .mp4
        guard exporter.supportedFileTypes.contains(type) else { throw CommandFailure("The media tracks cannot be preserved in this container.") }
        let replacements: [(AVMetadataIdentifier, String)] = type == .mov
            ? [(.quickTimeMetadataTitle, fields.title), (.quickTimeMetadataArtist, fields.artist), (.quickTimeMetadataAlbum, fields.album), (.quickTimeMetadataCopyright, fields.copyright), (.quickTimeMetadataDescription, fields.comment)]
            : [(.quickTimeUserDataFullName, fields.title), (.quickTimeUserDataArtist, fields.artist), (.quickTimeUserDataAlbum, fields.album), (.quickTimeUserDataCopyright, fields.copyright), (.quickTimeUserDataDescription, fields.comment)]
        let ids = Set(replacements.map(\.0)); let commonKeys: Set<AVMetadataKey> = [.commonKeyTitle, .commonKeyArtist, .commonKeyAlbumName, .commonKeyCopyrights, .commonKeyDescription]
        var metadata = try await asset.load(.metadata).filter { !($0.identifier.map(ids.contains) ?? false) && !($0.commonKey.map(commonKeys.contains) ?? false) }
        metadata += replacements.map { id, value in let item = AVMutableMetadataItem(); item.identifier = id; item.value = value as NSString; item.dataType = kCMMetadataBaseDataType_UTF8 as String; return item }
        exporter.outputURL = output; exporter.outputFileType = type; exporter.metadata = metadata
        await withTaskCancellationHandler { await exporter.export() } onCancel: { exporter.cancelExport() }
        try Task.checkCancellation()
        guard exporter.status == .completed else { throw exporter.error ?? CommandFailure("Media export did not complete.") }
    }
    public static func edit(_ url: URL, clockwise: Bool? = nil, fields: MediaFields? = nil, storage: MacStorageService = .shared) async throws -> OperationReport {
        let original = try ListedItem(url: url); let identity = FileIdentity(url)
        guard !original.isSymbolicLink, !original.isDirectory else { throw CommandFailure("Select a regular media file.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let rendered = folder.appendingPathComponent(".rendered-\(UUID().uuidString)." + url.pathExtension)
        if isImage(url) {
            let worker = Task.detached { try writeImage(url, to: rendered, clockwise: clockwise, fields: fields) }
            try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        } else if let fields { try await writeAV(url, to: rendered, fields: fields) }
        else { throw CommandFailure("Only images can be rotated.") }
        if !isImage(url), let fields {
            let verified = try await self.fields(rendered)
            let checks = [("title", verified.title, fields.title), ("artist", verified.artist, fields.artist), ("album", verified.album, fields.album), ("copyright", verified.copyright, fields.copyright), ("description", verified.comment, fields.comment)]
            let missing = checks.filter { $0.1 != $0.2 }.map { $0.0 }
            guard missing.isEmpty else { throw CommandFailure("The media container did not retain: " + missing.joined(separator: ", ") + ". The original was kept.") }
        }
        try Task.checkCancellation()
        let staged = folder.appendingPathComponent(url.lastPathComponent)
        // Clone filesystem metadata first, then replace only the byte stream.
        try FileManager.default.copyItem(at: url, to: staged)
        let input = try FileHandle(forReadingFrom: rendered); defer { try? input.close() }
        let output = try FileHandle(forWritingTo: staged); defer { try? output.close() }
        try output.truncate(atOffset: 0)
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); try output.write(contentsOf: data) }
        try output.synchronize()
        return try await storage.replacePrepared(staged, original: url, identity: identity, modified: original.modified, size: original.size)
    }
}

extension MacStorageService {
    public func replacePrepared(_ staged: URL, original: URL, identity: FileIdentity?, modified: Date?, size: Int64) throws -> OperationReport {
        let current = try ListedItem(url: original)
        guard identity != nil, identity == FileIdentity(original), current.modified == modified, current.size == size,
              staged.lastPathComponent == original.lastPathComponent else { throw StorageError.changedItem(original.lastPathComponent) }
        return perform(.copy, sources: [staged], destination: original.deletingLastPathComponent(), conflict: .replace)
    }
}
