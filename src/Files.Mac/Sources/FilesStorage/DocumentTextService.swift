import Foundation
import PDFKit
import CoreServices
import CArchive

public enum DocumentTextService {
    public static func contains(_ term: String, in url: URL) throws -> Bool? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
            for index in 0..<document.pageCount { try Task.checkCancellation(); if document.page(at: index)?.string?.localizedStandardContains(term) == true { return true } }
            return false
        case "docx", "xlsx", "pptx", "odt", "ods", "odp": return try officeContains(term, in: url)
        default: break
        }
        // Search large UTF-8 files incrementally, retaining enough overlap for matches across chunks.
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var tail = ""; var pending = Data(); var first = true
        let overlap = max(256, term.utf16.count * 4)
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            try Task.checkCancellation(); pending.append(chunk)
            if first {
                first = false
                if pending.starts(with: [0xFF, 0xFE]) || pending.starts(with: [0xFE, 0xFF]) {
                    // UTF-16 files use Foundation's BOM-aware decoder; report excessively large inputs as skipped.
                    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                    guard size <= 64 * 1024 * 1024, let text = String(data: try Data(contentsOf: url), encoding: .utf16) else { return nil }
                    return text.localizedStandardContains(term)
                }
            }
            if pending.contains(0) { return indexedContains(term, in: url) }
            var decoded: String?; var length = pending.count
            for trim in 0...min(3, pending.count) {
                length = pending.count - trim
                if let text = String(data: pending.prefix(length), encoding: .utf8) { decoded = text; break }
            }
            guard let text = decoded else { return indexedContains(term, in: url) }
            let window = tail + text
            if window.localizedStandardContains(term) { return true }
            tail = String(window.suffix(overlap)); pending.removeFirst(length)
        }
        guard pending.isEmpty else { return nil }
        return false
    }
    private static func indexedContains(_ term: String, in url: URL) -> Bool? {
        guard let item = MDItemCreate(nil, url.path as CFString), let text = MDItemCopyAttribute(item, kMDItemTextContent) as? String else { return nil }
        return text.localizedStandardContains(term)
    }
    private static func officeContains(_ term: String, in url: URL) throws -> Bool? {
        guard let reader = archive_read_new() else { return nil }; defer { archive_read_free(reader) }
        archive_read_support_filter_all(reader); archive_read_support_format_zip(reader)
        guard archive_read_open_filename(reader, url.path, 65536) == ARCHIVE_OK else { return nil }
        var entry: OpaquePointer?; var total = 0; var inspected = false
        while true {
            try Task.checkCancellation()
            let code = archive_read_next_header(reader, &entry); if code == ARCHIVE_EOF { break }
            guard code == ARCHIVE_OK, let entry, let raw = archive_entry_pathname(entry) else { return nil }
            let path = String(cString: raw)
            let accepted = path == "content.xml" || path == "word/document.xml" || path.hasPrefix("word/header") || path.hasPrefix("word/footer") || path == "xl/sharedStrings.xml" || path.hasPrefix("xl/worksheets/sheet") || path.hasPrefix("ppt/slides/slide") || path.hasPrefix("ppt/notesSlides/notesSlide")
            guard accepted && path.hasSuffix(".xml") else { archive_read_data_skip(reader); continue }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                try Task.checkCancellation()
                let count = archive_read_data(reader, &buffer, buffer.count)
                guard count >= 0 else { return nil }; if count == 0 { break }
                total += count; guard total <= 64 * 1024 * 1024 else { return nil }
                data.append(contentsOf: buffer.prefix(count))
            }
            guard data.range(of: Data("<!DOCTYPE".utf8)) == nil else { return nil }
            let parser = XMLParser(data: data); let delegate = OfficeTextParser(); parser.delegate = delegate; parser.shouldResolveExternalEntities = false
            guard parser.parse() else { return nil }; inspected = true
            if delegate.text.localizedStandardContains(term) { return true }
        }
        return inspected ? false : nil
    }
}
private final class OfficeTextParser: NSObject, XMLParserDelegate {
    var text = ""
    func parser(_ parser: XMLParser, foundCharacters string: String) { if text.utf8.count + string.utf8.count > 64 * 1024 * 1024 { parser.abortParsing() } else { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if ["w:p", "a:p", "row", "text:p", "si"].contains(elementName) { text += "\n" }
    }
}
