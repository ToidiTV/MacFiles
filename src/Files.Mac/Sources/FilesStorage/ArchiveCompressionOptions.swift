import Foundation

public struct ArchiveCompressionOptions: Sendable {
    public var level: Int
    public var dictionaryKiB: Int
    public var wordSize: Int
    public var threads: Int
    public init(level: Int = 5, dictionaryKiB: Int = 0, wordSize: Int = 0, threads: Int = 1) {
        self.level = level; self.dictionaryKiB = dictionaryKiB; self.wordSize = wordSize; self.threads = threads
    }
    func arguments(for format: ArchiveFormat) throws -> [String] {
        guard [0, 1, 3, 5, 7, 9].contains(level), (1...256).contains(threads),
              [0, 64, 256, 1024, 4096, 16384, 32768, 65536].contains(dictionaryKiB),
              wordSize == 0 || (5...273).contains(wordSize),
              format == .sevenZip || format == .zip else { throw ArchiveFailure("Invalid compression options.") }
        var args = ["-mx=\(level)", "-mmt=\(threads)"]
        if format == .sevenZip && level != 0 {
            args.append("-m0=LZMA2")
            if dictionaryKiB > 0 { args.append("-md=\(dictionaryKiB)k") }
            if wordSize > 0 { args.append("-mfb=\(wordSize)") }
        }
        return args
    }
}
