import Foundation

public struct GitChange: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let index: String
    public let worktree: String
    public var status: String { index + worktree }
}
public struct GitRepository: Sendable {
    public let root: URL
    public let branch: String
    public let branches: [String]
    public let changes: [GitChange]
    public let remotes: String
    public let log: String
}

public actor GitService {
    public init() {}
    private func git(_ args: [String], at folder: URL, check: Bool = true) async throws -> CommandResult {
        try await ProcessService.run("/usr/bin/git", GitHubCredentials.gitArguments + ["--no-optional-locks", "-C", folder.path] + args,
            environment: ["GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never", "LC_ALL": "C", "GIT_PAGER": "cat"], check: check)
    }
    public static func parseStatus(_ data: Data) -> [GitChange] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var changes: [GitChange] = []; var i = 0
        while i < fields.count {
            let field = Array(fields[i]); i += 1
            guard field.count >= 4, field[2] == 32 else { continue }
            let x = String(UnicodeScalar(field[0])), y = String(UnicodeScalar(field[1]))
            let path = String(decoding: field.dropFirst(3), as: UTF8.self)
            changes.append(GitChange(path: path, index: x, worktree: y))
            if x == "R" || x == "C" || y == "R" || y == "C" { i += 1 }
        }
        return changes
    }
    public func inspect(_ folder: URL) async throws -> GitRepository {
        let rootResult = try await git(["rev-parse", "--show-toplevel"], at: folder)
        let root = URL(fileURLWithPath: rootResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        let branch = try await git(["symbolic-ref", "--short", "HEAD"], at: root, check: false)
        let branches = try await git(["for-each-ref", "--format=%(refname:short)", "refs/heads"], at: root)
        let status = try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: root)
        let remotes = try await git(["remote", "-v"], at: root)
        let log = try await git(["log", "-30", "--date=short", "--format=%h  %ad  %s"], at: root, check: false)
        return GitRepository(root: root, branch: branch.status == 0 ? branch.output.trimmingCharacters(in: .newlines) : "Detached HEAD",
            branches: branches.output.split(separator: "\n").map(String.init), changes: Self.parseStatus(status.data), remotes: remotes.output,
            log: log.status == 0 ? log.output : "No commits yet")
    }
    public func diff(_ path: String, at root: URL, staged: Bool = false) async throws -> String {
        let result = try await git(["diff", "--no-ext-diff", "--no-textconv"] + (staged ? ["--cached"] : []) + ["--", path], at: root)
        return result.output.isEmpty ? "No tracked diff. New files appear after staging." : result.output
    }
    public func stage(_ paths: [String], at root: URL) async throws {
        guard !paths.isEmpty else { return }; _ = try await git(["add", "--"] + paths, at: root)
    }
    public func unstage(_ paths: [String], at root: URL) async throws {
        guard !paths.isEmpty else { return }
        let head = try await git(["rev-parse", "--verify", "HEAD"], at: root, check: false)
        _ = try await git(head.status == 0 ? ["reset", "HEAD", "--"] + paths : ["rm", "--cached", "--"] + paths, at: root)
    }
    public func commit(_ message: String, at root: URL) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandFailure("Enter a commit message.") }
        _ = try await git(["commit", "-m", message], at: root)
    }
    public func operation(_ action: String, at root: URL) async throws -> String {
        if action == "Sync" {
            let pull = try await operation("Pull", at: root)
            try Task.checkCancellation()
            let push = try await operation("Push", at: root)
            return pull + "\n" + push
        }
        let args: [String]
        switch action {
        case "Fetch": args = ["fetch", "--all", "--prune"]
        case "Pull": args = ["pull", "--ff-only"]
        case "Push": args = ["push"]
        case "Initialize": args = ["init"]
        default: throw CommandFailure("Unsupported Git action.")
        }
        return try await git(args, at: root).output
    }
    public func switchBranch(_ branch: String, at root: URL, create: Bool) async throws {
        _ = try await git(["check-ref-format", "--branch", branch], at: root)
        _ = try await git(create ? ["switch", "-c", branch] : ["switch", "--", branch], at: root)
    }
    public func clone(_ remote: String, to destination: URL) async throws {
        guard !remote.isEmpty, !remote.contains("\n"), !FileManager.default.fileExists(atPath: destination.path) else { throw CommandFailure("Choose a new destination and a repository URL.") }
        _ = try await ProcessService.run("/usr/bin/git", GitHubCredentials.gitArguments + ["clone", "--", remote, destination.path], environment: ["GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never"])
    }
}
