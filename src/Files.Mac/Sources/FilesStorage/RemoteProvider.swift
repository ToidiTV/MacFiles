import Foundation

public enum RemoteProtocol: String, Codable, CaseIterable, Sendable { case ftp = "FTP", ftps = "FTP over TLS", sftp = "SFTP (SSH keys)" }
public struct RemoteConnection: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: RemoteProtocol
    public var host: String
    public var port: Int
    public var username: String
    public var initialPath: String
    public init(id: UUID = UUID(), name: String, kind: RemoteProtocol, host: String, port: Int, username: String, initialPath: String = "/") {
        self.id = id; self.name = name; self.kind = kind; self.host = host; self.port = port; self.username = username; self.initialPath = initialPath
    }
}
public struct RemoteItem: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let directory: Bool
    public let size: Int64
    public let linkTarget: String?
    public let permissions: String?
    public let owner: String?
    public let group: String?
    public let modified: Date?
    public init(name: String, directory: Bool, size: Int64, linkTarget: String? = nil, permissions: String? = nil, owner: String? = nil, group: String? = nil, modified: Date? = nil) {
        self.name = name; self.directory = directory; self.size = size; self.linkTarget = linkTarget; self.permissions = permissions; self.owner = owner; self.group = group; self.modified = modified
    }
}

