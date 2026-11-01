import Foundation
import FilesShared

public enum SevenZipService {
    public static var executable: URL {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/7zz")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tools/7zz")
    }
    private static func input(_ password: String) throws -> Data? {
        guard !password.contains("\n"), !password.contains("\r"), !password.contains("\0") else { throw ArchiveFailure("Archive passwords cannot contain line breaks or NUL characters.") }
        return password.isEmpty ? nil : Data((password + "\n" + password + "\n").utf8)
    }
    public static func list(_ url: URL, password: String) async throws -> [ArchiveMember] {
        let result = try await ProcessService.run(executable.path, ["l", "-slt", "-ba", "-bd", "-sccUTF-8", "--", url.path], input: try input(password))
        return try parseListing(result.output)
    }
    public static func parseListing(_ text: String) throws -> [ArchiveMember] {
        var records: [[String: String]] = []; var record: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty { if !record.isEmpty { records.append(record); record = [:] }; continue }
            if line == "Enter password:" { continue }
            guard let range = line.range(of: " = ") else { throw ArchiveFailure("Unsupported archive entry name or listing.") }
            let key = String(line[..<range.lowerBound]); guard record[key] == nil else { throw ArchiveFailure("Ambiguous archive listing.") }
            record[key] = String(line[range.upperBound...])
        }
        if !record.isEmpty { records.append(record) }
        var seen = Set<String>()
        return try records.map { record in
            guard let path = record["Path"], let size = Int64(record["Size"] ?? ""), size >= 0 else { throw ArchiveFailure("Incomplete archive listing.") }
            let parts = try ArchiveService.validatedPath(path)
            guard !parts.isEmpty else { throw ArchiveFailure("Empty archive entry.") }
            let normalized = parts.joined(separator: "/")
            guard seen.insert(normalized).inserted else { throw ArchiveFailure("Duplicate archive paths cannot be extracted safely.") }
            let attributes = record["Attributes"] ?? ""
            let directory = record["Folder"] == "+" || attributes.hasPrefix("D") || attributes.contains(" dr")
            let link = record["Symbolic Link"] != nil || record["Hard Link"] != nil || attributes.contains(" lr") || (record["Mode"] ?? "").hasPrefix("l")
            let mode = attributes.split(separator: " ").last.map(String.init) ?? record["Mode"] ?? ""
            var permissions: UInt16?
            if mode.count == 10 {
                permissions = 0
                for (index, character) in mode.dropFirst().enumerated() where "rwxst".contains(character) { permissions! |= 1 << (8 - index) }
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let modified = record["Modified"].flatMap { formatter.date(from: String($0.prefix(19))) } ?? .distantPast
            return ArchiveMember(path: normalized + (directory ? "/" : ""), size: size, directory: directory, link: link, encrypted: record["Encrypted"] == "+", modified: modified, linkTarget: record["Symbolic Link"] ?? record["Hard Link"], hardLink: record["Hard Link"] != nil, posixPermissions: permissions)
        }
    }
    public static func extract(_ url: URL, to destination: URL, selected: Set<String>, password: String) async throws -> OperationReport {
        let fm = FileManager.default; let entries = try await list(url, password: password)
        let work = destination.appendingPathComponent(".MacFiles-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); defer { try? fm.removeItem(at: work) }
        var links: [(ArchiveMember, URL)] = []; var directories: [(ArchiveMember, URL)] = []
        for item in entries where selected.isEmpty || selected.contains(where: { item.path == $0 || item.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) {
            try Task.checkCancellation()
            let parts = try ArchiveService.validatedPath(item.path); let target = work.appendingPathComponent(parts.joined(separator: "/"))
            // Every output is written by MacFiles, never by an archive-supplied path in the subprocess.
            try fm.createDirectory(at: item.directory ? target : target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if item.link { links.append((item, target)); continue }
            if item.directory { directories.append((item, target)) }
            if !item.directory {
                _ = try await ProcessService.run(executable.path, ["x", "-so", "-bd", "-bsp0", "-bse2", "-spd", "--", url.path, item.path], input: try input(password), outputURL: target)
                let bytes = (try fm.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value
                guard bytes == item.size else { throw ArchiveFailure("Extracted entry size does not match its header.") }
                if item.modified != .distantPast { try fm.setAttributes([.modificationDate: item.modified], ofItemAtPath: target.path) }
                if let mode = item.posixPermissions { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path) }
            }
        }
        // Materialize links last so no subsequent archive member can traverse one.
        for (item, target) in links {
            try Task.checkCancellation()
            let value: String
            if let linkTarget = item.linkTarget { value = linkTarget }
            else {
                guard item.size <= 65536 else { throw ArchiveFailure("Archive link target is too long.") }
                let result = try await ProcessService.run(executable.path, ["x", "-so", "-bd", "-bsp0", "-bse2", "-spd", "--", url.path, item.path], input: try input(password))
                guard let text = String(data: result.data, encoding: .utf8), result.data.count == item.size else { throw ArchiveFailure("Invalid archive link target.") }
                value = text
            }
            guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.contains("\0") else { throw ArchiveFailure("Unsafe archive link target.") }
            let base = item.hardLink ? work : target.deletingLastPathComponent()
            let resolved = base.appendingPathComponent(value).standardizedFileURL
            guard resolved.path.hasPrefix(work.path + "/"), resolved.resolvingSymlinksInPath().path.hasPrefix(work.path + "/") else { throw ArchiveFailure("Archive link escapes its destination.") }
            if item.hardLink {
                guard (try fm.attributesOfItem(atPath: resolved.path)[.type] as? FileAttributeType) == .typeRegular else { throw ArchiveFailure("Invalid archive hard link.") }
                try fm.linkItem(at: resolved, to: target)
            } else { try fm.createSymbolicLink(atPath: target.path, withDestinationPath: value) }
        }
        for (item, folder) in directories.sorted(by: { $0.1.path.count > $1.1.path.count }) {
            if item.modified != .distantPast { try fm.setAttributes([.modificationDate: item.modified], ofItemAtPath: folder.path) }
            if let mode = item.posixPermissions { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: folder.path) }
        }
        let base = url.deletingPathExtension().lastPathComponent
        var target = destination.appendingPathComponent(base); var index = 2
        while (try? fm.attributesOfItem(atPath: target.path)) != nil { target = destination.appendingPathComponent("\(base) (\(index))"); index += 1 }
        try fm.moveItem(at: work, to: target)
        var report = OperationReport(); report.completed = [target]; report.undo = [.trash(target, identity: FileIdentity(target))]; return report
    }
    public static func compress(_ sources: [URL], to destination: URL, format: ArchiveFormat, password: String, volumeBytes: Int64?) async throws -> OperationReport {
        guard Set(sources.map(\.lastPathComponent)).count == sources.count else { throw ArchiveFailure("Select uniquely named items to archive.") }
        guard format == .zip || format == .sevenZip else { throw ArchiveFailure("Split archives use ZIP or 7z format.") }
        let fm = FileManager.default; let work = destination.deletingLastPathComponent().appendingPathComponent(".MacFiles-archive-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); defer { try? fm.removeItem(at: work) }
        let target = work.appendingPathComponent(destination.lastPathComponent)
        var args = ["a", format == .zip ? "-tzip" : "-t7z", "-bd", "-bsp0", "-snl"]
        if !password.isEmpty { args += ["-p", format == .sevenZip ? "-mhe=on" : "-mem=AES256"] }
        if let volumeBytes { guard volumeBytes >= 1024 else { throw ArchiveFailure("Volumes must be at least 1 KiB.") }; args += ["-v\(volumeBytes)b"] }
        if sources.isEmpty {
            let list = work.appendingPathComponent("empty.list"); try Data().write(to: list)
            args += ["-i@" + list.path]
        }
        args += ["--", target.path] + sources.map(\.path)
        _ = try await ProcessService.run(executable.path, args, input: try input(password))
        try? fm.removeItem(at: work.appendingPathComponent("empty.list"))
        let outputs = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        guard !outputs.isEmpty else { throw ArchiveFailure("No archive was produced.") }
        for output in outputs { let final = destination.deletingLastPathComponent().appendingPathComponent(output.lastPathComponent); guard (try? fm.attributesOfItem(atPath: final.path)) == nil else { throw StorageError.alreadyExists(final.lastPathComponent) } }
        var report = OperationReport()
        do {
            for output in outputs { let final = destination.deletingLastPathComponent().appendingPathComponent(output.lastPathComponent); try fm.moveItem(at: output, to: final); report.completed.append(final); report.undo.append(.trash(final, identity: FileIdentity(final))) }
        } catch { for output in report.completed { try? fm.removeItem(at: output) }; throw error }
        return report
    }
}
