import Foundation

// Replace only the iTunes metadata boxes; media bytes and their offsets never move.
enum MP4Metadata {
    private struct Box { let type: Data; let payload: Data }
    private static func uint(_ data: Data) -> UInt64 { data.reduce(0) { ($0 << 8) | UInt64($1) } }
    private static func number(_ value: UInt32) -> Data { var value = value.bigEndian; return withUnsafeBytes(of: &value) { Data($0) } }
    private static func code(_ value: String) -> Data { value.data(using: .isoLatin1)! }
    private static func box(_ type: Data, _ payload: Data) throws -> Data {
        guard payload.count <= Int(UInt32.max) - 8 else { throw CommandFailure("Media metadata is too large.") }
        return number(UInt32(payload.count + 8)) + type + payload
    }
    private static func boxes(_ data: Data) throws -> [Box] {
        var result: [Box] = []; var offset = 0
        while offset < data.count {
            guard data.count - offset >= 8 else { throw CommandFailure("Invalid media atom header.") }
            let short = uint(data.subdata(in: offset..<offset + 4)); let type = data.subdata(in: offset + 4..<offset + 8)
            let header = short == 1 ? 16 : 8
            guard data.count - offset >= header else { throw CommandFailure("Invalid extended media atom.") }
            let size = short == 1 ? uint(data.subdata(in: offset + 8..<offset + 16)) : short == 0 ? UInt64(data.count - offset) : short
            guard size >= header, size <= data.count - offset else { throw CommandFailure("Invalid media atom size.") }
            result.append(Box(type: type, payload: data.subdata(in: offset + header..<offset + Int(size))))
            offset += Int(size)
        }
        return result
    }
    private static func encoded(_ boxes: [Box]) throws -> Data { try boxes.reduce(into: Data()) { $0.append(try box($1.type, $1.payload)) } }
    static func write(_ source: URL, to output: URL, fields: MediaFields) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let length = try input.seekToEnd(); var offset: UInt64 = 0; var movie: (UInt64, UInt64, Data)?
        while offset < length {
            try Task.checkCancellation(); try input.seek(toOffset: offset)
            guard let header = try input.read(upToCount: 8), header.count == 8 else { throw CommandFailure("Invalid media file.") }
            let short = uint(header.prefix(4)); var headerSize: UInt64 = 8; let size: UInt64
            if short == 1 { guard let extended = try input.read(upToCount: 8), extended.count == 8 else { throw CommandFailure("Invalid media atom.") }; size = uint(extended); headerSize = 16 }
            else { size = short == 0 ? length - offset : short }
            guard size >= headerSize, size <= length - offset else { throw CommandFailure("Invalid media atom size.") }
            if header.suffix(4) == code("moof") { throw CommandFailure("Fragmented media metadata cannot be edited without remuxing.") }
            if header.suffix(4) == code("moov") {
                guard movie == nil, size <= 128 * 1024 * 1024, let data = try input.read(upToCount: Int(size - headerSize)), data.count == size - headerSize else { throw CommandFailure("Unsupported movie header.") }
                movie = (offset, size, data)
            }
            // A zero-sized final atom would swallow an appended movie header.
            guard short != 0 else { throw CommandFailure("Open-ended media atoms require remuxing before editing.") }
            offset += size
        }
        guard let movie else { throw CommandFailure("No movie header was found.") }
        var children = try boxes(movie.2)
        guard !children.contains(where: { $0.type == code("cmov") }) else { throw CommandFailure("Compressed movie headers require remuxing.") }
        var user = try children.first(where: { $0.type == code("udta") }).map { try boxes($0.payload) } ?? []
        guard children.filter({ $0.type == code("udta") }).count <= 1, user.filter({ $0.type == code("meta") }).count <= 1 else { throw CommandFailure("Ambiguous media metadata containers.") }
        var metadata: [Box] = []
        if let existing = user.first(where: { $0.type == code("meta") }) {
            guard existing.payload.count >= 4, existing.payload.prefix(4) == Data(repeating: 0, count: 4) else { throw CommandFailure("Unsupported metadata container version.") }
            metadata = try boxes(Data(existing.payload.dropFirst(4)))
            guard !metadata.contains(where: { $0.type == code("keys") }) else { throw CommandFailure("This metadata container uses indexed keys; edit it with its native media application.") }
        }
        let replacements = [("©nam", fields.title), ("©ART", fields.artist), ("©alb", fields.album), ("cprt", fields.copyright), ("©cmt", fields.comment)]
        let keys = Set(replacements.map { code($0.0) })
        var items = try metadata.first(where: { $0.type == code("ilst") }).map { try boxes($0.payload) } ?? []
        items.removeAll { keys.contains($0.type) }
        for (key, value) in replacements where !value.isEmpty {
            let data = number(1) + number(0) + Data(value.utf8)
            items.append(Box(type: code(key), payload: try box(code("data"), data)))
        }
        metadata.removeAll { $0.type == code("ilst") }
        if !metadata.contains(where: { $0.type == code("hdlr") }) {
            metadata.insert(Box(type: code("hdlr"), payload: Data(repeating: 0, count: 8) + code("mdir") + code("appl") + Data(repeating: 0, count: 9)), at: 0)
        }
        metadata.append(Box(type: code("ilst"), payload: try encoded(items)))
        user.removeAll { $0.type == code("meta") }; user.append(Box(type: code("meta"), payload: Data(repeating: 0, count: 4) + (try encoded(metadata))))
        children.removeAll { $0.type == code("udta") }; children.append(Box(type: code("udta"), payload: try encoded(user)))
        let replacement = try box(code("moov"), encoded(children))
        try CancellableCopy.copy(source, to: output)
        let handle = try FileHandle(forWritingTo: output); defer { try? handle.close() }
        try handle.seek(toOffset: movie.0 + 4); try handle.write(contentsOf: code("free"))
        try handle.seekToEnd(); try handle.write(contentsOf: replacement); try handle.synchronize()
    }
}
