import Foundation

public enum ClipboardPaths {
    public static func format(_ paths: [String], quoted: Bool) -> String {
        paths.map { quoted ? "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" : $0 }.joined(separator: "\n")
    }
}