public actor RemoteProvider {
    let connection: RemoteConnection
    let password: String
    let knownHostsOverride: URL?
    let certificateAuthority: URL?
    let sshConfigOverride: URL?
    public init(connection: RemoteConnection, password: String = "", knownHosts: URL? = nil, sshConfig: URL? = nil, certificateAuthority: URL? = nil) { self.certificateAuthority = certificateAuthority; self.connection = connection; self.password = password; knownHostsOverride = knownHosts; sshConfigOverride = sshConfig }
    private func validate() throws {
        guard !connection.host.isEmpty, !connection.host.hasPrefix("-"),
              !connection.host.contains(where: { $0.isWhitespace || "\"'@/\\".contains($0) }),
              !connection.username.contains(where: { $0.isWhitespace || "\"'@\\".contains($0) }),
              (1...65535).contains(connection.port) else { throw CommandFailure("Enter a valid host, username, and port.") }
    }
    public static func validatePath(_ path: String) throws {
        guard !path.contains("\n"), !path.contains("\r"), !path.contains("\0") else { throw CommandFailure("Remote paths cannot contain line breaks or NUL characters.") }
    }
    public static func child(_ parent: String, _ name: String) throws -> String {
        guard name != ".", name != "..", !name.isEmpty, !name.contains("/") else { throw StorageError.invalidName }
        try validatePath(name)
        return (parent.hasSuffix("/") ? parent : parent + "/") + name
    }
    private func remoteURL(_ path: String, directory: Bool) throws -> String {
        try validate(); try Self.validatePath(path)
        var components = URLComponents(); components.scheme = "ftp"; components.host = connection.host; components.port = connection.port
        components.path = path.hasPrefix("/") ? path : "/" + path
        if directory && !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { throw CommandFailure("Invalid remote URL.") }
        return url.absoluteString
    }
    private func configEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
    }
    private func curl(_ arguments: [String]) async throws -> CommandResult {
        try validate()
        let login = connection.username.isEmpty ? "anonymous:" : connection.username + ":" + password
        let config = "user = \"\(configEscape(login))\"\n"
        let tls = connection.kind == .ftps ? ["--ssl-reqd"] + (certificateAuthority.map { ["--cacert", $0.path] } ?? []) : []
        return try await ProcessService.run("/usr/bin/curl", ["--disable", "--silent", "--show-error", "--fail", "--connect-timeout", "20", "--max-time", "3600", "--config", "-"] + tls + arguments, input: Data(config.utf8))
    }
    private func quoted(_ value: String) throws -> String {
        try Self.validatePath(value)
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    private func sftp(_ commands: [String]) async throws -> CommandResult {
        try validate()
        let host = connection.host.contains(":") ? "[\(connection.host)]" : connection.host
        let address = connection.username.isEmpty ? host : "\(connection.username)@\(host)"
        var environment = ["LC_ALL": "C"]
        var secretURL: URL?
        defer { if let secretURL { try? FileManager.default.removeItem(at: secretURL) } }
        if !password.isEmpty {
            guard !password.contains("\n"), !password.contains("\0") else { throw CommandFailure("SSH passwords cannot contain line breaks or NUL characters.") }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-ssh-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: url.path, contents: Data((password + "\n").utf8), attributes: [.posixPermissions: 0o600]) else { throw CommandFailure("Cannot prepare SSH authentication.") }
            secretURL = url
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/macfiles-askpass")
            let helper = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : SevenZipService.executable.deletingLastPathComponent().appendingPathComponent("macfiles-askpass")
            environment.merge(["SSH_ASKPASS": helper.path, "SSH_ASKPASS_REQUIRE": "force", "MACFILES_ASKPASS_FILE": url.path]) { _, value in value }
        }
        var options = ["-oBatchMode=\(password.isEmpty ? "yes" : "no")", "-oNumberOfPasswordPrompts=1", "-oStrictHostKeyChecking=yes", "-oConnectTimeout=20"]
        if let sshConfigOverride { options += ["-F", sshConfigOverride.path] }
        let knownHosts = knownHostsOverride ?? SSHHostService.knownHosts
        if FileManager.default.fileExists(atPath: knownHosts.path) {
            let path = knownHosts.path.replacingOccurrences(of: "\"", with: "\\\"")
            options += ["-oUserKnownHostsFile=\"\(path)\"" + (knownHostsOverride == nil ? " ~/.ssh/known_hosts ~/.ssh/known_hosts2" : "")]
        }
        return try await ProcessService.run("/usr/bin/sftp", options + ["-b", "-", "-P", String(connection.port), address],
            input: Data((commands.joined(separator: "\n") + "\n").utf8), environment: environment)
    }
    public static func parseMLSD(_ text: String) -> [RemoteItem] {
        text.components(separatedBy: .newlines).compactMap { line in
            guard let boundary = line.firstIndex(of: " ") else { return nil }
            let facts = line[..<boundary].split(separator: ";")
            var values: [String: String] = [:]
            for fact in facts {
                let pair = fact.split(separator: "=", maxSplits: 1); if pair.count == 2 { values[pair[0].lowercased()] = String(pair[1]) }
            }
            let name = String(line[line.index(after: boundary)...])
            guard let type = values["type"], !["cdir", "pdir"].contains(type), !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
            guard ["file", "dir"].contains(type) else { return nil }
            let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT: 0); date.dateFormat = "yyyyMMddHHmmss"
            return RemoteItem(name: name, directory: type == "dir", size: Int64(values["size"] ?? "0") ?? 0, permissions: values["unix.mode"], owner: values["unix.owner"] ?? values["unix.uid"], group: values["unix.group"] ?? values["unix.gid"], modified: values["modify"].flatMap { date.date(from: String($0.prefix(14))) })
        }
    }
    public static func parseUnixList(_ text: String) -> [RemoteItem] {
        text.components(separatedBy: .newlines).compactMap { line in
            let pieces = line.split(maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard pieces.count == 9, let first = pieces[0].first, ["d", "-", "l"].contains(first), let size = Int64(pieces[4]) else { return nil }
            let fullName = String(pieces[8]); let arrow = first == "l" ? fullName.range(of: " -> ") : nil
            let name = arrow.map { String(fullName[..<$0.lowerBound]) } ?? fullName
            let link = arrow.map { String(fullName[$0.upperBound...]) }
            guard first != "l" || link != nil else { return nil }
            guard name != ".", name != "..", !name.contains("/") else { return nil }
            let flags = Array(pieces[0].dropFirst().prefix(9)); var mode = 0
            if flags.count == 9 { for (index, flag) in flags.enumerated() { if "rwxst".contains(flag) { mode |= 1 << (8 - index) } } }
            return RemoteItem(name: name, directory: first == "d", size: size, linkTarget: link, permissions: String(mode, radix: 8), owner: String(pieces[2]), group: String(pieces[3]))
        }
    }
    public static func checkedListing(_ text: String, mlsd: Bool, sftp: Bool = false) throws -> [RemoteItem] {
        let lines = text.components(separatedBy: .newlines).filter { line in
            let clean = line.trimmingCharacters(in: .whitespaces)
            return !clean.isEmpty && !(sftp && clean.hasPrefix("sftp> ")) && !(!mlsd && clean.hasPrefix("total "))
        }
        for line in lines {
            if mlsd {
                guard let boundary = line.firstIndex(of: " "), line[..<boundary].lowercased().contains("type=") else { throw CommandFailure("The server returned an unsupported directory listing. No transfer was started.") }
                if line[..<boundary].lowercased().contains("type=cdir;") || line[..<boundary].lowercased().contains("type=pdir;") { continue }
                guard parseMLSD(line).count == 1 else { throw CommandFailure("The server returned an unsafe or unsupported filename.") }
            } else {
                if line.hasSuffix(" .") || line.hasSuffix(" ..") { continue }
                guard parseUnixList(line).count == 1 else { throw CommandFailure("The server returned an unsupported directory listing. No transfer was started.") }
            }
        }
        return mlsd ? parseMLSD(lines.joined(separator: "\n")) : parseUnixList(lines.joined(separator: "\n"))
    }
    public func list(_ path: String) async throws -> [RemoteItem] {
        let items: [RemoteItem]
        if connection.kind == .sftp { items = try Self.checkedListing(try await sftp(["cd \(quoted(path))", "ls -ln"]).output, mlsd: false, sftp: true) }
        else {
            do { items = try Self.checkedListing(try await curl(["--request", "MLSD", try remoteURL(path, directory: true)]).output, mlsd: true) }
            catch is CancellationError { throw CancellationError() }
            catch { items = try Self.checkedListing(try await curl([try remoteURL(path, directory: true)]).output, mlsd: false) }
        }
        return items.sorted { $0.directory != $1.directory ? $0.directory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func download(_ item: RemoteItem, from path: String, to destination: URL) async throws -> URL {
        let target = destination.appendingPathComponent(item.name)
        guard (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil else { throw StorageError.alreadyExists(item.name) }
        let remote = try Self.child(path, item.name)
        if let link = item.linkTarget {
            try Self.validatePath(link)
            try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: link)
        } else if item.directory {
            let staging = destination.appendingPathComponent(".MacFiles-download-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: staging) }
            for child in try await list(remote) { _ = try await download(child, from: remote, to: staging) }
            try FileManager.default.moveItem(at: staging, to: target)
        } else {
            let staging = destination.appendingPathComponent(".MacFiles-download-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            if connection.kind == .sftp { _ = try await sftp(["get \(quoted(remote)) \(quoted(staging.path))"]) }
            else { _ = try await curl(["--output", staging.path, try remoteURL(remote, directory: false)]) }
            try FileManager.default.moveItem(at: staging, to: target)
        }
        return target
    }
    public func upload(_ url: URL, to path: String) async throws {
        guard !(try await list(path)).contains(where: { $0.name == url.lastPathComponent }) else { throw StorageError.alreadyExists(url.lastPathComponent) }
        let remote = try Self.child(path, url.lastPathComponent)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            try await mkdir(url.lastPathComponent, in: path)
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try await upload(child, to: remote) }
        } else if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            guard connection.kind == .sftp else { throw CommandFailure("This FTP server cannot create symbolic links. The source was retained.") }
            let link = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            _ = try await sftp(["ln -s \(quoted(link)) \(quoted(remote))"])
        } else {
            guard attrs[.type] as? FileAttributeType == .typeRegular else { throw CommandFailure("Upload regular files or folders; symbolic links are not followed.") }
            if connection.kind == .sftp { _ = try await sftp(["put \(quoted(url.path)) \(quoted(remote))"]) }
            else { _ = try await curl(["--upload-file", url.path, try remoteURL(remote, directory: false)]) }
        }
    }
    public func mkdir(_ name: String, in path: String) async throws {
        let remote = try Self.child(path, name)
        if connection.kind == .sftp { _ = try await sftp(["mkdir \(quoted(remote))"]) }
        else { _ = try await curl(["--quote", "MKD \(remote)", "--list-only", try remoteURL(path, directory: true)]) }
    }
    public func rename(_ item: RemoteItem, to name: String, in path: String) async throws {
        guard !(try await list(path)).contains(where: { $0.name == name }) else { throw StorageError.alreadyExists(name) }
        let source = try Self.child(path, item.name), target = try Self.child(path, name)
        if connection.kind == .sftp { _ = try await sftp(["rename \(quoted(source)) \(quoted(target))"]) }
        else { _ = try await curl(["--quote", "RNFR \(source)", "--quote", "RNTO \(target)", "--list-only", try remoteURL(path, directory: true)]) }
    }
    public func setPermissions(_ mode: UInt16, path: String) async throws {
        guard mode <= 0o777 else { throw StorageError.invalidName }; try Self.validatePath(path)
        if connection.kind == .sftp { _ = try await sftp(["chmod \(String(mode, radix: 8)) \(quoted(path))"]) }
        else { _ = try await curl(["--quote", "SITE CHMOD \(String(mode, radix: 8)) \(path)", "--list-only", try remoteURL((path as NSString).deletingLastPathComponent, directory: true)]) }
    }
    public func delete(_ item: RemoteItem, in path: String) async throws {
        let remote = try Self.child(path, item.name)
        if connection.kind == .sftp { _ = try await sftp(["\(item.directory ? "rmdir" : "rm") \(quoted(remote))"]) }
        else { _ = try await curl(["--quote", "\(item.directory ? "RMD" : "DELE") \(remote)", "--list-only", try remoteURL(path, directory: true)]) }
    }
}

public struct RemoteUndoStep: Codable, Sendable {
    public let from: String
    public let to: String
    public init(from: String, to: String) { self.from = from; self.to = to }
}
public struct RemoteOperationReport: Sendable {
    public var undo: [RemoteUndoStep] = []
    public var skipped = false
    public var destination: String?
    public init() {}
}
public extension RemoteProvider {
    func move(from: String, to: String) async throws {
        try Self.validatePath(from); try Self.validatePath(to)
        let parent = (to as NSString).deletingLastPathComponent
        guard !(try await list(parent.isEmpty ? "/" : parent)).contains(where: { $0.name == (to as NSString).lastPathComponent }) else { throw StorageError.alreadyExists((to as NSString).lastPathComponent) }
        if connection.kind == .sftp { _ = try await sftp(["rename \(quoted(from)) \(quoted(to))"]) }
        else { _ = try await curl(["--quote", "RNFR \(from)", "--quote", "RNTO \(to)", "--list-only", try remoteURL(parent, directory: true)]) }
    }
    func recoveryPath(in parent: String, name: String) async throws -> String {
        let folderName = ".MacFiles-Recovery"
        let items = try await list(parent)
        if let existing = items.first(where: { $0.name == folderName }) { guard existing.directory else { throw CommandFailure("The server recovery path is occupied by a file.") } }
        else { try await mkdir(folderName, in: parent) }
        return try Self.child(Self.child(parent, folderName), UUID().uuidString + "-" + name)
    }
    func trash(_ item: RemoteItem, in path: String) async throws -> RemoteOperationReport {
        let source = try Self.child(path, item.name); let backup = try await recoveryPath(in: path, name: item.name)
        try await move(from: source, to: backup)
        var report = RemoteOperationReport(); report.undo = [.init(from: backup, to: source)]; return report
    }
    func renameWithUndo(_ item: RemoteItem, to name: String, in path: String) async throws -> RemoteOperationReport {
        let source = try Self.child(path, item.name), target = try Self.child(path, name)
        try await move(from: source, to: target)
        var report = RemoteOperationReport(); report.undo = [.init(from: target, to: source)]; return report
    }
    func undoRemote(_ steps: [RemoteUndoStep]) async throws -> [RemoteUndoStep] {
        var completed: [RemoteUndoStep] = []
        do {
            for step in steps.reversed() { try Task.checkCancellation(); try await move(from: step.from, to: step.to); completed.append(step) }
        } catch {
            // Restore the pre-undo state if a later destination became occupied.
            var rollbackErrors: [String] = []
            for step in completed.reversed() { do { try await move(from: step.to, to: step.from) } catch { rollbackErrors.append(error.localizedDescription) } }
            if !rollbackErrors.isEmpty { throw CommandFailure(error.localizedDescription + "\nRollback: " + rollbackErrors.joined(separator: "\n")) }
            throw error
        }
        return completed.map { .init(from: $0.to, to: $0.from) }
    }
    func uploadWithConflicts(_ url: URL, to path: String, conflict: ConflictPolicy, verifyContents: Bool = false) async throws -> RemoteOperationReport {
        let fm = FileManager.default; let listed = try await list(path)
        var name = url.lastPathComponent; let existing = listed.first { $0.name == name }
        var report = RemoteOperationReport()
        if existing != nil {
            if conflict == .skip { report.skipped = true; return report }
            if conflict == .keepBoth {
                let ext = url.pathExtension; let stem = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent; var index = 2
                while listed.contains(where: { $0.name == name }) { name = "\(stem) (\(index))" + (ext.isEmpty ? "" : "." + ext); index += 1 }
            }
        }
        let target = try Self.child(path, name)
        let localStage = fm.temporaryDirectory.appendingPathComponent("MacFiles-upload-\(UUID().uuidString)")
        try fm.createDirectory(at: localStage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); defer { try? fm.removeItem(at: localStage) }
        let stageName = ".MacFiles-upload-" + UUID().uuidString
        let staged = localStage.appendingPathComponent(stageName)
        try CancellableCopy.copy(url, to: staged)
        let remoteStage = try Self.child(path, stageName)
        // Transfer into a private name; publish only after the entire tree has arrived.
        try await upload(staged, to: path)
        if verifyContents {
            let verification = localStage.appendingPathComponent("verify"); try fm.createDirectory(at: verification, withIntermediateDirectories: false)
            guard let remoteItem = try await list(path).first(where: { $0.name == stageName }) else { throw StorageError.changedItem(name) }
            let downloaded = try await download(remoteItem, from: path, to: verification)
            guard try TransferFingerprint.digest(staged) == TransferFingerprint.digest(downloaded) else { throw CommandFailure("The uploaded data did not match its source. The source was retained.") }
        }
        var backup: String?
        do {
            if let existing, conflict == .replace {
                let recovery = try await recoveryPath(in: path, name: existing.name)
                try await move(from: try Self.child(path, existing.name), to: recovery); backup = recovery
                report.undo.append(.init(from: recovery, to: target))
            }
            try await move(from: remoteStage, to: target)
            let undoTarget = try await recoveryPath(in: path, name: name)
            report.undo.append(.init(from: target, to: undoTarget)); report.destination = target
            return report
        } catch {
            if let backup { do { try await move(from: backup, to: target) } catch { throw CommandFailure("Upload failed. The original remains at \(backup); the pending upload is \(remoteStage). \(error.localizedDescription)") } }
            throw error
        }
    }
}
